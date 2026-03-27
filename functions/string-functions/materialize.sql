-- Materialize: 字符串函数 (String Functions)
--
-- 参考资料:
--   [1] Materialize Documentation - String Functions
--       https://materialize.com/docs/sql/functions/
--   [2] Materialize Documentation - Pattern Matching
--       https://materialize.com/docs/sql/pattern-matching/
--   [3] PostgreSQL Documentation - String Functions
--       https://www.postgresql.org/docs/current/functions-string.html
--
-- 说明: Materialize 基于 PostgreSQL 语法，字符串函数与 PostgreSQL 高度兼容。
--       流式计算场景中，字符串函数在各数据流中独立执行。

-- ============================================================
-- 1. 字符串拼接
-- ============================================================

-- || 操作符: SQL 标准拼接（推荐）
SELECT 'hello' || ' ' || 'world';                     -- 'hello world'

-- CONCAT: 函数形式，跳过 NULL
SELECT CONCAT('hello', ' ', 'world');                 -- 'hello world'
SELECT CONCAT('user', '_', 42);                       -- 'user_42'（数值自动转字符串）

-- CONCAT 与 || 的 NULL 处理差异:
--   || : 任一操作数为 NULL → 结果 NULL（SQL 标准）
--   CONCAT: 跳过 NULL → 结果非 NULL（PostgreSQL/Materialize 语义）
SELECT 'hello' || NULL;                               -- NULL
SELECT CONCAT('hello', NULL, 'world');                -- 'helloworld'（跳过 NULL）

-- ============================================================
-- 2. 长度函数
-- ============================================================

SELECT LENGTH('hello');                               -- 5（字符数，PostgreSQL 语义!）
SELECT CHAR_LENGTH('hello');                          -- 5（同 LENGTH，SQL 标准）
SELECT OCTET_LENGTH('hello');                         -- 5（字节数，ASCII）
SELECT OCTET_LENGTH('你好');                          -- 6（UTF-8 字节数）
SELECT BIT_LENGTH('hello');                           -- 40（位数）

-- 注意: Materialize 的 LENGTH 返回字符数（与 PostgreSQL 一致）
--       MySQL 的 LENGTH 返回字节数! 跨数据库迁移需注意

-- ============================================================
-- 3. 大小写转换
-- ============================================================

SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
SELECT INITCAP('hello world');                        -- 'Hello World'（首字母大写）

-- ============================================================
-- 4. 截取函数
-- ============================================================

SELECT SUBSTRING('hello world' FROM 7 FOR 5);         -- 'world'（SQL 标准语法）
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'（简写形式）
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'

-- ============================================================
-- 5. 查找与定位
-- ============================================================

SELECT POSITION('world' IN 'hello world');            -- 7（SQL 标准语法）
SELECT STRPOS('hello world', 'world');                -- 7（PostgreSQL 简写）

-- ============================================================
-- 6. 替换、填充与修剪
-- ============================================================

-- 替换
SELECT REPLACE('hello world', 'world', 'mz');         -- 'hello mz'
SELECT OVERLAY('hello world' PLACING 'mz' FROM 7 FOR 5);  -- 'hello mz'（SQL 标准）

-- 填充
SELECT LPAD('42', 5, '0');                            -- '00042'（左填充）
SELECT RPAD('hi', 5, '.');                            -- 'hi...'（右填充）

-- 修剪
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'
SELECT BTRIM('xxhelloxx', 'x');                       -- 'hello'（去两端指定字符）

-- ============================================================
-- 7. 翻转与重复
-- ============================================================

SELECT REVERSE('hello');                              -- 'olleh'
SELECT REPEAT('ab', 3);                               -- 'ababab'

-- ============================================================
-- 8. 正则表达式
-- ============================================================

-- REGEXP_MATCH: 返回匹配的子串数组
SELECT REGEXP_MATCH('abc 123 def', '\d+');            -- {123}

