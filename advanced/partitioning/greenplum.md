# Greenplum: 表分区策略

> 参考资料:
> - [Greenplum Documentation - Partitioning Tables](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-ddl-ddl-partition.html)


## RANGE 分区


```sql
CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount NUMERIC, order_date DATE
) DISTRIBUTED BY (user_id)
PARTITION BY RANGE (order_date) (
    PARTITION p2023 START ('2023-01-01') END ('2024-01-01'),
    PARTITION p2024 START ('2024-01-01') END ('2025-01-01'),
    PARTITION p2025 START ('2025-01-01') END ('2026-01-01'),
    DEFAULT PARTITION pother
);
```


按月自动生成
```sql
CREATE TABLE logs (
    id BIGINT, log_date DATE, message TEXT
) DISTRIBUTED BY (id)
PARTITION BY RANGE (log_date) (
    START ('2024-01-01') END ('2025-01-01') EVERY (INTERVAL '1 month'),
    DEFAULT PARTITION pother
);
```


## LIST 分区


```sql
CREATE TABLE users_region (
    id BIGINT, username VARCHAR(100), region VARCHAR(20)
) DISTRIBUTED BY (id)
PARTITION BY LIST (region) (
    PARTITION p_east VALUES ('Shanghai', 'Hangzhou'),
    PARTITION p_north VALUES ('Beijing', 'Tianjin'),
    DEFAULT PARTITION p_other
);
```


## 多级分区


```sql
CREATE TABLE sales (
    id BIGINT, sale_date DATE, region VARCHAR(20), amount NUMERIC
) DISTRIBUTED BY (id)
PARTITION BY RANGE (sale_date)
SUBPARTITION BY LIST (region)
SUBPARTITION TEMPLATE (
    SUBPARTITION east VALUES ('East'),
    SUBPARTITION west VALUES ('West'),
    DEFAULT SUBPARTITION other
) (
    PARTITION p2024 START ('2024-01-01') END ('2025-01-01'),
    PARTITION p2025 START ('2025-01-01') END ('2026-01-01')
);
```


## 分区管理


```sql
ALTER TABLE orders ADD PARTITION p2026
    START ('2026-01-01') END ('2027-01-01');
ALTER TABLE orders DROP PARTITION p2023;
ALTER TABLE orders TRUNCATE PARTITION p2023;
ALTER TABLE orders SPLIT DEFAULT PARTITION
    START ('2026-01-01') END ('2027-01-01')
    INTO (PARTITION p2026, DEFAULT PARTITION);
ALTER TABLE orders EXCHANGE PARTITION p2024
    WITH TABLE orders_2024_staging;
```


注意：Greenplum 使用 START/END 语法（与 PostgreSQL 声明式不同）
注意：EVERY 子句自动生成等间隔分区
注意：DISTRIBUTED BY 控制数据在段（Segment）间的分布
注意：分区 + 分布是 Greenplum 性能优化的两个维度
注意：DEFAULT PARTITION 捕获不匹配的数据
