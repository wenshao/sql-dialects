# Apache Impala: 表分区策略

> 参考资料:
> - [Impala Documentation - Partitioning](https://impala.apache.org/docs/build/html/topics/impala_partitioning.html)


## 分区表


```sql
CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2)
) PARTITIONED BY (order_date STRING)
  STORED AS PARQUET;
```


添加分区
```sql
ALTER TABLE orders ADD PARTITION (order_date='2024-06-15');
```


动态分区插入
```sql
INSERT INTO orders PARTITION (order_date)
SELECT id, user_id, amount, order_date FROM raw_orders;
```


## 多级分区


```sql
CREATE TABLE logs (id BIGINT, message STRING)
PARTITIONED BY (year INT, month INT, day INT)
STORED AS PARQUET;
```


## 分区管理


```sql
ALTER TABLE orders DROP PARTITION (order_date='2023-01-01');
ALTER TABLE orders ADD PARTITION (order_date='2024-07-01')
    LOCATION '/data/orders/2024-07-01';
```


刷新分区元数据
```sql
INVALIDATE METADATA orders;
REFRESH orders;
REFRESH orders PARTITION (order_date='2024-06-15');
```


## 分区裁剪


```sql
SELECT * FROM orders WHERE order_date = '2024-06-15';
-- 只扫描一个分区
```


查看分区统计
```sql
SHOW PARTITIONS orders;
```


注意：Impala 使用 Hive 风格分区
注意：分区对应 HDFS 目录
注意：INVALIDATE METADATA / REFRESH 用于同步元数据
注意：分区列不应有太高的基数
