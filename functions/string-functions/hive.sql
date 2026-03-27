-- Hive: 字符串函数
--
-- 参考资料:
--   [1] Apache Hive - String Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-StringFunctions
--   [2] Apache Hive Language Manual - UDF
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF

-- 拼接
SELECT CONCAT('hello', ' ', 'world');                    -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');                   -- 'a,b,c'
-- 注意：不支持 || 拼接运算符

-- 长度
SELECT LENGTH('hello');                                  -- 5（字符数）
SELECT OCTET_LENGTH('你好');                              -- 6（字节数，2.2+）
SELECT CHAR_LENGTH('hello');                             -- 5（2.2+）

-- 大小写
SELECT UPPER('hello');                                   -- 'HELLO'
SELECT LOWER('HELLO');                                   -- 'hello'
SELECT UCASE('hello');                                   -- 'HELLO'（别名）
SELECT LCASE('HELLO');                                   -- 'hello'（别名）
SELECT INITCAP('hello world');                           -- 'Hello World'（1.1+）

-- 截取
SELECT SUBSTR('hello world', 7, 5);                      -- 'world'
SELECT SUBSTRING('hello world', 7, 5);                   -- 'world'

-- 查找
SELECT INSTR('hello world', 'world');                    -- 7（1.2+）
SELECT LOCATE('world', 'hello world');                   -- 7
SELECT LOCATE('world', 'hello world world', 8);          -- 13（从第 8 位开始）

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'hive');          -- 'hello hive'（1.3+）
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
SELECT 'abc 123' RLIKE '[0-9]+';                         -- TRUE
SELECT 'abc 123' REGEXP '[0-9]+';                        -- TRUE（别名）

-- 分割
SELECT SPLIT('a,b,c', ',');                              -- 返回 ARRAY['a','b','c']
SELECT SPLIT('a,b,c', ',')[0];                           -- 'a'（0-based）

-- 编码
SELECT MD5('hello');                                     -- MD5 哈希（1.3+）
SELECT SHA1('hello');                                    -- SHA1（1.3+）
SELECT SHA2('hello', 256);                               -- SHA-256（1.3+）
SELECT BASE64(CAST('hello' AS BINARY));                  -- Base64 编码
SELECT UNBASE64('aGVsbG8=');                             -- Base64 解码

-- 其他
SELECT TRANSLATE('hello', 'helo', 'HELO');               -- 'HELLO'
SELECT SPACE(5);                                         -- '     '
SELECT ASCII('A');                                       -- 65
SELECT CHR(65);                                          -- 'A'（2.2+）
SELECT PARSE_URL('http://example.com?k=v', 'HOST');      -- 'example.com'
SELECT SENTENCES('Hello world. How are you?');           -- 分句分词
SELECT SOUNDEX('hello');                                 -- Soundex 编码
SELECT LEVENSHTEIN('kitten', 'sitting');                 -- 编辑距离（3）

-- 聚合拼接
SELECT COLLECT_LIST(username) FROM users;                -- 收集为数组
SELECT COLLECT_SET(city) FROM users;                     -- 收集为去重数组

-- 注意：不支持 || 运算符
-- 注意：正则使用 Java 正则语法
-- 注意：数组索引从 0 开始（与多数数据库不同）
-- 注意：REPLACE 函数在 1.3 引入，旧版用 REGEXP_REPLACE
