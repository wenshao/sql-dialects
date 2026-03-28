# Snowflake: 事务

> 参考资料:
> - [1] Snowflake SQL Reference - BEGIN / COMMIT / ROLLBACK
>   https://docs.snowflake.com/en/sql-reference/sql/begin
> - [2] Snowflake SQL Reference - Transactions
>   https://docs.snowflake.com/en/sql-reference/transactions


## 1. 基本语法


```sql
BEGIN TRANSACTION;  -- 或 BEGIN / BEGIN WORK / START TRANSACTION
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;  -- 或 COMMIT WORK

```

回滚

```sql
BEGIN TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;

```

自动提交（默认行为）

```sql
ALTER SESSION SET AUTOCOMMIT = TRUE;   -- 默认: 每条 DML 自动提交
ALTER SESSION SET AUTOCOMMIT = FALSE;  -- 关闭后需手动 COMMIT/ROLLBACK
SHOW PARAMETERS LIKE 'AUTOCOMMIT';

```

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 隔离级别: 仅 READ COMMITTED

 Snowflake 只支持 READ COMMITTED 隔离级别，不可更改。
 这是语句级别的一致性快照:
   事务内每条 SELECT 看到该语句开始时的最新已提交数据
   同一事务内两次 SELECT 可能看到不同结果（不可重复读）

 设计理由:
   (a) OLAP 场景以读为主，写冲突少
   (b) REPEATABLE READ 需要维护更长的快照，增加存储压力
   (c) SERIALIZABLE 需要全局排序（如 Spanner TrueTime），成本极高
   (d) Time Travel AT(TIMESTAMP) 提供了另一种"读一致性"方案

 对比:
   MySQL InnoDB:  默认 REPEATABLE READ（同事务内两次 SELECT 结果一致）
   PostgreSQL:    默认 READ COMMITTED，支持 SERIALIZABLE SSI
   Oracle:        默认 READ COMMITTED，支持 SERIALIZABLE
   BigQuery:      快照隔离（整个查询看到一致性快照）
   Spanner:       外部一致性（最强隔离，TrueTime 实现）
   Redshift:      SERIALIZABLE（但实现为快照隔离 + 冲突检测）

### 2.2 不支持 SAVEPOINT

 Snowflake 事务只能整体 COMMIT 或 ROLLBACK，无法部分回滚。
 对比:
   PostgreSQL: SAVEPOINT sp1; ... ROLLBACK TO sp1;（任意嵌套）
   Oracle:     SAVEPOINT sp1; ... ROLLBACK TO sp1;
   MySQL:      SAVEPOINT sp1; ... ROLLBACK TO sp1;
   SQL Server: SAVE TRANSACTION sp1; ... ROLLBACK TRANSACTION sp1;

 设计理由:
   SAVEPOINT 需要维护事务内的部分状态，增加 MVCC 复杂度。
   在 Snowflake 的微分区架构中，事务的原子性是分区级别的:
   一组新分区要么全部提交（替换旧分区），要么全部丢弃。
   部分回滚需要跟踪哪些分区对应哪个 SAVEPOINT → 实现复杂。

### 2.3 DDL 隐式提交

 DDL 语句（CREATE/ALTER/DROP）会隐式提交当前事务:
   BEGIN;
   INSERT INTO t VALUES (1);
   CREATE TABLE t2 (id NUMBER);  -- 隐式 COMMIT! INSERT 已提交
   ROLLBACK;                      -- 无法回滚之前的 INSERT

 对比:
   PostgreSQL: DDL 是事务性的（可以在事务中回滚 CREATE TABLE）
   SQL Server: DDL 是事务性的
   Oracle:     DDL 隐式提交（同 Snowflake）
   MySQL:      DDL 隐式提交（同 Snowflake）

 对引擎开发者的启示:
   DDL 事务性是引擎设计中的重要决策。
   事务性 DDL（PostgreSQL）需要 DDL 操作也使用 MVCC 或两阶段提交。
   非事务性 DDL（Oracle/MySQL/Snowflake）实现更简单，但用户体验不如。

## 3. 存储过程中的事务


```sql
CREATE OR REPLACE PROCEDURE transfer(
    p_from NUMBER, p_to NUMBER, p_amount NUMBER
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    BEGIN TRANSACTION;
    UPDATE accounts SET balance = balance - :p_amount WHERE id = :p_from;
    UPDATE accounts SET balance = balance + :p_amount WHERE id = :p_to;
    COMMIT;
    RETURN 'Success';
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RETURN 'Error: ' || SQLERRM;
END;
$$;

CALL transfer(1, 2, 100.00);

```

## 4. 并发与锁


并发 DML 修改同一分区可能冲突（后提交者失败）
锁超时设置:

```sql
ALTER SESSION SET LOCK_TIMEOUT = 600;  -- 默认 43200 秒（12 小时）

```

查看活跃事务和锁:

```sql
SHOW TRANSACTIONS;
SHOW LOCKS;

```

取消阻塞的查询:

```sql
SELECT SYSTEM$CANCEL_QUERY('query_id_here');

```

## 5. Time Travel: 事务恢复的替代方案


Time Travel 不是传统事务功能，但可以替代事务回滚实现数据恢复:

```sql
SELECT * FROM users AT(TIMESTAMP => '2024-01-15 10:00:00'::TIMESTAMP_NTZ);
SELECT * FROM users AT(OFFSET => -3600);  -- 1 小时前
SELECT * FROM users BEFORE(STATEMENT => '<query_id>');

```

从 Time Travel 恢复数据:

```sql
CREATE TABLE users_restored CLONE users
    AT(TIMESTAMP => '2024-01-15 10:00:00'::TIMESTAMP_NTZ);

```

UNDROP: 恢复误删的表/Schema/Database

```sql
DROP TABLE users;
UNDROP TABLE users;

ALTER TABLE users SET DATA_RETENTION_TIME_IN_DAYS = 90;

```

 对引擎开发者的启示:
   Time Travel 在某种程度上弥补了隔离级别的不足:
   不支持 REPEATABLE READ → 但可以用 AT(TIMESTAMP) 获得一致性快照
   不支持 SAVEPOINT → 但可以用 BEFORE(STATEMENT) 回到特定语句之前
   这是 Snowflake "不可变微分区"架构的天然优势

## 横向对比: 事务能力矩阵

| 能力            | Snowflake       | BigQuery     | PostgreSQL    | MySQL InnoDB |
|------|------|------|------|------|
| 默认隔离级别    | READ COMMITTED  | Snapshot     | READ COMMITTED| REPEATABLE READ |
| 最高隔离级别    | READ COMMITTED  | Snapshot     | SERIALIZABLE  | SERIALIZABLE |
| SAVEPOINT       | 不支持          | 不支持       | 支持          | 支持 |
| DDL 事务性      | 隐式提交        | 隐式提交     | 事务性        | 隐式提交 |
| 自动提交        | 默认开启        | 每条语句     | 默认开启      | 默认开启 |
| Time Travel     | 1-90 天         | 7 天         | 无原生        | 无原生 |
| UNDROP          | 支持            | 不支持       | 不支持        | 不支持 |
| 并发冲突处理    | 超时重试        | 序列化       | 死锁检测      | 死锁检测 |

