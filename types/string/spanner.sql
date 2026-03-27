-- Google Cloud Spanner: String Types (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- STRING(N): variable-length UTF-8, max N characters
-- STRING(MAX): variable-length, up to 2.5 MB
-- BYTES(N): variable-length binary, max N bytes
-- BYTES(MAX): variable-length binary, up to 10 MB

CREATE TABLE Examples (
    Name       STRING(100),                    -- max 100 characters
    ShortCode  STRING(5),                      -- max 5 characters
    Content    STRING(MAX),                    -- up to 2.5 MB
    Data       BYTES(MAX)                      -- binary, up to 10 MB
) PRIMARY KEY (Name);

-- Note: STRING requires length: STRING(N) or STRING(MAX)
-- Note: No CHAR, VARCHAR, TEXT types
-- Note: No CLOB/BLOB types
-- Note: String is always UTF-8 encoded

-- String literals
SELECT 'hello world';
SELECT "hello world";                          -- double quotes for strings too
SELECT '''multi
line string''';                                -- triple-quoted multi-line
SELECT r'\n is literal';                       -- raw string (no escapes)
SELECT b'binary data';                         -- BYTES literal
SELECT rb'\x00\x01';                           -- raw BYTES literal

-- Type casting
SELECT CAST('hello' AS STRING(100));
SELECT CAST(123 AS STRING);
SELECT SAFE_CAST('abc' AS INT64);              -- returns NULL on failure

-- Collation
SELECT COLLATE('hello', 'und:ci') = COLLATE('HELLO', 'und:ci');  -- TRUE (case-insensitive)
-- und:ci = Unicode default, case-insensitive

-- Column-level collation
CREATE TABLE LocalizedData (
    Id    INT64 NOT NULL,
    Name  STRING(100),
    NameCI STRING(100) AS (COLLATE(Name, 'und:ci')) STORED  -- case-insensitive column
) PRIMARY KEY (Id);

-- No ENUM type
-- Use STRING with CHECK constraint instead:
CREATE TABLE Users (
    UserId INT64 NOT NULL,
    Status STRING(20),
    CONSTRAINT chk_status CHECK (Status IN ('active', 'inactive', 'deleted'))
) PRIMARY KEY (UserId);

-- Proto and ENUM (Protocol Buffer types, Spanner-specific)
-- Spanner supports PROTO and ENUM types from Protocol Buffer definitions
-- CREATE PROTO BUNDLE (mypackage.MyProto);

-- Note: STRING(N) is required (no default length)
-- Note: STRING(MAX) for large text (up to 2.5 MB)
-- Note: SAFE_CAST returns NULL on failure (like BigQuery)
-- Note: Collation uses ICU locale identifiers (e.g., 'und:ci')
-- Note: No ENUM; use STRING + CHECK or Protocol Buffer ENUMs
-- Note: Raw strings (r'...') disable escape processing
