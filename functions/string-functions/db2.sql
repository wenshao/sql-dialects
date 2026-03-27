-- IBM Db2: String Functions
--
-- 参考资料:
--   [1] Db2 SQL Reference
--       https://www.ibm.com/docs/en/db2/11.5?topic=sql
--   [2] Db2 Built-in Functions
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in

-- Concatenation
SELECT 'hello' || ' ' || 'world';                         -- 'hello world'
SELECT CONCAT('hello', ' world');                          -- 'hello world' (two args only)

-- Length
SELECT LENGTH('hello');                                    -- 5
SELECT CHARACTER_LENGTH('hello');                          -- 5
SELECT OCTET_LENGTH('hello');                              -- 5 (bytes)

-- Case
SELECT UPPER('hello');                                     -- 'HELLO'
SELECT LOWER('HELLO');                                     -- 'hello'
SELECT INITCAP('hello world');                             -- 'Hello World' (Db2 11.1+)

-- Substring
SELECT SUBSTRING('hello world', 7, 5);                     -- 'world'
SELECT SUBSTR('hello world', 7, 5);                        -- 'world'
SELECT LEFT('hello', 3);                                   -- 'hel'
SELECT RIGHT('hello', 3);                                  -- 'llo'

-- Position
SELECT POSITION('world' IN 'hello world');                 -- 7
SELECT LOCATE('world', 'hello world');                     -- 7
SELECT LOCATE('l', 'hello world', 5);                      -- 11 (start from position 5)

-- Trim
SELECT TRIM('  hello  ');                                  -- 'hello'
SELECT TRIM(LEADING ' ' FROM '  hello  ');                 -- 'hello  '
SELECT TRIM(TRAILING ' ' FROM '  hello  ');                -- '  hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');                    -- 'hello'
SELECT LTRIM('  hello');                                   -- 'hello'
SELECT RTRIM('hello  ');                                   -- 'hello'
SELECT STRIP('  hello  ');                                 -- 'hello' (synonym for TRIM)

-- Padding
SELECT LPAD('42', 5, '0');                                 -- '00042'
SELECT RPAD('hi', 5, '.');                                 -- 'hi...'

-- Replace
SELECT REPLACE('hello world', 'world', 'db2');             -- 'hello db2'

-- Translate (character-by-character replacement)
SELECT TRANSLATE('hello', 'HELO', 'helo');                 -- 'HELLO'

-- Regular expressions (Db2 11.1+)
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');             -- '123'
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');       -- 'abc # def'
SELECT REGEXP_INSTR('abc 123 def', '[0-9]+');              -- 5
SELECT REGEXP_COUNT('a1b2c3', '[0-9]');                    -- 3
SELECT REGEXP_LIKE('abc 123', '[0-9]+');                   -- 1

-- String aggregation (Db2 11.1+)
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;

-- LISTAGG with DISTINCT (Db2 11.5+)
SELECT LISTAGG(DISTINCT city, ', ') WITHIN GROUP (ORDER BY city) FROM users;

-- Repeat / Reverse
SELECT REPEAT('ab', 3);                                    -- 'ababab'
SELECT REVERSE('hello');                                   -- 'olleh' (Db2 11.1+)

-- Other functions
SELECT ASCII('A');                                         -- 65
SELECT CHR(65);                                            -- 'A'
SELECT INSERT('hello world', 7, 5, 'db2');                 -- 'hello db2'
SELECT SPACE(5);                                           -- '     '

-- SOUNDEX (phonetic matching)
SELECT SOUNDEX('Smith');                                   -- 'S530'
SELECT DIFFERENCE('Smith', 'Smythe');                      -- 4 (0-4 scale)

-- Note: CONCAT takes only 2 arguments; use || for multi-part
-- Note: LISTAGG is the standard string aggregation (Db2 11.1+)
-- Note: REGEXP functions available from Db2 11.1+
