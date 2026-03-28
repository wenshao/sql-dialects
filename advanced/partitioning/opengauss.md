# openGauss: 表分区策略

> 参考资料:
> - [openGauss Documentation - CREATE TABLE PARTITION](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/CREATE-TABLE-PARTITION.html)
> - ============================================================
> - RANGE 分区
> - ============================================================

```sql
CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount NUMERIC, order_date DATE
) PARTITION BY RANGE (order_date) (
    PARTITION p2023 VALUES LESS THAN ('2024-01-01'),
    PARTITION p2024 VALUES LESS THAN ('2025-01-01'),
    PARTITION p2025 VALUES LESS THAN ('2026-01-01'),
    PARTITION pmax  VALUES LESS THAN (MAXVALUE)
);
```

## INTERVAL 分区（自动创建）

```sql
CREATE TABLE logs (
    id BIGINT, log_date DATE, message TEXT
) PARTITION BY RANGE (log_date)
  INTERVAL ('1 month') (
    PARTITION p_init VALUES LESS THAN ('2024-01-01')
);
```

## LIST 分区


```sql
CREATE TABLE users_region (
    id BIGINT, username VARCHAR, region VARCHAR
) PARTITION BY LIST (region) (
    PARTITION p_east VALUES ('Shanghai', 'Hangzhou'),
    PARTITION p_north VALUES ('Beijing', 'Tianjin'),
    PARTITION p_other VALUES (DEFAULT)
);
```

## HASH 分区


```sql
CREATE TABLE sessions (
    id BIGINT, user_id BIGINT, data TEXT
) PARTITION BY HASH (user_id) (
    PARTITION p0, PARTITION p1, PARTITION p2, PARTITION p3
);
```

## 分区管理


```sql
ALTER TABLE orders ADD PARTITION p2026 VALUES LESS THAN ('2027-01-01');
ALTER TABLE orders DROP PARTITION p2023;
ALTER TABLE orders TRUNCATE PARTITION p2023;
ALTER TABLE orders SPLIT PARTITION pmax AT ('2027-01-01')
    INTO (PARTITION p2026, PARTITION pmax);
ALTER TABLE orders MERGE PARTITIONS p2024, p2025 INTO PARTITION p2024_2025;
```

## 交换分区

```sql
ALTER TABLE orders EXCHANGE PARTITION (p2024) WITH TABLE orders_2024_staging;
```

注意：openGauss 使用自己的分区语法（非 PostgreSQL 声明式）
注意：支持 INTERVAL 分区自动创建
注意：支持 SPLIT, MERGE, EXCHANGE 分区操作
注意：LIST 分区支持 DEFAULT 值
