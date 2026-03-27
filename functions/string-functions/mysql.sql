-- MySQL: 字符串函数
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - String Functions
--       https://dev.mysql.com/doc/refman/8.0/en/string-functions.html
--   [2] MySQL 8.0 Reference Manual - Regular Expressions
--       https://dev.mysql.com/doc/refman/8.0/en/regexp.html

-- 拼接
SELECT CONCAT('hello', ' ', 'world');                -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');               -- 'a,b,c'（带分隔符）
-- 注意：MySQL 的 || 默认是逻辑 OR，不是拼接（除非设置 PIPES_AS_CONCAT）

-- 长度
SELECT LENGTH('hello');                               -- 5（字节数）
SELECT CHAR_LENGTH('你好');                            -- 2（字符数）
SELECT BIT_LENGTH('hello');                           -- 40（位数）

-- 大小写
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'

-- 截取
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'

-- 查找
SELECT INSTR('hello world', 'world');                 -- 7
SELECT LOCATE('world', 'hello world');                -- 7（参数顺序相反）
SELECT POSITION('world' IN 'hello world');            -- 7

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'mysql');      -- 'hello mysql'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'

-- 翻转 / 重复
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'

-- 8.0+: 正则
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');        -- '123'

-- GROUP_CONCAT（聚合拼接）
SELECT GROUP_CONCAT(username SEPARATOR ', ') FROM users;
-- 注意：GROUP_CONCAT 不支持窗口函数（OVER 子句）
-- 注意：默认最大长度 1024 字节，可通过 group_concat_max_len 调整
