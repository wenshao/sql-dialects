-- BigQuery: 聚合函数
--
-- 参考资料:
--   [1] BigQuery SQL Reference - Aggregate Functions
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/aggregate_functions
--   [2] BigQuery SQL Reference - GROUP BY
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#group_by_clause

-- 基本聚合
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT COUNTIF(age > 30) FROM users;                     -- 条件计数
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

-- GROUPING SETS / ROLLUP / CUBE
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

-- 字符串聚合
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;
SELECT STRING_AGG(DISTINCT city, ', ') FROM users;

-- 数组聚合
SELECT ARRAY_AGG(username ORDER BY username) FROM users;
SELECT ARRAY_AGG(DISTINCT city) FROM users;
SELECT ARRAY_CONCAT_AGG(tags) FROM users;                -- 合并数组

-- 统计函数
SELECT STDDEV(amount) FROM orders;                       -- 样本标准差
SELECT STDDEV_POP(amount) FROM orders;                   -- 总体标准差
SELECT STDDEV_SAMP(amount) FROM orders;                  -- 样本标准差
SELECT VARIANCE(amount) FROM orders;                     -- 样本方差
SELECT VAR_POP(amount) FROM orders;                      -- 总体方差
SELECT CORR(x, y) FROM data;                             -- 相关系数
SELECT COVAR_SAMP(x, y) FROM data;                       -- 样本协方差
SELECT COVAR_POP(x, y) FROM data;                        -- 总体协方差

-- 近似聚合（大规模数据优化）
SELECT APPROX_COUNT_DISTINCT(user_id) FROM events;       -- HyperLogLog++ 近似去重
SELECT APPROX_QUANTILES(amount, 100)[OFFSET(50)] FROM orders;  -- 近似中位数
SELECT APPROX_TOP_COUNT(city, 10) FROM users;            -- 近似 TOP N
SELECT APPROX_TOP_SUM(city, amount, 10) FROM users;     -- 近似 TOP N 按总和

-- 逻辑聚合
SELECT LOGICAL_AND(active) FROM users;                   -- 所有为 TRUE
SELECT LOGICAL_OR(active) FROM users;                    -- 任一为 TRUE

-- BIT 聚合
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;
SELECT BIT_XOR(flags) FROM settings;

-- 安全除法
SELECT SAFE_DIVIDE(SUM(revenue), COUNT(*)) FROM orders;  -- 除零返回 NULL

-- STRUCT 聚合
SELECT ANY_VALUE(name) FROM users;                       -- 任意值

-- 注意：COUNTIF 是 BigQuery 特有的便捷函数
-- 注意：APPROX_COUNT_DISTINCT 比 COUNT(DISTINCT) 更适合大数据量
-- 注意：没有 FILTER 子句（用 COUNTIF 或 IF 替代）
-- 注意：STRING_AGG 是主要的字符串聚合函数
