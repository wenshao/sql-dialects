# ksqlDB: DELETE

> 参考资料:
> - [ksqlDB Reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/)
> - [ksqlDB API Reference](https://docs.ksqldb.io/en/latest/developer-guide/api/)
> - ksqlDB 不支持 DELETE 语句
> - 数据删除通过其他机制实现
> - ============================================================
> - TABLE 删除（通过 Kafka tombstone 消息）
> - ============================================================
> - TABLE 中的记录可以通过发送 tombstone（NULL value）消息删除
> - 这需要通过 Kafka Producer API 完成，不是 ksqlDB SQL
> - 在 Kafka 中发送 tombstone 消息：
> - 发送 key=user_123, value=null 到 users_topic
> - ksqlDB TABLE 会自动删除 user_123 的记录
> - ============================================================
> - STREAM 不支持删除
> - ============================================================
> - STREAM 是不可变的追加流（append-only）
> - 每条记录都是独立的事件，不能删除
> - ============================================================
> - 删除 STREAM / TABLE（DDL 删除）
> - ============================================================
> - 删除 STREAM（仅删除 ksqlDB 定义，不删 Kafka topic）

```sql
DROP STREAM IF EXISTS pageviews;
```

## 删除 STREAM 并同时删除 Kafka topic

```sql
DROP STREAM IF EXISTS pageviews DELETE TOPIC;
```

## 删除 TABLE

```sql
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS users DELETE TOPIC;
```

## 数据保留（通过 Kafka Topic 配置）


Kafka Topic 的数据保留由 Kafka 配置控制
retention.ms: 消息保留时间
retention.bytes: 消息保留大小
创建 STREAM 时指定 Topic 配置

```sql
CREATE STREAM events (
    event_id VARCHAR KEY,
    event_type VARCHAR
) WITH (
    KAFKA_TOPIC = 'events_topic',
    VALUE_FORMAT = 'JSON',
    PARTITIONS = 6,
    REPLICAS = 3
);
```

## 终止持久查询


## 查看运行中的查询

```sql
SHOW QUERIES;
```

## 终止指定查询

```sql
TERMINATE QUERY_ID;
```

## 终止所有查询

```sql
TERMINATE ALL;
```

注意：ksqlDB 不支持 DELETE 语句
注意：TABLE 通过 Kafka tombstone 消息实现删除
注意：STREAM 是不可变的，不能删除记录
注意：数据保留由 Kafka Topic 配置控制
注意：DROP STREAM/TABLE DELETE TOPIC 会同时删除底层 Topic
