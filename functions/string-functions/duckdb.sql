-- DuckDB: String Functions (v0.8+)
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- Concatenation
SELECT 'hello' || ' ' || 'world';                    -- 'hello world' (recommended)
SELECT CONCAT('hello', ' ', 'world');                 -- 'hello world' (NULL-safe)
SELECT CONCAT_WS(',', 'a', 'b', 'c');                -- 'a,b,c'

-- Length
SELECT LENGTH('hello');                               -- 5 (characters)
SELECT STRLEN('hello');                               -- 5 (alias)
SELECT OCTET_LENGTH('你好');                           -- 6 (bytes, UTF-8)
SELECT CHAR_LENGTH('hello');                          -- 5
SELECT BIT_LENGTH('hello');                           -- 40

-- Case
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
SELECT INITCAP('hello world');                        -- 'Hello World'

-- Substring
SELECT SUBSTRING('hello world' FROM 7 FOR 5);         -- 'world' (SQL standard)
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'
SELECT SUBSTR('hello world', 7, 5);                   -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'
SELECT SUFFIX('hello', 3);                            -- 'llo' (alias for RIGHT)
SELECT PREFIX('hello', 3);                            -- 'hel' (alias for LEFT)

-- Search
SELECT POSITION('world' IN 'hello world');            -- 7
SELECT STRPOS('hello world', 'world');                -- 7
SELECT INSTR('hello world', 'world');                 -- 7
SELECT CONTAINS('hello world', 'world');              -- true (DuckDB-specific)
SELECT STARTS_WITH('hello world', 'hello');           -- true
SELECT ENDS_WITH('hello world', 'world');             -- true

-- Replace / Pad / Trim
SELECT REPLACE('hello world', 'world', 'duckdb');    -- 'hello duckdb'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT LTRIM('  hello  ');                            -- 'hello  '
SELECT RTRIM('  hello  ');                            -- '  hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');               -- 'hello'
SELECT STRIP_ACCENTS('cafe\u0301');                    -- 'cafe' (remove accents)

-- Reverse / Repeat
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'

-- Regular expressions
SELECT REGEXP_MATCHES('abc 123 def', '[0-9]+');       -- true
SELECT REGEXP_EXTRACT('abc 123 def', '[0-9]+');       -- '123'
SELECT REGEXP_EXTRACT('abc 123 def', '(\d+)', 1);    -- '123' (group 1)
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT REGEXP_SPLIT_TO_ARRAY('a,b,,c', ',');          -- ['a', 'b', '', 'c']
SELECT REGEXP_FULL_MATCH('hello', 'h.*o');            -- true (entire string)

-- String aggregation
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
SELECT GROUP_CONCAT(username, ', ') FROM users;       -- Alias

-- Split
SELECT SPLIT('a.b.c', '.');                           -- ['a', 'b', 'c']
SELECT STRING_SPLIT('a.b.c', '.');                    -- ['a', 'b', 'c']
SELECT SPLIT_PART('a.b.c', '.', 2);                  -- 'b'
SELECT STR_SPLIT_REGEX('a1b2c', '[0-9]');             -- ['a', 'b', 'c']

-- Other utility functions
SELECT TRANSLATE('hello', 'helo', 'HELO');            -- 'HELLO'
SELECT MD5('hello');                                  -- MD5 hash
SELECT SHA256('hello');                               -- SHA-256 hash
SELECT ENCODE('hello'::BLOB);                         -- Hex encoding
SELECT PRINTF('%s is %d years old', 'Alice', 25);    -- Format string (C-style)
SELECT FORMAT('{} is {} years old', 'Alice', 25);    -- Format string (Python-style)
SELECT BAR(0.5, 0, 1, 20);                           -- Visual bar: '██████████'

-- LIKE / ILIKE
SELECT 'Hello' LIKE 'H%';                            -- true (case-sensitive)
SELECT 'Hello' ILIKE 'h%';                           -- true (case-insensitive, DuckDB-specific)
SELECT 'Hello' SIMILAR TO 'H(e|a)llo';               -- true (SQL regex)

-- Levenshtein distance (fuzzy matching)
SELECT LEVENSHTEIN('kitten', 'sitting');              -- 3
SELECT JACCARD('hello', 'hallo');                     -- Jaccard similarity
SELECT JARO_WINKLER_SIMILARITY('hello', 'hallo');     -- Jaro-Winkler similarity

-- Unicode functions
SELECT UNICODE('A');                                  -- 65
SELECT CHR(65);                                       -- 'A'
SELECT ASCII('A');                                    -- 65

-- Note: DuckDB has ILIKE for case-insensitive matching (no need for LOWER + LIKE)
-- Note: CONTAINS, STARTS_WITH, ENDS_WITH are DuckDB-specific convenience functions
-- Note: PRINTF and FORMAT support C-style and Python-style format strings
-- Note: Fuzzy string matching (Levenshtein, Jaccard, Jaro-Winkler) built-in
-- Note: STRIP_ACCENTS removes diacritical marks from characters
