# Flink SQL: 数值类型

> 参考资料:
> - [Flink SQL Documentation](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
> - [Flink SQL - Built-in Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/)
> - [Flink SQL - Data Types](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

```sql
CREATE TABLE examples (
    tiny_val  TINYINT,
    small_val SMALLINT,
    int_val   INT,
    big_val   BIGINT
) WITH (
    'connector' = 'kafka',
    'topic' = 'examples',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

```

No unsigned integer types in Flink SQL

Floating point
FLOAT:  4 bytes, ~6 decimal digits precision
DOUBLE: 8 bytes, ~15 decimal digits precision
```sql
CREATE TABLE measurements (
    temperature FLOAT,
    precise_val DOUBLE
) WITH (
    'connector' = 'kafka',
    'topic' = 'measurements',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

```

Decimal (exact numeric)
DECIMAL(p, s) / DEC(p, s) / NUMERIC(p, s): Exact precision
p: total digits (1-38), s: decimal digits (0 to p)
```sql
CREATE TABLE prices (
    price   DECIMAL(10, 2),           -- Up to 99999999.99
    rate    DECIMAL(5, 4),            -- Up to 9.9999
    any_num DECIMAL                   -- Default: DECIMAL(10, 0)
) WITH (
    'connector' = 'kafka',
    'topic' = 'prices',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

```

Boolean
BOOLEAN: TRUE / FALSE / NULL
```sql
CREATE TABLE flags (
    active BOOLEAN
) WITH (
    'connector' = 'kafka',
    'topic' = 'flags',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

```

Numeric literals
```sql
SELECT 42;                            -- INT
SELECT CAST(42 AS BIGINT);            -- BIGINT
SELECT 3.14;                          -- DECIMAL
SELECT CAST(3.14 AS DOUBLE);          -- DOUBLE
SELECT 1e10;                          -- DOUBLE (scientific notation)

```

Type casting
```sql
SELECT CAST('123' AS INT);
SELECT CAST('3.14' AS DECIMAL(10, 2));
SELECT CAST(123 AS STRING);

```

TRY_CAST (Flink 1.15+)
```sql
SELECT TRY_CAST('abc' AS INT);        -- Returns NULL on failure

```

Numeric precision in streaming
Flink preserves DECIMAL precision through computations
SUM of DECIMAL(10,2) may produce DECIMAL(38,2) to avoid overflow

Type mapping with connectors
JSON format:  integer -> INT/BIGINT, number -> DOUBLE, decimal string -> DECIMAL
Avro format:  int -> INT, long -> BIGINT, float -> FLOAT, double -> DOUBLE
CSV format:   all fields are strings, require explicit CAST

Note: Flink uses Java types internally (byte, short, int, long, float, double)
Note: No unsigned integer types
Note: No HUGEINT or 128-bit integers
Note: DECIMAL max precision is 38 digits
Note: No auto-increment (IDs come from source systems)
Note: No MONEY type (use DECIMAL for currency)
Note: Numeric overflow behavior depends on the data type
      (integers overflow silently, DECIMAL throws error)
Note: JSON numbers map to DOUBLE by default; use DECIMAL for exact precision
