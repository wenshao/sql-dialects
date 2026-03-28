# YugabyteDB: INSERT

> 参考资料:
> - [YugabyteDB YSQL Reference](https://docs.yugabyte.com/stable/api/ysql/)
> - [YugabyteDB PostgreSQL Compatibility](https://docs.yugabyte.com/stable/explore/ysql-language-features/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

```

Multiple rows
```sql
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

```

INSERT ... RETURNING (same as PostgreSQL)
```sql
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
RETURNING id, username, created_at;

```

INSERT from query
```sql
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

```

CTE + INSERT
```sql
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age
    UNION ALL
    SELECT 'bob', 'bob@example.com', 30
)
INSERT INTO users (username, email, age)
SELECT * FROM new_users;

```

Insert with UUID generation
```sql
INSERT INTO products (id, name, price)
VALUES (gen_random_uuid(), 'Widget', 9.99);

```

Insert JSONB data
```sql
INSERT INTO events (user_id, event_type, data)
VALUES (1, 'login', '{"source": "web", "browser": "chrome"}'::JSONB);

```

Insert ARRAY data
```sql
INSERT INTO profiles (user_id, tags)
VALUES (1, ARRAY['vip', 'active', 'premium']);

```

INSERT ... ON CONFLICT (upsert, see upsert module)
```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 26)
ON CONFLICT (username) DO UPDATE SET email = EXCLUDED.email, age = EXCLUDED.age;

```

Batch insert with COPY (PostgreSQL-compatible)
COPY users (username, email, age) FROM '/path/to/data.csv' WITH CSV HEADER;

Insert into partitioned table (routes to correct partition)
```sql
INSERT INTO geo_orders (id, region, amount)
VALUES (1, 'us', 99.99);
```

Automatically inserted into geo_orders_us partition

Insert with sequence
```sql
INSERT INTO orders (user_id, amount)
VALUES (1, 99.99);
```

id auto-generated from BIGSERIAL sequence

Default values
```sql
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
```

Unspecified columns get DEFAULT or NULL

Insert with explicit partition (for list/range partitioned tables)
```sql
INSERT INTO geo_orders_us (id, region, amount)
VALUES (1, 'us', 99.99);

```

Note: INSERT performance benefits from batching multiple rows
Note: COPY is faster than individual INSERTs for bulk loading
Note: Distributed transactions ensure consistency across tablets
Note: RETURNING clause works the same as PostgreSQL
Note: Hash-sharded tables distribute inserts across tablets automatically
Note: Sequences are distributed (may produce non-contiguous values)
