-- YugabyteDB: String Functions (YSQL, v2.x+)
--
-- 参考资料:
--   [1] YugabyteDB YSQL Reference
--       https://docs.yugabyte.com/stable/api/ysql/
--   [2] YugabyteDB PostgreSQL Compatibility
--       https://docs.yugabyte.com/stable/explore/ysql-language-features/

-- YugabyteDB supports all PostgreSQL string functions

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
SELECT REPLACE('hello world', 'world', 'yb');         -- 'hello yb'
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

-- Regular expressions (same as PostgreSQL)
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT SUBSTRING('abc 123 def' FROM '[0-9]+');        -- '123'

-- String aggregation
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;

-- Split
SELECT SPLIT_PART('a.b.c', '.', 2);                  -- 'b'
SELECT STRING_TO_ARRAY('a,b,c', ',');                 -- {a,b,c}

-- Encoding
SELECT MD5('hello');
SELECT ENCODE('hello'::BYTEA, 'base64');
SELECT DECODE('aGVsbG8=', 'base64');
SELECT ENCODE('hello'::BYTEA, 'hex');

-- Other
SELECT TRANSLATE('hello', 'helo', 'HELO');            -- 'HELLO'
SELECT OVERLAY('hello world' PLACING 'YB' FROM 7 FOR 5);  -- 'hello YB'
SELECT ASCII('A');                                    -- 65
SELECT CHR(65);                                       -- 'A'
SELECT QUOTE_LITERAL('hello');                        -- '''hello'''
SELECT QUOTE_IDENT('my column');                      -- '"my column"'

-- Note: All PostgreSQL string functions supported
-- Note: || is the standard concatenation operator
-- Note: CONCAT handles NULL gracefully
-- Note: Based on PostgreSQL 11.2 string function set
-- Note: REGEXP_SUBSTR/REGEXP_COUNT not available (PG 15+ features)
