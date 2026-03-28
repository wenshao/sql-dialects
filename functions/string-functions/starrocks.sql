-- StarRocks: 字符串函数
--
-- 参考资料:
--   [1] StarRocks Documentation - String Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/

-- 与 Doris 完全兼容(同源，MySQL 兼容)
SELECT CONCAT('hello', ' ', 'world');
SELECT CONCAT_WS(',', 'a', 'b', 'c');
SELECT LENGTH('hello'), CHAR_LENGTH('hello');
SELECT UPPER('hello'), LOWER('HELLO'), INITCAP('hello world');
SELECT SUBSTRING('hello world', 7, 5);
SELECT LEFT('hello', 3), RIGHT('hello', 3);
SELECT INSTR('hello world', 'world');
SELECT LOCATE('world', 'hello world');
SELECT REPLACE('hello world', 'world', 'starrocks');
SELECT LPAD('42', 5, '0'), RPAD('hi', 5, '.');
SELECT TRIM('  hello  ');
SELECT REGEXP_REPLACE('abc 123', '[0-9]+', '#');
SELECT REGEXP_EXTRACT('abc 123', '[0-9]+', 0);
SELECT SPLIT_PART('a,b,c', ',', 2);
SELECT HEX('hello'), MD5('hello');
SELECT REVERSE('hello'), REPEAT('ab', 3);
SELECT GROUP_CONCAT(username SEPARATOR ', ') FROM users;

-- StarRocks vs Doris: 字符串函数完全相同。
-- Doris 额外支持 SM3(国密哈希)，StarRocks 不支持。
