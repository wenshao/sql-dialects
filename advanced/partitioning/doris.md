# Apache Doris: 分区策略

 Apache Doris: 分区策略

 参考资料:
   [1] Doris Documentation - Data Partition
       https://doris.apache.org/docs/table-design/data-partition

## 1. 两层数据分布: PARTITION + BUCKET

 Doris 的数据分布是两层设计:
   第一层 PARTITION: 按值范围/列表裁剪(Partition Pruning)
   第二层 BUCKET:    按 Hash 分散负载(并行查询)

 每个 Partition × Bucket 组合 = 一个 Tablet(最小存储/调度单元)。

 对比:
   StarRocks:  相同的两层设计(同源)
   ClickHouse: PARTITION BY + ORDER BY(单层分区 + 排序)
   BigQuery:   PARTITION BY + CLUSTER BY(概念类似但自动管理)
   MySQL:      PARTITION BY RANGE/LIST/HASH(单层，无 Bucket)

 对引擎开发者的启示:
   两层分布的核心价值:
     PARTITION 解决"数据生命周期"(按时间删除旧分区)
     BUCKET 解决"查询并行度"(每个 Bucket 独立扫描)

## 2. RANGE 分区 + HASH 分桶

```sql
CREATE TABLE orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    order_date DATE
)
DUPLICATE KEY(id)
PARTITION BY RANGE(order_date) (
    PARTITION p2023 VALUES [('2023-01-01'), ('2024-01-01')),
    PARTITION p2024 VALUES [('2024-01-01'), ('2025-01-01')),
    PARTITION p2025 VALUES [('2025-01-01'), ('2026-01-01'))
)
DISTRIBUTED BY HASH(user_id) BUCKETS 16
PROPERTIES ("replication_num" = "3");

```

 注意: RANGE 分区的区间是左闭右开 [start, end)

## 3. 动态分区 (自动创建/删除)

```sql
CREATE TABLE logs (
    id       BIGINT,
    log_time DATETIME,
    message  VARCHAR(4000)
)
DUPLICATE KEY(id)
PARTITION BY RANGE(log_time) ()
DISTRIBUTED BY HASH(id) BUCKETS 8
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.create_history_partition" = "true"
);

```

 自动创建未来 3 天分区，保留过去 30 天分区。

## 4. LIST 分区

```sql
CREATE TABLE users_region (
    id       BIGINT,
    username VARCHAR(100),
    region   VARCHAR(20)
)
DUPLICATE KEY(id)
PARTITION BY LIST(region) (
    PARTITION p_east VALUES IN ('Shanghai', 'Hangzhou'),
    PARTITION p_north VALUES IN ('Beijing', 'Tianjin')
)
DISTRIBUTED BY HASH(id) BUCKETS 8;

```

## 5. AUTO PARTITION (2.1+)

 数据写入时自动创建分区，无需手动定义。
 适合不确定分区键取值范围的场景。
 对比 StarRocks 3.1+ 的 Expression Partition: 功能类似。

## 6. 分区管理

```sql
ALTER TABLE orders ADD PARTITION p2026
    VALUES [('2026-01-01'), ('2027-01-01'));
ALTER TABLE orders DROP PARTITION p2023;

```

批量添加(2.1+)

```sql
ALTER TABLE orders ADD PARTITIONS
    FROM ('2024-01-01') TO ('2024-12-01') INTERVAL 1 MONTH;

```

## 7. 分桶策略选择

 分桶列选择原则:
   高基数列(如 user_id): 数据分布均匀
   JOIN 键: 两表用相同列分桶 → 可 Colocate JOIN(本地 JOIN)
   查询条件列: 加速点查(按分桶键路由到单个 Tablet)

 BUCKETS 数量经验:
   每个 Bucket 100MB~1GB 数据
   不超过 BE 节点数 × 10

## 8. 对比 StarRocks 分区差异

动态分区:     两者都支持(同源语法)
AUTO PARTITION: Doris 2.1+ vs StarRocks Expression Partition 3.1+
批量添加:     Doris ADD PARTITIONS ... INTERVAL(独有便捷语法)
自动分桶:     StarRocks 3.0+ 支持，Doris 需手动指定

