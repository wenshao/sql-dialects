# Trino: 分区

> 参考资料:
> - [Trino Documentation - Hive Connector (Partitioning)](https://trino.io/docs/current/connector/hive.html#partitioned-tables)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

## Hive Connector 分区


```sql
CREATE TABLE hive.mydb.orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2)
) WITH (
    format = 'PARQUET',
    partitioned_by = ARRAY['order_date']
);

```

添加分区数据
```sql
INSERT INTO hive.mydb.orders VALUES (1, 100, 99.99, DATE '2024-06-15');

```

查询（分区裁剪）
```sql
SELECT * FROM hive.mydb.orders WHERE order_date = DATE '2024-06-15';

```

管理分区
```sql
CALL hive.system.create_empty_partition('mydb', 'orders', ARRAY['order_date'], ARRAY['2024-07-01']);

```

## Iceberg Connector 分区


```sql
CREATE TABLE iceberg.mydb.events (
    event_id BIGINT, event_time TIMESTAMP, data VARCHAR
) WITH (
    format = 'PARQUET',
    partitioning = ARRAY['day(event_time)']
);

```

分区变换：year, month, day, hour, bucket, truncate

## Delta Lake Connector 分区


```sql
CREATE TABLE delta.mydb.logs (
    id BIGINT, log_date DATE, message VARCHAR
) WITH (
    location = 's3://bucket/logs',
    partitioned_by = ARRAY['log_date']
);

```

**注意:** Trino 的分区取决于底层 Connector
**注意:** Hive/Iceberg/Delta Lake 各有不同的分区语法
**注意:** Iceberg 支持分区变换（day, month, bucket 等）
**注意:** 分区裁剪在查询时自动进行
