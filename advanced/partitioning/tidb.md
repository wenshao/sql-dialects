# TiDB: 分区

> 参考资料:
> - [TiDB Documentation - Partitioned Tables](https://docs.pingcap.com/tidb/stable/partitioned-table)
> - [TiDB Documentation - Partition Management](https://docs.pingcap.com/tidb/stable/partitioned-table#partition-management)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

## RANGE 分区


```sql
CREATE TABLE orders (
    id BIGINT AUTO_INCREMENT, user_id BIGINT,
    amount DECIMAL(10,2), order_date DATE,
    PRIMARY KEY (id, order_date)
) PARTITION BY RANGE (YEAR(order_date)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);

```

RANGE COLUMNS
```sql
CREATE TABLE logs (
    id BIGINT, log_date DATE, message TEXT,
    PRIMARY KEY (id, log_date)
) PARTITION BY RANGE COLUMNS(log_date) (
    PARTITION p202401 VALUES LESS THAN ('2024-02-01'),
    PARTITION p202402 VALUES LESS THAN ('2024-03-01'),
    PARTITION pmax    VALUES LESS THAN (MAXVALUE)
);

```

## LIST 分区（5.4+）


```sql
CREATE TABLE users_region (
    id BIGINT, username VARCHAR(100), region VARCHAR(20),
    PRIMARY KEY (id, region)
) PARTITION BY LIST COLUMNS(region) (
    PARTITION p_east  VALUES IN ('Shanghai', 'Hangzhou'),
    PARTITION p_north VALUES IN ('Beijing', 'Tianjin')
);

```

## HASH 分区


```sql
CREATE TABLE sessions (
    id BIGINT, user_id BIGINT, data TEXT,
    PRIMARY KEY (id, user_id)
) PARTITION BY HASH(user_id) PARTITIONS 8;

```

KEY 分区
```sql
CREATE TABLE cache (
    id BIGINT PRIMARY KEY, value TEXT
) PARTITION BY KEY(id) PARTITIONS 4;

```

## 分区管理


```sql
ALTER TABLE orders ADD PARTITION (PARTITION p2026 VALUES LESS THAN (2027));
ALTER TABLE orders DROP PARTITION p2023;
ALTER TABLE orders TRUNCATE PARTITION p2023;
ALTER TABLE orders REORGANIZE PARTITION pmax INTO (
    PARTITION p2026 VALUES LESS THAN (2027),
    PARTITION pmax VALUES LESS THAN MAXVALUE
);
ALTER TABLE orders EXCHANGE PARTITION p2024 WITH TABLE orders_2024;

```

## 动态裁剪（5.1+）


启用动态分区裁剪
```sql
SET @@tidb_partition_prune_mode = 'dynamic';

```

查看分区裁剪效果
```sql
EXPLAIN SELECT * FROM orders WHERE order_date = '2024-06-15';

```

**注意:** TiDB 分区语法兼容 MySQL
**注意:** 5.1+ 支持动态分区裁剪模式
**注意:** 5.4+ 支持 LIST 分区和 LIST COLUMNS 分区
**注意:** 分区键必须包含在唯一索引中
**注意:** 分区表的数据分布在 TiKV 的 Region 中
