-- YugabyteDB: String Types (YSQL, v2.x+)
--
-- 参考资料:
--   [1] YugabyteDB YSQL Reference
--       https://docs.yugabyte.com/stable/api/ysql/
--   [2] YugabyteDB PostgreSQL Compatibility
--       https://docs.yugabyte.com/stable/explore/ysql-language-features/

-- YugabyteDB supports all PostgreSQL string types

-- VARCHAR(n): variable-length, max n characters
-- CHAR(n): fixed-length, padded with spaces
-- TEXT: variable-length, no limit
-- BYTEA: variable-length binary data

CREATE TABLE examples (
    name       VARCHAR(100),                   -- max 100 characters
    code       CHAR(5),                        -- fixed 5 characters, padded
    content    TEXT,                            -- unlimited text
    data       BYTEA                           -- binary data
);

-- Note: VARCHAR without length = TEXT (no limit)
-- Note: CHAR(n) is padded with spaces (avoid for variable-length data)
-- Note: TEXT has no practical length limit

-- Type casting (same as PostgreSQL)
SELECT CAST('hello' AS VARCHAR(10));
SELECT 'hello'::TEXT;
SELECT 'hello'::VARCHAR(100);

-- String literals (same as PostgreSQL)
SELECT 'hello world';                          -- standard single quote
SELECT E'hello\nworld';                        -- escape string (newline)
SELECT $$hello 'world'$$;                      -- dollar-quoted string
SELECT U&'\0041';                              -- Unicode escape (A)
SELECT '\x68656c6c6f'::BYTEA;                  -- BYTEA literal

-- Collation (same as PostgreSQL)
SELECT 'hello' COLLATE "en_US";
CREATE TABLE localized (
    name VARCHAR(100) COLLATE "en_US"
);

-- ENUM type (same as PostgreSQL)
CREATE TYPE status AS ENUM ('active', 'inactive', 'deleted');
CREATE TABLE users (
    id     BIGSERIAL PRIMARY KEY,
    name   VARCHAR(100),
    status status DEFAULT 'active'
);
ALTER TYPE status ADD VALUE 'suspended';

-- Safe casting (no built-in TRY_CAST)
SELECT CASE WHEN '123' ~ '^\d+$' THEN '123'::INT ELSE NULL END;

-- Binary encoding/decoding
SELECT ENCODE('hello'::BYTEA, 'base64');       -- encode to base64
SELECT DECODE('aGVsbG8=', 'base64');           -- decode from base64
SELECT ENCODE('hello'::BYTEA, 'hex');          -- encode to hex

-- Note: Same string types as PostgreSQL
-- Note: No STRING alias (use TEXT or VARCHAR)
-- Note: BYTEA for binary data (not BYTES)
-- Note: ENUM types supported via CREATE TYPE
-- Note: No CLOB/BLOB types (use TEXT/BYTEA)
-- Note: Collation follows PostgreSQL conventions
-- Note: Based on PostgreSQL 11.2 type system
