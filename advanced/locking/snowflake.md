# Snowflake: 锁机制与并发控制

> 参考资料:
> - [1] Snowflake Documentation - Transactions
>   https://docs.snowflake.com/en/sql-reference/transactions
> - [2] Snowflake Documentation - Lock Behavior
>   https://docs.snowflake.com/en/sql-reference/transactions#label-transactions-locking-resources


## 1. 并发模型概述


 Snowflake 使用 MVCC + 微分区级别的写锁:
   读操作: 不加锁，使用事务开始时的快照（MVCC）
   DML 操作: 获取修改涉及的微分区的写锁
   DDL 操作: 获取表级排他锁
   不支持: 行级锁、SELECT FOR UPDATE、LOCK TABLE、advisory locks

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 无行级锁的设计理由

 传统 OLTP 数据库（MySQL InnoDB, PostgreSQL）的行级锁基于:
   - B-tree 索引定位到行 → 在行上加锁 → 事务结束释放
   - 这要求索引结构支持快速行定位

 Snowflake 的不可变微分区架构无法支持行级锁:
   - 微分区一旦写入就不可变（immutable）
   - UPDATE 实际是: 读取旧分区 → 生成新分区 → 原子替换
   - 锁的粒度自然是"微分区级别"，而非"行级别"

 并发写入冲突:
   如果两个事务修改同一个微分区的不同行:
   → 传统数据库: 行级锁允许并发（不同行不冲突）
   → Snowflake: 微分区级锁导致冲突（后提交者需要重试）
   → 这在 OLAP 场景中很少发生（批量加载通常追加新分区，不修改已有分区）

 对比:
   MySQL InnoDB:   行级锁 + 间隙锁 + 意向锁（复杂但支持高并发 OLTP）
   PostgreSQL:     行级锁 + MVCC（最佳 OLTP 并发支持）
   Oracle:         行级锁 + UNDO 段 MVCC
   BigQuery:       无显式锁（DML 操作序列化，不适合高并发写入）
   Redshift:       表级锁（与 Snowflake 类似，不支持行级锁）
   Databricks:     Delta Lake 乐观并发（文件级别冲突检测）

 对引擎开发者的启示:
   锁粒度与存储架构紧密耦合:
   可变页存储 (InnoDB/PG heap) → 自然支持行级锁
   不可变文件存储 (Snowflake/Delta) → 自然支持文件级锁
   如果引擎采用不可变文件存储，实现行级锁需要额外的行级元数据层
   （如 Databricks 的行级并发通过 Row Tracking 实现）。

### 2.2 只支持 READ COMMITTED 隔离级别

 Snowflake 不支持 REPEATABLE READ 或 SERIALIZABLE:
   - READ COMMITTED: 事务内的每条 SELECT 看到最新已提交的数据
   - 不保证同一事务内两次 SELECT 结果一致（不可重复读）

 设计理由:
   (a) OLAP 场景以读为主，写冲突少，强隔离收益不大
   (b) 分布式环境下实现 SERIALIZABLE 需要全局排序（如 Spanner TrueTime），成本极高
   (c) Time Travel 提供了另一种"读一致性"方案（AT TIMESTAMP）

 对比:
   MySQL:       默认 REPEATABLE READ，支持 SERIALIZABLE
   PostgreSQL:  默认 READ COMMITTED，支持 SERIALIZABLE SSI
   Oracle:      默认 READ COMMITTED，支持 SERIALIZABLE
   BigQuery:    快照隔离（每个查询看到一致性快照）
   Spanner:     外部一致性（最强隔离级别，通过 TrueTime 实现）

## 3. 事务基本操作


手动事务

```sql
BEGIN TRANSACTION;
    INSERT INTO orders (id, status) VALUES (1, 'new');
    UPDATE orders SET status = 'confirmed' WHERE id = 1;
COMMIT;

```

自动提交（默认行为）

