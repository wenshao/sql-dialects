# CockroachDB: JSON 类型

> 参考资料:
> - [CockroachDB - SQL Statements](https://www.cockroachlabs.com/docs/stable/sql-statements)
> - [CockroachDB - Functions and Operators](https://www.cockroachlabs.com/docs/stable/functions-and-operators)
> - [CockroachDB - Data Types](https://www.cockroachlabs.com/docs/stable/data-types)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

```sql
CREATE TABLE events (
    id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    data JSONB
);

```

Note: In CockroachDB, JSON and JSONB are the same (both binary)

Insert JSON
```sql
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip"]}');
INSERT INTO events (data) VALUES (jsonb_build_object('name', 'bob', 'age', 30));

```

Access JSON fields (same as PostgreSQL)
```sql
SELECT data->'name' FROM events;               -- JSONB: "alice" (with quotes)
SELECT data->>'name' FROM events;              -- TEXT: alice (without quotes)
SELECT data->'tags'->0 FROM events;            -- array element by index
SELECT data#>'{tags,0}' FROM events;           -- path access (JSONB)
SELECT data#>>'{tags,0}' FROM events;          -- path access (TEXT)

```

Query conditions
```sql
SELECT * FROM events WHERE data->>'name' = 'alice';
SELECT * FROM events WHERE data @> '{"name": "alice"}'::JSONB;  -- containment
SELECT * FROM events WHERE data ? 'premium';                     -- key exists
SELECT * FROM events WHERE data ?| ARRAY['premium', 'vip'];     -- any key exists
SELECT * FROM events WHERE data ?& ARRAY['name', 'age'];        -- all keys exist

```

JSON path queries (v22.2+, PostgreSQL 12+ compatible)
```sql
SELECT jsonb_path_query(data, '$.tags[*]') FROM events;
SELECT * FROM events WHERE jsonb_path_exists(data, '$.age ? (@ > 20)');

```

JSON construction
```sql
SELECT jsonb_build_object('name', 'alice', 'age', 25);
SELECT jsonb_build_array(1, 2, 3);
SELECT to_jsonb(ROW('alice', 25));
SELECT row_to_json(u) FROM users u;

```

JSON modification
```sql
SELECT jsonb_set(data, '{city}', '"New York"') FROM events;      -- set value
SELECT data || '{"premium": true}'::JSONB FROM events;           -- merge
SELECT data - 'temporary' FROM events;                           -- remove key
SELECT data - ARRAY['key1', 'key2'] FROM events;                 -- remove keys
SELECT data #- '{tags,0}' FROM events;                           -- remove by path

```

JSON aggregation
```sql
SELECT jsonb_agg(username) FROM users;
SELECT jsonb_object_agg(username, age) FROM users;

```

JSON expansion
```sql
SELECT * FROM jsonb_each(data) FROM events;                      -- key-value pairs
SELECT * FROM jsonb_array_elements(data->'tags') AS tag FROM events;
SELECT jsonb_array_length(data->'tags') FROM events;
SELECT * FROM jsonb_object_keys(data) AS key FROM events;

```

JSON type checks
```sql
SELECT jsonb_typeof(data->'age') FROM events;  -- number, string, boolean, array, object, null

```

Inverted index for JSONB (CockroachDB-specific syntax)
```sql
CREATE INVERTED INDEX idx_data ON events (data);
```

Or PostgreSQL syntax:
```sql
CREATE INDEX idx_data_gin ON events USING GIN (data);

```

Partial inverted index
```sql
CREATE INVERTED INDEX idx_data_active ON events (data) WHERE status = 1;

```

Note: JSON and JSONB are identical in CockroachDB (both binary)
Note: All PostgreSQL JSONB operators supported (@>, ?, ?|, ?&)
Note: jsonb_path_query supported (v22.2+)
Note: INVERTED INDEX for fast JSON containment queries
Note: GIN index syntax also works (PostgreSQL compatibility)
