-- Greenplum: 聚合函数
--
-- 参考资料:
--   [1] Greenplum SQL Reference
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html
--   [2] Greenplum Admin Guide
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html

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

-- GROUPING SETS
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS ((city), (status), (city, status), ());

-- ROLLUP
SELECT city, status, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);

-- CUBE
SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE (city, status);

-- GROUPING 函数（判断是否为汇总行）
SELECT city, status,
    GROUPING(city) AS city_is_total,
    GROUPING(status) AS status_is_total,
    COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);

-- 字符串聚合
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;
SELECT STRING_AGG(DISTINCT city, ', ') FROM users;

-- JSON 聚合
SELECT jsonb_agg(username) FROM users;
SELECT jsonb_object_agg(username, age) FROM users;

-- 数组聚合
SELECT ARRAY_AGG(username ORDER BY username) FROM users;
SELECT ARRAY_AGG(DISTINCT city) FROM users;

-- 统计函数
SELECT STDDEV(amount) FROM orders;
SELECT STDDEV_POP(amount) FROM orders;
SELECT STDDEV_SAMP(amount) FROM orders;
SELECT VARIANCE(amount) FROM orders;
SELECT VAR_POP(amount) FROM orders;
SELECT VAR_SAMP(amount) FROM orders;
SELECT CORR(age, balance) FROM users;
SELECT COVAR_POP(age, balance) FROM users;
SELECT COVAR_SAMP(age, balance) FROM users;
SELECT REGR_SLOPE(balance, age) FROM users;

-- 百分位数
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) FROM orders;
SELECT PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY amount) FROM orders;

-- 排序聚合
SELECT MODE() WITHIN GROUP (ORDER BY city) FROM users;

-- FILTER 子句（条件聚合）
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE status = 1) AS active,
    COUNT(*) FILTER (WHERE age >= 18) AS adults,
    AVG(age) FILTER (WHERE status = 1) AS avg_active_age
FROM users;

-- BIT 聚合
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;

-- BOOL 聚合
SELECT BOOL_AND(active) FROM users;
SELECT BOOL_OR(active) FROM users;
SELECT EVERY(active) FROM users;             -- 同 BOOL_AND

-- 注意：Greenplum 兼容 PostgreSQL 聚合函数
-- 注意：支持 GROUPING SETS / ROLLUP / CUBE
-- 注意：STRING_AGG 替代 MySQL 的 GROUP_CONCAT
-- 注意：FILTER 子句用于条件聚合（非常强大）
