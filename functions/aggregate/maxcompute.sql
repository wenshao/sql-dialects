-- MaxCompute (ODPS): 聚合函数
--
-- 参考资料:
--   [1] MaxCompute SQL - Aggregate Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/aggregate-functions
--   [2] MaxCompute Built-in Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/built-in-functions-overview

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

-- GROUPING SETS / ROLLUP / CUBE（2.0+）
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
SELECT WM_CONCAT(',', username) FROM users;              -- MaxCompute 特有
-- 注意：不支持排序，不保证顺序

-- 数组聚合
SELECT COLLECT_LIST(username) FROM users;                -- 收集为数组（含重复）
SELECT COLLECT_SET(city) FROM users;                     -- 收集为去重数组

-- 统计函数
SELECT STDDEV(amount) FROM orders;                       -- 样本标准差
SELECT STDDEV_POP(amount) FROM orders;                   -- 总体标准差
SELECT STDDEV_SAMP(amount) FROM orders;                  -- 样本标准差
SELECT VARIANCE(amount) FROM orders;                     -- 样本方差
SELECT VAR_POP(amount) FROM orders;                      -- 总体方差
SELECT COVAR_SAMP(x, y) FROM data;                       -- 样本协方差
SELECT COVAR_POP(x, y) FROM data;                        -- 总体协方差
SELECT CORR(x, y) FROM data;                             -- 相关系数

-- 中位数 / 百分位
SELECT MEDIAN(amount) FROM orders;                       -- 中位数
SELECT PERCENTILE(amount, 0.5) FROM orders;              -- 百分位（精确）
SELECT PERCENTILE_APPROX(amount, 0.5) FROM orders;       -- 近似百分位

-- 近似聚合
SELECT APPROX_DISTINCT(user_id) FROM events;             -- 近似去重

-- 其他
SELECT ANY_VALUE(name) FROM users;                       -- 任意值（2.0+）
SELECT MAX_BY(name, age) FROM users;                     -- 按 age 最大值取 name
SELECT MIN_BY(name, age) FROM users;                     -- 按 age 最小值取 name

-- 条件聚合（使用 CASE/IF）
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN age < 30 THEN 1 ELSE 0 END) AS young,
    SUM(IF(status = 'active', amount, 0)) AS active_amount
FROM users;

-- 注意：WM_CONCAT 是字符串聚合函数（与 Oracle 类似）
-- 注意：不支持 STRING_AGG / LISTAGG
-- 注意：COLLECT_LIST/COLLECT_SET 返回数组
-- 注意：没有 FILTER 子句
