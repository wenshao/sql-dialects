# ksqlDB: 数据去重策略（Deduplication）

> 参考资料:
> - [ksqlDB Reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/)
> - ============================================================
> - 示例数据上下文
> - ============================================================
> - 假设 STREAM / TABLE:
> - CREATE STREAM events (event_id VARCHAR KEY, user_id VARCHAR, event_type VARCHAR)
> - WITH (KAFKA_TOPIC='events', VALUE_FORMAT='JSON');
> - ============================================================
> - 注意：ksqlDB 是流处理引擎，去重方式与传统数据库不同
> - ============================================================
> - ============================================================
> - 1. TABLE 天然去重（基于 KEY）
> - ============================================================
> - TABLE 基于 PRIMARY KEY 保留最新值（变更日志语义）

```sql
CREATE TABLE users (
    user_id VARCHAR PRIMARY KEY,
    email VARCHAR,
    username VARCHAR
) WITH (
    KAFKA_TOPIC = 'users_topic',
    VALUE_FORMAT = 'JSON'
);
```

## 查询 TABLE 自动返回每个 KEY 的最新值（已去重）

```sql
SELECT * FROM users;
```

## 使用 LATEST_BY_OFFSET 去重


## 创建物化表，按 user_id 保留最新事件

```sql
CREATE TABLE latest_events AS
SELECT user_id,
       LATEST_BY_OFFSET(event_type) AS latest_event_type,
       LATEST_BY_OFFSET(event_id) AS latest_event_id
FROM events
GROUP BY user_id
EMIT CHANGES;
```

## 窗口去重


## TUMBLING 窗口内按 key 去重

```sql
CREATE TABLE hourly_unique_users AS
SELECT user_id,
       COUNT(*) AS event_count,
       WINDOWSTART AS window_start,
       WINDOWEND AS window_end
FROM events
WINDOW TUMBLING (SIZE 1 HOUR)
GROUP BY user_id
EMIT CHANGES;
```

## 近似去重


## COUNT_DISTINCT（精确，但状态可能较大）

```sql
CREATE TABLE distinct_users AS
SELECT event_type,
       COUNT_DISTINCT(user_id) AS unique_users
FROM events
GROUP BY event_type
EMIT CHANGES;
```

## 性能考量


ksqlDB TABLE 基于 KEY 天然去重
LATEST_BY_OFFSET 是流式去重的核心函数
不支持 ROW_NUMBER / DISTINCT ON / QUALIFY / DELETE
精确去重（COUNT_DISTINCT）状态可能很大
