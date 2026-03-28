# YugabyteDB: JSON 类型

> 参考资料:
> - [YugabyteDB YSQL Reference](https://docs.yugabyte.com/stable/api/ysql/)
> - [YugabyteDB PostgreSQL Compatibility](https://docs.yugabyte.com/stable/explore/ysql-language-features/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

```sql
CREATE TABLE events (
    id   BIGSERIAL PRIMARY KEY,
    data JSONB                                 -- binary JSON (recommended)
);

```

Note: JSONB is recommended over JSON for performance
Note: JSONB normalizes keys (sorted, no duplicates)

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

GIN index for JSONB
```sql
CREATE INDEX idx_data ON events USING GIN (data);

```

Specific JSONB operator class
```sql
CREATE INDEX idx_data_path ON events USING GIN (data jsonb_path_ops);
```

jsonb_path_ops: only supports @> (containment), but smaller and faster

Expression index on JSON field
```sql
CREATE INDEX idx_data_name ON events ((data->>'name'));

```

Note: Same JSON types and operators as PostgreSQL
Note: JSONB recommended over JSON (binary, indexed, efficient)
Note: All PostgreSQL JSONB operators supported (@>, ?, ?|, ?&)
Note: GIN index for fast JSONB containment queries
Note: jsonb_path_ops for smaller, faster containment-only index
Note: Based on PostgreSQL 11.2 JSON implementation
Note: jsonb_path_query not available (requires PG 12+)
