# Flink SQL: JSON 类型

> 参考资料:
> - [Flink SQL Documentation](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
> - [Flink SQL - Built-in Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/)
> - [Flink SQL - Data Types](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

```sql
CREATE TABLE events (
    id         BIGINT,
    name       STRING,
    age        INT,
    tags       ARRAY<STRING>,
    address    ROW<city STRING, zip STRING>
) WITH (
    'connector' = 'kafka',
    'topic' = 'events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json',
    'json.fail-on-missing-field' = 'false',
    'json.ignore-parse-errors' = 'true'
);
```

The JSON format automatically maps JSON fields to columns

Raw JSON as STRING
```sql
CREATE TABLE raw_events (
    id      BIGINT,
    payload STRING                    -- Raw JSON stored as STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'raw-events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

```

JSON extraction functions (Flink 1.15+)
```sql
SELECT JSON_EXISTS(payload, '$.name') FROM raw_events;     -- TRUE/FALSE
SELECT JSON_VALUE(payload, '$.name') FROM raw_events;       -- String value
SELECT JSON_VALUE(payload, '$.age' RETURNING INT) FROM raw_events;  -- Typed value
SELECT JSON_QUERY(payload, '$.tags') FROM raw_events;       -- JSON sub-document

```

JSON_VALUE with error handling
```sql
SELECT JSON_VALUE(payload, '$.name'
    RETURNING STRING
    DEFAULT 'unknown' ON EMPTY
    DEFAULT 'error' ON ERROR
) FROM raw_events;

```

JSON_EXISTS with error handling
```sql
SELECT JSON_EXISTS(payload, '$.name'
    TRUE ON ERROR
) FROM raw_events;

```

JSON_QUERY for nested objects/arrays
```sql
SELECT JSON_QUERY(payload, '$.address') FROM raw_events;           -- JSON object
SELECT JSON_QUERY(payload, '$.tags' WITH WRAPPER) FROM raw_events;  -- Wrap in array
SELECT JSON_QUERY(payload, '$.tags' WITHOUT WRAPPER) FROM raw_events;

```

JSON_OBJECT (construct JSON)
```sql
SELECT JSON_OBJECT('name' VALUE 'alice', 'age' VALUE 25);
SELECT JSON_OBJECT(KEY 'name' VALUE username, KEY 'age' VALUE age) FROM users;

```

JSON_ARRAY (construct JSON array)
```sql
SELECT JSON_ARRAY('a', 'b', 'c');
SELECT JSON_ARRAY(1, 2, 3);

```

JSON_ARRAYAGG (aggregate into JSON array)
```sql
SELECT JSON_ARRAYAGG(username) FROM users;

```

JSON_OBJECTAGG (aggregate into JSON object)
```sql
SELECT JSON_OBJECTAGG(KEY username VALUE age) FROM users;

```

JSON format options
```sql
CREATE TABLE json_events (
    id         BIGINT,
    event_type STRING,
    payload    ROW<name STRING, value DOUBLE>
) WITH (
    'connector' = 'kafka',
    'topic' = 'events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json',
    'json.timestamp-format.standard' = 'SQL',
    'json.map-null-key.mode' = 'LITERAL',
    'json.map-null-key.literal' = 'null'
);

```

Canal JSON format (for CDC from MySQL)
```sql
CREATE TABLE mysql_cdc (
    id       BIGINT,
    username STRING,
    email    STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'mysql-binlog',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'canal-json'
);

```

Debezium JSON format (for CDC)
```sql
CREATE TABLE postgres_cdc (
    id       BIGINT,
    username STRING,
    email    STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'postgres-cdc',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'debezium-json'
);

```

Complex nested structures via ROW type (preferred over raw JSON)
```sql
CREATE TABLE complex_events (
    event_id BIGINT,
    user     ROW<id BIGINT, name STRING, email STRING>,
    items    ARRAY<ROW<product_id BIGINT, quantity INT, price DECIMAL(10,2)>>,
    metadata MAP<STRING, STRING>
) WITH (
    'connector' = 'kafka',
    'topic' = 'complex-events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

```

Access nested fields
```sql
SELECT user.id, user.name, items[1].product_id FROM complex_events;

```

Note: Flink maps JSON to SQL types via the 'json' format
Note: ROW type maps to JSON objects, ARRAY to JSON arrays, MAP to JSON objects
Note: JSON_VALUE, JSON_QUERY, JSON_EXISTS follow SQL/JSON standard (Flink 1.15+)
Note: For raw JSON manipulation, use STRING columns with JSON functions
Note: CDC formats (canal-json, debezium-json) automatically parse change events
Note: Structured types (ROW, ARRAY, MAP) are preferred over raw JSON STRING
Note: No JSONB or binary JSON type
