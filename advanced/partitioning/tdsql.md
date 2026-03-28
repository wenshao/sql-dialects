# TDSQL: 表分区策略

> 参考资料:
> - [TDSQL Documentation](https://cloud.tencent.com/document/product/557)
> - ============================================================
> - MySQL 兼容分区（单机版）
> - ============================================================

```sql
CREATE TABLE orders (
    id BIGINT AUTO_INCREMENT, user_id BIGINT,
    amount DECIMAL(10,2), order_date DATE,
    PRIMARY KEY (id, order_date)
) PARTITION BY RANGE (YEAR(order_date)) (
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);
```

## 分布式分片（TDSQL 分布式版）


## 分片表（按 shardkey 分布到多个 set）

```sql
CREATE TABLE distributed_orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2), order_date DATE
) shardkey=user_id;
```

## 分片 + 分区

```sql
CREATE TABLE sharded_partitioned (
    id BIGINT, user_id BIGINT, order_date DATE,
    PRIMARY KEY (id, user_id, order_date)
) shardkey=user_id
PARTITION BY RANGE(YEAR(order_date)) (
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026)
);
```

## 分区管理


```sql
ALTER TABLE orders ADD PARTITION (PARTITION p2026 VALUES LESS THAN (2027));
ALTER TABLE orders DROP PARTITION p2024;
```

注意：TDSQL 单机版兼容 MySQL 分区语法
注意：分布式版使用 shardkey 进行跨节点分片
注意：可以同时使用分片和分区
