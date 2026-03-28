# CockroachDB: 数值类型

> 参考资料:
> - [CockroachDB - SQL Statements](https://www.cockroachlabs.com/docs/stable/sql-statements)
> - [CockroachDB - Functions and Operators](https://www.cockroachlabs.com/docs/stable/functions-and-operators)
> - [CockroachDB - Data Types](https://www.cockroachlabs.com/docs/stable/data-types)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

```sql
CREATE TABLE examples (
    small_val  SMALLINT,                       -- 2 bytes
    medium_val INT,                            -- 4 bytes (alias: INT4, INTEGER)
    large_val  BIGINT,                         -- 8 bytes (alias: INT8)
    auto_id    SERIAL,                         -- INT4 + unique_rowid()
    auto_id_lg BIGSERIAL                       -- INT8 + unique_rowid()
);

```

Note: SERIAL uses unique_rowid() not sequences (unlike PostgreSQL)
Note: INT is 8 bytes by default in CockroachDB (unlike PostgreSQL's 4 bytes)
Can be changed: SET default_int_size = 4;

Floating point
FLOAT4 / REAL: 4 bytes, ~6 decimal digits precision
FLOAT8 / DOUBLE PRECISION / FLOAT: 8 bytes, ~15 decimal digits precision

```sql
CREATE TABLE measurements (
    approx  REAL,                              -- 4-byte float
    precise DOUBLE PRECISION                   -- 8-byte float (alias: FLOAT8)
);

```

Fixed-point (exact)
DECIMAL / NUMERIC: variable, up to 131072 digits before, 16383 after decimal

```sql
CREATE TABLE prices (
    price     DECIMAL(10, 2),                  -- 10 digits, 2 decimal places
    tax_rate  NUMERIC(5, 4),                   -- 5 digits, 4 decimal places
    exact_val DECIMAL                          -- arbitrary precision
);

```

Boolean
BOOL / BOOLEAN: TRUE, FALSE, NULL

```sql
CREATE TABLE flags (
    active BOOL DEFAULT TRUE,
    valid  BOOLEAN NOT NULL
);

```

Type casting
```sql
SELECT CAST('123' AS INT);
SELECT '123'::INT;
SELECT CAST('3.14' AS DECIMAL(10,2));

```

Special values
```sql
SELECT 'NaN'::FLOAT;
SELECT 'Infinity'::FLOAT;
SELECT '-Infinity'::FLOAT;

```

Math functions
```sql
SELECT ABS(-5);
SELECT MOD(10, 3);                             -- 1
SELECT ROUND(3.14159, 2);                      -- 3.14
SELECT TRUNC(3.14159, 2);                      -- 3.14
SELECT CEIL(3.14);                             -- 4
SELECT FLOOR(3.14);                            -- 3
SELECT POWER(2, 10);                           -- 1024
SELECT SQRT(16);                               -- 4
SELECT LOG(100);                               -- 2 (base 10)
SELECT LN(2.71828);                            -- ~1

```

unique_rowid() (CockroachDB-specific)
```sql
SELECT unique_rowid();                         -- time-ordered, node-unique 64-bit int

```

gen_random_uuid() (preferred for distributed primary keys)
```sql
SELECT gen_random_uuid();

```

Note: INT defaults to 8 bytes (INT8) in CockroachDB, not 4 bytes
Note: SERIAL uses unique_rowid(), not sequences
Note: DECIMAL supports arbitrary precision
Note: No MONEY type (use DECIMAL for currency)
Note: No UNSIGNED types
Note: Numeric overflow raises an error (no silent truncation)
