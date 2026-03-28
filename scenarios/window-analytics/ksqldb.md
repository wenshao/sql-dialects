# ksqlDB: 窗口函数实战分析

> 参考资料:
> - [ksqlDB Documentation - Window Functions](https://docs.ksqldb.io/en/latest/concepts/time-and-windows-in-ksqldb-queries/)
> - [ksqlDB Documentation - Aggregate Functions](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/aggregate-functions/)


ksqlDB 窗口处理与传统 SQL 完全不同
ksqlDB 使用流/表上的时间窗口进行聚合
不支持传统的 OVER() 窗口函数
支持三种窗口：TUMBLING, HOPPING, SESSION


假设:
CREATE STREAM sales_events (
product_id VARCHAR KEY, sale_date VARCHAR, amount DOUBLE,
region VARCHAR
) WITH (KAFKA_TOPIC='sales', VALUE_FORMAT='JSON');

## 移动平均（使用 HOPPING 窗口）


## 滑动窗口：每分钟计算过去 7 天的平均值（流处理方式）

```sql
SELECT product_id,
       WINDOWSTART AS window_start,
       WINDOWEND AS window_end,
       AVG(amount) AS avg_amount,
       COUNT(*) AS sale_count
FROM sales_events
WINDOW HOPPING (SIZE 7 DAYS, ADVANCE BY 1 DAY)
GROUP BY product_id
EMIT CHANGES;
```

## 滚动窗口聚合（代替同比/环比）


## 每月销售汇总

```sql
SELECT product_id,
       WINDOWSTART AS month_start,
       WINDOWEND AS month_end,
       SUM(amount) AS monthly_total,
       COUNT(*) AS order_count
FROM sales_events
WINDOW TUMBLING (SIZE 30 DAYS)
GROUP BY product_id
EMIT CHANGES;
```

## 每小时聚合

```sql
SELECT region,
       WINDOWSTART AS hour_start,
       SUM(amount) AS hourly_total,
       AVG(amount) AS hourly_avg
FROM sales_events
WINDOW TUMBLING (SIZE 1 HOUR)
GROUP BY region
EMIT CHANGES;
```

## 会话窗口（Sessionization）


ksqlDB 内建 SESSION 窗口
CREATE STREAM user_clicks (
user_id VARCHAR KEY, event_time VARCHAR,
event_type VARCHAR, page VARCHAR
) WITH (KAFKA_TOPIC='clicks', VALUE_FORMAT='JSON');
30 分钟无活动则结束会话

```sql
SELECT user_id,
       WINDOWSTART AS session_start,
       WINDOWEND AS session_end,
       COUNT(*) AS event_count,
       COLLECT_LIST(event_type) AS event_types
FROM user_clicks
WINDOW SESSION (30 MINUTES)
GROUP BY user_id
EMIT CHANGES;
```

## 简单聚合（无窗口函数）


## 创建持续聚合表

```sql
CREATE TABLE sales_by_product AS
SELECT product_id,
       COUNT(*) AS total_orders,
       SUM(amount) AS total_amount,
       AVG(amount) AS avg_amount,
       MIN(amount) AS min_amount,
       MAX(amount) AS max_amount
FROM sales_events
GROUP BY product_id
EMIT CHANGES;
```

## TOPK / TOPKDISTINCT（ksqlDB 特有）

```sql
SELECT region,
       TOPK(amount, 5) AS top_5_amounts,
       TOPKDISTINCT(product_id, 10) AS top_10_products
FROM sales_events
WINDOW TUMBLING (SIZE 1 DAY)
GROUP BY region
EMIT CHANGES;
```

## 时间处理


## EARLIEST_BY_OFFSET / LATEST_BY_OFFSET

```sql
SELECT product_id,
       EARLIEST_BY_OFFSET(amount) AS first_amount,
       LATEST_BY_OFFSET(amount) AS latest_amount
FROM sales_events
GROUP BY product_id
EMIT CHANGES;
```

## 注意事项

ksqlDB 是流处理引擎，不是传统数据库
不支持传统的 OVER() 窗口函数
不支持 LAG, LEAD, RANK, DENSE_RANK 等
不支持 PERCENTILE, NTILE 等
窗口类型: TUMBLING（滚动）, HOPPING（滑动）, SESSION（会话）
EMIT CHANGES 表示持续输出结果
所有查询都是持久化的流处理任务
