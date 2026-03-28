-- Snowflake: 条件函数
--
-- 参考资料:
--   [1] Snowflake SQL Reference - Conditional Functions
--       https://docs.snowflake.com/en/sql-reference/functions-conditional

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- CASE WHEN（SQL 标准）
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;

-- 简单 CASE
SELECT username,
    CASE status
        WHEN 0 THEN 'inactive'
        WHEN 1 THEN 'active'
        WHEN 2 THEN 'deleted'
        ELSE 'unknown'
    END AS status_name
FROM users;

-- COALESCE（返回第一个非 NULL 值）
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF（两值相等时返回 NULL）
SELECT NULLIF(age, 0) FROM users;

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 IFF: Snowflake 的三元条件函数
SELECT IFF(age >= 18, 'adult', 'minor') FROM users;
SELECT IFF(amount > 0, amount, 0) FROM orders;
SELECT IF(age >= 18, 'adult', 'minor') FROM users;  -- IF 是 IFF 的别名

-- IFF 等价于: CASE WHEN cond THEN true_val ELSE false_val END
-- 但更简洁，适合简单的二元分支。
--
-- 对比:
--   MySQL:      IF(cond, true, false)（与 Snowflake IF 一致）
--   PostgreSQL: 无 IFF/IF 函数（只有 CASE WHEN）
--   Oracle:     无 IFF/IF 函数（DECODE 是替代）
--   SQL Server: IIF(cond, true, false)（从 SQL Server 2012+）
--   BigQuery:   IF(cond, true, false)
--
-- 对引擎开发者的启示:
--   IFF/IF 是语法糖（可以用 CASE WHEN 完全替代），
--   但显著提升了 SQL 的可读性（特别是嵌套条件时）。
--   实现成本极低（解析时转换为 CASE WHEN 即可），推荐引擎支持。

-- 2.2 NVL / NVL2 / DECODE: Oracle 兼容函数
SELECT NVL(phone, 'no phone') FROM users;            -- = COALESCE(phone, 'no phone')
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;
SELECT DECODE(status, 0, 'inactive', 1, 'active', 'unknown') FROM users;

-- DECODE 等价于简单 CASE:
--   DECODE(expr, val1, res1, val2, res2, default)
--   = CASE expr WHEN val1 THEN res1 WHEN val2 THEN res2 ELSE default END
--
-- Snowflake 保留这些 Oracle 函数的设计理由:
--   大量从 Oracle 迁移到 Snowflake 的客户已有大量使用 NVL/DECODE 的 SQL
--   兼容这些函数降低了迁移成本
--
-- 对比:
--   PostgreSQL:  不支持 NVL/NVL2/DECODE（只有 COALESCE 和 CASE）
--   BigQuery:    不支持 NVL/DECODE（只有 COALESCE/IF/IFNULL）
--   Redshift:    支持 NVL/DECODE（也兼容 Oracle）
--   Databricks:  支持 NVL/DECODE

-- ============================================================
-- 3. NULL 处理函数
-- ============================================================

SELECT IFNULL(phone, 'no phone') FROM users;         -- = NVL = COALESCE(2参数)
SELECT ZEROIFNULL(amount) FROM orders;               -- NULL → 0
SELECT NULLIFZERO(amount) FROM orders;               -- 0 → NULL

-- EQUAL_NULL: NULL 安全比较
SELECT EQUAL_NULL(NULL, NULL);    -- TRUE（普通 = 运算中 NULL = NULL 为 UNKNOWN）
SELECT EQUAL_NULL(1, NULL);       -- FALSE

-- 对比:
--   MySQL:      <=> 运算符（NULL 安全等于）
--   PostgreSQL: IS NOT DISTINCT FROM（SQL 标准语法）
--   Oracle:     DECODE(a, b, 1, 0)（变通方案）
--   BigQuery:   IS NOT DISTINCT FROM
--
-- 对引擎开发者的启示:
--   NULL 安全比较在 JOIN 条件和 MERGE ON 中非常重要。
--   推荐引擎同时支持 IS NOT DISTINCT FROM（标准）和 EQUAL_NULL（便捷函数）。

