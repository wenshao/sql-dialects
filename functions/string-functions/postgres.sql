-- PostgreSQL: 字符串函数
--
-- 参考资料:
--   [1] PostgreSQL Documentation - String Functions
--       https://www.postgresql.org/docs/current/functions-string.html
--   [2] PostgreSQL Documentation - Pattern Matching
--       https://www.postgresql.org/docs/current/functions-matching.html

-- ============================================================
-- 1. 字符串拼接: || 运算符是推荐方式
-- ============================================================

SELECT 'hello' || ' ' || 'world';          -- 'hello world'（推荐）
SELECT CONCAT('hello', ' ', 'world');       -- 'hello world'（NULL安全）
SELECT CONCAT_WS(',', 'a', 'b', NULL, 'c');-- 'a,b,c'（跳过NULL）

-- || 运算符的设计:
--   PostgreSQL 的 || 严格遵循 SQL 标准——如果任一操作数为 NULL，结果为 NULL。
--   CONCAT() 则跳过 NULL（非标准但实用）。
--   MySQL 的 || 默认是 OR 运算符！（除非设置 PIPES_AS_CONCAT）
--   这是 MySQL → PostgreSQL 迁移的经典陷阱。

-- 类型严格性: || 不会隐式转换类型
-- SELECT 'hello' || 42;       -- 错误！
SELECT 'hello' || 42::TEXT;    -- 正确: 'hello42'

-- ============================================================
-- 2. 长度函数
-- ============================================================

SELECT LENGTH('你好');                      -- 2 (字符数)
SELECT OCTET_LENGTH('你好');                -- 6 (UTF-8 字节数)
SELECT CHAR_LENGTH('hello');               -- 5 (同 LENGTH)
SELECT BIT_LENGTH('hello');                -- 40 (位数)

-- PostgreSQL 的 LENGTH() 返回字符数（与编码无关）
-- 对比:
--   MySQL: LENGTH() 返回字节数，CHAR_LENGTH() 返回字符数
--   Oracle: LENGTH() 返回字符数，LENGTHB() 返回字节数

-- ============================================================
-- 3. 大小写与截取
-- ============================================================

SELECT UPPER('hello');                      -- 'HELLO'
SELECT LOWER('HELLO');                      -- 'hello'
SELECT INITCAP('hello world');              -- 'Hello World'

SELECT SUBSTRING('hello world' FROM 7 FOR 5); -- 'world' (SQL标准)
SELECT SUBSTR('hello world', 7, 5);         -- 'world'
SELECT LEFT('hello', 3);                    -- 'hel'
SELECT RIGHT('hello', 3);                   -- 'llo'

-- ============================================================
-- 4. 查找与替换
-- ============================================================

SELECT POSITION('world' IN 'hello world');  -- 7 (SQL标准)
SELECT STRPOS('hello world', 'world');      -- 7 (PostgreSQL语法)
SELECT REPLACE('hello world', 'world', 'pg'); -- 'hello pg'
SELECT TRANSLATE('hello', 'helo', 'HELO');  -- 'HELLO' (字符级替换)

-- ============================================================
-- 5. 填充与修剪
-- ============================================================

SELECT LPAD('42', 5, '0');                  -- '00042'
SELECT RPAD('hi', 5, '.');                  -- 'hi...'
SELECT TRIM('  hello  ');                   -- 'hello'
SELECT TRIM(BOTH 'x' FROM 'xxhelloxx');     -- 'hello'
SELECT BTRIM('xxhelloxx', 'x');             -- 'hello'
SELECT LTRIM('  hello');                    -- 'hello'
SELECT RTRIM('hello  ');                    -- 'hello'

-- ============================================================
-- 6. 正则表达式: PostgreSQL 的强项
-- ============================================================

-- POSIX 正则运算符 (所有版本)
SELECT 'abc 123' ~ '[0-9]+';               -- TRUE (匹配)
SELECT 'abc 123' ~* 'ABC';                 -- TRUE (不区分大小写)
SELECT 'abc 123' !~ '[0-9]+';              -- FALSE (不匹配)

-- 正则替换
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');       -- 'abc # def'
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#', 'g');  -- 全局替换

-- 正则提取
SELECT SUBSTRING('abc 123 def' FROM '[0-9]+');             -- '123'
SELECT REGEXP_SUBSTR('abc 123 def', '[0-9]+');             -- '123' (15+)
SELECT REGEXP_COUNT('a1b2c3', '[0-9]');                    -- 3 (15+)

