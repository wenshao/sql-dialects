-- Snowflake: 聚合函数
--
-- 参考资料:
--   [1] Snowflake SQL Reference - Aggregate Functions
--       https://docs.snowflake.com/en/sql-reference/functions-aggregation

-- ============================================================
-- 1. 基本聚合
-- ============================================================

SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount), AVG(amount), MIN(amount), MAX(amount) FROM orders;

-- GROUP BY + HAVING
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city
HAVING COUNT(*) > 10;

-- GROUP BY ALL（自动推断非聚合列，Snowflake 独有）
SELECT city, status, COUNT(*)
FROM users
GROUP BY ALL;

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 GROUP BY ALL: Snowflake 的语法糖
-- 自动将 SELECT 中未被聚合函数包裹的列作为 GROUP BY 列。
-- 消除了手动列举分组列的繁琐（特别是列多的时候）。
--
-- 对比:
--   BigQuery:   GROUP BY ALL（2023+ 也支持）
--   Databricks: GROUP BY ALL（也支持）
--   PostgreSQL: 不支持（必须显式列举所有分组列）
--   MySQL:      ONLY_FULL_GROUP_BY 模式下不支持（宽松模式下允许省略，但语义不同）
--
-- 对引擎开发者的启示:
--   GROUP BY ALL 实现简单（解析时检查 SELECT 列表即可推断），但提升用户体验。
--   潜在风险: 修改 SELECT 列表可能意外改变 GROUP BY 语义。

-- 2.2 条件聚合: IFF + COUNT/SUM
-- Snowflake 不支持 FILTER 子句（SQL:2003 标准扩展）:
--   PostgreSQL: COUNT(*) FILTER (WHERE age < 30)
--   Snowflake:  COUNT(IFF(age < 30, 1, NULL))     -- 用 IFF 替代
-- IFF 返回 NULL 时不计入 COUNT/SUM，效果等价。
SELECT
    COUNT(*) AS total,
    COUNT(IFF(age < 30, 1, NULL)) AS young,
    SUM(IFF(status = 'active', amount, 0)) AS active_amount
FROM users;
--
-- 对比:
--   PostgreSQL: COUNT(*) FILTER (WHERE ...)（最优雅）
--   MySQL:      SUM(CASE WHEN ... THEN 1 ELSE 0 END)
--   BigQuery:   COUNTIF(condition)（专用函数）
--   Snowflake:  IFF + COUNT/SUM（灵活但稍繁琐）

-- ============================================================
-- 3. GROUPING SETS / ROLLUP / CUBE
-- ============================================================

SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS ((city), (status), ());

SELECT city, status, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);

SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE (city, status);

SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users
GROUP BY ROLLUP (city);
-- GROUPING() 函数返回 0 或 1，指示该列是否为汇总行

-- 对比: 所有主流数据库都支持 GROUPING SETS/ROLLUP/CUBE

-- ============================================================
-- 4. 字符串聚合
-- ============================================================

-- LISTAGG: SQL:2016 标准函数
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
SELECT LISTAGG(DISTINCT city, ', ') FROM users;

-- ARRAY_AGG: 聚合为数组
SELECT ARRAY_AGG(username) WITHIN GROUP (ORDER BY username) FROM users;
SELECT ARRAY_AGG(DISTINCT city) FROM users;
SELECT ARRAY_UNIQUE_AGG(city) FROM users;  -- 去重数组聚合

-- ARRAY_TO_STRING: 数组转字符串
SELECT ARRAY_TO_STRING(ARRAY_AGG(username), ', ') FROM users;

-- OBJECT_AGG: 聚合为 VARIANT 对象
SELECT OBJECT_AGG(key, value) FROM kv_table;

-- 对比:
--   PostgreSQL: STRING_AGG(col, sep ORDER BY ...) 或 ARRAY_AGG
--   MySQL:      GROUP_CONCAT(col ORDER BY ... SEPARATOR sep)
--   Oracle:     LISTAGG（与 Snowflake 语法一致）
--   BigQuery:   STRING_AGG(col, sep ORDER BY ...)
--
-- 对引擎开发者的启示:
--   LISTAGG + ARRAY_AGG + OBJECT_AGG 覆盖了三种聚合输出格式:
--   字符串、数组、对象。这对半结构化数据处理非常有价值。

