# MariaDB: 事务

与 MySQL InnoDB 事务行为一致, Aria 引擎差异

参考资料:
[1] MariaDB Knowledge Base - Transactions
https://mariadb.com/kb/en/transactions/

## 1. 基本事务

```sql
START TRANSACTION;
INSERT INTO accounts (user_id, balance) VALUES (1, 1000.00);
UPDATE accounts SET balance = balance - 100 WHERE user_id = 1;
UPDATE accounts SET balance = balance + 100 WHERE user_id = 2;
COMMIT;
```


回滚
```sql
START TRANSACTION;
DELETE FROM users WHERE age < 18;
ROLLBACK;
```


## 2. 保存点

```sql
START TRANSACTION;
INSERT INTO orders (user_id, amount) VALUES (1, 100.00);
SAVEPOINT sp1;
INSERT INTO orders (user_id, amount) VALUES (1, 200.00);
ROLLBACK TO SAVEPOINT sp1;   -- 只回滚第二条 INSERT
COMMIT;                       -- 第一条 INSERT 生效
```


## 3. 隔离级别

```sql
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
```

READ UNCOMMITTED: 脏读 (不推荐)
READ COMMITTED: 不可重复读
REPEATABLE READ: 默认, InnoDB MVCC 实现
SERIALIZABLE: 所有 SELECT 隐式加共享锁
MariaDB 与 MySQL 的隔离级别实现基本一致 (都基于 InnoDB MVCC)

## 4. DDL 事务性

MariaDB (同 MySQL): DDL 隐式提交当前事务
不能 START TRANSACTION; CREATE TABLE ...; ROLLBACK;
**对比 PostgreSQL: DDL 是事务性的, 可以回滚 CREATE TABLE**


## 5. START TRANSACTION WITH CONSISTENT SNAPSHOT

```sql
START TRANSACTION WITH CONSISTENT SNAPSHOT;
```

创建一致性快照 (MVCC 读取点), 用于备份等场景
**对比 MySQL: 行为相同, 但 MariaDB 的 GTID 实现不同**


## 6. 对引擎开发者: MVCC 实现差异

MariaDB 的 InnoDB 与 MySQL 的 InnoDB 的 MVCC 实现已有微小差异:
1. Undo log 格式: 两者独立维护, 可能有布局差异
2. Purge 线程: 清理旧版本的策略和线程模型不同
3. Read View: 创建和回收时机的优化路径不同
这些差异在极端并发场景下可能导致不同的性能特征
