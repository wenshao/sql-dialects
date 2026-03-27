-- CockroachDB: String Functions (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- CockroachDB supports all PostgreSQL string functions

-- Concatenation
SELECT 'hello' || ' ' || 'world';                    -- 'hello world'
SELECT CONCAT('hello', ' ', 'world');                 -- NULL-safe
SELECT CONCAT_WS(',', 'a', 'b', 'c');                -- 'a,b,c'

-- Length
SELECT LENGTH('hello');                               -- 5 (characters)
SELECT OCTET_LENGTH('hello');                         -- 5 (bytes)
SELECT CHAR_LENGTH('hello');                          -- 5
SELECT BIT_LENGTH('hello');                           -- 40

-- Case
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
SELECT INITCAP('hello world');                        -- 'Hello World'

-- Substring
SELECT SUBSTRING('hello world' FROM 7 FOR 5);         -- 'world'
SELECT SUBSTR('hello world', 7, 5);                   -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'

-- Search
SELECT POSITION('world' IN 'hello world');            -- 7
SELECT STRPOS('hello world', 'world');                -- 7

-- Replace / Pad / Trim
SELECT REPLACE('hello world', 'world', 'crdb');       -- 'hello crdb'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');               -- 'hello'
SELECT BTRIM('xxhelloxx', 'x');                       -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'

-- Reverse / Repeat
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'

-- Regular expressions
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT SUBSTRING('abc 123 def' FROM '[0-9]+');        -- '123'
SELECT REGEXP_EXTRACT('abc 123 def', '[0-9]+');       -- '123' (CockroachDB-specific)
SELECT 'abc123' ~ '^[a-z]+[0-9]+$';                  -- true

-- String aggregation
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;

-- Split
SELECT SPLIT_PART('a.b.c', '.', 2);                  -- 'b'
SELECT STRING_TO_ARRAY('a,b,c', ',');                 -- {a,b,c}

-- Encoding
SELECT MD5('hello');
SELECT SHA256('hello'::BYTES);
SELECT ENCODE('hello'::BYTES, 'base64');
SELECT DECODE('aGVsbG8=', 'base64');
SELECT ENCODE('hello'::BYTES, 'hex');

-- Other
SELECT TRANSLATE('hello', 'helo', 'HELO');            -- 'HELLO'
SELECT OVERLAY('hello world' PLACING 'CRDB' FROM 7 FOR 5);  -- 'hello CRDB'
SELECT ASCII('A');                                    -- 65
SELECT CHR(65);                                       -- 'A'
SELECT QUOTE_LITERAL('hello');                        -- '''hello'''
SELECT QUOTE_IDENT('my column');                      -- '"my column"'

-- Note: All PostgreSQL string functions supported
-- Note: REGEXP_EXTRACT is CockroachDB-specific (similar to SUBSTRING FROM)
-- Note: || is the standard concatenation operator
-- Note: CONCAT handles NULL gracefully (treats as empty string)
