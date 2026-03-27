-- Firebird: String Functions
--
-- 参考资料:
--   [1] Firebird SQL Reference
--       https://firebirdsql.org/en/reference-manuals/
--   [2] Firebird Release Notes
--       https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html

-- Concatenation
SELECT 'hello' || ' ' || 'world' FROM RDB$DATABASE;         -- 'hello world'
-- Note: || is the only concatenation method (no CONCAT function)

-- Length
SELECT CHAR_LENGTH('hello') FROM RDB$DATABASE;               -- 5
SELECT CHARACTER_LENGTH('hello') FROM RDB$DATABASE;          -- 5
SELECT OCTET_LENGTH('hello') FROM RDB$DATABASE;              -- 5 (bytes)
SELECT BIT_LENGTH('hello') FROM RDB$DATABASE;                -- 40

-- Case
SELECT UPPER('hello') FROM RDB$DATABASE;                     -- 'HELLO'
SELECT LOWER('HELLO') FROM RDB$DATABASE;                     -- 'hello'
-- No INITCAP; implement via UDF or EXECUTE BLOCK

-- Substring
SELECT SUBSTRING('hello world' FROM 7 FOR 5) FROM RDB$DATABASE;  -- 'world' (SQL standard)
SELECT SUBSTRING('hello world' FROM 7) FROM RDB$DATABASE;        -- 'world'

-- Left / Right (via SUBSTRING)
SELECT LEFT('hello', 3) FROM RDB$DATABASE;                   -- 'hel' (2.1+)
SELECT RIGHT('hello', 3) FROM RDB$DATABASE;                  -- 'llo' (2.1+)

-- Position
SELECT POSITION('world' IN 'hello world') FROM RDB$DATABASE; -- 7
SELECT POSITION('world', 'hello world') FROM RDB$DATABASE;   -- 7 (alternative syntax)
SELECT POSITION('l' IN 'hello world' STARTING 4) FROM RDB$DATABASE; -- 4

-- Trim
SELECT TRIM('  hello  ') FROM RDB$DATABASE;                  -- 'hello'
SELECT TRIM(LEADING ' ' FROM '  hello  ') FROM RDB$DATABASE; -- 'hello  '
SELECT TRIM(TRAILING ' ' FROM '  hello  ') FROM RDB$DATABASE;-- '  hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx') FROM RDB$DATABASE;    -- 'hello'

-- Padding
SELECT LPAD('42', 5, '0') FROM RDB$DATABASE;                 -- '00042' (2.1+)
SELECT RPAD('hi', 5, '.') FROM RDB$DATABASE;                 -- 'hi...' (2.1+)

-- Replace
SELECT REPLACE('hello world', 'world', 'fb') FROM RDB$DATABASE;  -- 'hello fb' (2.1+)

-- Reverse
SELECT REVERSE('hello') FROM RDB$DATABASE;                   -- 'olleh' (2.0+)

-- Overlay (insert/replace at position)
SELECT OVERLAY('hello world' PLACING 'fb' FROM 7 FOR 5) FROM RDB$DATABASE; -- 'hello fb'

-- ASCII / CHAR
SELECT ASCII_CHAR(65) FROM RDB$DATABASE;                     -- 'A'
SELECT ASCII_VAL('A') FROM RDB$DATABASE;                     -- 65

-- Hash
SELECT HASH('hello') FROM RDB$DATABASE;                      -- hash value (2.1+)

-- SIMILAR TO (regex-like pattern matching, 2.5+)
SELECT CASE WHEN 'abc 123' SIMILAR TO '%[0-9]+%' THEN 'match' ELSE 'no match' END
FROM RDB$DATABASE;

-- CONTAINING (case-insensitive substring match, Firebird-specific)
SELECT * FROM users WHERE username CONTAINING 'alice';

-- STARTING WITH (prefix match, uses index)
SELECT * FROM users WHERE username STARTING WITH 'ali';

-- String aggregation (4.0+)
-- LIST() aggregate function
SELECT LIST(username, ', ') FROM users;               -- Firebird-specific
SELECT LIST(DISTINCT city, '; ') FROM users;

-- Note: RDB$DATABASE is the single-row system table
-- Note: many functions added in 2.0/2.1 (REPLACE, LPAD, RPAD, LEFT, RIGHT)
-- Note: no REGEXP functions; use SIMILAR TO for pattern matching
-- Note: LIST() is Firebird's string aggregation function
-- Note: CONTAINING is case-insensitive (unique to Firebird)
