# ClickHouse: 表分区策略

> 参考资料:
> - [1] ClickHouse Documentation - Table Engines (MergeTree)
>   https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree
> - [2] ClickHouse Documentation - Custom Partitioning Key
>   https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/custom-partitioning-key


## PARTITION BY（MergeTree 引擎）


按月分区

```sql
CREATE TABLE orders (
    id UInt64,
    user_id UInt64,
    amount Decimal(10,2),
    order_date Date
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(order_date)
ORDER BY (user_id, order_date);

```

按日分区

```sql
CREATE TABLE events (
    event_id UUID,
    event_time DateTime,
    data String
) ENGINE = MergeTree()
PARTITION BY toDate(event_time)
ORDER BY (event_time);

```

按年分区

```sql
CREATE TABLE historical_data (
    id UInt64, year UInt16, value Float64
) ENGINE = MergeTree()
PARTITION BY year
ORDER BY id;

```

复合分区键

```sql
CREATE TABLE sales (
    id UInt64, region String, sale_date Date, amount Decimal(10,2)
) ENGINE = MergeTree()
PARTITION BY (toYYYYMM(sale_date), region)
ORDER BY (sale_date, id);

```

## 分区管理


查看分区

```sql
SELECT partition, name, rows, bytes_on_disk
FROM system.parts
WHERE table = 'orders' AND active = 1
ORDER BY partition;

```

删除分区

```sql
ALTER TABLE orders DROP PARTITION 202301;

```

分离分区（移到 detached 目录）

```sql
ALTER TABLE orders DETACH PARTITION 202301;

```

附加分区

```sql
ALTER TABLE orders ATTACH PARTITION 202301;

```

清空分区

```sql
ALTER TABLE orders CLEAR COLUMN data IN PARTITION 202301;

```

替换分区（从另一个表移动）

```sql
ALTER TABLE orders REPLACE PARTITION 202401 FROM orders_staging;

```

移动分区到另一个表

```sql
ALTER TABLE orders MOVE PARTITION 202301 TO TABLE orders_archive;

```

冻结/解冻分区（备份用）

```sql
ALTER TABLE orders FREEZE PARTITION 202401;
ALTER TABLE orders UNFREEZE PARTITION 202401;

```

## TTL（数据过期自动删除）


```sql
CREATE TABLE logs (
    id UInt64,
    log_time DateTime,
    message String
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(log_time)
ORDER BY log_time
TTL log_time + INTERVAL 90 DAY;  -- 90 天后自动删除

```

列级 TTL

```sql
CREATE TABLE metrics (
    id UInt64, time DateTime,
    value Float64,
    details String TTL time + INTERVAL 30 DAY  -- 30 天后清除此列
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(time)
ORDER BY time;

```

TTL 移动到不同存储

```sql
CREATE TABLE tiered_data (
    id UInt64, time DateTime, data String
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(time)
ORDER BY time
TTL time + INTERVAL 30 DAY TO VOLUME 'cold',
    time + INTERVAL 365 DAY DELETE;

```

## 分区裁剪


ClickHouse 自动进行分区裁剪

```sql
SELECT * FROM orders WHERE order_date >= '2024-01-01' AND order_date < '2024-02-01';
```

只扫描 202401 分区

查看分区裁剪效果

```sql
EXPLAIN ESTIMATE SELECT * FROM orders WHERE order_date = '2024-06-15';

```

## 最佳实践


分区数量建议：不要太多（数百个以内）
每个分区的数据量：至少数百万行
ORDER BY 键比分区键更重要（用于数据跳过）

注意：ClickHouse 分区是 MergeTree 引擎的特性
注意：分区主要用于数据管理（删除/移动），不是查询优化的主要手段
注意：ORDER BY（主键）的 Granule 跳过是查询优化的核心
注意：TTL 可以自动删除过期数据或移动到冷存储
注意：REPLACE PARTITION 可以原子性地替换分区数据
注意：分区数量不宜过多（建议数百个以内）

