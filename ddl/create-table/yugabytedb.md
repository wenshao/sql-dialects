# YugabyteDB: CREATE TABLE

> 参考资料:
> - [YugabyteDB YSQL Reference](https://docs.yugabyte.com/stable/api/ysql/)
> - [YugabyteDB PostgreSQL Compatibility](https://docs.yugabyte.com/stable/explore/ysql-language-features/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

```sql
CREATE TABLE users (
    id         BIGSERIAL PRIMARY KEY,
    username   VARCHAR(100) NOT NULL,
    email      VARCHAR(255) NOT NULL UNIQUE,
    age        INT,
    balance    DECIMAL(10,2),
    bio        TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Note: Primary key is hash-sharded by default (not range-sharded)
Rows with id=1 and id=2 may be on different tablets

Explicit hash sharding (default behavior)
```sql
CREATE TABLE orders (
    id         BIGSERIAL,
    user_id    BIGINT NOT NULL REFERENCES users (id),
    amount     DECIMAL(10,2),
    order_date DATE NOT NULL DEFAULT CURRENT_DATE,
    PRIMARY KEY (id HASH)                      -- explicit hash sharding
);

```

Range sharding (for ordered scans)
```sql
CREATE TABLE events (
    id         BIGSERIAL,
    ts         TIMESTAMPTZ NOT NULL DEFAULT now(),
    event_type VARCHAR(50),
    data       JSONB,
    PRIMARY KEY (id ASC)                       -- range sharding
);

```

Composite sharding (hash + range)
```sql
CREATE TABLE order_items (
    order_id   BIGINT,
    item_id    INT,
    product_id BIGINT,
    quantity   INT,
    price      DECIMAL(10,2),
    PRIMARY KEY ((order_id) HASH, item_id ASC) -- hash on order_id, range on item_id
);

```

Tablegroups (co-locate related tables for join performance, v2.1+)
```sql
CREATE TABLEGROUP order_group;
CREATE TABLE orders_grouped (
    id     BIGSERIAL PRIMARY KEY,
    amount DECIMAL(10,2)
) TABLEGROUP order_group;
CREATE TABLE order_items_grouped (
    id       BIGSERIAL PRIMARY KEY,
    order_id BIGINT,
    product  VARCHAR(100)
) TABLEGROUP order_group;

```

Colocation (co-locate all tables in a database)
CREATE DATABASE mydb WITH COLOCATION = true;
Tables in a colocated DB share a single tablet by default

Opt out of colocation for large tables
```sql
CREATE TABLE large_events (
    id   BIGSERIAL PRIMARY KEY,
    data JSONB
) WITH (COLOCATION = false);

```

Tablespace for geo-partitioning (multi-region, v2.5+)
CREATE TABLESPACE us_east_ts WITH (replica_placement =
  '{"num_replicas": 3, "placement_blocks": [
    {"cloud":"aws","region":"us-east-1","zone":"us-east-1a","min_num_replicas":1}
  ]}');
```sql
CREATE TABLE regional_users (
    id       BIGSERIAL PRIMARY KEY,
    username VARCHAR(100),
    region   VARCHAR(20)
) TABLESPACE us_east_ts;

```

Row-level geo-partitioning (partition by region)
```sql
CREATE TABLE geo_orders (
    id     BIGSERIAL,
    region VARCHAR(20) NOT NULL,
    amount DECIMAL(10,2),
    PRIMARY KEY (id, region)
) PARTITION BY LIST (region);

CREATE TABLE geo_orders_us PARTITION OF geo_orders
    FOR VALUES IN ('us') TABLESPACE us_east_ts;
CREATE TABLE geo_orders_eu PARTITION OF geo_orders
    FOR VALUES IN ('eu') TABLESPACE eu_west_ts;

```

CREATE TABLE AS SELECT
```sql
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01';

```

IF NOT EXISTS
```sql
CREATE TABLE IF NOT EXISTS users (
    id       BIGSERIAL PRIMARY KEY,
    username VARCHAR(100)
);

```

ARRAY and JSONB columns (same as PostgreSQL)
```sql
CREATE TABLE profiles (
    id       BIGSERIAL PRIMARY KEY,
    tags     TEXT[],
    metadata JSONB
);

```

Computed columns (same as PostgreSQL GENERATED ALWAYS AS)
```sql
CREATE TABLE products (
    id         BIGSERIAL PRIMARY KEY,
    price      DECIMAL(10,2),
    tax_rate   DECIMAL(5,4),
    total      DECIMAL(10,2) GENERATED ALWAYS AS (price * (1 + tax_rate)) STORED
);

```

Tablet splitting options
```sql
CREATE TABLE high_throughput (
    id   BIGSERIAL PRIMARY KEY,
    data TEXT
) SPLIT INTO 10 TABLETS;                       -- pre-split into 10 tablets

```

SPLIT AT for range-sharded tables
```sql
CREATE TABLE range_table (
    id   INT PRIMARY KEY ASC,
    data TEXT
) SPLIT AT VALUES ((100), (200), (300));

```

Note: Default sharding is HASH (unlike PostgreSQL's B-tree range)
Note: TEMPORARY tables are supported but local to the tserver
Note: Supports table inheritance (INHERITS) like PostgreSQL
Note: No UNLOGGED tables (all data is replicated)
Note: Sequences work but are distributed (may have gaps)
