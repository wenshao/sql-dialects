# OceanBase: 分区

> 参考资料:
> - [OceanBase Documentation - Partitioned Tables](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## RANGE 分区


```sql
CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2), order_date DATE,
    PRIMARY KEY (id, order_date)
) PARTITION BY RANGE(order_date) (
    PARTITION p2023 VALUES LESS THAN ('2024-01-01'),
    PARTITION p2024 VALUES LESS THAN ('2025-01-01'),
    PARTITION p2025 VALUES LESS THAN ('2026-01-01'),
    PARTITION pmax  VALUES LESS THAN (MAXVALUE)
);

```

## HASH 分区


```sql
CREATE TABLE sessions (
    id BIGINT, user_id BIGINT, data TEXT,
    PRIMARY KEY (id, user_id)
) PARTITION BY HASH(user_id) PARTITIONS 8;

```

## LIST 分区


```sql
CREATE TABLE users_region (
    id BIGINT, username VARCHAR(100), region VARCHAR(20),
    PRIMARY KEY (id, region)
) PARTITION BY LIST(region) (
    PARTITION p_east VALUES IN ('Shanghai', 'Hangzhou'),
    PARTITION p_north VALUES IN ('Beijing', 'Tianjin')
);

```

## 复合分区


```sql
CREATE TABLE sales (
    id BIGINT, sale_date DATE, region VARCHAR(20), amount DECIMAL(10,2),
    PRIMARY KEY (id, sale_date, region)
) PARTITION BY RANGE(sale_date)
  SUBPARTITION BY HASH(region) SUBPARTITIONS 4 (
    PARTITION p2024 VALUES LESS THAN ('2025-01-01'),
    PARTITION p2025 VALUES LESS THAN ('2026-01-01')
);

```

## 分区管理


```sql
ALTER TABLE orders ADD PARTITION p2026 VALUES LESS THAN ('2027-01-01');
ALTER TABLE orders DROP PARTITION p2023;
ALTER TABLE orders TRUNCATE PARTITION p2023;

```

**注意:** OceanBase 兼容 MySQL 分区语法
**注意:** 支持 RANGE、HASH、LIST 和复合分区
**注意:** 分区键必须包含在主键中
**注意:** 分区数据自动在 OBServer 节点间分布
