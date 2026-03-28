# DuckDB: 数值类型

> 参考资料:
> - [DuckDB - SQL Reference](https://duckdb.org/docs/sql/introduction)
> - [DuckDB - Functions](https://duckdb.org/docs/sql/functions/overview)
> - [DuckDB - Data Types](https://duckdb.org/docs/sql/data_types/overview)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

```sql
CREATE TABLE examples (
    tiny_val   TINYINT,
    small_val  SMALLINT,
    int_val    INTEGER,
    big_val    BIGINT,
    huge_val   HUGEINT                -- Unique to DuckDB: 128-bit integer
);

```

Unsigned integer types (DuckDB-specific)
UTINYINT:   1 byte,  0 ~ 255
USMALLINT:  2 bytes, 0 ~ 65535
UINTEGER:   4 bytes, 0 ~ 2^32-1
UBIGINT:    8 bytes, 0 ~ 2^64-1
UHUGEINT:   16 bytes, 0 ~ 2^128-1
```sql
CREATE TABLE counters (
    count_8  UTINYINT,
    count_16 USMALLINT,
    count_32 UINTEGER,
    count_64 UBIGINT
);

```

Floating point
FLOAT / FLOAT4 / REAL: 4 bytes, ~6 decimal digits precision
DOUBLE / FLOAT8 / DOUBLE PRECISION: 8 bytes, ~15 decimal digits precision
```sql
CREATE TABLE measurements (
    temperature FLOAT,
    precise_val DOUBLE
);

```

Decimal (exact numeric)
DECIMAL(p, s) / NUMERIC(p, s): Exact precision
p: total digits (1-38), s: decimal digits
```sql
CREATE TABLE prices (
    price     DECIMAL(10, 2),         -- Up to 99999999.99
    rate      DECIMAL(5, 4),          -- Up to 9.9999
    any_num   DECIMAL                 -- Default: DECIMAL(18, 3)
);

```

Boolean
```sql
CREATE TABLE flags (
    active BOOLEAN DEFAULT TRUE       -- TRUE / FALSE / NULL
);
SELECT TRUE, FALSE, NULL::BOOLEAN;

```

Special numeric values
```sql
SELECT 'NaN'::DOUBLE;                -- Not a Number
SELECT 'Infinity'::DOUBLE;           -- Positive infinity
SELECT '-Infinity'::DOUBLE;          -- Negative infinity

```

Auto-increment (via sequences)
```sql
CREATE SEQUENCE user_id_seq START 1;
CREATE TABLE users (
    id BIGINT DEFAULT nextval('user_id_seq') PRIMARY KEY
);

```

Numeric literals
```sql
SELECT 42;                            -- INTEGER
SELECT 42::BIGINT;                    -- Explicit BIGINT
SELECT 3.14;                          -- DECIMAL
SELECT 3.14::DOUBLE;                  -- Explicit DOUBLE
SELECT 1e10;                          -- Scientific notation (DOUBLE)
SELECT 0xFF;                          -- Hexadecimal
SELECT 0b1010;                        -- Binary literal
SELECT 0o17;                          -- Octal literal

```

Type casting
```sql
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;                -- PostgreSQL-style cast
SELECT TRY_CAST('abc' AS INTEGER);    -- Returns NULL on failure (DuckDB-specific)

```

Note: HUGEINT (128-bit) is unique to DuckDB, useful for large ID spaces
Note: Unsigned types are supported (unlike PostgreSQL)
Note: TRY_CAST is a safe cast that returns NULL instead of error
Note: DECIMAL supports up to 38 digits of precision
Note: No MONEY type (use DECIMAL for currency)
Note: No SERIAL type; use sequences with DEFAULT nextval(...)
