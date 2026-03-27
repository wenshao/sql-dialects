-- TDSQL: 字符串函数
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

-- 拼接
SELECT CONCAT('hello', ' ', 'world');                -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');               -- 'a,b,c'

-- 长度
SELECT LENGTH('hello');                               -- 5（字节数）
SELECT CHAR_LENGTH('你好');                            -- 2（字符数）

-- 大小写
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'

-- 截取
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'

-- 查找
SELECT INSTR('hello world', 'world');                 -- 7
SELECT LOCATE('world', 'hello world');                -- 7

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'tdsql');      -- 'hello tdsql'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'

-- 翻转 / 重复
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'

-- 正则
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');

-- GROUP_CONCAT
SELECT GROUP_CONCAT(username SEPARATOR ', ') FROM users;

-- 注意事项：
-- 字符串函数与 MySQL 完全兼容
-- GROUP_CONCAT 在跨分片查询中由代理层合并
