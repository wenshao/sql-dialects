# CockroachDB: 分区

> 参考资料:
> - [CockroachDB Documentation - Partitioning](https://www.cockroachlabs.com/docs/stable/partitioning.html)
> - [CockroachDB Documentation - Define Table Partitions](https://www.cockroachlabs.com/docs/stable/alter-table.html#define-partitions)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

## PARTITION BY（Enterprise 特性）


LIST 分区
```sql
CREATE TABLE users (
    id INT PRIMARY KEY, username STRING, region STRING,
    INDEX idx_region (region)
) PARTITION BY LIST (region) (
    PARTITION us VALUES IN ('us-east', 'us-west'),
    PARTITION eu VALUES IN ('eu-west', 'eu-central'),
    PARTITION ap VALUES IN ('ap-southeast', 'ap-northeast')
);

```

RANGE 分区
```sql
CREATE TABLE orders (
    id INT, order_date DATE, amount DECIMAL,
    PRIMARY KEY (order_date, id)
) PARTITION BY RANGE (order_date) (
    PARTITION p2023 VALUES FROM (MINVALUE) TO ('2024-01-01'),
    PARTITION p2024 VALUES FROM ('2024-01-01') TO ('2025-01-01'),
    PARTITION p2025 VALUES FROM ('2025-01-01') TO ('2026-01-01'),
    PARTITION pmax  VALUES FROM ('2026-01-01') TO (MAXVALUE)
);

```

## 地理分区（Geo-Partitioning）


将数据固定到特定区域的节点
```sql
ALTER PARTITION us OF TABLE users
CONFIGURE ZONE USING constraints = '[+region=us]';

ALTER PARTITION eu OF TABLE users
CONFIGURE ZONE USING constraints = '[+region=eu]';

```

数据驻留（Data Domiciling）：确保数据不离开特定区域

## 索引分区


```sql
ALTER INDEX users@idx_region PARTITION BY LIST (region) (
    PARTITION us VALUES IN ('us-east', 'us-west'),
    PARTITION eu VALUES IN ('eu-west', 'eu-central')
);

```

## 分区管理


重新分区
```sql
ALTER TABLE orders PARTITION BY RANGE (order_date) (
    PARTITION p_old VALUES FROM (MINVALUE) TO ('2025-01-01'),
    PARTITION p_new VALUES FROM ('2025-01-01') TO (MAXVALUE)
);

```

查看分区信息
```sql
SHOW PARTITIONS FROM TABLE orders;
SHOW PARTITIONS FROM DATABASE mydb;

```

**注意:** CockroachDB 分区是 Enterprise 特性
**注意:** 地理分区可以将数据固定到特定区域（数据驻留）
**注意:** 分区 + Zone 配置实现多区域数据治理
**注意:** 分区键必须是主键的前缀
**注意:** CockroachDB 自动处理数据分布和复制
