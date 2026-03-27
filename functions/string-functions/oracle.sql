-- Oracle: 字符串函数
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Character Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Single-Row-Functions.html
--   [2] Oracle SQL Language Reference - SQL Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SQL-Functions.html

-- 拼接
SELECT 'hello' || ' ' || 'world' FROM dual;          -- 'hello world'
SELECT CONCAT('hello', ' world') FROM dual;           -- CONCAT 只接受 2 个参数！
-- 多个拼接只能嵌套或用 ||

-- 长度
SELECT LENGTH('hello') FROM dual;                     -- 5（字符数）
SELECT LENGTHB('你好') FROM dual;                      -- 6（字节数，UTF-8）

-- 大小写
SELECT UPPER('hello') FROM dual;                      -- 'HELLO'
SELECT LOWER('HELLO') FROM dual;                      -- 'hello'
SELECT INITCAP('hello world') FROM dual;              -- 'Hello World'

-- 截取（注意：Oracle 下标从 1 开始，0 被视为 1）
SELECT SUBSTR('hello world', 7, 5) FROM dual;         -- 'world'
SELECT SUBSTRB('hello world', 7, 5) FROM dual;        -- 按字节截取
-- 没有 LEFT/RIGHT，用 SUBSTR 替代

-- 查找
SELECT INSTR('hello world', 'world') FROM dual;       -- 7
SELECT INSTR('hello world hello', 'hello', 1, 2) FROM dual; -- 13（第2次出现的位置）

-- 替换 / 填充 / 修剪
SELECT REPLACE('hello world', 'world', 'oracle') FROM dual;
SELECT LPAD('42', 5, '0') FROM dual;                  -- '00042'
SELECT RPAD('hi', 5, '.') FROM dual;                  -- 'hi...'
SELECT TRIM('  hello  ') FROM dual;                   -- 'hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx') FROM dual;    -- 'hello'
SELECT LTRIM('  hello') FROM dual;                    -- 'hello'
SELECT RTRIM('hello  ') FROM dual;                    -- 'hello'

-- 翻转
SELECT REVERSE('hello') FROM dual;                    -- 'olleh'（非文档化函数，10g+ 可用）

-- 正则（10g+）
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#') FROM dual;
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+') FROM dual;
SELECT REGEXP_COUNT('a1b2c3', '[0-9]') FROM dual;     -- 3（11g+）
SELECT REGEXP_INSTR('abc 123 def', '[0-9]+') FROM dual;

-- LISTAGG（聚合拼接，11g R2+）
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
-- 12c R2+: LISTAGG 支持 ON OVERFLOW TRUNCATE（避免超长报错）
SELECT LISTAGG(username, ', ' ON OVERFLOW TRUNCATE '...')
    WITHIN GROUP (ORDER BY username) FROM users;

-- TRANSLATE（逐字符替换）
SELECT TRANSLATE('hello', 'helo', 'HELO') FROM dual;  -- 'HELLO'
