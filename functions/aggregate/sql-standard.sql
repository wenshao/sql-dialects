-- SQL 标准: 聚合函数
--
-- 参考资料:
--   [1] ISO/IEC 9075 SQL Standard
--       https://www.iso.org/standard/76583.html
--   [2] Modern SQL - by Markus Winand
--       https://modern-sql.com/
--   [3] Modern SQL - Aggregate Functions
--       https://modern-sql.com/feature/filter

-- SQL-86 (SQL1):
-- COUNT / SUM / AVG / MIN / MAX
-- GROUP BY / HAVING

SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;

SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > 10;

-- SQL-92 (SQL2):
-- 无聚合函数重大变化
-- 明确了 NULL 在聚合中的处理规则

-- SQL:1999 (SQL3):
-- GROUPING SETS / ROLLUP / CUBE
-- GROUPING() 函数
-- EVERY / ANY / SOME（布尔聚合）

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

-- 布尔聚合（SQL:1999）
SELECT EVERY(active) FROM users;                         -- 所有为 TRUE
SELECT ANY(active) FROM users;                           -- 任一为 TRUE
SELECT SOME(active) FROM users;                          -- 同 ANY

-- SQL:2003:
-- 统计函数
-- STDDEV_POP / STDDEV_SAMP
-- VAR_POP / VAR_SAMP
-- CORR / COVAR_POP / COVAR_SAMP
-- REGR_SLOPE / REGR_INTERCEPT / REGR_COUNT / REGR_R2 等
-- PERCENTILE_CONT / PERCENTILE_DISC（有序集聚合）

SELECT STDDEV_POP(amount) FROM orders;
SELECT VAR_SAMP(amount) FROM orders;
SELECT CORR(x, y) FROM data;
SELECT COVAR_POP(x, y) FROM data;
SELECT REGR_SLOPE(y, x) FROM data;

-- 有序集聚合（SQL:2003）
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) FROM orders;
SELECT PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY amount) FROM orders;

-- SQL:2008:
-- FILTER 子句（条件聚合）
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young,
    COUNT(*) FILTER (WHERE age >= 30) AS senior
FROM users;

-- SQL:2011:
-- 无聚合函数重大新增

-- SQL:2016:
-- LISTAGG（字符串聚合）
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;

-- JSON_ARRAYAGG / JSON_OBJECTAGG（JSON 聚合）
SELECT JSON_ARRAYAGG(username ORDER BY username) FROM users;
SELECT JSON_OBJECTAGG(KEY username VALUE age) FROM users;

-- SQL:2023:
-- ANY_VALUE
SELECT ANY_VALUE(name) FROM users;

-- 注意：标准中没有 STRING_AGG / GROUP_CONCAT（使用 LISTAGG）
-- 注意：标准中没有 ARRAY_AGG（各厂商扩展）
-- 注意：FILTER 子句在 SQL:2008 标准化，但很多数据库不支持
-- 注意：LISTAGG 在 SQL:2016 标准化
-- 注意：有序集聚合（WITHIN GROUP）在 SQL:2003 标准化
