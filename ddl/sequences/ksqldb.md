# ksqlDB: Sequences & Auto-Increment

> 参考资料:
> - [ksqlDB Documentation - Data Types](https://docs.ksqldb.io/en/latest/reference/sql/data-types/)
> - [ksqlDB Documentation - Scalar Functions](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/scalar-functions/)
> - ============================================
> - ksqlDB 是流处理引擎，不支持传统的序列和自增
> - ============================================
> - 不支持 CREATE SEQUENCE
> - 不支持 AUTO_INCREMENT / IDENTITY / SERIAL
> - ============================================
> - 替代方案
> - ============================================
> - 方法 1：使用 Kafka 消息的 KEY 作为标识符
> - Kafka 消息天然有 offset，可作为序列号

```sql
CREATE STREAM events (
    id VARCHAR KEY,                          -- Kafka Key 作为标识符
    event_type VARCHAR,
    event_data VARCHAR
) WITH (
    KAFKA_TOPIC = 'events',
    VALUE_FORMAT = 'JSON',
    KEY_FORMAT = 'KAFKA'
);
```

方法 2：使用 ROWOFFSET / ROWPARTITION（ksqlDB 0.25+）
查询时获取 Kafka 的 offset 信息
SELECT ROWOFFSET, ROWPARTITION, * FROM events EMIT CHANGES;
方法 3：在上游（生产者端）生成 UUID
Kafka 生产者在发送消息时生成 UUID 作为 Key
方法 4：使用 AS_VALUE 复制 Key 到 Value

```sql
CREATE STREAM events_with_id AS
SELECT
    id,
    AS_VALUE(id) AS event_id,               -- 将 Key 复制到 Value 中
    event_type,
    event_data
FROM events
EMIT CHANGES;
```

## 序列 vs 自增 权衡

ksqlDB 是流处理引擎，设计理念不同于 OLTP：
1. 事件的唯一性由 Kafka Key 或 Topic offset 保证
2. 不需要数据库级别的自增序列
3. UUID 应在生产者端（应用层）生成
4. ROWOFFSET 提供了 Kafka 级别的消息序号
限制：
不支持 CREATE SEQUENCE
不支持 AUTO_INCREMENT / IDENTITY / SERIAL
不支持 GENERATED AS IDENTITY
不支持 UUID 生成函数（需在应用层生成）
