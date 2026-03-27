-- KingbaseES (人大金仓): 字符串函数
-- PostgreSQL compatible syntax.
--
-- 参考资料:
--   [1] KingbaseES SQL Reference
--       https://help.kingbase.com.cn/v8/index.html
--   [2] KingbaseES Documentation
--       https://help.kingbase.com.cn/v8/index.html

-- 拼接
SELECT 'hello' || ' ' || 'world';                    -- 'hello world'
SELECT CONCAT('hello', ' ', 'world');                 -- 'hello world'
SELECT CONCAT_WS(',', 'a', 'b', 'c');                -- 'a,b,c'

-- 长度
SELECT LENGTH('hello');                               -- 5
SELECT OCTET_LENGTH('你好');                           -- 6（UTF-8 字节数）
SELECT CHAR_LENGTH('hello');                          -- 5

-- 大小写
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
SELECT INITCAP('hello world');                        -- 'Hello World'

-- 截取
SELECT SUBSTRING('hello world' FROM 7 FOR 5);         -- 'world'
SELECT SUBSTR('hello world', 7, 5);                   -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'

-- 查找
SELECT POSITION('world' IN 'hello world');            -- 7
SELECT STRPOS('hello world', 'world');                -- 7

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'kingbase');   -- 'hello kingbase'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT BTRIM('xxhelloxx', 'x');                       -- 'hello'

-- 翻转 / 重复
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'

-- 正则
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');
SELECT SUBSTRING('abc 123 def' FROM '[0-9]+');

-- STRING_AGG
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;

-- 其他
SELECT SPLIT_PART('a.b.c', '.', 2);                  -- 'b'
SELECT TRANSLATE('hello', 'helo', 'HELO');            -- 'HELLO'

-- 注意事项：
-- 字符串函数与 PostgreSQL 完全兼容
-- Oracle 兼容模式下也支持 INSTR、SUBSTR 等 Oracle 函数