```sql
ALTER SESSION SET AUTOCOMMIT = TRUE;   -- 默认: 每条 DML 自动提交

```

禁用自动提交

```sql
ALTER SESSION SET AUTOCOMMIT = FALSE;
```

 之后需要手动 COMMIT 或 ROLLBACK

## 4. 锁管理


查看当前锁

```sql
SHOW LOCKS;
SHOW LOCKS IN ACCOUNT;

```

锁超时设置

```sql
ALTER SESSION SET LOCK_TIMEOUT = 43200;   -- 默认 43200 秒（12 小时）
ALTER SESSION SET LOCK_TIMEOUT = 60;      -- 设置为 1 分钟

```

语句超时

```sql
ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = 3600;  -- 1 小时

```

查看运行中的查询（排查锁等待）

```sql
SELECT query_id, query_text, user_name, start_time, execution_status
FROM TABLE(information_schema.query_history())
WHERE execution_status = 'RUNNING'
ORDER BY start_time;

```

取消阻塞的查询

```sql
SELECT SYSTEM$CANCEL_QUERY('query_id_here');

```

## 5. 并发冲突处理


并发 DML 修改同一分区可能失败:
事务 A: UPDATE orders SET status = 'a' WHERE id = 1;
事务 B: UPDATE orders SET status = 'b' WHERE id = 1;  -- 可能失败!
解决方案: 应用层重试机制

应用层乐观锁模式:

```sql
CREATE TABLE orders (
    id         NUMBER NOT NULL,
    status     VARCHAR(50),
    version    NUMBER NOT NULL DEFAULT 1,
    updated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

BEGIN TRANSACTION;
    UPDATE orders
    SET status = 'shipped', version = version + 1,
        updated_at = CURRENT_TIMESTAMP()
    WHERE id = 100 AND version = 5;
    -- 检查 ROW_COUNT: 如果 = 0 则版本冲突，需要重试
COMMIT;

```

## 6. Time Travel: 无锁的历史数据访问


Time Travel 不需要锁，读取历史快照:

```sql
SELECT * FROM orders AT(TIMESTAMP => '2024-01-15 10:00:00'::TIMESTAMP_NTZ);
SELECT * FROM orders AT(OFFSET => -300);  -- 5 分钟前
SELECT * FROM orders BEFORE(STATEMENT => 'query_id_here');

```

 Time Travel 的设计意义:
   传统数据库需要 REPEATABLE READ 或 SERIALIZABLE 保证读一致性。
   Snowflake 通过 Time Travel AT(TIMESTAMP) 提供了另一种方案:
   用户可以显式指定"我要读取某个时间点的数据"。
   这比隐式的隔离级别更直观，但需要用户主动使用。

## 横向对比: 并发控制能力矩阵

| 能力               | Snowflake       | BigQuery    | PostgreSQL     | MySQL InnoDB |
|------|------|------|------|------|
| 锁粒度             | 微分区级        | 表级(序列化)| 行级           | 行级+间隙锁 |
| 默认隔离级别       | READ COMMITTED  | Snapshot    | READ COMMITTED | REPEATABLE READ |
| 最高隔离级别       | READ COMMITTED  | Snapshot    | SERIALIZABLE   | SERIALIZABLE |
| SELECT FOR UPDATE  | 不支持          | 不支持      | 支持           | 支持 |
| MVCC               | 微分区快照      | 内部快照    | 元组级 MVCC    | UNDO 日志 |
| 死锁检测           | 超时机制        | 不适用      | 主动检测       | 主动检测 |
| 历史数据访问       | Time Travel     | 快照装饰器  | 无原生         | 无原生 |

对引擎开发者的启示:
Snowflake 的锁模型是"OLAP 极简主义": 只有必要的锁，没有复杂的锁升级/降级。
这降低了引擎实现复杂度（无需死锁检测），但限制了 OLTP 并发能力。
Hybrid Tables (2024) 引入行级锁，标志着 Snowflake 补充 OLTP 能力。

