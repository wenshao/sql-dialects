# BigQuery: 事务

> 参考资料:
> - [1] BigQuery - Multi-Statement Transactions
>   https://cloud.google.com/bigquery/docs/multi-statement-queries#transactions
> - [2] BigQuery - Snapshot Isolation
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/transactions


## 1. BigQuery 的事务模型（对引擎开发者）


 BigQuery 支持多语句事务，但与传统 OLTP 数据库的事务有本质区别:

 OLTP 事务（MySQL/PostgreSQL）:
   面向高并发、低延迟、逐行操作
   MVCC + 行级锁 + WAL → 数千个并发事务

 BigQuery 事务:
   面向低并发、高吞吐、批量操作
   快照隔离 + 表级乐观锁 → 同一表最多约 5 个并发 DML

 为什么并发这么低?
 (a) COW 机制: 每个 DML 重写存储文件，两个并发 DML 会产生冲突
 (b) 无服务器: 没有常驻进程维护锁状态，依赖乐观并发控制
 (c) 设计目标: BigQuery 不是为 OLTP 设计的，事务是为 ETL 原子性服务的

## 2. 基本事务语法


```sql
BEGIN TRANSACTION;

UPDATE myproject.mydataset.accounts SET balance = balance - 100 WHERE id = 1;
UPDATE myproject.mydataset.accounts SET balance = balance + 100 WHERE id = 2;

COMMIT TRANSACTION;

```

回滚

```sql
BEGIN TRANSACTION;
UPDATE myproject.mydataset.accounts SET balance = balance - 100 WHERE id = 1;
```

发现问题，回滚

```sql
ROLLBACK TRANSACTION;

```

脚本中的事务（配合 BEGIN...END 脚本块）

```sql
BEGIN
    BEGIN TRANSACTION;
    INSERT INTO myproject.mydataset.audit_log VALUES (CURRENT_TIMESTAMP(), 'transfer');
    UPDATE myproject.mydataset.accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE myproject.mydataset.accounts SET balance = balance + 100 WHERE id = 2;
    COMMIT TRANSACTION;
EXCEPTION WHEN ERROR THEN
    ROLLBACK TRANSACTION;
    SELECT @@error.message;
END;

```

## 3. 快照隔离（Snapshot Isolation）


 BigQuery 事务使用快照隔离:
   BEGIN TRANSACTION 时创建一致性快照
   事务内的 SELECT 看到的是快照时的数据（不会看到其他事务的修改）
   COMMIT 时检查冲突（乐观并发控制）

 冲突检测:
   如果两个事务修改了同一个表的同一个分区 → 后提交的事务失败
   需要应用层重试

 事务限制:
   最大持续时间: 6 小时
   最多修改: 100 个表
   DML 配额: 事务内的每个 DML 都消耗配额
   不支持: DDL（CREATE TABLE/ALTER TABLE 不能在事务中）

## 4. 事务的典型用例


### 4.1 ETL 原子加载（最常见的用例）

```sql
BEGIN TRANSACTION;
```

清除旧数据

```sql
DELETE FROM myproject.mydataset.daily_report WHERE report_date = '2024-01-15';
```

加载新数据

```sql
INSERT INTO myproject.mydataset.daily_report
SELECT * FROM myproject.mydataset.staging_report WHERE report_date = '2024-01-15';
COMMIT TRANSACTION;
```

 → 要么全部成功（旧数据被新数据替换），要么全部回滚

### 4.2 多表原子更新

```sql
BEGIN TRANSACTION;
INSERT INTO myproject.mydataset.orders VALUES (1001, 42, 99.99, CURRENT_DATE());
UPDATE myproject.mydataset.inventory SET quantity = quantity - 1 WHERE product_id = 42;
UPDATE myproject.mydataset.user_stats SET order_count = order_count + 1 WHERE user_id = 1;
COMMIT TRANSACTION;

```

### 4.3 带错误处理的事务

```sql
BEGIN
    DECLARE total_balance FLOAT64;
    BEGIN TRANSACTION;
    UPDATE myproject.mydataset.accounts SET balance = balance - 100 WHERE id = 1;
    SET total_balance = (SELECT balance FROM myproject.mydataset.accounts WHERE id = 1);
    IF total_balance < 0 THEN
        ROLLBACK TRANSACTION;
        RAISE USING MESSAGE = 'Insufficient balance';
    END IF;
    COMMIT TRANSACTION;
EXCEPTION WHEN ERROR THEN
    ROLLBACK TRANSACTION;
END;

```

## 5. 时间旅行（Time Travel）: 事务的安全网


BigQuery 保留表的历史快照（默认 7 天），可以查询过去的数据:

```sql
SELECT * FROM myproject.mydataset.users
FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR);

```

恢复误删数据:

```sql
INSERT INTO myproject.mydataset.users
SELECT * FROM myproject.mydataset.users
FOR SYSTEM_TIME AS OF TIMESTAMP '2024-01-15 10:00:00 UTC'
WHERE id = 42;

```

 设计分析:
   时间旅行基于 BigQuery 的快照机制（每次 DML 创建新快照）。
   这与 Snowflake 的 Time Travel 设计理念相同。
   对比: MySQL/PostgreSQL 需要从备份恢复，没有内置时间旅行。

## 6. 对比与引擎开发者启示

BigQuery 事务的设计:
(1) 快照隔离 + 乐观并发 → 适合低并发批量操作
(2) 表级冲突检测 → 不支持行级锁
(3) ETL 原子性 → 事务的主要用例
(4) 时间旅行 → 误操作的安全网
(5) 不支持 DDL → 事务范围限于 DML

对比:
MySQL/PostgreSQL: 完整 ACID，行级锁，高并发
SQLite:           完整 ACID，文件级锁，事务性 DDL
ClickHouse:       单语句原子性，分区原子替换
BigQuery:         快照隔离，表级乐观锁，DML-only 事务

对引擎开发者的启示:
云数仓的事务设计应优化 ETL 场景（批量加载的原子性），
而非 OLTP 场景（高并发逐行操作）。
乐观并发控制（OCC）比悲观锁更适合低并发环境。
时间旅行是云数仓的标配功能，实现成本不高但价值巨大。

