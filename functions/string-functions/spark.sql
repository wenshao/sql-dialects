-- Spark SQL: String Functions (Spark 2.0+)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Concatenation
SELECT CONCAT('hello', ' ', 'world');                 -- 'hello world' (NULL-safe)
SELECT CONCAT_WS(',', 'a', 'b', 'c');                -- 'a,b,c'
SELECT 'hello' || ' ' || 'world';                    -- 'hello world' (Spark 2.4+)

-- Length
SELECT LENGTH('hello');                               -- 5 (characters)
SELECT CHAR_LENGTH('hello');                          -- 5
SELECT CHARACTER_LENGTH('hello');                     -- 5
SELECT OCTET_LENGTH('你好');                           -- 6 (bytes, UTF-8)
SELECT BIT_LENGTH('hello');                           -- 40

-- Case
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
SELECT INITCAP('hello world');                        -- 'Hello World'

-- Substring
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'
SELECT SUBSTRING('hello world' FROM 7 FOR 5);         -- 'world'
SELECT SUBSTR('hello world', 7, 5);                   -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'

-- Search
SELECT POSITION('world' IN 'hello world');            -- 7
SELECT INSTR('hello world', 'world');                 -- 7
SELECT LOCATE('world', 'hello world');                -- 7
SELECT LOCATE('world', 'hello world', 8);             -- 0 (start from position 8)

-- Replace / Pad / Trim
SELECT REPLACE('hello world', 'world', 'spark');     -- 'hello spark'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT LTRIM('  hello  ');                            -- 'hello  '
SELECT RTRIM('  hello  ');                            -- '  hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');               -- 'hello'
SELECT BTRIM('xxhelloxx', 'x');                       -- 'hello' (Spark 3.0+)

-- OVERLAY (replace substring at position)
SELECT OVERLAY('hello world' PLACING 'spark' FROM 7 FOR 5);  -- 'hello spark'

-- Reverse / Repeat
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'

-- Regular expressions
SELECT 'abc 123' RLIKE '[0-9]+';                      -- true
SELECT REGEXP_EXTRACT('abc 123 def', '(\\d+)', 1);   -- '123'
SELECT REGEXP_REPLACE('abc 123 def', '\\d+', '#');    -- 'abc # def'
SELECT REGEXP_LIKE('abc 123', '\\d+');                -- true (Spark 3.2+)
SELECT REGEXP_COUNT('a1b2c3', '\\d');                 -- 3 (Spark 3.4+)
SELECT REGEXP_SUBSTR('abc 123 def', '\\d+');          -- '123' (Spark 3.4+)
SELECT REGEXP_INSTR('abc 123 def', '\\d+');           -- 5 (Spark 3.4+)

-- String aggregation
SELECT CONCAT_WS(', ', COLLECT_LIST(username)) FROM users;
-- Or with sorting (Spark 3.4+):
-- SELECT ARRAY_JOIN(SORT_ARRAY(COLLECT_LIST(username)), ', ') FROM users;

-- Split
SELECT SPLIT('a.b.c', '\\.');                         -- ['a', 'b', 'c'] (regex split)
SELECT SPLIT('a,b,c', ',');                           -- ['a', 'b', 'c']

-- Sentences (tokenize into words)
SELECT SENTENCES('Hello World. How are you?');        -- [['Hello','World'],['How','are','you']]

-- Encoding
SELECT BASE64(CAST('hello' AS BINARY));               -- 'aGVsbG8='
SELECT UNBASE64('aGVsbG8=');                          -- binary
SELECT HEX('hello');                                  -- '68656C6C6F'
SELECT UNHEX('68656C6C6F');                           -- binary

-- Other utility functions
SELECT TRANSLATE('hello', 'helo', 'HELO');            -- 'HELLO'
SELECT MD5('hello');                                  -- MD5 hash
SELECT SHA1('hello');                                 -- SHA-1 hash
SELECT SHA2('hello', 256);                            -- SHA-256 hash
SELECT SOUNDEX('hello');                              -- Phonetic hash
SELECT LEVENSHTEIN('kitten', 'sitting');              -- 3 (edit distance)
SELECT ASCII('A');                                    -- 65
SELECT CHR(65);                                       -- 'A'
SELECT FORMAT_STRING('%s is %d years old', 'Alice', 25);  -- Formatted string
SELECT PRINTF('%s is %d years old', 'Alice', 25);    -- Same (Spark 3.5+)

-- URL functions
SELECT PARSE_URL('http://example.com/path?q=1', 'HOST');     -- 'example.com'
SELECT PARSE_URL('http://example.com/path?q=1', 'QUERY');    -- 'q=1'
SELECT URL_ENCODE('hello world');                             -- 'hello+world' (Spark 3.4+)
SELECT URL_DECODE('hello+world');                             -- 'hello world' (Spark 3.4+)

-- LIKE / RLIKE
SELECT 'Hello' LIKE 'H%';                            -- true
SELECT 'Hello' LIKE 'h%';                            -- false (case-sensitive)
-- Case-insensitive: use LOWER
SELECT LOWER('Hello') LIKE 'h%';                     -- true
SELECT 'Hello' RLIKE '(?i)h.*';                      -- true (regex case-insensitive flag)

-- Note: Spark uses Java regex syntax (double backslash for escapes)
-- Note: No ILIKE; use LOWER() + LIKE or regex (?i) flag
-- Note: SPLIT uses regex pattern (escape special characters with \\)
-- Note: COLLECT_LIST + CONCAT_WS replaces STRING_AGG
-- Note: LEVENSHTEIN distance is built-in
-- Note: SENTENCES function is unique to Spark (natural language tokenization)
