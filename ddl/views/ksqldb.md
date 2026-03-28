# ksqlDB: Views

> 参考资料:
> - [ksqlDB Documentation - CREATE STREAM / TABLE](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/create-stream/)
> - [ksqlDB Documentation - Materialized Views](https://docs.ksqldb.io/en/latest/concepts/materialized-views/)
> - [ksqlDB Documentation - CREATE TABLE AS SELECT](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/create-table-as-select/)


ksqlDB 没有传统的 CREATE VIEW
使用 CREATE STREAM AS SELECT / CREATE TABLE AS SELECT 替代
这些在 ksqlDB 中被称为"持久化查询"或"物化视图"


## 基于 STREAM 的派生流（类似视图）

首先定义源 STREAM
CREATE STREAM users_stream (
id BIGINT KEY,
username VARCHAR,
email VARCHAR,
age INT
) WITH (
KAFKA_TOPIC = 'users',
VALUE_FORMAT = 'JSON'
);
创建派生 STREAM（持续查询，实时处理）

```sql
CREATE STREAM active_users AS
SELECT id, username, email
FROM users_stream
WHERE age >= 18
EMIT CHANGES;
```

## 物化视图 (TABLE AS SELECT)

ksqlDB 的核心概念：物化表是持续更新的聚合

```sql
CREATE TABLE order_summary AS
SELECT
    user_id,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM orders_stream
GROUP BY user_id
EMIT CHANGES;
```

## 带窗口的物化视图

```sql
CREATE TABLE windowed_order_stats AS
SELECT
    user_id,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM orders_stream
WINDOW TUMBLING (SIZE 1 HOUR)
GROUP BY user_id
EMIT CHANGES;
```

## Pull Query（即时查询物化视图的当前状态）

SELECT * FROM order_summary WHERE user_id = 42;
Push Query（持续订阅物化视图的变更）
SELECT * FROM order_summary EMIT CHANGES;

## 可更新视图

ksqlDB 的 TABLE 不可直接更新

## 数据通过 Kafka Topic 流入

## 删除

```sql
DROP STREAM active_users;
DROP STREAM IF EXISTS active_users;
DROP STREAM active_users DELETE TOPIC;       -- 同时删除底层 Kafka Topic

DROP TABLE order_summary;
DROP TABLE IF EXISTS order_summary;
DROP TABLE order_summary DELETE TOPIC;
```

限制：
不支持传统的 CREATE VIEW
所有查询都是持续运行的流处理任务
TABLE AS SELECT 是 ksqlDB 的"物化视图"
Pull Query 仅支持对物化表的主键查询
不支持 WITH CHECK OPTION
