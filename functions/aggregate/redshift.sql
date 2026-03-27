-- Redshift: 聚合函数
--
-- 参考资料:
--   [1] Redshift SQL Reference
--       https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html
--   [2] Redshift SQL Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html
--   [3] Redshift Data Types
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html

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

-- GROUPING SETS
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS ((city), (status), ());

-- ROLLUP
SELECT city, status, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);

-- CUBE
SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE (city, status);

-- GROUPING() 函数
SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users
GROUP BY ROLLUP (city);

-- 字符串聚合
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
SELECT city, LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) AS user_list
FROM users GROUP BY city;

-- 近似计数（HyperLogLog，Redshift 特有高效近似）
SELECT APPROXIMATE COUNT(DISTINCT user_id) FROM events;
-- 比 COUNT(DISTINCT) 快得多，误差约 2%

-- HLL 函数
SELECT HLL(user_id) FROM events;                     -- 创建 HLL sketch
SELECT HLL_CARDINALITY(HLL(user_id)) FROM events;   -- 从 sketch 估算基数
-- HLL sketch 可以合并
SELECT HLL_COMBINE(sketch_col) FROM daily_sketches;

-- 统计函数
SELECT STDDEV(amount) FROM orders;                   -- 样本标准差
SELECT STDDEV_POP(amount) FROM orders;               -- 总体标准差
SELECT STDDEV_SAMP(amount) FROM orders;              -- 同 STDDEV
SELECT VARIANCE(amount) FROM orders;                 -- 样本方差
SELECT VAR_POP(amount) FROM orders;                  -- 总体方差
SELECT VAR_SAMP(amount) FROM orders;                 -- 同 VARIANCE

-- 百分位
SELECT MEDIAN(age) FROM users;                       -- 中位数（Redshift 特有快捷方式）
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY age) FROM users;
SELECT PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY age) FROM users;
SELECT PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY amount) FROM orders;

-- 位聚合
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;

-- 布尔聚合
SELECT BOOL_AND(active) FROM users;                  -- 所有为 TRUE
SELECT BOOL_OR(active) FROM users;                   -- 任一为 TRUE

-- 注意：LISTAGG 是字符串聚合函数（不是 STRING_AGG）
-- 注意：APPROXIMATE COUNT(DISTINCT) 是 Redshift 特有的高效近似计数
-- 注意：HLL 函数可以跨时间窗口合并 sketch
-- 注意：MEDIAN 是 PERCENTILE_CONT(0.5) 的快捷方式
-- 注意：不支持 FILTER 子句
-- 注意：不支持 ARRAY_AGG / JSON_AGG
