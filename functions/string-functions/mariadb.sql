-- MariaDB: String Functions
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- All MySQL string functions are supported:
-- CONCAT, CONCAT_WS, LENGTH, CHAR_LENGTH, UPPER, LOWER,
-- SUBSTRING, LEFT, RIGHT, INSTR, LOCATE, REPLACE, LPAD, RPAD,
-- TRIM, LTRIM, RTRIM, REVERSE, REPEAT, etc.

-- Concatenation (same as MySQL)
SELECT CONCAT('hello', ' ', 'world');
SELECT CONCAT_WS(',', 'a', 'b', 'c');

-- || as string concatenation (with sql_mode)
-- In MariaDB, you can enable || for concatenation:
SET sql_mode = PIPES_AS_CONCAT;
SELECT 'hello' || ' ' || 'world';  -- 'hello world'
-- Default: || is logical OR (same as MySQL)

-- Length (same as MySQL)
SELECT LENGTH('hello');
SELECT CHAR_LENGTH('hello');
SELECT OCTET_LENGTH('hello');  -- same as LENGTH, counts bytes

-- Case (same as MySQL)
SELECT UPPER('hello');
SELECT LOWER('HELLO');

-- Substring (same as MySQL)
SELECT SUBSTRING('hello world', 7, 5);
SELECT LEFT('hello', 3);
SELECT RIGHT('hello', 3);

-- Search (same as MySQL)
SELECT INSTR('hello world', 'world');
SELECT LOCATE('world', 'hello world');

-- Replace / Pad / Trim (same as MySQL)
SELECT REPLACE('hello world', 'world', 'mariadb');
SELECT LPAD('42', 5, '0');
SELECT RPAD('hi', 5, '.');
SELECT TRIM('  hello  ');

-- Regexp functions (10.0.5+)
-- MariaDB has PCRE-based regexp (Perl Compatible Regular Expressions)
-- MySQL 8.0 uses ICU-based regexp
-- PCRE supports more features like lookahead, lookbehind, etc.
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');
SELECT REGEXP_INSTR('abc 123 def', '[0-9]+');

-- PCRE-specific features (not available in MySQL 8.0 ICU):
-- Lookahead / Lookbehind
SELECT REGEXP_SUBSTR('foobar', 'foo(?=bar)');     -- 'foo' (positive lookahead)
SELECT REGEXP_SUBSTR('foobar', '(?<=foo)bar');    -- 'bar' (positive lookbehind)

-- Named capture groups
SELECT REGEXP_REPLACE('2024-01-15', '(?P<y>\\d{4})-(?P<m>\\d{2})-(?P<d>\\d{2})', '\\3/\\2/\\1');

-- Default regexp flags (PCRE vs ICU):
-- MariaDB PCRE: case-sensitive by default
-- MySQL ICU: depends on collation

-- GROUP_CONCAT (same as MySQL)
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;

-- GROUP_CONCAT with LIMIT (10.3.3+, MariaDB-specific)
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ' LIMIT 5) FROM users;
-- Returns only the first 5 values concatenated

-- SUBSTR with negative position (same as MySQL)
SELECT SUBSTR('hello world', -5);  -- 'world'

-- CHR function (10.3.1+, MariaDB extension)
-- Returns character for given code point (Oracle-compatible)
SELECT CHR(65);     -- 'A'
SELECT CHR(8364);   -- Euro sign

-- NATURAL_SORT_KEY (10.7.1+, MariaDB-specific)
-- Generate a sort key that sorts strings with numbers naturally
SELECT name FROM files ORDER BY NATURAL_SORT_KEY(name);
-- Sorts: file1, file2, file10 (not file1, file10, file2)

-- Differences from MySQL 8.0:
-- PCRE-based regexp (MySQL uses ICU-based)
-- PCRE supports lookahead/lookbehind (ICU does not)
-- GROUP_CONCAT ... LIMIT (MariaDB-specific, 10.3.3+)
-- CHR() function (MariaDB-specific, 10.3.1+)
-- NATURAL_SORT_KEY() (MariaDB-specific, 10.7.1+)
-- Different regexp behavior for edge cases (PCRE vs ICU)
