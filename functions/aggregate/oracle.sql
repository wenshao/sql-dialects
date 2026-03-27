-- Oracle: 聚合函数
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Aggregate Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Aggregate-Functions.html
--   [2] Oracle SQL Language Reference - SELECT
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html

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

-- GROUPING SETS（9i+）
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

-- GROUPING() / GROUPING_ID()
SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users
GROUP BY ROLLUP (city);

-- 字符串聚合（11g R2+）
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
-- 12c R2+: 防溢出
SELECT LISTAGG(username, ', ' ON OVERFLOW TRUNCATE '...' WITHOUT COUNT)
    WITHIN GROUP (ORDER BY username) FROM users;

-- 19c+: LISTAGG DISTINCT
SELECT LISTAGG(DISTINCT city, ', ') WITHIN GROUP (ORDER BY city) FROM users;

-- JSON 聚合（12c R2+）
SELECT JSON_ARRAYAGG(username ORDER BY username) FROM users;
SELECT JSON_OBJECTAGG(username VALUE age) FROM users;

-- 统计函数
SELECT STDDEV(amount) FROM orders;
SELECT STDDEV_POP(amount) FROM orders;
SELECT VARIANCE(amount) FROM orders;
SELECT VAR_POP(amount) FROM orders;
SELECT CORR(x, y) FROM data;
SELECT COVAR_SAMP(x, y) FROM data;
SELECT REGR_SLOPE(y, x) FROM data;
SELECT MEDIAN(age) FROM users;                         -- 中位数（Oracle 特有）

-- KEEP（在排名相同的行中取值）
SELECT
    MIN(age) KEEP (DENSE_RANK FIRST ORDER BY created_at) AS first_age,
    MIN(age) KEEP (DENSE_RANK LAST ORDER BY created_at) AS last_age
FROM users;

-- COLLECT（收集为嵌套表，10g+）
-- SELECT COLLECT(username) FROM users;

-- APPROX_COUNT_DISTINCT（近似去重计数，12c+，适合大数据量）
SELECT APPROX_COUNT_DISTINCT(city) FROM users;
