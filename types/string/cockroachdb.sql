-- CockroachDB: String Types (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- CockroachDB supports all PostgreSQL string types

-- VARCHAR(n): variable-length, max n characters
-- CHAR(n): fixed-length, padded with spaces
-- TEXT / STRING: variable-length, no limit
-- BYTES: variable-length binary data

CREATE TABLE examples (
    name       VARCHAR(100),                   -- max 100 characters
    code       CHAR(5),                        -- fixed 5 characters, padded
    content    TEXT,                            -- unlimited text
    alias      STRING,                         -- CockroachDB alias for TEXT
    data       BYTES                           -- binary data
);

-- Note: STRING is a CockroachDB alias for TEXT (not in PostgreSQL)
-- Note: VARCHAR without length = TEXT (no limit)
-- Note: CHAR(n) is padded with spaces (avoid for variable-length data)

-- Type casting
SELECT CAST('hello' AS VARCHAR(10));
SELECT 'hello'::TEXT;
SELECT 'hello'::STRING;                        -- CockroachDB alias

-- String literals
SELECT 'hello world';                          -- standard single quote
SELECT E'hello\nworld';                        -- escape string (newline)
SELECT $$hello 'world'$$;                      -- dollar-quoted string
SELECT U&'\0041';                              -- Unicode escape (A)
SELECT b'\x68\x65\x6c\x6c\x6f';               -- BYTES literal

-- Collation (same as PostgreSQL)
SELECT 'hello' COLLATE "en_US";
CREATE TABLE localized (
    name VARCHAR(100) COLLATE "de_DE"
);

-- ENUM type (CockroachDB supports CREATE TYPE)
CREATE TYPE status AS ENUM ('active', 'inactive', 'deleted');
CREATE TABLE users (
    id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name   VARCHAR(100),
    status status DEFAULT 'active'
);
ALTER TYPE status ADD VALUE 'suspended';

-- Safe casting
-- CockroachDB does not have TRY_CAST, use conditional logic:
SELECT CASE WHEN '123' ~ '^\d+$' THEN '123'::INT ELSE NULL END;

-- Note: STRING is preferred alias in CockroachDB (same as TEXT)
-- Note: BYTES stores raw binary (use encode/decode for hex/base64)
-- Note: Collation support follows PostgreSQL
-- Note: ENUM types supported via CREATE TYPE
-- Note: No CLOB/BLOB types (use TEXT/BYTES instead)
-- Note: Maximum value size is 64 MiB
