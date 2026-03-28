# ksqlDB: 聚合函数

## 基本聚合（仅在 GROUP BY 或 窗口中使用）

```sql
CREATE TABLE user_stats AS
SELECT user_id,
    COUNT(*) AS event_count,
    SUM(amount) AS total_amount,
    AVG(amount) AS avg_amount,
    MIN(amount) AS min_amount,
    MAX(amount) AS max_amount
FROM orders
GROUP BY user_id
EMIT CHANGES;
```

## COUNT_DISTINCT（近似去重计数）

```sql
CREATE TABLE unique_users AS
SELECT page_url,
    COUNT_DISTINCT(user_id) AS unique_visitors
FROM pageviews
GROUP BY page_url
EMIT CHANGES;
```

## TOPK / TOPKDISTINCT

```sql
CREATE TABLE top_products AS
SELECT TOPK(product, 5) AS top_5_products
FROM orders
GROUP BY user_id
EMIT CHANGES;

CREATE TABLE top_distinct AS
SELECT TOPKDISTINCT(product, 5) AS top_5_distinct
FROM orders
GROUP BY user_id
EMIT CHANGES;
```

## COLLECT_LIST / COLLECT_SET

```sql
CREATE TABLE user_products AS
SELECT user_id,
    COLLECT_LIST(product) AS all_products,
    COLLECT_SET(product) AS unique_products
FROM orders
GROUP BY user_id
EMIT CHANGES;
```

## HISTOGRAM

```sql
CREATE TABLE product_histogram AS
SELECT HISTOGRAM(product) AS product_counts
FROM orders
GROUP BY user_id
EMIT CHANGES;
```

## EARLIEST_BY_OFFSET / LATEST_BY_OFFSET

```sql
CREATE TABLE latest_values AS
SELECT user_id,
    EARLIEST_BY_OFFSET(amount) AS first_amount,
    LATEST_BY_OFFSET(amount) AS last_amount
FROM orders
GROUP BY user_id
EMIT CHANGES;
```

## 窗口聚合

```sql
CREATE TABLE hourly_stats AS
SELECT user_id,
    COUNT(*) AS cnt,
    SUM(amount) AS total
FROM orders
WINDOW TUMBLING (SIZE 1 HOUR)
GROUP BY user_id
EMIT CHANGES;
```

注意：聚合函数必须配合 GROUP BY 使用
注意：COUNT_DISTINCT 是近似计算
注意：TOPK/TOPKDISTINCT 用于取 Top-N
注意：COLLECT_LIST/COLLECT_SET 收集值到数组
注意：不支持 HAVING 子句
