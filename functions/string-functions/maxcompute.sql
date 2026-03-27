-- MaxCompute (ODPS): 字符串函数
--
-- 参考资料:
--   [1] MaxCompute SQL - String Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/string-functions
--   [2] MaxCompute Built-in Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/built-in-functions-overview

-- 拼接
SELECT CONCAT('hello', ' ', 'world');                    -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');                   -- 'a,b,c'
-- 注意：不支持 || 拼接运算符

-- 长度
SELECT LENGTH('hello');                                  -- 5（字节数，非字符数！）
SELECT CHAR_LENGTH('hello');                             -- 5（字符数，2.0+）
SELECT LENGTHB('你好');                                   -- 6（字节数）

-- 大小写
SELECT UPPER('hello');                                   -- 'HELLO'
SELECT LOWER('HELLO');                                   -- 'hello'
SELECT INITCAP('hello world');                           -- 'Hello World'

-- 截取
SELECT SUBSTR('hello world', 7, 5);                      -- 'world'
SELECT SUBSTRING('hello world', 7, 5);                   -- 'world'（2.0+）

-- 查找
SELECT INSTR('hello world', 'world');                    -- 7
SELECT LOCATE('world', 'hello world');                   -- 7

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'mc');            -- 'hello mc'
SELECT LPAD('42', 5, '0');                               -- '00042'
SELECT RPAD('hi', 5, '.');                               -- 'hi...'
SELECT TRIM('  hello  ');                                -- 'hello'
SELECT LTRIM('  hello  ');                               -- 'hello  '
SELECT RTRIM('  hello  ');                               -- '  hello'

-- 翻转 / 重复
SELECT REVERSE('hello');                                 -- 'olleh'
SELECT REPEAT('ab', 3);                                  -- 'ababab'

-- 正则
SELECT REGEXP_EXTRACT('abc 123 def', '[0-9]+', 0);       -- '123'
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');     -- 'abc # def'
SELECT REGEXP_COUNT('a1b2c3', '[0-9]');                  -- 3
SELECT REGEXP_INSTR('abc 123', '[0-9]+');                -- 5（2.0+）

-- 分割
SELECT SPLIT_PART('a.b.c', '.', 2);                      -- 'b'
-- SPLIT 返回 ARRAY<STRING>
SELECT SPLIT('a,b,c', ',');

-- 编码
SELECT MD5('hello');                                     -- MD5 哈希
SELECT SHA1('hello');                                    -- SHA1 哈希
SELECT SHA2('hello', 256);                               -- SHA-256
SELECT TO_BASE64('hello');
SELECT FROM_BASE64(TO_BASE64('hello'));

-- 其他
SELECT TRANSLATE('hello', 'helo', 'HELO');               -- 'HELLO'
SELECT SPACE(5);                                         -- '     '
SELECT ASCII('A');                                       -- 65
SELECT CHR(65);                                          -- 'A'（2.0+）
SELECT PARSE_URL('http://example.com/path?k=v', 'HOST'); -- 'example.com'
SELECT URL_ENCODE('hello world');                        -- 'hello+world'
SELECT URL_DECODE('hello+world');                        -- 'hello world'

-- 聚合拼接
SELECT WM_CONCAT(',', username) FROM users;              -- MaxCompute 特有

-- 注意：LENGTH 返回字节数（与多数数据库不同）
-- 注意：CHAR_LENGTH 才是字符数（2.0+）
-- 注意：不支持 || 运算符
-- 注意：正则使用 Java 正则语法
