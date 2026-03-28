# ksqlDB: 窗口函数

> 参考资料:
> - [ksqlDB Reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/)
> - [ksqlDB API Reference](https://docs.ksqldb.io/en/latest/developer-guide/api/)
> - ksqlDB 提供流式窗口聚合（不是传统 SQL 窗口函数）
> - 三种窗口类型：TUMBLING, HOPPING, SESSION
> - ============================================================
> - TUMBLING 窗口（固定大小，不重叠）
> - ============================================================
> - 每小时统计

```sql
CREATE TABLE hourly_counts AS
SELECT user_id,
       COUNT(*) AS event_count,
       SUM(amount) AS total_amount
FROM orders
WINDOW TUMBLING (SIZE 1 HOUR)
GROUP BY user_id
EMIT CHANGES;
```

## 每天统计

```sql
CREATE TABLE daily_stats AS
SELECT user_id,
       COUNT(*) AS order_count,
       AVG(amount) AS avg_amount
FROM orders
WINDOW TUMBLING (SIZE 1 DAY)
GROUP BY user_id
EMIT CHANGES;
```

## 每 5 分钟统计

```sql
CREATE TABLE five_min_counts AS
SELECT page_url, COUNT(*) AS view_count
FROM pageviews
WINDOW TUMBLING (SIZE 5 MINUTES)
GROUP BY page_url
EMIT CHANGES;
```

## HOPPING 窗口（固定大小，可重叠）


## 窗口大小 1 小时，每 10 分钟推进一次

```sql
CREATE TABLE hopping_counts AS
SELECT user_id,
       COUNT(*) AS event_count
FROM orders
WINDOW HOPPING (SIZE 1 HOUR, ADVANCE BY 10 MINUTES)
GROUP BY user_id
EMIT CHANGES;
```

## 窗口大小 24 小时，每 1 小时推进

```sql
CREATE TABLE rolling_24h AS
SELECT user_id,
       SUM(amount) AS rolling_total
FROM orders
WINDOW HOPPING (SIZE 24 HOURS, ADVANCE BY 1 HOUR)
GROUP BY user_id
EMIT CHANGES;
```

## SESSION 窗口（基于活动间隔）


## 30 分钟无活动则视为新会话

```sql
CREATE TABLE user_sessions AS
SELECT user_id,
       COUNT(*) AS event_count,
       MIN(ROWTIME) AS session_start,
       MAX(ROWTIME) AS session_end
FROM pageviews
WINDOW SESSION (30 MINUTES)
GROUP BY user_id
EMIT CHANGES;
```

## GRACE PERIOD（宽限期，处理延迟数据）


```sql
CREATE TABLE windowed_counts AS
SELECT user_id, COUNT(*) AS cnt
FROM orders
WINDOW TUMBLING (SIZE 1 HOUR, GRACE PERIOD 10 MINUTES)
GROUP BY user_id
EMIT CHANGES;
```

## 窗口边界查询


## 使用 WINDOWSTART 和 WINDOWEND

```sql
SELECT user_id,
       WINDOWSTART AS window_start,
       WINDOWEND AS window_end,
       COUNT(*) AS cnt
FROM orders
WINDOW TUMBLING (SIZE 1 HOUR)
GROUP BY user_id
EMIT CHANGES;
```

## Pull Query 查询特定窗口

```sql
SELECT * FROM hourly_counts
WHERE user_id = 'user_123'
    AND WINDOWSTART >= '2024-01-15T00:00:00'
    AND WINDOWEND <= '2024-01-15T01:00:00';
```

## 不支持的窗口函数


不支持 ROW_NUMBER, RANK, DENSE_RANK
不支持 LAG, LEAD
不支持 FIRST_VALUE, LAST_VALUE
不支持 NTILE, PERCENT_RANK, CUME_DIST
不支持 ROWS BETWEEN ... AND ...
注意：ksqlDB 的窗口是流式处理窗口，不是 SQL 分析窗口
注意：三种窗口：TUMBLING（不重叠）、HOPPING（重叠）、SESSION（会话）
注意：GRACE PERIOD 用于处理延迟到达的数据
注意：窗口查询必须配合 GROUP BY 使用
注意：不支持传统 SQL 窗口函数（ROW_NUMBER, LAG 等）
