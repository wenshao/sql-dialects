-- StarRocks: 字符串函数
--
-- 参考资料:
--   [1] StarRocks - String Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/string-functions/
--   [2] StarRocks SQL Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/

-- 拼接
SELECT CONCAT('hello', ' ', 'world');                    -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');                   -- 'a,b,c'
-- 注意：支持 || 运算符（3.0+）

-- 长度
SELECT LENGTH('hello');                                  -- 5（字节数）
SELECT CHAR_LENGTH('hello');                             -- 5（字符数）
SELECT CHARACTER_LENGTH('hello');                        -- 5

-- 大小写
SELECT UPPER('hello');                                   -- 'HELLO'
SELECT LOWER('HELLO');                                   -- 'hello'
SELECT LCASE('HELLO');                                   -- 'hello'（别名）
SELECT UCASE('hello');                                   -- 'HELLO'（别名）
SELECT INITCAP('hello world');                           -- 'Hello World'

-- 截取
SELECT SUBSTR('hello world', 7, 5);                      -- 'world'
SELECT SUBSTRING('hello world', 7, 5);                   -- 'world'
SELECT LEFT('hello', 3);                                 -- 'hel'
SELECT RIGHT('hello', 3);                                -- 'llo'

-- 查找
SELECT INSTR('hello world', 'world');                    -- 7
SELECT LOCATE('world', 'hello world');                   -- 7
SELECT FIND_IN_SET('b', 'a,b,c');                        -- 2
SELECT STARTS_WITH('hello world', 'hello');              -- TRUE（2.5+）
SELECT ENDS_WITH('hello world', 'world');                -- TRUE（2.5+）

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'sr');            -- 'hello sr'
SELECT LPAD('42', 5, '0');                               -- '00042'
SELECT RPAD('hi', 5, '.');                               -- 'hi...'
SELECT TRIM('  hello  ');                                -- 'hello'
SELECT LTRIM('  hello  ');                               -- 'hello  '
SELECT RTRIM('  hello  ');                               -- '  hello'

-- 翻转 / 重复
SELECT REVERSE('hello');                                 -- 'olleh'
SELECT REPEAT('ab', 3);                                  -- 'ababab'

-- 正则
SELECT REGEXP('abc 123', '[0-9]+');                       -- TRUE（2.5+）
SELECT REGEXP_EXTRACT('abc 123 def', '[0-9]+');           -- '123'
SELECT REGEXP_EXTRACT_ALL('a1b2c3', '[0-9]+');            -- ['1','2','3']（3.0+）
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');     -- 'abc # def'

-- 分割
SELECT SPLIT('a,b,c', ',');                              -- 返回 ARRAY
SELECT SPLIT_PART('a.b.c', '.', 2);                      -- 'b'

-- 聚合拼接
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;

-- 编码
SELECT MD5('hello');                                     -- MD5 哈希
SELECT SHA2('hello', 256);                               -- SHA-256
SELECT SM3('hello');                                     -- SM3 国密哈希（2.5+）
SELECT HEX('hello');                                     -- 十六进制
SELECT UNHEX('68656C6C6F');                              -- 从十六进制
SELECT TO_BASE64('hello');
SELECT FROM_BASE64(TO_BASE64('hello'));

-- 其他
SELECT SPACE(5);                                         -- '     '
SELECT ASCII('A');                                       -- 65
SELECT CHAR(65);                                         -- 'A'
SELECT PARSE_URL('http://example.com?k=v', 'HOST');      -- 'example.com'
SELECT URL_ENCODE('hello world');
SELECT URL_DECODE('hello+world');
SELECT MONEY_FORMAT(1234.5);                             -- '$1,234.50'

-- 注意：与 MySQL 字符串函数基本兼容
-- 注意：LENGTH 返回字节数（MySQL 兼容），CHAR_LENGTH 返回字符数
-- 注意：正则使用 POSIX ERE 语法