-- ============================================================
-- 5. 统计函数
-- ============================================================

SELECT STDDEV(amount) FROM orders;         -- 样本标准差
SELECT STDDEV_POP(amount) FROM orders;     -- 总体标准差
SELECT VARIANCE(amount) FROM orders;       -- 样本方差
SELECT VAR_POP(amount) FROM orders;        -- 总体方差
SELECT CORR(x, y) FROM data;              -- Pearson 相关系数
SELECT COVAR_SAMP(x, y) FROM data;        -- 样本协方差
SELECT REGR_SLOPE(y, x) FROM data;        -- 线性回归斜率
SELECT KURTOSIS(amount) FROM orders;       -- 峰度
SELECT SKEW(amount) FROM orders;           -- 偏度

-- MEDIAN / MODE（Snowflake 便捷函数）
SELECT MEDIAN(amount) FROM orders;         -- 精确中位数
SELECT MODE(city) FROM users;              -- 众数

-- 对比: PostgreSQL/Oracle 也有完整的统计函数
-- MEDIAN 在大多数引擎中需要 PERCENTILE_CONT(0.5) 实现

-- ============================================================
-- 6. 近似聚合（大数据量优化）
-- ============================================================

SELECT APPROX_COUNT_DISTINCT(user_id) FROM events;     -- HyperLogLog
SELECT APPROX_PERCENTILE(amount, 0.5) FROM orders;     -- 近似中位数
SELECT APPROX_TOP_K(city, 10) FROM users;               -- 近似 Top-K

-- 近似函数的设计意义:
--   精确 COUNT(DISTINCT) 在 TB 级数据上需要巨大内存（维护完整哈希表）
--   HyperLogLog 以 <1% 误差率，仅需 ~12KB 内存完成去重计数
--   对引擎开发者: HLL 是云数仓的标配功能
--
-- 对比:
--   BigQuery:   APPROX_COUNT_DISTINCT（也是 HLL）
--   Redshift:   APPROXIMATE COUNT(DISTINCT ...)
--   Databricks: APPROX_COUNT_DISTINCT
--   PostgreSQL: 无原生（需要 HLL 扩展）

-- ============================================================
-- 7. 位聚合与布尔聚合
-- ============================================================

SELECT BITAND_AGG(flags) FROM settings;
SELECT BITOR_AGG(flags) FROM settings;
SELECT BOOLAND_AGG(active) FROM users;    -- 所有为 TRUE → TRUE
SELECT BOOLOR_AGG(active) FROM users;     -- 任一为 TRUE → TRUE

-- ============================================================
-- 8. 其他聚合
-- ============================================================

SELECT ANY_VALUE(name) FROM users;        -- 组内任意值（不确定性）
SELECT HASH_AGG(*) FROM users;            -- 整表哈希（数据校验）

-- ============================================================
-- 横向对比: 聚合函数亮点
-- ============================================================
-- 特性            | Snowflake       | BigQuery     | PostgreSQL  | MySQL
-- GROUP BY ALL    | 支持            | 支持         | 不支持      | 不支持
-- FILTER 子句     | 不支持(用IFF)   | COUNTIF      | 支持        | 不支持
-- LISTAGG         | 支持            | STRING_AGG   | STRING_AGG  | GROUP_CONCAT
-- ARRAY_AGG       | 支持            | 支持         | 支持        | 不支持
-- OBJECT_AGG      | 支持(VARIANT)   | 不支持       | 不支持      | 不支持
-- APPROX_COUNT    | HyperLogLog     | HyperLogLog  | 扩展        | 不支持
-- MEDIAN          | 内置            | 不支持       | 不支持      | 不支持
-- 统计函数        | 完整            | 完整         | 完整        | 基本
