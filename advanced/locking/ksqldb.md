# ksqlDB: 锁机制 (Locking)

> 参考资料:
> - [ksqlDB Documentation - Concepts](https://docs.ksqldb.io/en/latest/concepts/)
> - [ksqlDB Documentation - Processing Guarantees](https://docs.ksqldb.io/en/latest/operate-and-deploy/exactly-once-semantics/)
> - ============================================================
> - ksqlDB 并发模型概述
> - ============================================================
> - ksqlDB 是基于 Kafka Streams 的流式 SQL 引擎:
> - 1. 不支持传统的锁机制
> - 2. 数据通过 Kafka topics 流入流出
> - 3. 使用 Kafka Streams 的分区级并行处理
> - 4. 不支持事务 (BEGIN/COMMIT)
> - 5. 通过 Kafka 的 exactly-once 语义保证一致性
> - ============================================================
> - 流处理中的并发
> - ============================================================
> - 创建流（对应 Kafka topic 的分区并行处理）

```sql
CREATE STREAM orders_stream (
    id BIGINT KEY,
    status VARCHAR,
    amount DECIMAL(10,2)
) WITH (
    KAFKA_TOPIC = 'orders',
    VALUE_FORMAT = 'JSON',
    PARTITIONS = 8                -- 分区数决定最大并行度
);
```

## 创建物化表（通过 Kafka 的压缩 topic 维护状态）

```sql
CREATE TABLE order_counts AS
SELECT status, COUNT(*) AS cnt
FROM orders_stream
GROUP BY status;
```

## 处理保证


Exactly-once 语义（通过 Kafka 事务实现）
在 ksqlDB server 配置中启用:
processing.guarantee = exactly_once_v2
At-least-once（默认）
processing.guarantee = at_least_once

## 注意事项


## 不支持传统锁机制

## 不支持 SELECT FOR UPDATE / FOR SHARE

## 不支持 LOCK TABLE

## 并发通过 Kafka 分区并行处理

## 一致性通过 Kafka exactly-once 语义保证

## pull query 读取物化视图的最新状态

## push query 持续推送更新
