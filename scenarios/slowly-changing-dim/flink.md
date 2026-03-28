# Flink SQL: 缓慢变化维

> 参考资料:
> - [Flink Documentation - Temporal Join](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/joins/#temporal-joins)
> - [Flink Documentation - CDC Connectors](https://ververica.github.io/flink-cdc-connectors/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

## Flink 使用 Temporal Join 处理维度表变化

维度表（使用 CDC connector 实时同步）
```sql
CREATE TABLE dim_customer (
    customer_id STRING,
    name        STRING,
    city        STRING,
    tier        STRING,
    PRIMARY KEY (customer_id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'lookup.cache.max-rows' = '5000',
    'lookup.cache.ttl' = '10min'
);

```

事实流
```sql
CREATE TABLE orders_stream (
    order_id    STRING,
    customer_id STRING,
    amount      DOUBLE,
    order_time  TIMESTAMP(3),
    WATERMARK FOR order_time AS order_time - INTERVAL '5' SECOND
) WITH ('connector' = 'kafka', 'format' = 'json');

```

Temporal Join（查询时自动关联最新维度值）
```sql
SELECT o.order_id, o.amount, d.name, d.city, d.tier
FROM   orders_stream o
JOIN   dim_customer FOR SYSTEM_TIME AS OF o.order_time AS d
ON     o.customer_id = d.customer_id;

```

SCD Type 1 本质上由 CDC 源自动处理
SCD Type 2 需要在维度表中维护版本，Flink 在 join 时查找匹配时间的版本
