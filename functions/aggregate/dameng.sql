-- DamengDB (达梦): 聚合函数
-- Oracle compatible syntax.
--
-- 参考资料:
--   [1] DamengDB SQL Reference
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html
--   [2] DamengDB System Admin Manual
--       https://eco.dameng.com/document/dm/zh-cn/pm/index.html

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

-- 字符串聚合（LISTAGG，Oracle 兼容）
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
SELECT city, LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username)
FROM users GROUP BY city;

-- 统计函数
SELECT STDDEV(amount) FROM orders;
SELECT STDDEV_POP(amount) FROM orders;
SELECT VARIANCE(amount) FROM orders;
SELECT VAR_POP(amount) FROM orders;
SELECT CORR(x, y) FROM data;
SELECT COVAR_SAMP(x, y) FROM data;
SELECT REGR_SLOPE(y, x) FROM data;

-- MEDIAN（中位数，Oracle 兼容）
SELECT MEDIAN(age) FROM users;

-- 注意事项：
-- 聚合函数与 Oracle 兼容
-- 使用 LISTAGG 进行字符串聚合（不是 GROUP_CONCAT）
-- 支持 GROUPING SETS / ROLLUP / CUBE
-- 支持 MEDIAN 中位数函数
