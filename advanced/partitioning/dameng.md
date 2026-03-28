# 达梦 (DM): 表分区策略

> 参考资料:
> - [达梦数据库 SQL 语言使用手册](https://eco.dameng.com/document/dm/zh-cn/sql-dev/)


## RANGE 分区


```sql
CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2), order_date DATE
) PARTITION BY RANGE(order_date) (
    PARTITION p2023 VALUES LESS THAN (DATE '2024-01-01'),
    PARTITION p2024 VALUES LESS THAN (DATE '2025-01-01'),
    PARTITION p2025 VALUES LESS THAN (DATE '2026-01-01'),
    PARTITION pmax  VALUES LESS THAN (MAXVALUE)
);
```

## LIST 分区


```sql
CREATE TABLE users_region (
    id BIGINT, username VARCHAR(100), region VARCHAR(20)
) PARTITION BY LIST(region) (
    PARTITION p_east VALUES ('Shanghai', 'Hangzhou'),
    PARTITION p_north VALUES ('Beijing', 'Tianjin')
);
```

## HASH 分区


```sql
CREATE TABLE sessions (
    id BIGINT, user_id BIGINT, data CLOB
) PARTITION BY HASH(user_id) PARTITIONS 8;
```

## 分区管理


```sql
ALTER TABLE orders ADD PARTITION p2026 VALUES LESS THAN (DATE '2027-01-01');
ALTER TABLE orders DROP PARTITION p2023;
```

注意：达梦分区语法兼容 Oracle
注意：支持 RANGE, LIST, HASH 分区
注意：支持复合分区
