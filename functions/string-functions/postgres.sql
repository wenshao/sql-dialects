-- PostgreSQL: 字符串函数
--
-- 参考资料:
--   [1] PostgreSQL Documentation - String Functions
--       https://www.postgresql.org/docs/current/functions-string.html
--   [2] PostgreSQL Documentation - Pattern Matching
--       https://www.postgresql.org/docs/current/functions-matching.html

-- 拼接
SELECT 'hello' || ' ' || 'world';                    -- 'hello world'（推荐）
SELECT CONCAT('hello', ' ', 'world');                 -- 'hello world'（NULL 安全）
SELECT CONCAT_WS(',', 'a', 'b', 'c');                -- 'a,b,c'

-- 长度
SELECT LENGTH('hello');                               -- 5（字符数）
SELECT OCTET_LENGTH('你好');                           -- 6（UTF-8 字节数）
SELECT CHAR_LENGTH('hello');                          -- 5
SELECT BIT_LENGTH('hello');                           -- 40

-- 大小写
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
SELECT INITCAP('hello world');                        -- 'Hello World'

-- 截取
SELECT SUBSTRING('hello world' FROM 7 FOR 5);         -- 'world'（SQL 标准）
SELECT SUBSTR('hello world', 7, 5);                   -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'

-- 查找
SELECT POSITION('world' IN 'hello world');            -- 7
SELECT STRPOS('hello world', 'world');                -- 7

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'pg');         -- 'hello pg'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');               -- 'hello'
SELECT BTRIM('xxhelloxx', 'x');                       -- 'hello'

-- 翻转 / 重复
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'

-- 正则（所有版本）
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT SUBSTRING('abc 123 def' FROM '[0-9]+');        -- '123'
-- 15+:
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');        -- '123'
SELECT REGEXP_COUNT('a1b2c3', '[0-9]');               -- 3

-- STRING_AGG（聚合拼接，9.0+）
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;

-- 其他实用函数
SELECT SPLIT_PART('a.b.c', '.', 2);                  -- 'b'
SELECT TRANSLATE('hello', 'helo', 'HELO');            -- 'HELLO'
SELECT MD5('hello');                                  -- hash
SELECT ENCODE('hello'::bytea, 'base64');              -- 编码
