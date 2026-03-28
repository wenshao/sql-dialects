# TDSQL: 事务

TDSQL distributed MySQL-compatible syntax.

> 参考资料:
> - [TDSQL-C MySQL Documentation](https://cloud.tencent.com/document/product/1003)
> - [TDSQL MySQL Documentation](https://cloud.tencent.com/document/product/557)


## 基本事务

```sql
START TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;
```

## 回滚

```sql
START TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;
```

## 保存点

```sql
START TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TO SAVEPOINT sp1;
COMMIT;
```

## 自动提交

```sql
SELECT @@autocommit;
SET autocommit = 0;
```

## 隔离级别

```sql
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;    -- 默认
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

## 全局 / 会话级别

```sql
SET GLOBAL TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
```

## 查看当前隔离级别

```sql
SELECT @@transaction_isolation;
```

## 只读事务

```sql
START TRANSACTION READ ONLY;
```

## 锁相关

```sql
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR SHARE;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE SKIP LOCKED;
```

注意事项：
TDSQL 使用分布式事务保证强一致性
跨分片事务使用两阶段提交（2PC）
分布式事务的隔离级别为全局一致
单分片事务与 MySQL 行为一致
DDL 语句会隐式提交事务
分布式死锁检测由代理层处理
分布式事务有额外的延迟开销
