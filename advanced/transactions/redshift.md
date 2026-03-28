# Redshift: 事务

> 参考资料:
> - [Redshift SQL Reference](https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html)
> - [Redshift SQL Functions](https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html)
> - [Redshift Data Types](https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html)


基本事务
```sql
BEGIN;  -- 或 BEGIN TRANSACTION 或 START TRANSACTION
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;  -- 或 END
```


回滚
```sql
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;
```


隐式事务
Redshift 默认自动提交（每条语句是一个事务）
BEGIN ... COMMIT 显式定义事务边界

隔离级别
Redshift 仅支持 SERIALIZABLE 隔离级别（默认且唯一）
使用 MVCC（多版本并发控制）实现
快照隔离：事务看到开始时的快照

锁
Redshift 使用表级锁
写操作（INSERT/UPDATE/DELETE）获取排他锁
读操作（SELECT）使用快照，不阻塞写入

并发限制
Redshift 的并发查询有限（通过 WLM 控制）
WLM（Workload Management）控制并发和优先级

存储过程中的事务
```sql
CREATE OR REPLACE PROCEDURE transfer(
    p_from_id BIGINT,
    p_to_id BIGINT,
    p_amount DECIMAL(10,2)
)
AS $$
DECLARE
    v_balance DECIMAL(10,2);
BEGIN
    SELECT balance INTO v_balance FROM accounts WHERE id = p_from_id;

    IF v_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient balance';
    END IF;

    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from_id;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to_id;
```


存储过程中可以显式提交
```sql
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
$$ LANGUAGE plpgsql;
```


TRUNCATE 在事务中
```sql
BEGIN;
TRUNCATE TABLE staging;
COPY staging FROM 's3://...' IAM_ROLE '...' CSV;
COMMIT;
-- 注意：TRUNCATE 在 Redshift 事务中可以被 ROLLBACK 回滚
```


死锁
Redshift 自动检测死锁并终止其中一个事务
减少死锁的方法：
1. 按固定顺序访问表
2. 避免长事务
3. 避免并发写入同一表

查看活跃事务
```sql
SELECT * FROM stv_inflight;
SELECT * FROM stv_locks;
SELECT * FROM svl_terminate;                 -- 被终止的查询
```


查看锁等待
```sql
SELECT * FROM svv_transactions WHERE lockable_object_type = 'relation';
```


终止长事务
```sql
SELECT pg_terminate_backend(pid) FROM stv_inflight
WHERE starttime < DATEADD(HOUR, -1, GETDATE());
```


注意：Redshift 仅支持 SERIALIZABLE 隔离级别
注意：使用 MVCC 实现，读不阻塞写
注意：表级锁，并发写入同一表会串行化
注意：DDL（CREATE TABLE 等）是事务性的（可以回滚，与多数数据库不同）
注意：TRUNCATE 是事务性的（可以回滚，与 MySQL 等不同）
注意：存储过程中支持 COMMIT / ROLLBACK
注意：长事务会阻止 VACUUM 回收空间
