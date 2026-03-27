-- Google Cloud Spanner: Numeric Types (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- INT64: 8 bytes, -2^63 ~ 2^63-1 (only integer type)
-- FLOAT32: 4 bytes, IEEE 754 single precision (2023+)
-- FLOAT64: 8 bytes, IEEE 754 double precision
-- NUMERIC: 29 digits before decimal, 9 after (fixed-point)
-- BOOL: TRUE / FALSE / NULL

CREATE TABLE Examples (
    Id         INT64 NOT NULL,
    SmallVal   INT64,                          -- only integer type
    Price      NUMERIC,                        -- exact: 29.9 precision
    Ratio      FLOAT64,                        -- approximate
    RatioSmall FLOAT32,                        -- 4-byte float (2023+)
    Active     BOOL DEFAULT (true)
) PRIMARY KEY (Id);

-- Note: No INT, INTEGER, SMALLINT, TINYINT, BIGINT
-- INT64 is the only integer type
-- Note: No DECIMAL / NUMERIC(P,S) with precision parameters

-- Type casting
SELECT CAST('123' AS INT64);
SELECT CAST('3.14' AS FLOAT64);
SELECT CAST('3.14' AS NUMERIC);
SELECT SAFE_CAST('abc' AS INT64);              -- returns NULL on failure

-- Special values
SELECT CAST('nan' AS FLOAT64);                 -- NaN
SELECT CAST('inf' AS FLOAT64);                 -- Infinity
SELECT IEEE_DIVIDE(1, 0);                      -- Infinity
SELECT IEEE_DIVIDE(0, 0);                      -- NaN

-- Boolean
SELECT CAST(1 AS BOOL);                        -- TRUE
SELECT CAST(0 AS BOOL);                        -- FALSE

-- Math functions
SELECT ABS(-5);                                -- 5
SELECT MOD(10, 3);                             -- 1
SELECT ROUND(3.14159, 2);                      -- 3.14
SELECT TRUNC(3.14159, 2);                      -- 3.14
SELECT CEIL(3.14);                             -- 4
SELECT FLOOR(3.14);                            -- 3
SELECT POWER(2, 10);                           -- 1024
SELECT SQRT(16.0);                             -- 4.0
SELECT LOG(100.0);                             -- ~4.605 (natural log)
SELECT LOG10(100.0);                           -- 2.0
SELECT SIGN(-5);                               -- -1
SELECT DIV(10, 3);                             -- 3 (integer division)

-- Generating unique IDs
SELECT GENERATE_UUID();                        -- returns STRING (UUID v4)

-- Bit-reversed sequences (for sequential-yet-distributed IDs)
-- CREATE SEQUENCE MySeq OPTIONS (sequence_kind = 'bit_reversed_positive');
-- SELECT GET_NEXT_SEQUENCE_VALUE(SEQUENCE MySeq);

-- Note: INT64 is the only integer type (no smaller variants)
-- Note: NUMERIC has fixed precision (29 digits before, 9 after decimal)
-- Note: No NUMERIC(P,S) parameterized form
-- Note: No SERIAL / AUTO_INCREMENT
-- Note: No MONEY, UNSIGNED, or BIT types
-- Note: SAFE_CAST returns NULL on failure (very useful)
-- Note: IEEE_DIVIDE handles division by zero gracefully
-- Note: Use GENERATE_UUID() for unique string IDs
