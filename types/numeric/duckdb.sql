-- DuckDB: Numeric Types (v0.8+)
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- Integer types
-- TINYINT / INT1:    1 byte,  -128 ~ 127
-- SMALLINT / INT2:   2 bytes, -32768 ~ 32767
-- INTEGER / INT / INT4: 4 bytes, -2^31 ~ 2^31-1
-- BIGINT / INT8:     8 bytes, -2^63 ~ 2^63-1
-- HUGEINT:           16 bytes, -2^127 ~ 2^127-1 (DuckDB-specific)
-- UHUGEINT:          16 bytes, 0 ~ 2^128-1 (unsigned, DuckDB v0.10+)

CREATE TABLE examples (
    tiny_val   TINYINT,
    small_val  SMALLINT,
    int_val    INTEGER,
    big_val    BIGINT,
    huge_val   HUGEINT                -- Unique to DuckDB: 128-bit integer
);

-- Unsigned integer types (DuckDB-specific)
-- UTINYINT:   1 byte,  0 ~ 255
-- USMALLINT:  2 bytes, 0 ~ 65535
-- UINTEGER:   4 bytes, 0 ~ 2^32-1
-- UBIGINT:    8 bytes, 0 ~ 2^64-1
-- UHUGEINT:   16 bytes, 0 ~ 2^128-1
CREATE TABLE counters (
    count_8  UTINYINT,
    count_16 USMALLINT,
    count_32 UINTEGER,
    count_64 UBIGINT
);

-- Floating point
-- FLOAT / FLOAT4 / REAL: 4 bytes, ~6 decimal digits precision
-- DOUBLE / FLOAT8 / DOUBLE PRECISION: 8 bytes, ~15 decimal digits precision
CREATE TABLE measurements (
    temperature FLOAT,
    precise_val DOUBLE
);

-- Decimal (exact numeric)
-- DECIMAL(p, s) / NUMERIC(p, s): Exact precision
-- p: total digits (1-38), s: decimal digits
CREATE TABLE prices (
    price     DECIMAL(10, 2),         -- Up to 99999999.99
    rate      DECIMAL(5, 4),          -- Up to 9.9999
    any_num   DECIMAL                 -- Default: DECIMAL(18, 3)
);

-- Boolean
CREATE TABLE flags (
    active BOOLEAN DEFAULT TRUE       -- TRUE / FALSE / NULL
);
SELECT TRUE, FALSE, NULL::BOOLEAN;

-- Special numeric values
SELECT 'NaN'::DOUBLE;                -- Not a Number
SELECT 'Infinity'::DOUBLE;           -- Positive infinity
SELECT '-Infinity'::DOUBLE;          -- Negative infinity

-- Auto-increment (via sequences)
CREATE SEQUENCE user_id_seq START 1;
CREATE TABLE users (
    id BIGINT DEFAULT nextval('user_id_seq') PRIMARY KEY
);

-- Numeric literals
SELECT 42;                            -- INTEGER
SELECT 42::BIGINT;                    -- Explicit BIGINT
SELECT 3.14;                          -- DECIMAL
SELECT 3.14::DOUBLE;                  -- Explicit DOUBLE
SELECT 1e10;                          -- Scientific notation (DOUBLE)
SELECT 0xFF;                          -- Hexadecimal
SELECT 0b1010;                        -- Binary literal
SELECT 0o17;                          -- Octal literal

-- Type casting
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;                -- PostgreSQL-style cast
SELECT TRY_CAST('abc' AS INTEGER);    -- Returns NULL on failure (DuckDB-specific)

-- Note: HUGEINT (128-bit) is unique to DuckDB, useful for large ID spaces
-- Note: Unsigned types are supported (unlike PostgreSQL)
-- Note: TRY_CAST is a safe cast that returns NULL instead of error
-- Note: DECIMAL supports up to 38 digits of precision
-- Note: No MONEY type (use DECIMAL for currency)
-- Note: No SERIAL type; use sequences with DEFAULT nextval(...)
