-- Snowflake: 字符串函数
--
-- 参考资料:
--   [1] Snowflake SQL Reference - String Functions
--       https://docs.snowflake.com/en/sql-reference/functions-string
--   [2] Snowflake SQL Reference - Regular Expressions
--       https://docs.snowflake.com/en/sql-reference/functions-regexp

-- 拼接
SELECT 'hello' || ' ' || 'world';                        -- 'hello world'
SELECT CONCAT('hello', ' ', 'world');                    -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');                   -- 'a,b,c'

-- 长度
SELECT LENGTH('hello');                                  -- 5（字符数）
SELECT LEN('hello');                                     -- 5（LENGTH 的别名）
SELECT CHAR_LENGTH('hello');                             -- 5
SELECT OCTET_LENGTH('你好');                              -- 6（字节数）

-- 大小写
SELECT UPPER('hello');                                   -- 'HELLO'
SELECT LOWER('HELLO');                                   -- 'hello'
SELECT INITCAP('hello world');                           -- 'Hello World'

-- 截取
SELECT SUBSTR('hello world', 7, 5);                      -- 'world'
SELECT SUBSTRING('hello world', 7, 5);                   -- 'world'
SELECT LEFT('hello', 3);                                 -- 'hel'
SELECT RIGHT('hello', 3);                                -- 'llo'

-- 查找
SELECT POSITION('world' IN 'hello world');               -- 7
SELECT CHARINDEX('world', 'hello world');                -- 7
SELECT CONTAINS('hello world', 'world');                 -- TRUE
SELECT STARTSWITH('hello world', 'hello');               -- TRUE
SELECT ENDSWITH('hello world', 'world');                 -- TRUE

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'sf');            -- 'hello sf'
SELECT LPAD('42', 5, '0');                               -- '00042'
SELECT RPAD('hi', 5, '.');                               -- 'hi...'
SELECT TRIM('  hello  ');                                -- 'hello'
SELECT LTRIM('  hello  ');                               -- 'hello  '
SELECT RTRIM('  hello  ');                               -- '  hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');                  -- 'hello'

-- 翻转 / 重复
SELECT REVERSE('hello');                                 -- 'olleh'
SELECT REPEAT('ab', 3);                                  -- 'ababab'

-- 正则
SELECT REGEXP_LIKE('abc 123', '[0-9]+');                  -- TRUE
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');            -- '123'
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');     -- 'abc # def'
SELECT REGEXP_COUNT('a1b2c3', '[0-9]');                  -- 3
SELECT REGEXP_INSTR('abc 123', '[0-9]+');                -- 5
SELECT RLIKE('abc 123', '[0-9]+');                       -- TRUE（别名）

-- 分割
SELECT SPLIT('a,b,c', ',');                              -- 返回 ARRAY
SELECT SPLIT_PART('a.b.c', '.', 2);                      -- 'b'
SELECT STRTOK('a,b,c', ',', 2);                          -- 'b'

-- 聚合拼接
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
SELECT ARRAY_AGG(username) FROM users;

-- 编码
SELECT BASE64_ENCODE('hello');
SELECT BASE64_DECODE_STRING(BASE64_ENCODE('hello'));
SELECT MD5('hello');
SELECT SHA2('hello', 256);                               -- SHA-256
SELECT HEX_ENCODE('hello');

-- 其他
SELECT TRANSLATE('hello', 'helo', 'HELO');               -- 'HELLO'
SELECT SPACE(5);                                         -- '     '
SELECT INSERT('hello world', 7, 5, 'sf');                -- 'hello sf'
SELECT ASCII('A');                                       -- 65
SELECT CHR(65);                                          -- 'A'
SELECT UNICODE('A');                                     -- 65

-- 注意：正则使用 POSIX 语法
-- 注意：LISTAGG 是聚合拼接的标准函数
-- 注意：CONTAINS/STARTSWITH/ENDSWITH 返回 BOOLEAN