-- REGEXP_REPLACE: 正则替换
SELECT REGEXP_REPLACE('abc 123 def', '[0-9]+', '#');  -- 'abc # def'
SELECT REGEXP_REPLACE('abc 123 def 456', '\d+', 'X', 'g');  -- 全局替换

-- 正则匹配操作符
SELECT 'hello123' ~ '^[a-z]+[0-9]+$';                -- true（匹配）
SELECT 'hello123' !~ '^[a-z]+$';                     -- true（不匹配）
SELECT 'Hello' ~* 'hello';                           -- true（大小写不敏感匹配）

-- ============================================================
-- 9. ASCII / 字符转换
-- ============================================================

SELECT ASCII('A');                                    -- 65
SELECT CHR(65);                                       -- 'A'
SELECT UNICODE('你');                                 -- 20320（Unicode 码点）

-- ============================================================
-- 10. SPLIT_PART: 分隔符分割
-- ============================================================

SELECT SPLIT_PART('a,b,c', ',', 2);                  -- 'b'（第 2 段）
SELECT SPLIT_PART('2024-01-15', '-', 1);             -- '2024'（年份）
SELECT SPLIT_PART('one;two;three', ';', 3);          -- 'three'

-- ============================================================
-- 11. TRANSLATE: 字符映射
-- ============================================================

SELECT TRANSLATE('hello', 'helo', 'HELO');            -- 'HELLO'
SELECT TRANSLATE('123-456-7890', '-()', ' ');         -- '123 456 7890'

-- ============================================================
-- 12. 编码与解码
-- ============================================================

SELECT ENCODE(E'\\xDEAD'::BYTEA, 'hex');             -- 'dead'
SELECT ENCODE('hello'::BYTEA, 'base64');              -- 'aGVsbG8='
SELECT DECODE('aGVsbG8=', 'base64');                  -- 'hello' (BYTEA)

-- ============================================================
-- 13. 字符串聚合: STRING_AGG
-- ============================================================

SELECT STRING_AGG(username, ', ') FROM users;                         -- 基本拼接
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;       -- 带排序
SELECT department, STRING_AGG(name, '; ') FROM employees
GROUP BY department;                                                  -- 分组拼接

-- ============================================================
-- 14. 物化视图中的字符串函数
-- ============================================================

-- 字符串函数在物化视图中可增量维护
CREATE MATERIALIZED VIEW user_display AS
SELECT
    UPPER(SUBSTRING(username FROM 1 FOR 1)) || LOWER(SUBSTRING(username FROM 2)) AS display_name,
    COALESCE(email, 'no-email') AS contact
FROM users;

-- ============================================================
-- 15. 横向对比: Materialize vs PostgreSQL vs MySQL
-- ============================================================

-- LENGTH 语义:
--   Materialize: LENGTH = 字符数（同 PG）
--   PostgreSQL:  LENGTH = 字符数
--   MySQL:       LENGTH = 字节数!（迁移陷阱）

-- 拼接操作符:
--   Materialize: || = 字符串拼接（SQL 标准）
--   PostgreSQL:  || = 字符串拼接
--   MySQL:       || = 逻辑 OR!（迁移陷阱）

-- NULL 处理:
--   CONCAT: Materialize/PG 跳过 NULL（非标准但实用）
--   ||:     Materialize/PG 遵循标准 NULL 传播

-- ============================================================
-- 16. 版本演进与注意事项
-- ============================================================
-- Materialize 0.x: 基础字符串函数（||/LENGTH/UPPER/LOWER/SUBSTRING）
-- Materialize 0.7+: REGEXP_MATCH, REGEXP_REPLACE, SPLIT_PART
-- Materialize 0.9+: 完整编码函数（ENCODE/DECODE）
--
-- 注意事项:
--   1. 字符串函数与 PostgreSQL 语法高度兼容
--   2. LENGTH 返回字符数（非字节数），与 MySQL 不同
--   3. 支持 || 拼接（与 MySQL 的 || = OR 完全不同）
--   4. 正则表达式使用 PostgreSQL POSIX 语法（非 ICU/PCRE）
--   5. 物化视图中字符串函数的变更可增量维护
