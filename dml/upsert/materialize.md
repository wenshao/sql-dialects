# Materialize: UPSERT

> 参考资料:
> - [Materialize SQL Reference](https://materialize.com/docs/sql/)
> - [Materialize Source Envelopes](https://materialize.com/docs/sql/create-source/)


Materialize 不支持 INSERT ... ON CONFLICT 语法
也不支持 MERGE 语句
UPSERT 语义通过 SOURCE 的 ENVELOPE UPSERT 或物化视图实现

## TABLE: INSERT（无 UPSERT 语法支持）


## 创建表（支持 UNIQUE 约束，但 ON CONFLICT 不可用）

```sql
CREATE TABLE users (
    id       INT NOT NULL UNIQUE,
    username TEXT NOT NULL,
    email    TEXT NOT NULL,
    age      INT
);
```

## 只能使用普通 INSERT，不支持 ON CONFLICT / ON DUPLICATE KEY

```sql
INSERT INTO users (id, username, email, age)
VALUES (1, 'alice', 'alice@example.com', 25);
```

## 批量 INSERT

```sql
INSERT INTO users (id, username, email, age) VALUES
    (1, 'alice', 'alice@example.com', 25),
    (2, 'bob', 'bob@example.com', 30);
```

## SOURCE 中的 UPSERT 语义（推荐方式）


## PostgreSQL CDC SOURCE 自带 UPSERT 语义

源表的 UPDATE/DELETE 操作会自动反映为下游的更新

```sql
CREATE SOURCE pg_source
FROM POSTGRES CONNECTION pg_conn (PUBLICATION 'mz_source')
FOR TABLES (users, orders);
```

## Kafka SOURCE 的 UPSERT 语义

通过 ENVELOPE UPSERT 实现: 相同 key 的新消息自动替换旧记录

```sql
CREATE SOURCE kafka_users
FROM KAFKA CONNECTION kafka_conn (TOPIC 'users')
FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn
ENVELOPE UPSERT;                   -- 指定 UPSERT envelope
```

## 物化视图自动处理 UPSERT


## 当上游数据通过 SOURCE UPSERT 时，物化视图自动增量更新

```sql
CREATE MATERIALIZED VIEW user_stats AS
SELECT COUNT(*) AS total_users, AVG(age) AS avg_age
FROM users;
```

## UPSERT SOURCE 数据后，user_stats 自动更新

## 模拟 UPSERT 的变通方案


## 方法: 使用去重视图（取最新版本）

```sql
CREATE SOURCE raw_events
FROM KAFKA CONNECTION kafka_conn (TOPIC 'events')
FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn
ENVELOPE UPSERT;
```

## 物化视图自动维护每个 key 的最新状态

```sql
CREATE MATERIALIZED VIEW latest_events AS
SELECT event_id, payload, occurred_at
FROM raw_events;
```

## 注意事项


## Materialize 不支持 INSERT ... ON CONFLICT（与 PostgreSQL 不兼容）

## 不支持 MERGE 语句

## TABLE 仅支持 INSERT，不支持 UPDATE / DELETE（流处理引擎定位）

## SOURCE 通过 ENVELOPE UPSERT 实现 Kafka 消息级别的 UPSERT

## 物化视图自动增量维护，无需手动刷新

## 如需表级 UPSERT，建议使用 PostgreSQL 作为上游，通过 CDC 同步
