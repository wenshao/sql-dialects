-- SQL Server: 聚合函数
--
-- 参考资料:
--   [1] SQL Server T-SQL - Aggregate Functions
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/aggregate-functions-transact-sql
--   [2] SQL Server T-SQL - GROUP BY
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/select-group-by-transact-sql

-- 基本聚合
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT COUNT_BIG(*) FROM users;                        -- 返回 BIGINT
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

-- GROUPING SETS（2008+）
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS ((city), (status), ());

-- ROLLUP（2008+）
SELECT city, status, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);
-- 传统语法: GROUP BY city, status WITH ROLLUP

-- CUBE（2008+）
SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE (city, status);
-- 传统语法: GROUP BY city, status WITH CUBE

-- GROUPING() / GROUPING_ID()
SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users
GROUP BY ROLLUP (city);

-- 字符串聚合（2017+）
SELECT STRING_AGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;

-- 2017 之前用 FOR XML PATH 模拟
SELECT STUFF((SELECT ', ' + username FROM users ORDER BY username FOR XML PATH('')), 1, 2, '');

-- JSON 聚合（2016+，用 FOR JSON）
SELECT username, age FROM users FOR JSON PATH;

-- 统计函数
SELECT STDEV(amount) FROM orders;                      -- 样本标准差
SELECT STDEVP(amount) FROM orders;                     -- 总体标准差
SELECT VAR(amount) FROM orders;                        -- 样本方差
SELECT VARP(amount) FROM orders;                       -- 总体方差

-- CHECKSUM_AGG（聚合校验和）
SELECT CHECKSUM_AGG(CHECKSUM(username)) FROM users;

-- 2019+: APPROX_COUNT_DISTINCT（近似去重计数）
SELECT APPROX_COUNT_DISTINCT(city) FROM users;
