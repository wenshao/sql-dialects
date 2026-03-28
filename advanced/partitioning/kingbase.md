# 人大金仓 (KingbaseES): 表分区策略

> 参考资料:
> - [KingbaseES 基于 PostgreSQL，分区语法兼容](https://help.kingbase.com.cn/)


## 声明式分区（兼容 PostgreSQL）


```sql
CREATE TABLE orders (
    id BIGSERIAL, user_id BIGINT, amount NUMERIC, order_date DATE NOT NULL
) PARTITION BY RANGE (order_date);

CREATE TABLE orders_2024 PARTITION OF orders
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE orders_2025 PARTITION OF orders
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
```

## LIST 分区

```sql
CREATE TABLE users_region (
    id BIGSERIAL, username VARCHAR, region VARCHAR NOT NULL
) PARTITION BY LIST (region);

CREATE TABLE users_east PARTITION OF users_region
    FOR VALUES IN ('Shanghai', 'Hangzhou');
```

## HASH 分区

```sql
CREATE TABLE sessions (
    id BIGSERIAL, user_id BIGINT NOT NULL
) PARTITION BY HASH (user_id);

CREATE TABLE sessions_0 PARTITION OF sessions
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);
```

## 分区管理


```sql
ALTER TABLE orders DETACH PARTITION orders_2024;
DROP TABLE orders_2024;
```

## 注意：KingbaseES 兼容 PostgreSQL 声明式分区

注意：支持 RANGE, LIST, HASH 分区和多级分区
