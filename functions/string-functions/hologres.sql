-- Hologres: 字符串函数
-- Hologres 兼容 PostgreSQL 字符串函数
--
-- 参考资料:
--   [1] Hologres - String Functions
--       https://help.aliyun.com/zh/hologres/user-guide/string-functions
--   [2] Hologres Built-in Functions
--       https://help.aliyun.com/zh/hologres/user-guide/built-in-functions

-- 拼接
SELECT 'hello' || ' ' || 'world';                        -- 'hello world'
SELECT CONCAT('hello', ' ', 'world');                    -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');                   -- 'a,b,c'

-- 长度
SELECT LENGTH('hello');                                  -- 5（字符数）
SELECT OCTET_LENGTH('你好');                              -- 6（字节数）
SELECT CHAR_LENGTH('hello');                             -- 5

-- 大小写
SELECT UPPER('hello');                                   -- 'HELLO'
SELECT LOWER('HELLO');                                   -- 'hello'
SELECT INITCAP('hello world');                           -- 'Hello World'

-- 截取
SELECT SUBSTRING('hello world' FROM 7 FOR 5);            -- 'world'（SQL 标准）
SELECT SUBSTR('hello world', 7, 5);                      -- 'world'
SELECT LEFT('hello', 3);                                 -- 'hel'
SELECT RIGHT('hello', 3);                                -- 'llo'

-- 查找
SELECT POSITION('world' IN 'hello world');               -- 7
SELECT STRPOS('hello world', 'world');                   -- 7

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'hg');            -- 'hello hg'
SELECT LPAD('42', 5, '0');                               -- '00042'
SELECT RPAD('hi', 5, '.');                               -- 'hi...'
SELECT TRIM('  hello  ');                                -- 'hello'
SELECT BTRIM('xxhelloxx', 'x');                          -- 'hello'

-- 翻转 / 重复
SELECT REVERSE('hello');                                 -- 'olleh'
SELECT REPEAT('ab', 3);                                  -- 'ababab'

-- 正则
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');     -- 'abc # def'
SELECT SUBSTRING('abc 123 def' FROM '[0-9]+');           -- '123'
-- 注意：Hologres 正则支持可能比 PostgreSQL 有限

-- 分割
SELECT SPLIT_PART('a.b.c', '.', 2);                      -- 'b'

-- 聚合拼接
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;

-- 编码
SELECT MD5('hello');
SELECT ENCODE('hello'::bytea, 'base64');

-- 其他
SELECT TRANSLATE('hello', 'helo', 'HELO');               -- 'HELLO'
SELECT ASCII('A');                                       -- 65
SELECT CHR(65);                                          -- 'A'

-- 注意：与 PostgreSQL 字符串函数基本一致
-- 注意：部分高级函数可能不支持（如 REGEXP_SUBSTR, REGEXP_COUNT）
-- 注意：性能特征与 PostgreSQL 不同（列存引擎）
