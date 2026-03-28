# Vertica: 事务


Vertica 支持 ACID 事务

## 基本事务


Vertica 默认自动提交（AUTOCOMMIT ON）
显式事务需要 BEGIN

```sql
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;
```


回滚
```sql
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;
```


## 保存点


```sql
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TO SAVEPOINT sp1;
RELEASE SAVEPOINT sp1;
COMMIT;
```


## 隔离级别


Vertica 支持两种隔离级别
```sql
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL READ COMMITTED;  -- 默认
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```


事务级别设置
```sql
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```


查看当前隔离级别
```sql
SHOW TRANSACTION_ISOLATION;
```


## 只读事务


```sql
BEGIN TRANSACTION READ ONLY;
SELECT * FROM users;
COMMIT;
```


## 锁


表级锁（INSERT/UPDATE/DELETE 自动获取）
Vertica 使用表级锁，不支持行级锁
```sql
SELECT LOCK_TABLE('users', 'E');  -- Exclusive lock
SELECT LOCK_TABLE('users', 'S');  -- Shared lock
```


查看锁信息
```sql
SELECT * FROM v_monitor.locks;
```


等待锁超时
```sql
SET LockTimeout = 300;  -- 秒
```


## COPY 事务


COPY 命令是原子的
全部成功或全部失败
```sql
COPY users FROM '/data/users.csv' DELIMITER ',';
```


COPY 带错误容忍
```sql
COPY users FROM '/data/users.csv'
    DELIMITER ','
    REJECTMAX 100
    REJECTED DATA '/data/rejects.csv';
-- 超过 REJECTMAX 行错误则回滚整个 COPY
```


## 自动提交


查看自动提交状态
```sql
SHOW AUTOCOMMIT;
```


关闭自动提交（VSQL 客户端）
\set AUTOCOMMIT off

## MVCC


Vertica 使用 MVCC（多版本并发控制）
读操作不阻塞写操作
写操作不阻塞读操作
每个查询看到一致性快照

历史查询（Vertica 特有）
SELECT * FROM users AT EPOCH LATEST;
SELECT * FROM users AT TIME '2024-01-15 10:00:00';

## 存储过程中的事务


存储过程支持 COMMIT/ROLLBACK
CREATE OR REPLACE PROCEDURE my_proc()
LANGUAGE PLvSQL AS $$
BEGIN
INSERT INTO t1 VALUES (1);
COMMIT;
INSERT INTO t2 VALUES (2);
ROLLBACK;  -- 只回滚第二个 INSERT
END;
$$;

> **注意**: Vertica 默认 AUTOCOMMIT 开启
> **注意**: 使用表级锁（不支持行级锁）
> **注意**: 支持 READ COMMITTED 和 SERIALIZABLE 隔离级别
> **注意**: COPY 是原子操作
> **注意**: MVCC 实现读写互不阻塞
