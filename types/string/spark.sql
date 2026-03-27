-- Spark SQL: String Types (Spark 2.0+)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- STRING: Primary string type (variable-length, UTF-8)
-- VARCHAR(n): Alias for STRING (length not enforced before Spark 3.1)
-- CHAR(n): Fixed-length (Spark 3.1+, enforced)
-- BINARY: Binary data type

CREATE TABLE examples (
    code    CHAR(10),                 -- Fixed-length (Spark 3.1+, padded)
    name    VARCHAR(255),             -- Variable-length (enforced Spark 3.1+)
    content STRING                   -- Variable-length, no limit (recommended)
) USING PARQUET;

-- Spark recommendation: Always use STRING
-- VARCHAR(n) and CHAR(n) are primarily for Hive compatibility

-- Binary data
CREATE TABLE files (
    data BINARY                       -- Raw bytes
) USING PARQUET;

-- String literals
SELECT 'hello world';                -- Single quotes
SELECT "hello world";                -- Double quotes also work in Spark
SELECT 'it''s a test';               -- Escaped single quote
SELECT 'line1\nline2';               -- Escape sequences in strings

-- Unicode
SELECT '你好世界';                     -- UTF-8 native
SELECT LENGTH('你好');                 -- 2 (character count)
SELECT OCTET_LENGTH('你好');           -- 6 (byte count, UTF-8)

-- String encoding/decoding
SELECT ENCODE('hello', 'UTF-8');     -- String to binary
SELECT DECODE(ENCODE('hello', 'UTF-8'), 'UTF-8');  -- Binary to string
SELECT BASE64(CAST('hello' AS BINARY));  -- Base64 encode
SELECT UNBASE64('aGVsbG8=');         -- Base64 decode

-- Type casting
SELECT CAST(123 AS STRING);          -- Number to string
SELECT CAST('123' AS INT);           -- String to number
SELECT STRING(123);                  -- Alternative cast syntax

-- Collation (Spark 3.4+, limited support)
-- Spark uses binary comparison by default
-- Collation support is being added progressively

-- Note: STRING is the standard string type in Spark (not VARCHAR or TEXT)
-- Note: VARCHAR(n) was ignored before Spark 3.1 (treated as STRING)
-- Note: CHAR(n) pads with spaces and trims on comparison (Spark 3.1+)
-- Note: Maximum string size limited by JVM memory and Spark configuration
-- Note: Double quotes for string literals is Spark-specific (not SQL standard)
-- Note: No ENUM type; use string values or map to integers
