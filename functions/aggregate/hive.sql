-- Hive: 聚合函数
--
-- 参考资料:
--   [1] Apache Hive - Aggregate Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-Built-inAggregateFunctions(UDAF)
--   [2] Apache Hive - GROUP BY
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+GroupBy

-- 基本聚合
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;

-- GROUP BY
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city;

-- HAVING
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > 10;

-- GROUPING SETS / ROLLUP / CUBE（0.10+）
SELECT city, status, COUNT(*)
FROM users
GROUP BY city, status
GROUPING SETS ((city), (status), ());

SELECT city, status, COUNT(*)
FROM users
GROUP BY city, status
WITH ROLLUP;

SELECT city, status, COUNT(*)
FROM users
GROUP BY city, status
WITH CUBE;

SELECT city, GROUPING__ID, COUNT(*)
FROM users
GROUP BY city
WITH ROLLUP;

-- 注意：Hive 的 GROUPING SETS 语法与 SQL 标准略有不同

-- 数组/集合聚合
SELECT COLLECT_LIST(username) FROM users;                -- 收集为数组（含重复）
SELECT COLLECT_SET(city) FROM users;                     -- 收集为去重数组
-- 注意：不支持 ORDER BY 排序

-- 字符串聚合
-- Hive 没有内置 STRING_AGG / LISTAGG
-- 使用 COLLECT_LIST（0.13+）+ CONCAT_WS 实现
SELECT CONCAT_WS(',', COLLECT_LIST(username)) FROM users;

-- 统计函数
SELECT STDDEV(amount) FROM orders;                       -- 样本标准差
SELECT STDDEV_POP(amount) FROM orders;                   -- 总体标准差
SELECT STDDEV_SAMP(amount) FROM orders;                  -- 样本标准差
SELECT VARIANCE(amount) FROM orders;                     -- 样本方差
SELECT VAR_POP(amount) FROM orders;                      -- 总体方差
SELECT VAR_SAMP(amount) FROM orders;                     -- 样本方差
SELECT COVAR_SAMP(x, y) FROM data;                       -- 样本协方差
SELECT COVAR_POP(x, y) FROM data;                        -- 总体协方差
SELECT CORR(x, y) FROM data;                             -- 相关系数
SELECT REGR_SLOPE(y, x) FROM data;                       -- 线性回归

-- 百分位
SELECT PERCENTILE(amount, 0.5) FROM orders;              -- 精确中位数（仅 BIGINT）
SELECT PERCENTILE_APPROX(amount, 0.5) FROM orders;       -- 近似百分位（任意数值）
SELECT PERCENTILE_APPROX(amount, ARRAY(0.25, 0.5, 0.75)) FROM orders; -- 多个百分位
SELECT HISTOGRAM_NUMERIC(amount, 10) FROM orders;        -- 直方图

-- NTILE 等分（仅窗口函数，此处列出参考）
-- SELECT NTILE(4) OVER (ORDER BY amount) FROM orders;

-- 其他
SELECT COUNT(DISTINCT a, b) FROM t;                      -- 多列去重（Hive 特有语法）

-- UDAF（用户自定义聚合函数）
-- Hive 支持通过 Java 编写自定义聚合函数
-- CREATE FUNCTION my_agg AS 'com.example.MyAggFunction';

-- 条件聚合（使用 CASE/IF）
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN age < 30 THEN 1 ELSE 0 END) AS young,
    SUM(IF(status = 'active', amount, 0)) AS active_amount
FROM users;

-- 注意：没有 STRING_AGG / LISTAGG（用 COLLECT_LIST + CONCAT_WS）
-- 注意：没有 FILTER 子句
-- 注意：COLLECT_LIST/COLLECT_SET 在大数据量时可能 OOM
-- 注意：COUNT(DISTINCT a, b) 多列去重是 Hive 特有语法
-- 注意：GROUPING SETS 语法与 SQL 标准不完全一致
