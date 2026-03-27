-- Apache Impala: 聚合函数
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- 基本聚合
SELECT COUNT(*) FROM users;
SELECT COUNT(email) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;

-- GROUP BY
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city;

-- GROUP BY + HAVING
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > 10;

-- GROUP BY 位置引用
SELECT city, COUNT(*) FROM users GROUP BY 1;

-- 注意：不支持 GROUPING SETS / ROLLUP / CUBE
-- 需要通过 UNION ALL 模拟

-- UNION ALL 模拟 ROLLUP
SELECT city, COUNT(*) FROM users GROUP BY city
UNION ALL
SELECT NULL AS city, COUNT(*) FROM users;

-- 字符串聚合
SELECT GROUP_CONCAT(username, ', ') FROM users;
-- 注意：GROUP_CONCAT 不支持 ORDER BY

-- 统计函数
SELECT STDDEV(amount) FROM orders;
SELECT STDDEV_POP(amount) FROM orders;
SELECT STDDEV_SAMP(amount) FROM orders;
SELECT VARIANCE(amount) FROM orders;
SELECT VARIANCE_POP(amount) FROM orders;
SELECT VARIANCE_SAMP(amount) FROM orders;

-- 近似聚合
SELECT NDV(user_id) FROM orders;              -- 近似去重（HyperLogLog）
SELECT APPX_MEDIAN(amount) FROM orders;       -- 近似中位数

-- 采样
SELECT NDV(user_id) FROM orders TABLESAMPLE SYSTEM(10);  -- 10% 采样

-- 条件聚合（使用 CASE）
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) AS active,
    SUM(CASE WHEN age >= 18 THEN 1 ELSE 0 END) AS adults,
    AVG(CASE WHEN status = 1 THEN age END) AS avg_active_age
FROM users;

-- MIN/MAX 用于字符串
SELECT MIN(username) FROM users;              -- 字典序最小
SELECT MAX(username) FROM users;              -- 字典序最大

-- 多列去重计数
SELECT COUNT(DISTINCT city, status) FROM users;  -- 不支持
-- 替代方案：
SELECT COUNT(DISTINCT CONCAT(city, '|', CAST(status AS STRING))) FROM users;

-- 注意：Impala 不支持 GROUPING SETS / ROLLUP / CUBE
-- 注意：NDV 是 HyperLogLog 近似去重（比 COUNT(DISTINCT) 快）
-- 注意：不支持 STRING_AGG / LISTAGG
-- 注意：GROUP_CONCAT 是 Impala 特有的聚合函数
-- 注意：不支持 FILTER 子句
-- 注意：APPX_MEDIAN 是近似中位数
