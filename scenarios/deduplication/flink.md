# Flink SQL: 数据去重

> 参考资料:
> - [Flink Documentation - Deduplication](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/deduplication/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

## 示例数据上下文

假设表结构:
  events(event_id INT, user_id INT, event_type VARCHAR, event_time TIMESTAMP(3),
         WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND)

## 流式去重（Flink 内置模式识别）


Flink 自动识别去重模式（ROW_NUMBER + WHERE rn = 1）
按 event_time 保留最早记录
```sql
SELECT event_id, user_id, event_type, event_time
FROM (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY user_id
               ORDER BY event_time ASC
           ) AS rn
    FROM events
)
WHERE rn = 1;

```

按 event_time 保留最新记录
```sql
SELECT event_id, user_id, event_type, event_time
FROM (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY user_id
               ORDER BY event_time DESC
           ) AS rn
    FROM events
)
WHERE rn = 1;

```

## 按 Processing Time 去重


```sql
SELECT event_id, user_id, event_type, event_time
FROM (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY user_id
               ORDER BY PROCTIME() ASC
           ) AS rn
    FROM events
)
WHERE rn = 1;

```

## 查找重复（批模式）


```sql
SELECT user_id, COUNT(*) AS cnt
FROM events
GROUP BY user_id
HAVING COUNT(*) > 1;

```

## DISTINCT 聚合


```sql
SELECT COUNT(DISTINCT user_id) AS unique_users
FROM events;

```

## 性能考量


Flink 自动识别去重模式（ROW_NUMBER + WHERE rn = 1）
流式去重是增量计算，状态大小与不同 key 数量成正比
建议设置状态 TTL 防止无限增长
ORDER BY event_time ASC：保留最早记录
ORDER BY event_time DESC：保留最新记录
ORDER BY PROCTIME()：按处理时间去重
