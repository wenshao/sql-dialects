# DamengDB (达梦): 事务

Oracle compatible transaction handling.

> 参考资料:
> - [DamengDB SQL Reference](https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html)
> - [DamengDB System Admin Manual](https://eco.dameng.com/document/dm/zh-cn/pm/index.html)
> - 达梦与 Oracle 一样，DML 自动开启事务，不需要显式 BEGIN

```sql
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;
```

## 回滚

```sql
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;
```

## 保存点

```sql
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TO SAVEPOINT sp1;
COMMIT;
```

## 隔离级别（支持 4 种标准隔离级别）

```sql
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;     -- 默认
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

## 只读事务

```sql
SET TRANSACTION READ ONLY;
```

## 锁相关

```sql
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE WAIT 5;   -- 等待 5 秒
```

## 锁定特定列

```sql
SELECT * FROM accounts WHERE id = 1 FOR UPDATE OF balance;
```

## 手动锁表

```sql
LOCK TABLE accounts IN EXCLUSIVE MODE;
LOCK TABLE accounts IN SHARE MODE;
```

自治事务（PL/SQL 中使用）
CREATE OR REPLACE PROCEDURE log_action(...)
AS
PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
INSERT INTO log_table ...;
COMMIT;  -- 独立提交，不影响主事务
END;
注意事项：
与 Oracle 一样，DML 自动开启事务
没有显式 BEGIN TRANSACTION
DDL 语句会隐式提交当前事务
支持自治事务（AUTONOMOUS_TRANSACTION）
使用 MVCC 实现读不阻塞写
支持 FOR UPDATE WAIT n 等待指定秒数
