# Materialize: INSERT

> 参考资料:
> - [Materialize SQL Reference](https://materialize.com/docs/sql/)
> - [Materialize SQL Functions](https://materialize.com/docs/sql/functions/)


Materialize 的 TABLE 支持 INSERT
SOURCE 和 MATERIALIZED VIEW 不支持直接 INSERT
单行插入

```sql
INSERT INTO users (id, username, email, age) VALUES (1, 'alice', 'alice@example.com', 25);
```

## 多行插入

```sql
INSERT INTO users (id, username, email, age) VALUES
    (1, 'alice', 'alice@example.com', 25),
    (2, 'bob', 'bob@example.com', 30),
    (3, 'charlie', 'charlie@example.com', 35);
```

## 从查询结果插入

```sql
INSERT INTO users_archive (id, username, email, age)
SELECT id, username, email, age FROM users WHERE age > 60;
```

## DEFAULT 值

```sql
INSERT INTO events (id, event_type) VALUES (1, 'login');
```

## CTE + INSERT

```sql
WITH new_users AS (
    SELECT 4 AS id, 'dave' AS username, 'dave@example.com' AS email, 28 AS age
    UNION ALL
    SELECT 5, 'eve', 'eve@example.com', 32
)
INSERT INTO users (id, username, email, age)
SELECT * FROM new_users;
```

## NULL 值

```sql
INSERT INTO users (id, username, email, age)
VALUES (6, 'frank', 'frank@example.com', NULL);
```

## 数据摄入的主要方式：SOURCE


## 大部分数据通过 SOURCE 进入（而非手动 INSERT）

从 Kafka 摄入

```sql
CREATE SOURCE kafka_events
FROM KAFKA CONNECTION kafka_conn (TOPIC 'events')
FORMAT JSON;
```

## 从 PostgreSQL CDC 摄入

```sql
CREATE SOURCE pg_source
FROM POSTGRES CONNECTION pg_conn (PUBLICATION 'mz_source')
FOR TABLES (users, orders);
```

## 从 Webhook 摄入

```sql
CREATE SOURCE webhook_source
FROM WEBHOOK BODY FORMAT JSON;
```

注意：只有 TABLE 支持 INSERT
注意：SOURCE 的数据由外部系统推送
注意：MATERIALIZED VIEW 由查询自动维护，不能手动 INSERT
注意：大规模数据摄入推荐使用 SOURCE
注意：兼容 PostgreSQL 的 INSERT 语法
