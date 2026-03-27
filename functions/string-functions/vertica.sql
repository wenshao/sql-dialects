-- Vertica: 字符串函数
--
-- 参考资料:
--   [1] Vertica SQL Reference
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm
--   [2] Vertica Functions
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm

-- 拼接
SELECT 'hello' || ' ' || 'world';                    -- 'hello world'
SELECT CONCAT('hello', ' ', 'world');                 -- 'hello world'

-- 长度
SELECT LENGTH('hello');                               -- 5（字符数）
SELECT OCTET_LENGTH('你好');                          -- 6（字节数）
SELECT CHAR_LENGTH('hello');                          -- 5
SELECT BIT_LENGTH('hello');                           -- 40

-- 大小写
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
SELECT INITCAP('hello world');                       -- 'Hello World'

-- 截取
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'
SELECT SUBSTR('hello world', 7, 5);                   -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'

-- 查找
SELECT POSITION('world' IN 'hello world');            -- 7
SELECT INSTR('hello world', 'world');                 -- 7
SELECT STRPOS('hello world', 'world');                -- 7

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'vertica');    -- 'hello vertica'
SELECT OVERLAY('hello world' PLACING 'VT' FROM 7 FOR 5);  -- 'hello VT'
SELECT TRANSLATE('hello', 'el', 'EL');               -- 'hELLo'
SELECT LPAD('42', 5, '0');                            -- '00042'
SELECT RPAD('hi', 5, '.');                            -- 'hi...'
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT BTRIM('xxhelloxx', 'x');                      -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'

-- 翻转 / 重复
SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'

-- 正则
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');       -- '123'
SELECT REGEXP_LIKE('abc', '[a-z]+');                 -- TRUE
SELECT REGEXP_COUNT('abc 123 def 456', '[0-9]+');    -- 2
SELECT REGEXP_INSTR('abc 123 def', '[0-9]+');        -- 5

-- 分割
SELECT SPLIT_PART('a,b,c', ',', 2);                  -- 'b'

-- 编码
SELECT MD5('hello');
SELECT SHA1('hello');
SELECT SHA256('hello');

-- 格式化
SELECT TO_CHAR(123.45, '999.99');                    -- ' 123.45'

-- 引用
SELECT QUOTE_IDENT('table_name');                    -- "table_name"
SELECT QUOTE_LITERAL('it''s');                       -- 'it''s'

-- GROUP_CONCAT / STRING_AGG（Vertica 特有）
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;

-- 注意：Vertica 同时支持 PostgreSQL 和 Oracle 风格的函数
-- 注意：|| 运算符用于拼接
-- 注意：支持丰富的正则函数（REGEXP_COUNT, REGEXP_INSTR 等）
-- 注意：LISTAGG 用于聚合拼接（类似 GROUP_CONCAT）
