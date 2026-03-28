# SQL 标准: 事务

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [Modern SQL - Transaction Isolation](https://modern-sql.com/concept/isolation-level)

## SQL-86 (SQL-1): 基本事务

定义了 COMMIT 和 ROLLBACK

```sql
COMMIT WORK;
ROLLBACK WORK;
```

- **注意：SQL-86 没有 BEGIN 语句**
事务隐式开始，COMMIT 或 ROLLBACK 结束

## SQL-92 (SQL2): 完善事务模型

新增 SET TRANSACTION
新增隔离级别定义
新增 START TRANSACTION（推荐替代隐式开始）

```sql
START TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;
```

隔离级别（SQL-92 定义的四个标准级别）
```sql
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;  -- 允许脏读
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;    -- 不允许脏读
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;   -- 不允许不可重复读
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;      -- 完全串行化
```

只读事务
```sql
SET TRANSACTION READ ONLY;
SET TRANSACTION READ WRITE;  -- 默认
```

组合
```sql
START TRANSACTION ISOLATION LEVEL SERIALIZABLE, READ ONLY;
```

隔离级别与异常现象的关系（SQL-92 定义）：
READ UNCOMMITTED: 允许脏读、不可重复读、幻读
READ COMMITTED:   不允许脏读，允许不可重复读、幻读
REPEATABLE READ:  不允许脏读和不可重复读，允许幻读
SERIALIZABLE:     不允许任何异常

## SQL-92: 保存点

```sql
SAVEPOINT sp1;
```

... 一些操作 ...
```sql
ROLLBACK TO SAVEPOINT sp1;
RELEASE SAVEPOINT sp1;
```

## SQL:1999 (SQL3): 增强

SAVEPOINT 更完善
嵌套 SAVEPOINT

```sql
START TRANSACTION;
INSERT INTO orders VALUES (1, 100);
SAVEPOINT sp1;
INSERT INTO order_items VALUES (1, 1, 50);
SAVEPOINT sp2;
INSERT INTO order_items VALUES (1, 2, 50);
ROLLBACK TO SAVEPOINT sp2;  -- 只撤销最后一个 INSERT
RELEASE SAVEPOINT sp1;
COMMIT;
```

## SQL:2003: 增强

标准更加完善，但核心概念不变

## SQL:2011: 增强

事务与时态表的集成

时态查询（查看历史数据）
```sql
SELECT * FROM users FOR SYSTEM_TIME AS OF TIMESTAMP '2024-01-15 10:00:00';
SELECT * FROM users FOR SYSTEM_TIME BETWEEN
    TIMESTAMP '2024-01-01' AND TIMESTAMP '2024-01-31';
```

## 标准中的事务概念

原子性（Atomicity）: 事务要么全部成功，要么全部回滚
一致性（Consistency）: 事务前后数据满足所有约束
隔离性（Isolation）: 并发事务互不干扰
持久性（Durability）: 提交的事务永久保存

标准定义的锁模式
```sql
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;    -- 排他锁
SELECT * FROM accounts WHERE id = 1 FOR READ ONLY; -- 共享锁（标准语法）
```

## 各数据库实现对比

MySQL: START TRANSACTION / BEGIN, AUTOCOMMIT, InnoDB 必须
PostgreSQL: BEGIN, DDL 可回滚, SSI
Oracle: 隐式开始, READ COMMITTED 默认, 没有 READ UNCOMMITTED
SQL Server: BEGIN TRAN, 支持所有级别
SQLite: BEGIN, DEFERRED/IMMEDIATE/EXCLUSIVE
BigQuery: BEGIN TRANSACTION, 快照隔离
Snowflake: 只支持 READ COMMITTED
ClickHouse: 不支持多语句事务

- **注意：SQL 标准定义了四个隔离级别，但各数据库实现差异很大**
- **注意：标准没有定义 BEGIN 语句（使用 START TRANSACTION）**
- **注意：WORK 关键字是可选的（COMMIT WORK = COMMIT）**
- **注意：分析型数据库通常只支持有限的事务**
