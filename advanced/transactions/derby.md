# Derby: 事务

Derby 默认自动提交
在 JDBC 中设置：connection.setAutoCommit(false)
在 ij 工具中关闭自动提交

```sql
AUTOCOMMIT OFF;
```

## 基本事务

```sql
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
INSERT INTO users (username, email) VALUES ('bob', 'bob@example.com');
COMMIT;
```

## 回滚

```sql
DELETE FROM users WHERE id = 1;
ROLLBACK;
```

## 保存点

```sql
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
SAVEPOINT sp1;
INSERT INTO users (username, email) VALUES ('bob', 'bob@example.com');
ROLLBACK TO SAVEPOINT sp1;
RELEASE SAVEPOINT sp1;
COMMIT;
```

隔离级别
Derby 支持 4 种标准隔离级别
在 JDBC 中设置：
connection.setTransactionIsolation(Connection.TRANSACTION_READ_UNCOMMITTED);
connection.setTransactionIsolation(Connection.TRANSACTION_READ_COMMITTED);     -- 默认
connection.setTransactionIsolation(Connection.TRANSACTION_REPEATABLE_READ);
connection.setTransactionIsolation(Connection.TRANSACTION_SERIALIZABLE);
在 ij 工具中

```sql
SET ISOLATION READ UNCOMMITTED;
SET ISOLATION READ COMMITTED;                          -- 默认
SET ISOLATION REPEATABLE READ;
SET ISOLATION SERIALIZABLE;
```

## 查看隔离级别

```sql
VALUES CURRENT ISOLATION;
```

## 锁

```sql
SELECT * FROM users WHERE id = 1 FOR UPDATE;
```

## 锁超时

```sql
CALL SYSCS_UTIL.SYSCS_SET_DATABASE_PROPERTY(
    'derby.locks.waitTimeout', '10');                   -- 10 秒
```

## 死锁超时

```sql
CALL SYSCS_UTIL.SYSCS_SET_DATABASE_PROPERTY(
    'derby.locks.deadlockTimeout', '5');                -- 5 秒
```

## 表锁 vs 行锁

```sql
ALTER TABLE users LOCKSIZE TABLE;                      -- 表级锁
ALTER TABLE users LOCKSIZE ROW;                        -- 行级锁（默认）
```

只读模式
connection.setReadOnly(true);
注意：默认自动提交
注意：不支持 BEGIN 语句（由连接的 autocommit 控制）
注意：默认隔离级别为 READ COMMITTED
注意：支持 SAVEPOINT
注意：DDL 语句不会隐式提交（与 MySQL 不同）
注意：支持行级锁和表级锁
