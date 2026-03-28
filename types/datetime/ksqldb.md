# ksqlDB: 日期时间类型

> 参考资料:
> - [ksqlDB Reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/)
> - [ksqlDB API Reference](https://docs.ksqldb.io/en/latest/developer-guide/api/)


TIMESTAMP: 毫秒精度的日期时间
DATE: 日期
TIME: 时间

```sql
CREATE STREAM events (
    event_id    VARCHAR KEY,
    event_time  TIMESTAMP,
    event_date  DATE,
    event_hour  TIME,
    epoch_ms    BIGINT
) WITH (
    KAFKA_TOPIC = 'events_topic',
    VALUE_FORMAT = 'JSON',
    TIMESTAMP = 'epoch_ms'
);
```

## ROWTIME（内置时间戳）


## 每条记录都有 ROWTIME（Kafka 消息时间戳）

```sql
SELECT event_id, ROWTIME FROM events EMIT CHANGES;
```

## 使用自定义时间戳列

TIMESTAMP = 'event_time' 在 WITH 子句中指定

## 时间函数


## 字符串转时间

```sql
SELECT STRINGTOTIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss')
FROM events EMIT CHANGES;
```

## 时间转字符串

```sql
SELECT TIMESTAMPTOSTRING(ROWTIME, 'yyyy-MM-dd HH:mm:ss')
FROM events EMIT CHANGES;
```

## 类型转换

```sql
SELECT CAST('2024-01-15' AS DATE) FROM events EMIT CHANGES;
SELECT CAST('10:30:00' AS TIME) FROM events EMIT CHANGES;
```

## 从 Unix 毫秒转换

```sql
SELECT FROM_UNIXTIME(epoch_ms) FROM events EMIT CHANGES;
```

## 转 Unix 毫秒

```sql
SELECT UNIX_TIMESTAMP() FROM events EMIT CHANGES;
```

## 时间运算


## 时间戳算术（毫秒单位）

```sql
SELECT ROWTIME + 3600000 AS one_hour_later FROM events EMIT CHANGES;  -- +1小时
```

## 窗口中的时间


```sql
SELECT event_id,
    WINDOWSTART AS window_start,
    WINDOWEND AS window_end,
    TIMESTAMPTOSTRING(WINDOWSTART, 'yyyy-MM-dd HH:mm:ss') AS start_str
FROM events
WINDOW TUMBLING (SIZE 1 HOUR)
GROUP BY event_id
EMIT CHANGES;
```

注意：TIMESTAMP 是毫秒精度
注意：ROWTIME 是每条消息的内置时间戳
注意：没有 INTERVAL 类型
注意：时间运算基于毫秒
注意：不支持时区转换函数
