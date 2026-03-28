# CockroachDB: INSERT

> 参考资料:
> - [CockroachDB - SQL Statements](https://www.cockroachlabs.com/docs/stable/sql-statements)
> - [CockroachDB - Functions and Operators](https://www.cockroachlabs.com/docs/stable/functions-and-operators)
> - [CockroachDB - Data Types](https://www.cockroachlabs.com/docs/stable/data-types)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

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

Insert with unique_rowid()
```sql
INSERT INTO orders (id, user_id, amount)
VALUES (unique_rowid(), '550e8400-e29b-41d4-a716-446655440000', 99.99);

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

Bulk insert with IMPORT (CockroachDB-specific, for large data loads)
IMPORT INTO users (username, email, age)
    CSV DATA ('gs://bucket/users.csv')
    WITH delimiter = ',', skip = '1';

IMPORT from multiple files
IMPORT INTO users CSV DATA (
    'gs://bucket/users_1.csv',
    'gs://bucket/users_2.csv'
);

COPY (PostgreSQL-compatible, for streaming inserts)
COPY users (username, email, age) FROM STDIN WITH CSV;

Default values
```sql
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
```

Unspecified columns get DEFAULT or NULL

Note: No DML quota limits (unlike BigQuery)
Note: Bulk inserts are faster with IMPORT INTO than individual INSERTs
Note: RETURNING clause works for all DML operations
Note: Transactions automatically retry on contention (implicit retries)
