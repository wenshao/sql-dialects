# DuckDB: JSON 类型

> 参考资料:
> - [DuckDB - SQL Reference](https://duckdb.org/docs/sql/introduction)
> - [DuckDB - Functions](https://duckdb.org/docs/sql/functions/overview)
> - [DuckDB - Data Types](https://duckdb.org/docs/sql/data_types/overview)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

```sql
INSTALL json;
LOAD json;

```

JSON type (stored as VARCHAR internally)
```sql
CREATE TABLE events (
    id   BIGINT PRIMARY KEY,
    data JSON
);

```

Insert JSON
```sql
INSERT INTO events (id, data) VALUES (1, '{"name": "alice", "age": 25, "tags": ["vip", "new"]}');

```

DuckDB alternative: Use native STRUCT/LIST/MAP types instead of JSON
This is more efficient and type-safe
```sql
CREATE TABLE events_native (
    id   BIGINT PRIMARY KEY,
    name VARCHAR,
    age  INTEGER,
    tags VARCHAR[]
);

```

Reading JSON fields (arrow operator)
```sql
SELECT data->>'name' FROM events;              -- Text: alice
SELECT data->'name' FROM events;               -- JSON: "alice"
SELECT data->'tags'->0 FROM events;            -- First element: "vip"
SELECT data->'tags'->>1 FROM events;           -- Text: new

```

JSON extract functions
```sql
SELECT json_extract(data, '$.name') FROM events;        -- JSON value
SELECT json_extract_string(data, '$.name') FROM events;  -- String value
SELECT json_extract(data, '$.tags[0]') FROM events;      -- Array element

```

Multiple path extraction
```sql
SELECT json_extract(data, ['$.name', '$.age']) FROM events;  -- Returns list

```

JSON type checking
```sql
SELECT json_type(data->'name') FROM events;    -- 'VARCHAR'
SELECT json_type(data->'age') FROM events;     -- 'BIGINT'
SELECT json_type(data->'tags') FROM events;    -- 'ARRAY'
SELECT json_valid('{"key": "value"}');          -- true

```

JSON structure inspection
```sql
SELECT json_keys(data) FROM events;            -- ['name', 'age', 'tags']
SELECT json_array_length(data->'tags') FROM events;  -- 2

```

JSON construction
```sql
SELECT json_object('name', 'alice', 'age', 25);
SELECT json_array('a', 'b', 'c');
SELECT to_json(STRUCT_PACK(name := 'alice', age := 25));

```

JSON modification
```sql
SELECT json_merge_patch(data, '{"email": "a@e.com"}') FROM events;
```

Note: JSON is immutable; modifications return new JSON

JSON to table (unnest JSON arrays)
```sql
SELECT * FROM json_each('{"a": 1, "b": 2, "c": 3}');
SELECT * FROM json_array_elements('[1, 2, 3]'::JSON);

```

Read JSON files directly
```sql
SELECT * FROM read_json_auto('data.json');
SELECT * FROM read_json('data.json', format='array', columns={name: 'VARCHAR', age: 'INTEGER'});

```

Read newline-delimited JSON (NDJSON)
```sql
SELECT * FROM read_json_auto('logs.ndjson', format='newline_delimited');

```

JSON aggregation
```sql
SELECT json_group_array(username) FROM users;
SELECT json_group_object(username, age) FROM users;

```

Convert between JSON and native types
```sql
SELECT data::STRUCT(name VARCHAR, age INTEGER, tags VARCHAR[]) FROM events;
SELECT from_json(data, '{"name": "VARCHAR", "age": "INTEGER"}') FROM events;

```

DuckDB native types as JSON alternative (recommended for known schemas)
```sql
CREATE TABLE events_typed (
    id      BIGINT,
    name    VARCHAR,
    age     INTEGER,
    tags    VARCHAR[],                -- LIST
    address STRUCT(city VARCHAR, zip VARCHAR),  -- STRUCT
    meta    MAP(VARCHAR, VARCHAR)     -- MAP
);

```

Note: DuckDB can directly query JSON files without loading into tables
Note: Native types (STRUCT, LIST, MAP) are preferred over JSON for known schemas
Note: JSON type is stored as VARCHAR; no binary JSON format like JSONB
Note: Arrow operators (-> / ->>) work like PostgreSQL
Note: json_extract uses JSONPath syntax ($.field, $.array[0])
Note: read_json_auto auto-detects schema from JSON files
