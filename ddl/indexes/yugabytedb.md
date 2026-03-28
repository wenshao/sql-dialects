# YugabyteDB: 索引

> 参考资料:
> - [YugabyteDB YSQL Reference](https://docs.yugabyte.com/stable/api/ysql/)
> - [YugabyteDB PostgreSQL Compatibility](https://docs.yugabyte.com/stable/explore/ysql-language-features/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

## Standard indexes (LSM-tree based, not B-tree)


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

## Hash vs range sharded indexes (YugabyteDB-specific)


Hash-sharded index (default, distributes writes evenly)
```sql
CREATE INDEX idx_orders_user ON orders (user_id HASH);

```

Range-sharded index (better for ordered scans)
```sql
CREATE INDEX idx_events_ts ON events (ts ASC);

```

Composite: hash + range
```sql
CREATE INDEX idx_orders_user_date ON orders (user_id HASH, order_date ASC);

```

## Partial index (same as PostgreSQL)


```sql
CREATE INDEX idx_active_users ON users (username) WHERE status = 1;

```

## Covering index (INCLUDE)


```sql
CREATE INDEX idx_users_email_cover ON users (email) INCLUDE (username, age);

```

## Expression index


```sql
CREATE INDEX idx_users_lower_email ON users (lower(email));
CREATE INDEX idx_users_jsonb_name ON users ((metadata->>'name'));

```

## GIN indexes (for JSONB, arrays, full-text)


JSONB GIN index
```sql
CREATE INDEX idx_metadata ON users USING GIN (metadata);

```

Specific JSONB operator class
```sql
CREATE INDEX idx_metadata_path ON users USING GIN (metadata jsonb_path_ops);

```

Array GIN index
```sql
CREATE INDEX idx_tags ON users USING GIN (tags);

```

Full-text search GIN index
```sql
CREATE INDEX idx_search ON articles USING GIN (to_tsvector('english', content));

```

Trigram index (requires pg_trgm)
```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_trgm_name ON users USING GIN (username gin_trgm_ops);

```

## GiST indexes (spatial)


```sql
CREATE INDEX idx_location ON places USING GIST (location);

```

## Pre-split indexes (YugabyteDB-specific)


Split index into multiple tablets at creation
```sql
CREATE INDEX idx_orders_amount ON orders (amount ASC)
    SPLIT AT VALUES ((100.00), (500.00), (1000.00));

```

## Index management


Drop index
```sql
DROP INDEX idx_users_email;
DROP INDEX IF EXISTS idx_users_email;
DROP INDEX CONCURRENTLY idx_users_email;       -- non-blocking drop

```

Create index concurrently (non-blocking, v2.14+)
```sql
CREATE INDEX CONCURRENTLY idx_users_email ON users (email);

```

Rename index
```sql
ALTER INDEX idx_users_email RENAME TO idx_email;

```

Set tablespace for index (geo-distribution)
```sql
ALTER INDEX idx_users_email SET TABLESPACE us_east_ts;

```

Reindex
```sql
REINDEX INDEX idx_users_email;
REINDEX TABLE users;

```

Show indexes
```sql
\di+ users                                     -- psql command

```

Note: Default index sharding is HASH (distributes writes evenly)
Note: Use ASC/DESC for range-sharded indexes (ordered scans)
Note: LSM-tree based storage (not B-tree like PostgreSQL)
Note: Index backfill is done online in the background
Note: Supports CONCURRENTLY for non-blocking index creation
Note: SPLIT AT / SPLIT INTO for controlling tablet distribution
Note: No BRIN indexes (not needed with distributed storage)
