-- SQLite: 聚合函数
--
-- 参考资料:
--   [1] SQLite Documentation - Aggregate Functions
--       https://www.sqlite.org/lang_aggfunc.html
--   [2] SQLite Documentation - SELECT (GROUP BY)
--       https://www.sqlite.org/lang_select.html

-- 基本聚合
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;
SELECT TOTAL(amount) FROM orders;                      -- 同 SUM 但返回 0.0 而非 NULL

-- GROUP BY
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city;

-- HAVING
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING cnt > 10;

-- 字符串聚合
SELECT GROUP_CONCAT(username, ', ') FROM users;
SELECT GROUP_CONCAT(DISTINCT city, ', ') FROM users;
-- 注意：GROUP_CONCAT 不支持 ORDER BY

-- JSON 聚合（3.33.0+）
SELECT json_group_array(username) FROM users;
SELECT json_group_object(username, age) FROM users;

-- 注意：不支持 GROUPING SETS / ROLLUP / CUBE
-- 3.30.0+: 支持 FILTER 子句
-- SELECT COUNT(*) FILTER (WHERE age > 18) FROM users;
-- 注意：没有统计函数（STDDEV、VARIANCE 等），需要自己计算

-- 3.25.0+: 窗口聚合
SELECT username, age,
    SUM(age) OVER () AS total_age,
    AVG(age) OVER () AS avg_age
FROM users;
