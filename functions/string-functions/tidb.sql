-- TiDB: String Functions
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- All MySQL string functions are supported:
-- CONCAT, CONCAT_WS, LENGTH, CHAR_LENGTH, UPPER, LOWER,
-- SUBSTRING, LEFT, RIGHT, INSTR, LOCATE, REPLACE, LPAD, RPAD,
-- TRIM, LTRIM, RTRIM, REVERSE, REPEAT, etc.

-- Concatenation (same as MySQL)
SELECT CONCAT('hello', ' ', 'world');
SELECT CONCAT_WS(',', 'a', 'b', 'c');

-- Length functions (same as MySQL)
SELECT LENGTH('hello');
SELECT CHAR_LENGTH('hello');

-- Case conversion (same as MySQL)
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
SELECT REPLACE('hello world', 'world', 'tidb');
SELECT LPAD('42', 5, '0');
SELECT RPAD('hi', 5, '.');
SELECT TRIM('  hello  ');

-- Regexp functions (same as MySQL 8.0)
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');
SELECT REGEXP_INSTR('abc 123 def', '[0-9]+');
SELECT REGEXP_LIKE('abc 123', '[0-9]+');

-- GROUP_CONCAT (same as MySQL)
SELECT GROUP_CONCAT(username SEPARATOR ', ') FROM users;
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;

-- GROUP_CONCAT: TiDB has a default length limit
-- tidb_group_concat_max_len controls the maximum result length
-- Default: 1024 (same as MySQL's group_concat_max_len)
SET SESSION group_concat_max_len = 65535;

-- Collation-aware functions:
-- String comparison behavior depends on collation
-- TiDB defaults to utf8mb4_bin (case-sensitive)
-- This affects LOCATE, INSTR, REPLACE when comparing characters
SELECT LOCATE('HELLO', 'hello world');
-- Returns 0 in utf8mb4_bin (case-sensitive)
-- Returns 1 in utf8mb4_general_ci (case-insensitive)

-- TiDB-specific: WEIGHT_STRING for collation sort keys
SELECT WEIGHT_STRING('hello');

-- CONVERT with charset (same as MySQL)
SELECT CONVERT('hello' USING utf8mb4);

-- Limitations:
-- All MySQL string functions work the same
-- Collation differences (utf8mb4_bin default) affect case-sensitive behavior
-- GROUP_CONCAT memory usage may be higher in distributed queries
-- Very large string operations may hit txn-entry-size-limit
-- || is OR by default (same as MySQL, not string concatenation)
