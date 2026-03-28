# BigQuery: 表分区策略

> 参考资料:
> - [1] Google Cloud - Partitioned Tables
>   https://cloud.google.com/bigquery/docs/partitioned-tables
> - [2] Google Cloud - Clustered Tables
>   https://cloud.google.com/bigquery/docs/clustered-tables


## 时间分区（最常用）


按日期列分区

```sql
CREATE TABLE `project.dataset.orders` (
    id INT64,
    user_id INT64,
    amount NUMERIC,
    order_date DATE
)
PARTITION BY order_date;

```

按 TIMESTAMP 列分区（按日截断）

```sql
CREATE TABLE `project.dataset.events` (
    event_id STRING,
    event_time TIMESTAMP,
    data STRING
)
PARTITION BY TIMESTAMP_TRUNC(event_time, DAY);

```

按月/年分区

```sql
CREATE TABLE `project.dataset.monthly_data` (
    id INT64, value NUMERIC, created_at DATE
)
PARTITION BY DATE_TRUNC(created_at, MONTH);

```

## 摄取时间分区


按数据加载时间分区（不需要分区列）

```sql
CREATE TABLE `project.dataset.logs` (
    message STRING, level STRING
)
PARTITION BY _PARTITIONDATE;

```

查询时使用伪列

```sql
SELECT * FROM `project.dataset.logs`
WHERE _PARTITIONDATE = '2024-01-15';

```

## 整数范围分区


```sql
CREATE TABLE `project.dataset.users` (
    id INT64, username STRING, age INT64
)
PARTITION BY RANGE_BUCKET(id, GENERATE_ARRAY(0, 1000000, 10000));

```

## 聚簇表（Clustering）


聚簇进一步优化分区内的数据排列

```sql
CREATE TABLE `project.dataset.orders` (
    id INT64, user_id INT64, amount NUMERIC,
    order_date DATE, region STRING
)
PARTITION BY order_date
CLUSTER BY region, user_id;

```

 最多 4 个聚簇列

## 分区过期


```sql
CREATE TABLE `project.dataset.temp_data` (
    id INT64, data STRING, created DATE
)
PARTITION BY created
OPTIONS (
    partition_expiration_days = 90  -- 分区 90 天后自动删除
);

```

## 分区裁剪


查询时过滤分区列实现分区裁剪

```sql
SELECT * FROM `project.dataset.orders`
WHERE order_date = '2024-06-15';  -- 只扫描一个分区

SELECT * FROM `project.dataset.orders`
WHERE order_date BETWEEN '2024-01-01' AND '2024-03-31';

```

## 分区管理


删除特定分区数据

```sql
DELETE FROM `project.dataset.orders`
WHERE order_date = '2023-01-01';

```

 复制分区
 bq cp project:dataset.orders$20240101 project:dataset.orders_backup$20240101

## 查看分区信息


```sql
SELECT table_name, partition_id, total_rows, total_logical_bytes
FROM `project.dataset.INFORMATION_SCHEMA.PARTITIONS`
WHERE table_name = 'orders'
ORDER BY partition_id;

```

注意：BigQuery 分区主要基于时间列（DATE / TIMESTAMP）
注意：分区 + 聚簇（Clustering）组合使用效果最好
注意：分区裁剪直接减少扫描量和费用
注意：partition_expiration_days 自动清理过期分区
注意：_PARTITIONDATE 伪列用于摄取时间分区
注意：最多 4000 个分区限制

