-- SQLite: 聚合函数
--
-- 参考资料:
--   [1] SQLite Documentation - Aggregate Functions
--       https://www.sqlite.org/lang_aggfunc.html
--   [2] SQLite Documentation - Window Functions
--       https://www.sqlite.org/windowfunctions.html

-- ============================================================
-- 1. 内置聚合函数（数量有限但覆盖核心需求）
-- ============================================================

SELECT COUNT(*) FROM users;                  -- 行数
SELECT COUNT(email) FROM users;              -- 非 NULL 计数
SELECT COUNT(DISTINCT status) FROM users;    -- 去重计数
SELECT SUM(amount) FROM orders;
SELECT AVG(age) FROM users;
SELECT MIN(age), MAX(age) FROM users;
SELECT TOTAL(amount) FROM orders;            -- 类似 SUM 但返回 0.0 而非 NULL
SELECT GROUP_CONCAT(username, ', ') FROM users;  -- 字符串拼接

-- TOTAL vs SUM:
--   SUM(空集) → NULL
--   TOTAL(空集) → 0.0（始终返回浮点数）
--   这是 SQLite 独有的设计，避免 NULL 处理

-- GROUP_CONCAT（SQLite 特有名称，MySQL 也有）:
SELECT GROUP_CONCAT(username, '; ') FROM users;
SELECT GROUP_CONCAT(DISTINCT status) FROM users;

-- ============================================================
-- 2. SQLite 聚合函数的局限（对引擎开发者）
-- ============================================================

-- SQLite 只有约 10 个内置聚合函数（vs PostgreSQL 的 40+）。
-- 不支持:
--   PERCENTILE_CONT / PERCENTILE_DISC（百分位数）
--   STDDEV / VARIANCE（标准差/方差，需要自定义函数）
--   ARRAY_AGG（数组聚合，用 json_group_array 替代）
--   STRING_AGG（标准 SQL 名称，用 GROUP_CONCAT 替代）
--   LISTAGG（Oracle 名称）
--   BOOL_AND / BOOL_OR（布尔聚合）

-- 替代方案: 自定义聚合函数（通过 C API / Python API）
-- conn.create_aggregate("stddev", 1, StddevClass)
-- 或使用 JSON 聚合:
SELECT json_group_array(username) FROM users;     -- ["alice","bob","charlie"]
SELECT json_group_object(username, age) FROM users; -- {"alice":25,"bob":30}

-- ============================================================
-- 3. FILTER 子句（3.30.0+）
-- ============================================================

-- FILTER 允许在聚合时按条件过滤:
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE status = 1) AS active_count,
    SUM(amount) FILTER (WHERE status = 1) AS active_sum
FROM users;

-- 等价于 CASE WHEN 但更简洁:
-- COUNT(CASE WHEN status = 1 THEN 1 END) AS active_count

-- 对比:
--   PostgreSQL: 支持 FILTER（9.4+）
--   MySQL:      不支持 FILTER（需要 CASE WHEN）
--   ClickHouse: 支持 -If 后缀（countIf, sumIf）
--   BigQuery:   支持 COUNTIF, 不支持通用 FILTER

-- ============================================================
-- 4. 对比与引擎开发者启示
-- ============================================================
-- SQLite 聚合的设计:
--   (1) 内置函数少 → 自定义聚合 API 补充
--   (2) TOTAL → 避免 SUM(空集)=NULL 的陷阱
--   (3) GROUP_CONCAT → 字符串拼接（非标准名称）
--   (4) FILTER → 3.30.0+ 支持
--   (5) json_group_array → 替代 ARRAY_AGG
--
-- 对引擎开发者的启示:
--   核心聚合函数（COUNT/SUM/AVG/MIN/MAX）是必需的。
--   自定义聚合 API 比内置大量聚合函数更灵活。
--   TOTAL（空集返回 0）是好的设计：减少了 NULL 处理的心智负担。
