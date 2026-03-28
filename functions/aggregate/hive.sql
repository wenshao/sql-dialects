-- Hive: 聚合函数
--
-- 参考资料:
--   [1] Apache Hive - Aggregate Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-Built-inAggregateFunctions
--   [2] Apache Hive - GROUP BY
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+GroupBy

-- ============================================================
-- 1. 基本聚合函数
-- ============================================================
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT COUNT(DISTINCT city, status) FROM users;  -- 多列去重（Hive 特有）
SELECT SUM(amount), AVG(amount), MIN(amount), MAX(amount) FROM orders;

-- GROUP BY + HAVING
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city
HAVING COUNT(*) > 10;

-- ============================================================
-- 2. GROUPING SETS / ROLLUP / CUBE (0.10+)
-- ============================================================
-- GROUPING SETS: 指定多组聚合维度
SELECT city, status, COUNT(*)
FROM users
GROUP BY city, status
GROUPING SETS ((city), (status), (city, status), ());

-- ROLLUP: 层级汇总（从明细到总计）
SELECT city, status, COUNT(*)
FROM users
GROUP BY city, status
WITH ROLLUP;

-- CUBE: 所有可能的维度组合
SELECT city, status, COUNT(*)
FROM users
GROUP BY city, status
WITH CUBE;

-- GROUPING__ID: 标识聚合级别
SELECT city, GROUPING__ID, COUNT(*)
FROM users
GROUP BY city WITH ROLLUP;

-- 设计分析: Hive GROUPING SETS 的语法差异
-- SQL 标准: GROUP BY GROUPING SETS ((city), (status), ())
-- Hive:     GROUP BY city, status GROUPING SETS ((city), (status), ())
-- Hive 要求在 GROUP BY 中列出所有可能的列，再用 GROUPING SETS 指定组合
-- 这是早期实现的遗留问题，Hive 3.0+ 也支持 SQL 标准语法

-- ============================================================
-- 3. 集合聚合: COLLECT_LIST / COLLECT_SET (Hive 特色)
-- ============================================================
-- COLLECT_LIST: 聚合为数组（含重复）
SELECT department, COLLECT_LIST(name) AS members
FROM employees GROUP BY department;

-- COLLECT_SET: 聚合为去重数组
SELECT department, COLLECT_SET(name) AS unique_members
FROM employees GROUP BY department;

-- 字符串聚合: COLLECT_LIST + CONCAT_WS
SELECT department, CONCAT_WS(',', COLLECT_LIST(name)) AS member_csv
FROM employees GROUP BY department;

-- 注意: COLLECT_LIST/COLLECT_SET 在大数据量下可能 OOM
-- 因为它们将一个分组内的所有值收集到内存中的数组里
-- 如果某个分组有数百万行，数组可能超过 JVM 内存限制

-- 对比:
--   PostgreSQL: ARRAY_AGG(name) / STRING_AGG(name, ',')
--   MySQL:      GROUP_CONCAT(name SEPARATOR ',')
--   BigQuery:   ARRAY_AGG(name) / STRING_AGG(name, ',')
--   Spark SQL:  COLLECT_LIST/COLLECT_SET（继承 Hive）

-- ============================================================
-- 4. 条件聚合
-- ============================================================
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN age < 30 THEN 1 ELSE 0 END) AS young_count,
    SUM(IF(status = 'active', amount, 0)) AS active_total,
    COUNT(CASE WHEN city = 'Beijing' THEN 1 END) AS beijing_count
FROM users;

-- Hive 不支持 FILTER 子句:
-- SQL 标准: COUNT(*) FILTER (WHERE age < 30)
-- Hive:     SUM(CASE WHEN age < 30 THEN 1 ELSE 0 END)

-- ============================================================
-- 5. 统计聚合函数
-- ============================================================
SELECT STDDEV(amount) FROM orders;          -- 样本标准差
SELECT STDDEV_POP(amount) FROM orders;      -- 总体标准差
SELECT VARIANCE(amount) FROM orders;        -- 样本方差
SELECT VAR_POP(amount) FROM orders;         -- 总体方差
SELECT COVAR_SAMP(x, y) FROM data;          -- 样本协方差
SELECT COVAR_POP(x, y) FROM data;           -- 总体协方差
SELECT CORR(x, y) FROM data;               -- 相关系数

-- 百分位
SELECT PERCENTILE(amount, 0.5) FROM orders;                    -- 精确中位数（仅 BIGINT）
SELECT PERCENTILE_APPROX(amount, 0.5) FROM orders;             -- 近似百分位
SELECT PERCENTILE_APPROX(amount, ARRAY(0.25, 0.5, 0.75)) FROM orders; -- 多百分位

-- 直方图
SELECT HISTOGRAM_NUMERIC(amount, 10) FROM orders;

-- ============================================================
-- 6. 跨引擎对比: 聚合函数
-- ============================================================
-- 功能             Hive               MySQL          PostgreSQL     BigQuery
-- 字符串聚合       COLLECT_LIST+CONCAT GROUP_CONCAT   STRING_AGG     STRING_AGG
-- 数组聚合         COLLECT_LIST        无             ARRAY_AGG      ARRAY_AGG
-- 去重数组         COLLECT_SET         无             无(需DISTINCT) 无(需DISTINCT)
-- 多列去重COUNT    COUNT(DISTINCT a,b) 支持           不支持         COUNT(DISTINCT a||b)
-- 条件聚合         CASE WHEN           CASE WHEN      FILTER         COUNTIF
-- 近似百分位       PERCENTILE_APPROX   无             无(需扩展)     APPROX_QUANTILES
-- GROUPING SETS   支持(0.10+)         8.0+           支持           支持

-- ============================================================
-- 7. 已知限制
-- ============================================================
-- 1. 无 STRING_AGG / LISTAGG: 用 COLLECT_LIST + CONCAT_WS 替代
-- 2. 无 FILTER 子句: 用 CASE WHEN 替代条件聚合
-- 3. COLLECT_LIST 大数据量 OOM: 单个分组数据过多时内存溢出
-- 4. PERCENTILE 仅支持 BIGINT: 浮点数需要用 PERCENTILE_APPROX
-- 5. 无 WITHIN GROUP: Hive 没有有序聚合语法
-- 6. GROUPING__ID 行为与 SQL 标准不一致: 位编码方式不同

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================
-- 1. COLLECT_LIST/COLLECT_SET 是大数据引擎的标配:
--    将行聚合为数组是处理嵌套数据的基础能力
-- 2. 近似聚合对大数据量很重要: PERCENTILE_APPROX 比 PERCENTILE 快得多，
--    大数据引擎应该提供近似计算选项（如 APPROX_COUNT_DISTINCT）
-- 3. GROUPING SETS 的 SQL 标准兼容性: 不同引擎的语法差异是迁移的痛点
-- 4. FILTER 子句应该被支持: 比 CASE WHEN 更简洁，可读性更好
