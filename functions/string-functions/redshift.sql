-- Redshift: 字符串函数
--
-- 参考资料:
--   [1] Redshift SQL Reference
--       https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html
--   [2] Redshift SQL Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html
--   [3] Redshift Data Types
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html

-- 拼接
SELECT 'hello' || ' ' || 'world';                    -- 'hello world'（推荐）
SELECT CONCAT('hello', ' ', 'world');                 -- 'hello world'

-- 长度
SELECT LEN('hello');                                  -- 5（去除尾部空格后的长度）
SELECT LENGTH('hello');                               -- 5
SELECT CHAR_LENGTH('hello');                          -- 5
SELECT OCTET_LENGTH('你好');                           -- 6（UTF-8 字节数）

-- 大小写
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
SELECT INITCAP('hello world');                        -- 'Hello World'

-- 截取
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'
SELECT SUBSTR('hello world', 7, 5);                   -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'

-- 查找
SELECT POSITION('world' IN 'hello world');            -- 7
SELECT STRPOS('hello world', 'world');                -- 7
SELECT CHARINDEX('world', 'hello world');             -- 7（兼容 SQL Server）

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'redshift');   -- 'hello redshift'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'
SELECT TRIM(BOTH ' ' FROM '  hello  ');              -- 'hello'
SELECT BTRIM('xxhelloxx', 'x');                       -- 'hello'

-- 翻转 / 重复
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'

-- 正则表达式
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');        -- '123'
SELECT REGEXP_COUNT('a1b2c3', '[0-9]');               -- 3
SELECT REGEXP_INSTR('abc 123 def', '[0-9]+');         -- 5

-- 字符串聚合
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
-- LISTAGG 是 Redshift 的字符串聚合函数（不是 STRING_AGG）

-- 分组聚合
SELECT city, LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) AS user_list
FROM users GROUP BY city;

-- 分割
SELECT SPLIT_PART('a.b.c', '.', 2);                  -- 'b'

-- 编码 / 解码
SELECT MD5('hello');                                  -- MD5 哈希
SELECT SHA1('hello');                                 -- SHA1 哈希（Redshift 2022+）
SELECT SHA2('hello', 256);                            -- SHA-256 哈希

-- TRANSLATE
SELECT TRANSLATE('hello', 'helo', 'HELO');            -- 'HELLO'

-- TEXTLEN（SUPER 类型中的字符串长度）
SELECT TEXTLEN(data.name) FROM events;

-- 注意：LISTAGG 是字符串聚合函数（不是 STRING_AGG 或 GROUP_CONCAT）
-- 注意：LEN 去除尾部空格，LENGTH 不去除
-- 注意：正则函数支持 POSIX 正则语法
-- 注意：CONCAT_WS 从 2023+ 可用，旧版本用 || 和 COALESCE 替代
-- 注意：CHARINDEX 与 SQL Server 兼容
