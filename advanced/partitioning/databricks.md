# Databricks SQL: 表分区策略

> 参考资料:
> - [Databricks Documentation - Delta Lake Partitioning](https://docs.databricks.com/delta/best-practices.html#choose-the-right-partition-column)


## Delta Lake 分区


```sql
CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2), order_date DATE
) USING DELTA PARTITIONED BY (order_date);
```


插入（自动分区）
```sql
INSERT INTO orders VALUES (1, 100, 99.99, '2024-06-15');
```


分区裁剪
```sql
SELECT * FROM orders WHERE order_date = '2024-06-15';
```


## OPTIMIZE + ZORDER


文件合并优化
```sql
OPTIMIZE orders WHERE order_date >= '2024-01-01';
```


Z-ORDER 多维聚簇
```sql
OPTIMIZE orders ZORDER BY (user_id);
```


## Liquid Clustering（Databricks 13.3+）


替代传统分区 + ZORDER 的新方式
```sql
CREATE TABLE events (
    event_id BIGINT, event_time TIMESTAMP, user_id BIGINT, data STRING
) USING DELTA CLUSTER BY (event_time, user_id);
```


触发聚簇
```sql
OPTIMIZE events;
```


## 分区管理


删除分区数据
```sql
DELETE FROM orders WHERE order_date < '2023-01-01';
```


VACUUM 清理旧文件
```sql
VACUUM orders RETAIN 168 HOURS;
```


注意：Databricks 推荐 Delta Lake 格式
注意：OPTIMIZE + ZORDER 是传统的优化方式
注意：Liquid Clustering（13.3+）是更新的自动优化方式
注意：分区列应选择低基数列（如日期）
注意：VACUUM 清理不再需要的旧版本文件
