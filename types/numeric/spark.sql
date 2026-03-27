-- Spark SQL: Numeric Types (Spark 2.0+)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Integer types
-- TINYINT / BYTE:   1 byte,  -128 ~ 127
-- SMALLINT / SHORT: 2 bytes, -32768 ~ 32767
-- INT / INTEGER:    4 bytes, -2^31 ~ 2^31-1
-- BIGINT / LONG:    8 bytes, -2^63 ~ 2^63-1

CREATE TABLE examples (
    tiny_val  TINYINT,
    small_val SMALLINT,
    int_val   INT,
    big_val   BIGINT
) USING PARQUET;

-- No unsigned integer types in Spark

-- Floating point
-- FLOAT / REAL:   4 bytes, ~6 decimal digits precision
-- DOUBLE:         8 bytes, ~15 decimal digits precision
CREATE TABLE measurements (
    temperature FLOAT,
    precise_val DOUBLE
) USING PARQUET;

-- Decimal (exact numeric)
-- DECIMAL(p, s) / DEC(p, s) / NUMERIC(p, s): Exact precision
-- p: total digits (max 38), s: decimal digits
CREATE TABLE prices (
    price   DECIMAL(10, 2),           -- Up to 99999999.99
    rate    DECIMAL(5, 4),            -- Up to 9.9999
    any_num DECIMAL                   -- Default: DECIMAL(10, 0)
) USING PARQUET;

-- Boolean
CREATE TABLE flags (
    active BOOLEAN                    -- TRUE / FALSE / NULL
) USING PARQUET;

-- Numeric literals
SELECT 42;                            -- INT
SELECT 42L;                           -- BIGINT (L suffix)
SELECT 42S;                           -- SMALLINT (S suffix)
SELECT 42Y;                           -- TINYINT (Y suffix)
SELECT 3.14;                          -- DECIMAL
SELECT 3.14D;                         -- DOUBLE (D suffix)
SELECT 3.14F;                         -- FLOAT (F suffix)
SELECT 3.14BD;                        -- DECIMAL (BD suffix, Spark 3.0+)
SELECT 1e10;                          -- DOUBLE (scientific notation)
SELECT 0xFF;                          -- Hexadecimal INT

-- Type casting
SELECT CAST('123' AS INT);
SELECT INT('123');                     -- Function-style cast (Spark-specific)
SELECT DOUBLE('3.14');
SELECT DECIMAL(123.456);

-- Safe casting (Spark 3.4+)
SELECT TRY_CAST('abc' AS INT);        -- Returns NULL on failure

-- Special values
SELECT DOUBLE('NaN');                  -- Not a Number
SELECT DOUBLE('Infinity');             -- Positive infinity
SELECT DOUBLE('-Infinity');            -- Negative infinity

-- Auto-increment alternatives
-- No SERIAL or IDENTITY; use these instead:
SELECT monotonically_increasing_id() AS id, username FROM users;
-- Note: monotonically_increasing_id() is not sequential, but unique per partition

-- Type widening rules
-- TINYINT -> SMALLINT -> INT -> BIGINT -> DECIMAL -> FLOAT -> DOUBLE
-- Spark automatically widens types in operations

-- Overflow handling (Spark 3.0+)
-- SET spark.sql.ansi.enabled = true;
-- With ANSI mode: arithmetic overflow throws error
-- Without ANSI: overflow wraps around silently

-- Note: Spark uses JVM types internally (Byte, Short, Int, Long, Float, Double)
-- Note: No unsigned integer types
-- Note: No HUGEINT or 128-bit integers
-- Note: DECIMAL max precision is 38 digits
-- Note: Numeric suffix literals (L, S, Y, D, F, BD) are Spark-specific
-- Note: No MONEY type (use DECIMAL for currency)
