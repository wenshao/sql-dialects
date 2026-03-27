-- SAP HANA: String Functions
--
-- 参考资料:
--   [1] SAP HANA SQL Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/

-- Concatenation
SELECT 'hello' || ' ' || 'world' FROM DUMMY;               -- 'hello world'
SELECT CONCAT('hello', ' world') FROM DUMMY;                -- 'hello world' (two args)

-- Length
SELECT LENGTH('hello') FROM DUMMY;                          -- 5
SELECT CHAR_LENGTH('hello') FROM DUMMY;                     -- 5 (synonym)
SELECT OCTET_LENGTH('hello') FROM DUMMY;                    -- 5 (bytes)

-- Case
SELECT UPPER('hello') FROM DUMMY;                           -- 'HELLO'
SELECT LOWER('HELLO') FROM DUMMY;                           -- 'hello'
SELECT INITCAP('hello world') FROM DUMMY;                   -- 'Hello World'

-- Substring
SELECT SUBSTRING('hello world', 7, 5) FROM DUMMY;           -- 'world'
SELECT SUBSTR('hello world', 7, 5) FROM DUMMY;              -- 'world'
SELECT LEFT('hello', 3) FROM DUMMY;                         -- 'hel'
SELECT RIGHT('hello', 3) FROM DUMMY;                        -- 'llo'

-- Position
SELECT LOCATE('hello world', 'world') FROM DUMMY;           -- 7
-- Note: LOCATE(haystack, needle) -- reverse order from some databases
SELECT LOCATE_REGEXPR('[0-9]+' IN 'abc 123 def') FROM DUMMY; -- 5

-- Trim
SELECT TRIM('  hello  ') FROM DUMMY;                        -- 'hello'
SELECT LTRIM('  hello') FROM DUMMY;                         -- 'hello'
SELECT RTRIM('hello  ') FROM DUMMY;                         -- 'hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx') FROM DUMMY;          -- 'hello'

-- Padding
SELECT LPAD('42', 5, '0') FROM DUMMY;                       -- '00042'
SELECT RPAD('hi', 5, '.') FROM DUMMY;                       -- 'hi...'

-- Replace
SELECT REPLACE('hello world', 'world', 'hana') FROM DUMMY;  -- 'hello hana'

-- Regular expressions
SELECT SUBSTR_REGEXPR('[0-9]+' IN 'abc 123 def') FROM DUMMY;           -- '123'
SELECT REPLACE_REGEXPR('[0-9]+' IN 'abc 123 def' WITH '#') FROM DUMMY; -- 'abc # def'
SELECT OCCURRENCES_REGEXPR('[0-9]' IN 'a1b2c3') FROM DUMMY;            -- 3
SELECT LOCATE_REGEXPR('[0-9]+' IN 'abc 123 def') FROM DUMMY;           -- 5

-- String aggregation
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;

-- Other functions
SELECT REVERSE('hello') FROM DUMMY;                         -- 'olleh'
SELECT REPEAT('ab', 3) FROM DUMMY;                          -- 'ababab' (LPAD alternative)
SELECT ASCII('A') FROM DUMMY;                               -- 65
SELECT CHAR(65) FROM DUMMY;                                 -- 'A'

-- ABAP string functions (SAP-specific)
SELECT ABAP_UPPER('hello') FROM DUMMY;                      -- 'HELLO'
SELECT ABAP_LOWER('HELLO') FROM DUMMY;                      -- 'hello'

-- UNICODE / NCHAR
SELECT UNICODE('A') FROM DUMMY;                             -- 65 (Unicode code point)
SELECT NCHAR(65) FROM DUMMY;                                -- 'A'

-- TO_VARCHAR / TO_NVARCHAR (type conversion)
SELECT TO_NVARCHAR(12345) FROM DUMMY;                       -- '12345'
SELECT TO_NVARCHAR(CURRENT_DATE, 'YYYY-MM-DD') FROM DUMMY;

-- SOUNDEX
SELECT SOUNDEX('Smith') FROM DUMMY;                         -- 'S530'

-- HAMMING_DISTANCE (for similarity)
SELECT HAMMING_DISTANCE('karolin', 'kathrin') FROM DUMMY;

-- Note: LOCATE parameter order is (haystack, needle), opposite from MySQL
-- Note: REGEXPR functions use regex syntax natively
-- Note: DUMMY is SAP HANA's single-row table
