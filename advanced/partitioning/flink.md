# Flink SQL: 分区

> 参考资料:
> - [Flink Documentation - Partitions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/alter/#add-partition)
> - [Flink Documentation - Filesystem Connector](https://nightlies.apache.org/flink/flink-docs-stable/docs/connectors/table/filesystem/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

## 分区表（文件系统连接器）


```sql
CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2),
    dt STRING, hr STRING
) PARTITIONED BY (dt, hr) WITH (
    'connector' = 'filesystem',
    'path' = 'hdfs:///data/orders',
    'format' = 'parquet'
);

```

## Hive 分区表


```sql
CREATE TABLE hive_orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2)
) PARTITIONED BY (order_date STRING) WITH (
    'connector' = 'hive',
    'hive.database' = 'mydb'
);

```

## 分区管理


添加分区
```sql
ALTER TABLE orders ADD PARTITION (dt='2024-06-15', hr='10');

```

删除分区
```sql
ALTER TABLE orders DROP PARTITION (dt='2024-06-15', hr='10');

```

## 动态分区写入


流式写入自动创建分区
```sql
INSERT INTO orders
SELECT id, user_id, amount,
       DATE_FORMAT(order_time, 'yyyy-MM-dd') AS dt,
       DATE_FORMAT(order_time, 'HH') AS hr
FROM order_stream;

```

## 分区提交策略


配置分区提交
```sql
CREATE TABLE partitioned_sink (
    id BIGINT, data STRING, dt STRING
) PARTITIONED BY (dt) WITH (
    'connector' = 'filesystem',
    'path' = '/output',
    'format' = 'parquet',
    'sink.partition-commit.trigger' = 'partition-time',
    'sink.partition-commit.delay' = '1 h',
    'sink.partition-commit.policy.kind' = 'success-file'
);

```

**注意:** Flink 分区主要用于文件系统和 Hive 连接器
**注意:** 流式写入可以动态创建分区
**注意:** 分区提交策略控制何时认为分区数据完整
**注意:** Kafka 连接器不使用表级分区（使用 Kafka 分区）