-- ============================================================
-- 4. GREATEST / LEAST
-- ============================================================

SELECT GREATEST(1, 3, 2);    -- 3
SELECT LEAST(1, 3, 2);       -- 1
SELECT GREATEST(a, b, c) FROM data;

-- 对比:
--   PostgreSQL: 支持 GREATEST/LEAST
--   MySQL:      支持 GREATEST/LEAST
--   Oracle:     支持 GREATEST/LEAST
--   SQL Server: 不支持（需要 CASE WHEN 或 VALUES + MAX 变通）
-- Snowflake 的 GREATEST/LEAST 对 NULL 的处理: 忽略 NULL（返回非 NULL 值中的最大/最小）

-- ============================================================
-- 5. TYPEOF: 运行时类型检查
-- ============================================================

SELECT TYPEOF(123);           -- 'INTEGER'
SELECT TYPEOF('hello');       -- 'VARCHAR'
SELECT TYPEOF(NULL);          -- 'NULL_VALUE'
SELECT TYPEOF(PARSE_JSON('{"a":1}')); -- 'OBJECT'

-- TYPEOF 对 VARIANT 列特别有用:
SELECT TYPEOF(data:field) FROM events;
-- 返回 VARIANT 内部值的实际类型（VARCHAR/INTEGER/OBJECT/ARRAY/...）

-- ============================================================
-- 6. IS 判断
-- ============================================================

SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;

-- IS_NULL_VALUE: 判断 VARIANT 中的 JSON null（不同于 SQL NULL）
-- JSON null: { "field": null }  → IS_NULL_VALUE(data:field) = TRUE
-- SQL NULL:  field 不存在       → data:field IS NULL = TRUE
-- 这两者是不同的概念! 对 VARIANT 查询时必须注意区分

-- ============================================================
-- 7. 安全转换函数（与条件逻辑结合）
-- ============================================================

SELECT TRY_CAST('abc' AS INTEGER);       -- NULL
SELECT TRY_TO_NUMBER('abc');             -- NULL
SELECT TRY_TO_DATE('invalid');           -- NULL
SELECT TRY_TO_TIMESTAMP('invalid');      -- NULL
SELECT TRY_TO_BOOLEAN('maybe');          -- NULL

-- TRY_* + COALESCE 组合处理脏数据:
SELECT COALESCE(TRY_TO_NUMBER(raw_value), 0) AS clean_value FROM staging;

-- :: 运算符（PostgreSQL 风格类型转换）
SELECT '123'::INTEGER;
SELECT '2024-01-15'::DATE;
SELECT CURRENT_TIMESTAMP()::VARCHAR;

-- 对比:
--   PostgreSQL: :: 运算符（原创者）
--   Snowflake:  :: 运算符（借鉴 PG）
--   BigQuery:   不支持 ::（只有 CAST/SAFE_CAST）
--   MySQL:      不支持 ::（只有 CAST/CONVERT）

-- ============================================================
-- 横向对比: 条件函数矩阵
-- ============================================================
-- 函数         | Snowflake | BigQuery | PostgreSQL | MySQL  | Oracle
-- IFF/IF       | IFF/IF    | IF       | 无         | IF     | 无
-- NVL/NVL2     | 支持      | 无       | 无         | 无     | 原创
-- DECODE       | 支持      | 无       | 无         | 无     | 原创
-- COALESCE     | 支持      | 支持     | 支持       | 支持   | 支持
-- NULLIF       | 支持      | 支持     | 支持       | 支持   | 支持
-- EQUAL_NULL   | 支持      | IS NOT D | IS NOT D   | <=>    | DECODE
-- TRY_CAST     | 支持      | SAFE_CAST| 无         | 无     | 无
-- TYPEOF       | 支持      | 无       | pg_typeof  | 无     | 无
-- :: 运算符    | 支持      | 无       | 原创       | 无     | 无
