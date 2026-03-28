-- Apache Doris: 字符串函数
--
-- 参考资料:
--   [1] Doris Documentation - String Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/string-functions/

-- ============================================================
-- 1. 拼接
-- ============================================================
SELECT CONCAT('hello', ' ', 'world');
SELECT CONCAT_WS(',', 'a', 'b', 'c');

-- ============================================================
-- 2. 长度
-- ============================================================
SELECT LENGTH('hello');        -- 5 (字节数)
SELECT CHAR_LENGTH('hello');   -- 5 (字符数)

-- ============================================================
-- 3. 大小写
-- ============================================================
SELECT UPPER('hello'), LOWER('HELLO'), INITCAP('hello world');

-- ============================================================
-- 4. 截取
-- ============================================================
SELECT SUBSTRING('hello world', 7, 5);
SELECT LEFT('hello', 3), RIGHT('hello', 3);

-- ============================================================
-- 5. 查找
-- ============================================================
SELECT INSTR('hello world', 'world');
SELECT LOCATE('world', 'hello world');
SELECT POSITION('world' IN 'hello world');

-- ============================================================
-- 6. 替换/填充/修剪
-- ============================================================
SELECT REPLACE('hello world', 'world', 'doris');
SELECT LPAD('42', 5, '0'), RPAD('hi', 5, '.');
SELECT TRIM('  hello  '), LTRIM('  hello'), RTRIM('hello  ');
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');

-- ============================================================
-- 7. 正则
-- ============================================================
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');
SELECT REGEXP_EXTRACT('abc 123 def', '[0-9]+', 0);
SELECT 'abc' REGEXP '[a-z]+';

-- ============================================================
-- 8. 分割
-- ============================================================
SELECT SPLIT_PART('a,b,c', ',', 2);
SELECT EXPLODE_SPLIT('a,b,c', ',');  -- 多行输出

-- ============================================================
-- 9. 编码
-- ============================================================
SELECT HEX('hello'), UNHEX('68656C6C6F');
SELECT MD5('hello'), SM3('hello');
SELECT REVERSE('hello'), REPEAT('ab', 3);

-- ============================================================
-- 10. 聚合拼接
-- ============================================================
SELECT GROUP_CONCAT(username SEPARATOR ', ') FROM users;
SELECT GROUP_CONCAT(DISTINCT city ORDER BY city SEPARATOR ', ') FROM users;

-- 对比: SM3(国密) 是 Doris 特有(中国合规需求)。
