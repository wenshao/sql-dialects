-- YugabyteDB: Numeric Types (YSQL, v2.x+)
--
-- 参考资料:
--   [1] YugabyteDB YSQL Reference
--       https://docs.yugabyte.com/stable/api/ysql/
--   [2] YugabyteDB PostgreSQL Compatibility
--       https://docs.yugabyte.com/stable/explore/ysql-language-features/

-- YugabyteDB supports all PostgreSQL numeric types

-- Integer types
-- SMALLINT / INT2: 2 bytes, -32768 ~ 32767
-- INTEGER / INT / INT4: 4 bytes, -2^31 ~ 2^31-1
-- BIGINT / INT8: 8 bytes, -2^63 ~ 2^63-1

CREATE TABLE examples (
    small_val  SMALLINT,                       -- 2 bytes
    medium_val INTEGER,                        -- 4 bytes
    large_val  BIGINT,                         -- 8 bytes
    auto_id    SERIAL,                         -- INT4 + sequence
    auto_id_lg BIGSERIAL                       -- INT8 + sequence
);

-- Note: SERIAL/BIGSERIAL use distributed sequences
-- Distributed sequences may produce non-contiguous values

-- Floating point
-- REAL / FLOAT4: 4 bytes, ~6 decimal digits precision
-- DOUBLE PRECISION / FLOAT8: 8 bytes, ~15 decimal digits precision

CREATE TABLE measurements (
    approx  REAL,                              -- 4-byte float
    precise DOUBLE PRECISION                   -- 8-byte float
);

-- Fixed-point (exact)
-- NUMERIC / DECIMAL: variable, up to 131072 digits before, 16383 after

CREATE TABLE prices (
    price     DECIMAL(10, 2),                  -- 10 digits, 2 decimal places
    tax_rate  NUMERIC(5, 4),                   -- 5 digits, 4 decimal places
    exact_val NUMERIC                          -- arbitrary precision
);

-- Boolean
-- BOOLEAN / BOOL: TRUE, FALSE, NULL

CREATE TABLE flags (
    active BOOL DEFAULT TRUE,
    valid  BOOLEAN NOT NULL
);

-- Type casting (same as PostgreSQL)
SELECT CAST('123' AS INTEGER);
SELECT '123'::INT;
SELECT '123'::BIGINT;
SELECT CAST('3.14' AS DECIMAL(10,2));

-- Special values
SELECT 'NaN'::FLOAT;
SELECT 'Infinity'::FLOAT;
SELECT '-Infinity'::FLOAT;

-- Math functions (same as PostgreSQL)
SELECT ABS(-5);
SELECT MOD(10, 3);                             -- 1
SELECT ROUND(3.14159, 2);                      -- 3.14
SELECT TRUNC(3.14159, 2);                      -- 3.14
SELECT CEIL(3.14);                             -- 4
SELECT FLOOR(3.14);                            -- 3
SELECT POWER(2, 10);                           -- 1024
SELECT SQRT(16);                               -- 4
SELECT LOG(2, 100);                            -- log base 2 of 100
SELECT LN(2.71828);                            -- ~1

-- UUID generation
SELECT gen_random_uuid();

-- Note: Same numeric types as PostgreSQL
-- Note: SERIAL uses distributed sequences (may have gaps)
-- Note: No MONEY type is recommended (use NUMERIC for currency)
-- Note: No UNSIGNED types
-- Note: Numeric overflow raises an error
-- Note: Based on PostgreSQL 11.2 type system
