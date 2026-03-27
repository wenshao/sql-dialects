-- Google Cloud Spanner: String Functions (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- Concatenation
SELECT CONCAT('hello', ' ', 'world');                 -- 'hello world' (NULL-safe)
SELECT 'hello' || ' ' || 'world';                    -- 'hello world'
-- Note: || returns NULL if any operand is NULL; CONCAT treats NULL as ''

-- Length
SELECT LENGTH('hello');                               -- 5 (characters)
SELECT CHAR_LENGTH('hello');                          -- 5
SELECT BYTE_LENGTH('hello');                          -- 5 (UTF-8 bytes)

-- Case
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
SELECT INITCAP('hello world');                        -- 'Hello World'

-- Substring
SELECT SUBSTR('hello world', 7, 5);                   -- 'world'
SELECT SUBSTR('hello world', 7);                      -- 'world' (to end)
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'

-- Search
SELECT STRPOS('hello world', 'world');                -- 7
SELECT INSTR('hello world', 'world');                 -- 7
SELECT STARTS_WITH('hello world', 'hello');           -- TRUE
SELECT ENDS_WITH('hello world', 'world');             -- TRUE
SELECT CONTAINS_SUBSTR('hello world', 'world');       -- TRUE (case-insensitive)

-- Replace / Pad / Trim
SELECT REPLACE('hello world', 'world', 'spanner');    -- 'hello spanner'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'
SELECT TRIM('x' FROM 'xxhelloxx');                    -- 'hello'

-- Reverse / Repeat
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'

-- Regular expressions
SELECT REGEXP_CONTAINS('abc 123', r'[0-9]+');         -- TRUE
SELECT REGEXP_EXTRACT('abc 123 def', r'[0-9]+');      -- '123'
SELECT REGEXP_EXTRACT_ALL('a1b2c3', r'[0-9]+');       -- ['1', '2', '3']
SELECT REGEXP_REPLACE('abc 123 def', r'[0-9]+', '#'); -- 'abc # def'
SELECT REGEXP_INSTR('abc 123', r'[0-9]+');            -- 5

-- FORMAT (printf-style)
SELECT FORMAT('%s has %d items', 'cart', 5);          -- 'cart has 5 items'
SELECT FORMAT('%010d', 42);                           -- '0000000042'

-- String aggregation
SELECT STRING_AGG(Username, ', ' ORDER BY Username) FROM Users;
SELECT STRING_AGG(DISTINCT City, ', ') FROM Users;

-- Split
SELECT SPLIT('a,b,c', ',');                           -- ['a', 'b', 'c'] (returns ARRAY)

-- JSON to string
SELECT TO_JSON_STRING(STRUCT('alice' AS name, 25 AS age));

-- Encoding
SELECT TO_HEX(CAST('hello' AS BYTES));               -- hex encoding
SELECT FROM_HEX('68656c6c6f');                        -- hex decoding
SELECT TO_BASE64(CAST('hello' AS BYTES));             -- base64 encoding
SELECT FROM_BASE64('aGVsbG8=');                       -- base64 decoding

-- Hashing
SELECT SHA256(CAST('hello' AS BYTES));
SELECT SHA512(CAST('hello' AS BYTES));
SELECT MD5(CAST('hello' AS BYTES));

-- Soundex
SELECT SOUNDEX('hello');                              -- 'H400'

-- Unicode
SELECT UNICODE('A');                                  -- 65
SELECT CHR(65);                                       -- 'A'
SELECT NORMALIZE('hello', NFC);                       -- Unicode normalization

-- Note: Regular expressions use r'...' raw string syntax
-- Note: REGEXP_EXTRACT returns first match, REGEXP_EXTRACT_ALL returns all
-- Note: SPLIT returns ARRAY<STRING> (not like PostgreSQL's STRING_TO_ARRAY)
-- Note: CONTAINS_SUBSTR is case-insensitive
-- Note: No POSITION() function (use STRPOS or INSTR)
-- Note: No TRANSLATE() function
-- Note: FORMAT uses printf-style formatting
