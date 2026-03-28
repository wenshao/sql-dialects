# Materialize: 事务

Materialize 支持 PostgreSQL 兼容的事务语法（有限制）
基本事务

```sql
BEGIN;
INSERT INTO users (id, username, email) VALUES (1, 'alice', 'alice@example.com');
INSERT INTO users (id, username, email) VALUES (2, 'bob', 'bob@example.com');
COMMIT;
```

## 回滚

```sql
BEGIN;
DELETE FROM users WHERE id = 1;
ROLLBACK;
```

## 一致性模型


Materialize 提供严格串行化（strict serializability）
所有读取都反映最新的写入
时间戳一致性
每个事务都有一个逻辑时间戳
物化视图在同一时间戳下一致

## AS OF（时间旅行查询）


## 查询某个时间点的数据快照

```sql
SELECT * FROM users AS OF AT LEAST NOW() - INTERVAL '1 hour';
```

## 对物化视图也适用

```sql
SELECT * FROM order_summary AS OF AT LEAST NOW() - INTERVAL '30 minutes';
```

## 隔离级别


## Materialize 默认提供严格串行化

所有读取都看到一致的快照

```sql
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;          -- 默认且唯一
```

## 限制


不支持 SAVEPOINT
不支持 SELECT ... FOR UPDATE（无悲观锁）
不支持 LOCK TABLE
只有 TABLE 支持写事务（SOURCE/VIEW 不支持）
注意：Materialize 提供严格串行化一致性
注意：AS OF 支持时间旅行查询
注意：事务主要用于 TABLE 的写操作
注意：物化视图在同一逻辑时间戳下一致
