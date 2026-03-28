# Flink SQL: 字符串类型

> 参考资料:
> - [Flink SQL Documentation](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
> - [Flink SQL - Built-in Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/)
> - [Flink SQL - Data Types](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

```sql
CREATE TABLE examples (
    code    CHAR(10),                 -- Fixed-length, padded
    name    VARCHAR(255),             -- Variable-length with limit
    content STRING,                   -- Variable-length, no limit (recommended)
    data    BYTES                     -- Binary data
) WITH (
    'connector' = 'kafka',
    'topic' = 'examples',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

```

Type equivalences
STRING = VARCHAR(2147483647) (max INT)
BYTES = VARBINARY(2147483647)

CHAR vs VARCHAR
CHAR(n): Always n characters, padded with spaces on the right
VARCHAR(n): Up to n characters, no padding
STRING: Unlimited length VARCHAR

String literals
```sql
SELECT 'hello world';                -- Single quotes
SELECT 'it''s a test';               -- Escaped single quote

```

Unicode
```sql
SELECT '你好世界';                     -- UTF-8 native
SELECT CHAR_LENGTH('你好');           -- 2 (character count)
SELECT OCTET_LENGTH('你好');          -- 6 (byte count, UTF-8)

```

Type casting
```sql
SELECT CAST(123 AS STRING);          -- Number to string
SELECT CAST('123' AS INT);           -- String to number
SELECT CAST('2024-01-15' AS DATE);   -- String to date

```

Binary operations
```sql
SELECT CAST('hello' AS BYTES);       -- String to binary
SELECT CAST(x'48656C6C6F' AS STRING); -- Hex literal to string

```

String type in table creation with connectors
```sql
CREATE TABLE json_events (
    event_id   STRING,                -- JSON string fields map to STRING
    payload    STRING,                -- Raw JSON payload as string
    created_at STRING                 -- Timestamp as string before parsing
) WITH (
    'connector' = 'kafka',
    'topic' = 'events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

```

Note: STRING is the recommended type for text data in Flink
Note: VARCHAR without length is equivalent to STRING
Note: No TEXT type (use STRING instead)
Note: No ENUM type
Note: CHAR(n) comparisons ignore trailing spaces
Note: String length is limited by available memory in the TaskManager
Note: When using JSON format, most fields are naturally STRING
