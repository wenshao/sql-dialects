-- Teradata: String Types
--
-- 参考资料:
--   [1] Teradata SQL Reference
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates
--   [2] Teradata Database Documentation
--       https://docs.teradata.com/

-- CHAR(n) / CHARACTER(n): fixed-length, padded with spaces
-- VARCHAR(n) / CHARACTER VARYING(n): variable-length, max 64000 bytes
-- CLOB: Character Large Object, up to 2GB

CREATE TABLE examples (
    code    CHAR(10),              -- fixed-length
    name    VARCHAR(255),          -- variable-length
    content CLOB                   -- large text
);

-- Unicode types
-- CHAR/VARCHAR default charset depends on session/database setting
-- Use CHARACTER SET UNICODE for explicit Unicode
CREATE TABLE unicode_example (
    name VARCHAR(100) CHARACTER SET UNICODE,
    bio  VARCHAR(10000) CHARACTER SET UNICODE
);

-- GRAPHIC / VARGRAPHIC (fixed/variable-length double-byte character)
CREATE TABLE graphic_example (
    code GRAPHIC(10),
    name VARGRAPHIC(255)
);

-- CLOB with character set
CREATE TABLE text_data (
    content CLOB(1M) CHARACTER SET UNICODE
);

-- BYTE / VARBYTE (binary data)
CREATE TABLE binary_data (
    fixed_data BYTE(100),
    var_data   VARBYTE(10000)
);

-- BLOB (Binary Large Object)
CREATE TABLE files (
    data BLOB(10M)
);

-- String with COMPRESS (save space for repeated values)
CREATE TABLE logs (
    level VARCHAR(20) COMPRESS ('INFO', 'WARN', 'ERROR', 'DEBUG')
);

-- PERIOD types (Teradata-specific, not strings but text representation)
-- PERIOD(DATE), PERIOD(TIME), PERIOD(TIMESTAMP)

-- Collation
-- Server-level character set and collation
-- Session-level: SET SESSION CHARACTER SET UNICODE;

-- Note: VARCHAR maximum is 64000 bytes (not characters)
-- Note: UNICODE characters use 2-3 bytes each, so max chars is less
-- Note: CLOB columns cannot be used in PRIMARY INDEX
-- Note: no TEXT type; use CLOB or VARCHAR