-- REGEXP_MATCHES: 返回所有匹配（返回 SET）
SELECT REGEXP_MATCHES('a1b2c3', '[0-9]', 'g');             -- {1}, {2}, {3}

-- 正则分割
SELECT REGEXP_SPLIT_TO_TABLE('a,b,,c', ',');               -- 4行（含空串）
SELECT REGEXP_SPLIT_TO_ARRAY('a,b,,c', ',');               -- {a,b,"",c}

-- 设计分析: PostgreSQL 的正则运算符 (~ ~* !~ !~*)
--   这是 PostgreSQL 独有的——其他数据库只有 LIKE 和函数调用。
--   ~ 运算符可以直接在 WHERE 中使用: WHERE col ~ '^[A-Z]'
--   对比:
--     MySQL:      WHERE col REGEXP '^[A-Z]'（REGEXP 关键字）
--     Oracle:     WHERE REGEXP_LIKE(col, '^[A-Z]')（函数调用）

-- ============================================================
-- 7. 实用字符串函数
-- ============================================================

SELECT REVERSE('hello');                    -- 'olleh'
SELECT REPEAT('ab', 3);                     -- 'ababab'
SELECT SPLIT_PART('a.b.c', '.', 2);        -- 'b'
SELECT MD5('hello');                        -- 哈希值
SELECT ENCODE('hello'::bytea, 'base64');    -- 编码
SELECT FORMAT('Hello, %s! You are %s.', 'Alice', 'admin'); -- 格式化 (9.1+)

-- STRING_AGG: 聚合拼接 (9.0+)
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;

-- ============================================================
-- 8. $$ 美元引号: PostgreSQL 的字符串字面量设计
-- ============================================================

-- 标准 SQL 用单引号，内部单引号需要转义: 'it''s'
-- PostgreSQL 支持 $$ 美元引号（消除转义需求）:
SELECT $$it's a "test"$$;                   -- it's a "test"
SELECT $tag$内容包含 ' 和 " 和 $$tag$;      -- 自定义标签

-- 设计价值:
--   $$ 主要用于 PL/pgSQL 函数体——函数体中大量单引号时，
--   转义会让代码不可读。$$ 是解决嵌套引号的优雅方案。
--   对比: MySQL 用反斜杠转义 'it\'s'（非 SQL 标准）
--         Oracle 用双单引号 'it''s'（SQL 标准）

-- ============================================================
-- 9. 横向对比: 字符串函数差异
-- ============================================================

-- 1. 拼接运算符:
--   PostgreSQL: ||（SQL标准，NULL传播）
--   MySQL:      CONCAT()（|| 默认是 OR 运算符！）
--   Oracle:     ||（但 Oracle 的 '' = NULL，所以 'a' || '' = 'a'）
--   SQL Server: + (字符串加法)
--
-- 2. LENGTH 语义:
--   PostgreSQL: LENGTH() = 字符数
--   MySQL:      LENGTH() = 字节数, CHAR_LENGTH() = 字符数
--
-- 3. 正则支持:
--   PostgreSQL: ~ 运算符 + REGEXP_* 函数（最丰富）
--   MySQL:      REGEXP 关键字, REGEXP_* 函数 (8.0+)
--   Oracle:     REGEXP_* 函数 (10g+)
--   SQL Server: 无原生正则（需 CLR）

-- ============================================================
-- 10. 对引擎开发者的启示
-- ============================================================

-- (1) || 运算符的语义选择:
--     PostgreSQL 遵循 SQL 标准（|| = 拼接），MySQL 遵循 C 语言（|| = OR）。
--     新引擎应该遵循 SQL 标准，但提供 CONCAT() 作为 NULL 安全替代。
--
-- (2) $$ 美元引号是低成本高回报的语法特性:
--     实现简单（词法分析器增加一个 token 状态），
--     但极大提升了函数体的可读性。
--
-- (3) 正则运算符 (~) 比函数调用更符合 SQL 的声明式风格:
--     WHERE col ~ '^[A-Z]' 比 WHERE REGEXP_LIKE(col, '^[A-Z]') 更直观。

-- ============================================================
-- 11. 版本演进
-- ============================================================
-- PostgreSQL 8.3:  regexp_split_to_table, regexp_split_to_array
-- PostgreSQL 9.0:  STRING_AGG
-- PostgreSQL 9.1:  FORMAT() 函数
-- PostgreSQL 15:   REGEXP_SUBSTR, REGEXP_COUNT (Oracle 兼容)
-- PostgreSQL 16:   REGEXP_* 函数增强
