# YugabyteDB: 分区

> 参考资料:
> - [YugabyteDB Documentation - Table Partitioning](https://docs.yugabyte.com/preview/explore/ysql-language-features/advanced-features/partitions/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

## 声明式分区（兼容 PostgreSQL 10+）


RANGE 分区
```sql
CREATE TABLE orders (
    id BIGSERIAL, user_id BIGINT, amount NUMERIC, order_date DATE NOT NULL
) PARTITION BY RANGE (order_date);

CREATE TABLE orders_2024 PARTITION OF orders
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE orders_2025 PARTITION OF orders
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

```

LIST 分区
```sql
CREATE TABLE users_region (
    id BIGSERIAL, username VARCHAR, region VARCHAR NOT NULL
) PARTITION BY LIST (region);

CREATE TABLE users_east PARTITION OF users_region
    FOR VALUES IN ('Shanghai', 'Hangzhou');

```

HASH 分区
```sql
CREATE TABLE sessions (
    id BIGSERIAL, user_id BIGINT NOT NULL, data JSONB
) PARTITION BY HASH (user_id);

CREATE TABLE sessions_0 PARTITION OF sessions
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE sessions_1 PARTITION OF sessions
    FOR VALUES WITH (MODULUS 4, REMAINDER 1);

```

## 分区管理


```sql
ALTER TABLE orders DETACH PARTITION orders_2024;
ALTER TABLE orders ATTACH PARTITION orders_2024
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
DROP TABLE orders_2024;

```

## Tablet 分片（YugabyteDB 特有）


YugabyteDB 自动将表分片为 Tablet
每个分区进一步被分片
Tablet 数量在创建表时指定：
```sql
CREATE TABLE large_table (id BIGINT PRIMARY KEY, data TEXT)
SPLIT INTO 16 TABLETS;

```

**注意:** YugabyteDB 兼容 PostgreSQL 声明式分区
**注意:** 分区 + Tablet 分片提供两级数据划分
**注意:** Tablet 自动在集群节点间分布
**注意:** SPLIT INTO 控制初始 Tablet 数量
