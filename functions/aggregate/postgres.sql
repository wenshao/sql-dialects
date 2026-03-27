-- PostgreSQL: 聚合函数
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Aggregate Functions
--       https://www.postgresql.org/docs/current/functions-aggregate.html
--   [2] PostgreSQL Documentation - GROUP BY
--       https://www.postgresql.org/docs/current/queries-table-expressions.html#QUERIES-GROUP

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

-- GROUPING SETS（9.5+）
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS ((city), (status), ());

-- ROLLUP（9.5+）
SELECT city, status, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);

-- CUBE（9.5+）
SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE (city, status);

-- GROUPING() 函数（判断是否是汇总行）
SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users
GROUP BY ROLLUP (city);

-- 字符串聚合（9.0+）
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;
SELECT STRING_AGG(DISTINCT city, ', ') FROM users;

-- JSON 聚合
SELECT JSON_AGG(username) FROM users;
SELECT JSONB_AGG(username) FROM users;
SELECT JSON_OBJECT_AGG(username, age) FROM users;

-- 数组聚合
SELECT ARRAY_AGG(username ORDER BY username) FROM users;
SELECT ARRAY_AGG(DISTINCT city) FROM users;

-- 统计函数
SELECT STDDEV(amount) FROM orders;                     -- 样本标准差
SELECT STDDEV_POP(amount) FROM orders;                 -- 总体标准差
SELECT VARIANCE(amount) FROM orders;                   -- 样本方差
SELECT VAR_POP(amount) FROM orders;                    -- 总体方差
SELECT CORR(x, y) FROM data;                          -- 相关系数
SELECT COVAR_SAMP(x, y) FROM data;                    -- 样本协方差
SELECT REGR_SLOPE(y, x) FROM data;                    -- 线性回归斜率

-- FILTER（聚合条件过滤，9.4+）
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young,
    COUNT(*) FILTER (WHERE age >= 30) AS senior
FROM users;

-- 布尔聚合
SELECT BOOL_AND(active) FROM users;                    -- 所有为 TRUE
SELECT BOOL_OR(active) FROM users;                     -- 任一为 TRUE
SELECT EVERY(active) FROM users;                       -- 同 BOOL_AND

-- BIT 聚合
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;
