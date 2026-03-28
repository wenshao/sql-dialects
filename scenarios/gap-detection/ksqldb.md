# ksqlDB: 间隙检测与岛屿问题 (Gap Detection & Islands)

> 参考资料:
> - [ksqlDB Documentation - Queries](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/select-push-query/)
> - [ksqlDB Documentation - Window Functions](https://docs.ksqldb.io/en/latest/concepts/time-and-windows-in-ksqldb-queries/)
> - ============================================================
> - ksqlDB 是流处理引擎，间隙检测的概念与传统数据库不同
> - ============================================================
> - 创建流

```sql
CREATE STREAM orders_stream (
    id INT KEY,
    info VARCHAR
) WITH (
    KAFKA_TOPIC = 'orders',
    VALUE_FORMAT = 'JSON'
);
```

## ksqlDB 不支持传统的 LAG/LEAD 窗口函数

## 间隙检测主要通过 Session Window 实现


## 使用 Session Window 检测时间间隙

如果事件间隔超过窗口大小，则认为存在间隙

```sql
SELECT
    WINDOWSTART AS session_start,
    WINDOWEND   AS session_end,
    COUNT(*)    AS event_count
FROM orders_stream
WINDOW SESSION (1 HOUR)
GROUP BY id
EMIT CHANGES;
```

## 使用 Hopping/Tumbling Window 发现缺失时段


## 检测每小时是否有数据

```sql
SELECT
    WINDOWSTART AS hour_start,
    WINDOWEND   AS hour_end,
    COUNT(*)    AS event_count
FROM orders_stream
WINDOW TUMBLING (SIZE 1 HOUR)
GROUP BY id
EMIT CHANGES;
```

## 创建物化视图检测间隙


```sql
CREATE TABLE order_counts AS
SELECT id,
       COUNT(*) AS total_count,
       WINDOWSTART AS window_start
FROM orders_stream
WINDOW TUMBLING (SIZE 1 DAY)
GROUP BY id
EMIT CHANGES;
```

## 4-6. ksqlDB 的局限性


ksqlDB 不支持：
递归 CTE
自连接（流与流的自连接有限制）
generate_series 等序列生成
ROW_NUMBER / LEAD / LAG 分析函数
间隙检测推荐在下游消费者（如 Flink、Spark）中处理
注意：ksqlDB 是流处理引擎，不适合传统的间隙与岛屿分析
注意：使用 Session Window 可以间接检测事件流中的时间间隙
注意：复杂的间隙分析建议使用 Kafka Streams 或 Flink
注意：ksqlDB 的窗口函数仅支持聚合窗口，不支持分析窗口
