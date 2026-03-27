-- OceanBase: String Functions
-- OceanBase has dual mode: MySQL mode and Oracle mode. Both shown where relevant.
--
-- 参考资料:
--   [1] OceanBase SQL Reference (MySQL Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase SQL Reference (Oracle Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- MySQL Mode (same as MySQL)
-- ============================================================

-- Concatenation
SELECT CONCAT('hello', ' ', 'world');
SELECT CONCAT_WS(',', 'a', 'b', 'c');

-- Length
SELECT LENGTH('hello');
SELECT CHAR_LENGTH('hello');

-- Case
SELECT UPPER('hello');
SELECT LOWER('HELLO');

-- Substring
SELECT SUBSTRING('hello world', 7, 5);
SELECT LEFT('hello', 3);
SELECT RIGHT('hello', 3);

-- Search
SELECT INSTR('hello world', 'world');
SELECT LOCATE('world', 'hello world');

-- Replace / Pad / Trim
SELECT REPLACE('hello world', 'world', 'oceanbase');
SELECT LPAD('42', 5, '0');
SELECT RPAD('hi', 5, '.');
SELECT TRIM('  hello  ');

-- Regexp (4.0+)
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');

-- GROUP_CONCAT
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;

-- ============================================================
-- Oracle Mode
-- ============================================================

-- Concatenation (Oracle: || operator for string concatenation)
SELECT 'hello' || ' ' || 'world' FROM DUAL;
-- CONCAT only takes 2 arguments in Oracle mode
SELECT CONCAT('hello', ' world') FROM DUAL;

-- Length
SELECT LENGTH('hello') FROM DUAL;           -- character count
SELECT LENGTHB('hello') FROM DUAL;          -- byte count

-- Case
SELECT UPPER('hello') FROM DUAL;
SELECT LOWER('HELLO') FROM DUAL;
SELECT INITCAP('hello world') FROM DUAL;    -- 'Hello World' (Oracle-specific)

-- Substring
SELECT SUBSTR('hello world', 7, 5) FROM DUAL;  -- 'world' (SUBSTR, not SUBSTRING)
SELECT SUBSTR('hello world', -5) FROM DUAL;    -- 'world' (negative position)

-- Search
SELECT INSTR('hello world', 'world') FROM DUAL;
SELECT INSTR('hello world hello', 'hello', 1, 2) FROM DUAL;  -- 4-arg: find 2nd occurrence

-- Replace
SELECT REPLACE('hello world', 'world', 'oceanbase') FROM DUAL;
-- TRANSLATE: character-by-character replacement (Oracle-specific)
SELECT TRANSLATE('hello', 'helo', 'HELO') FROM DUAL;  -- 'HELLO'

-- Padding
SELECT LPAD('42', 5, '0') FROM DUAL;
SELECT RPAD('hi', 5, '.') FROM DUAL;

-- Trim
SELECT TRIM('  hello  ') FROM DUAL;
SELECT TRIM(LEADING '0' FROM '00042') FROM DUAL;    -- '42'
SELECT TRIM(TRAILING '.' FROM 'hi...') FROM DUAL;   -- 'hi'

-- Regexp (Oracle mode)
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#') FROM DUAL;
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+') FROM DUAL;
SELECT REGEXP_INSTR('abc 123 def', '[0-9]+') FROM DUAL;
SELECT REGEXP_COUNT('abc 123 def 456', '[0-9]+') FROM DUAL;  -- 2 (Oracle-specific)

-- LISTAGG (Oracle mode, similar to GROUP_CONCAT)
SELECT city, LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username)
FROM users GROUP BY city;

-- NVL (Oracle mode, similar to IFNULL)
SELECT NVL(phone, 'N/A') FROM users;
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;

-- DECODE (Oracle mode, similar to CASE)
SELECT DECODE(status, 1, 'active', 2, 'inactive', 'unknown') FROM users;

-- Limitations:
-- MySQL mode: same as MySQL string functions
-- Oracle mode: || for concatenation, SUBSTR (not SUBSTRING), INITCAP, TRANSLATE
-- Oracle mode: LISTAGG instead of GROUP_CONCAT
-- Oracle mode: REGEXP_COUNT available (not in MySQL mode)
-- Oracle mode: NVL/NVL2 instead of IFNULL
