-- StarRocks: 聚合函数
--
-- 参考资料:
--   [1] StarRocks - Aggregate Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/aggregate-functions/
--   [2] StarRocks SQL Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/

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

-- GROUPING_ID（多列判断）
SELECT city, status, GROUPING_ID(city, status), COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);

-- 字符串聚合
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;
SELECT GROUP_CONCAT(DISTINCT city SEPARATOR ', ') FROM users;

-- 数组聚合
SELECT ARRAY_AGG(username ORDER BY username) FROM users;  -- 3.0+

-- BITMAP 聚合（StarRocks 核心特性）
SELECT BITMAP_UNION_COUNT(user_bitmap) FROM agg_table;    -- 位图合并去重计数
SELECT BITMAP_UNION(user_bitmap) FROM agg_table;          -- 位图合并
SELECT BITMAP_INTERSECT(user_bitmap) FROM agg_table;      -- 位图交集
SELECT BITMAP_COUNT(BITMAP_UNION(user_bitmap)) FROM agg_table;

-- HLL 聚合
SELECT HLL_UNION_AGG(uv_hll) FROM agg_table;             -- HLL 合并
SELECT HLL_CARDINALITY(HLL_UNION_AGG(uv_hll)) FROM agg_table; -- HLL 去重计数
SELECT NDV(user_id) FROM events;                         -- 近似去重（HLL）

-- 百分位
SELECT PERCENTILE_APPROX(amount, 0.5) FROM orders;       -- 近似中位数
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) FROM orders; -- 精确

-- 统计函数
SELECT STDDEV(amount) FROM orders;                       -- 样本标准差
SELECT STDDEV_POP(amount) FROM orders;                   -- 总体标准差
SELECT STDDEV_SAMP(amount) FROM orders;                  -- 样本标准差
SELECT VARIANCE(amount) FROM orders;                     -- 样本方差
SELECT VAR_POP(amount) FROM orders;                      -- 总体方差
SELECT VAR_SAMP(amount) FROM orders;                     -- 样本方差
SELECT CORR(x, y) FROM data;                             -- 相关系数
SELECT COVAR_SAMP(x, y) FROM data;                       -- 样本协方差
SELECT COVAR_POP(x, y) FROM data;                        -- 总体协方差

-- 其他
SELECT ANY_VALUE(name) FROM users;                       -- 任意值
SELECT MAX_BY(name, age) FROM users;                     -- 按 age 最大值取 name（2.5+）
SELECT MIN_BY(name, age) FROM users;                     -- 按 age 最小值取 name（2.5+）
SELECT MULTI_DISTINCT_COUNT(city, status) FROM users;    -- 多列去重计数

-- 条件聚合（使用 CASE/IF）
SELECT
    COUNT(*) AS total,
    SUM(IF(age < 30, 1, 0)) AS young,
    SUM(IF(status = 'active', amount, 0)) AS active_amount
FROM users;

-- 注意：GROUP_CONCAT 与 MySQL 兼容
-- 注意：BITMAP/HLL 聚合是 StarRocks 的核心分析特性
-- 注意：NDV 是 COUNT(DISTINCT) 的 HLL 近似版
-- 注意：没有 FILTER 子句
-- 注意：聚合模型表可以预聚合提升查询性能
