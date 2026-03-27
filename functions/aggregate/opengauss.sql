-- openGauss/GaussDB: 聚合函数
-- PostgreSQL compatible syntax.
--
-- 参考资料:
--   [1] openGauss SQL Reference
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html
--   [2] GaussDB Documentation
--       https://support.huaweicloud.com/gaussdb/index.html

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
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;
SELECT STRING_AGG(DISTINCT city, ', ') FROM users;

-- JSON 聚合
SELECT JSON_AGG(username) FROM users;
SELECT JSONB_AGG(username) FROM users;
SELECT JSON_OBJECT_AGG(username, age) FROM users;

-- 数组聚合
SELECT ARRAY_AGG(username ORDER BY username) FROM users;

-- 统计函数
SELECT STDDEV(amount) FROM orders;
SELECT STDDEV_POP(amount) FROM orders;
SELECT VARIANCE(amount) FROM orders;
SELECT VAR_POP(amount) FROM orders;

-- FILTER
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young,
    COUNT(*) FILTER (WHERE age >= 30) AS senior
FROM users;

-- 布尔聚合
SELECT BOOL_AND(active) FROM users;
SELECT BOOL_OR(active) FROM users;
SELECT EVERY(active) FROM users;

-- 注意事项：
-- 聚合函数与 PostgreSQL 兼容
-- 支持 GROUPING SETS / ROLLUP / CUBE
-- 支持 FILTER 子句
-- GaussDB 分布式版本中聚合需要跨 DN 合并
