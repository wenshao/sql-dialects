# CockroachDB: 索引

> 参考资料:
> - [CockroachDB - SQL Statements](https://www.cockroachlabs.com/docs/stable/sql-statements)
> - [CockroachDB - Functions and Operators](https://www.cockroachlabs.com/docs/stable/functions-and-operators)
> - [CockroachDB - Data Types](https://www.cockroachlabs.com/docs/stable/data-types)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

## Standard indexes (B-tree, default)


```sql
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);

```

Unique index
```sql
CREATE UNIQUE INDEX idx_users_email_uniq ON users (email);

```

Multi-column index
```sql
CREATE INDEX idx_users_city_age ON users (city, age);

```

Descending index
```sql
CREATE INDEX idx_users_age_desc ON users (age DESC);

```

Partial index (same as PostgreSQL)
```sql
CREATE INDEX idx_active_users ON users (username) WHERE status = 1;

```

Covering index (STORING / INCLUDE, same as PostgreSQL)
```sql
CREATE INDEX idx_users_email_cover ON users (email) STORING (username, age);
```

STORING is CockroachDB preferred syntax (INCLUDE also works)

Expression index
```sql
CREATE INDEX idx_users_lower_email ON users (lower(email));
CREATE INDEX idx_users_jsonb_name ON users ((metadata->>'name'));

```

## Hash-sharded indexes (CockroachDB-specific)


Prevents write hotspots on sequential keys
```sql
CREATE INDEX idx_events_ts ON events (ts) USING HASH;

```

Hash-sharded with bucket count
```sql
CREATE INDEX idx_events_ts_sharded ON events (ts) USING HASH WITH (bucket_count = 8);

```

Hash-sharded primary key
```sql
CREATE TABLE timeseries (
    ts   TIMESTAMPTZ NOT NULL,
    data JSONB,
    PRIMARY KEY (ts) USING HASH
);

```

## GIN indexes (for JSONB, arrays, full-text)


JSONB inverted index
```sql
CREATE INVERTED INDEX idx_metadata ON users (metadata);
```

Or PostgreSQL-compatible syntax:
```sql
CREATE INDEX idx_metadata_gin ON users USING GIN (metadata);

```

Array inverted index
```sql
CREATE INVERTED INDEX idx_tags ON users (tags);

```

Partial inverted index
```sql
CREATE INVERTED INDEX idx_active_metadata ON users (metadata) WHERE status = 1;

```

Multi-column inverted index (v21.2+)
```sql
CREATE INVERTED INDEX idx_type_metadata ON users (user_type, metadata);

```

## Spatial indexes (v20.2+)


```sql
CREATE INDEX idx_location ON places USING GIST (location);

```

## Trigram indexes (v22.2+)


Requires pg_trgm extension
SET CLUSTER SETTING sql.defaults.extension_schema = 'public';
```sql
CREATE INDEX idx_trgm_name ON users USING GIN (username gin_trgm_ops);

```

## Index management


Drop index
```sql
DROP INDEX idx_users_email;
DROP INDEX IF EXISTS idx_users_email;

```

Rename index
```sql
ALTER INDEX idx_users_email RENAME TO idx_email;

```

Configure zone for index (placement/replication)
```sql
ALTER INDEX idx_users_email CONFIGURE ZONE USING num_replicas = 5;

```

Make index not visible (v22.2+)
```sql
ALTER INDEX idx_users_email NOT VISIBLE;
ALTER INDEX idx_users_email VISIBLE;

```

Show indexes
```sql
SHOW INDEXES FROM users;
SHOW INDEX FROM users;

```

Note: All indexes are distributed across nodes
Note: USING HASH prevents sequential key hotspots (most impactful optimization)
Note: STORING stores extra columns in index to avoid table lookups
Note: CockroachDB uses INVERTED INDEX instead of GIN for JSONB/arrays
Note: Index creation is online and non-blocking
Note: No BRIN, HASH (PostgreSQL-style), or SP-GiST index types
