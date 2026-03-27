-- Greenplum: 字符串类型
--
-- 参考资料:
--   [1] Greenplum SQL Reference
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html
--   [2] Greenplum Admin Guide
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html

-- CHAR(n) / CHARACTER(n): 定长，最大 10485760（10MB），尾部补空格
-- VARCHAR(n) / CHARACTER VARYING(n): 变长，最大 10485760
-- TEXT: 变长，无长度限制
-- BYTEA: 二进制数据

CREATE TABLE examples (
    code       CHAR(10),                  -- 定长
    name       VARCHAR(255),              -- 变长（推荐）
    content    TEXT,                       -- 无限长文本
    data       BYTEA                      -- 二进制数据
)
DISTRIBUTED BY (code);

-- VARCHAR 不指定长度（等同于 TEXT）
CREATE TABLE t (name VARCHAR)
DISTRIBUTED RANDOMLY;

-- 字符串字面量
SELECT 'hello world';                     -- 单引号
SELECT E'hello\nworld';                   -- 转义字符串
SELECT $$hello 'world'$$;                -- 美元引号（避免转义）
SELECT $tag$hello 'world'$tag$;          -- 带标签的美元引号

-- 类型转换
SELECT CAST('123' AS INTEGER);
SELECT 123::TEXT;                         -- PostgreSQL 简写
SELECT '2024-01-15'::DATE;

-- 字符集和排序规则
SELECT 'hello' COLLATE "en_US";
CREATE TABLE t (name TEXT COLLATE "C")
DISTRIBUTED RANDOMLY;

-- 字符串运算符
SELECT 'hello' || ' ' || 'world';        -- 拼接
SELECT 'hello' LIKE 'hel%';              -- 模式匹配
SELECT 'hello' SIMILAR TO 'h(e|a)llo';   -- 正则相似
SELECT 'hello' ~ 'h.*o';                 -- POSIX 正则
SELECT 'hello' ~* 'H.*O';               -- POSIX 正则（不区分大小写）

-- 注意：Greenplum 兼容 PostgreSQL 字符串类型
-- 注意：TEXT 和 VARCHAR 性能无差异
-- 注意：支持 COLLATION
-- 注意：支持 POSIX 正则运算符
-- 注意：|| 运算符用于字符串拼接
