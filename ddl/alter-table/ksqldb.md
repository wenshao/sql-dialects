# ksqlDB: ALTER TABLE / ALTER STREAM

> 参考资料:
> - [ksqlDB Reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/)
> - [ksqlDB API Reference](https://docs.ksqldb.io/en/latest/developer-guide/api/)
> - ksqlDB 的 ALTER 功能非常有限
> - 主要通过重建 STREAM/TABLE 实现 schema 变更
> - ============================================================
> - ALTER STREAM（仅支持有限操作）
> - ============================================================
> - 目前 ksqlDB 不支持传统的 ALTER STREAM ADD COLUMN
> - schema 变更通常通过重建实现
> - 方式一：使用 CREATE OR REPLACE 重建

```sql
CREATE OR REPLACE STREAM pageviews (
    user_id    VARCHAR KEY,
    page_url   VARCHAR,
    view_time  BIGINT,
    referrer   VARCHAR                -- 新增列
) WITH (
    KAFKA_TOPIC = 'pageviews_topic',
    VALUE_FORMAT = 'JSON'
);
```

## 方式二：创建新 STREAM 映射同一 topic（schema 已在 topic 中更新）

```sql
DROP STREAM IF EXISTS pageviews;
CREATE STREAM pageviews (
    user_id    VARCHAR KEY,
    page_url   VARCHAR,
    view_time  BIGINT,
    referrer   VARCHAR
) WITH (
    KAFKA_TOPIC = 'pageviews_topic',
    VALUE_FORMAT = 'JSON'
);
```

## 修改持久查询


## 不能直接修改持久查询，需要先终止再重建

查看运行中的查询

```sql
SHOW QUERIES;
```

## 终止查询

```sql
TERMINATE QUERY_ID;
TERMINATE ALL;
```

## 重建持久查询

```sql
CREATE OR REPLACE STREAM enriched_orders AS
SELECT o.order_id, o.amount, o.product, u.username
FROM orders o
LEFT JOIN users u ON o.user_id = u.user_id
EMIT CHANGES;
```

## DROP 操作


```sql
DROP STREAM IF EXISTS pageviews;
DROP STREAM IF EXISTS pageviews DELETE TOPIC;    -- 同时删除 Kafka topic
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS users DELETE TOPIC;
```

注意：ksqlDB 不支持 ALTER STREAM/TABLE ADD COLUMN
注意：schema 变更主要通过 DROP + CREATE 或 CREATE OR REPLACE 实现
注意：使用 Avro/Protobuf 格式时，schema 由 Schema Registry 管理
注意：DROP ... DELETE TOPIC 会同时删除底层 Kafka topic
