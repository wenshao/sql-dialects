-- Apache Doris: 聚合函数
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- 基本聚合
SELECT COUNT(*) FROM users;                           -- 总行数
SELECT COUNT(email) FROM users;                       -- 非 NULL 行数
SELECT COUNT(DISTINCT city) FROM users;               -- 去重计数
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
HAVING cnt > 10;

-- GROUP BY 位置引用
SELECT city, COUNT(*) FROM users GROUP BY 1;

-- GROUPING SETS
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS ((city), (status), (city, status), ());

-- ROLLUP（层级汇总）
SELECT city, status, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);

-- CUBE（全组合汇总）
SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE (city, status);

-- 字符串聚合
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;
SELECT GROUP_CONCAT(DISTINCT city SEPARATOR ', ') FROM users;

-- 统计函数
SELECT STDDEV(amount) FROM orders;                    -- 标准差
SELECT STDDEV_SAMP(amount) FROM orders;              -- 样本标准差
SELECT VARIANCE(amount) FROM orders;                  -- 方差
SELECT VAR_SAMP(amount) FROM orders;                 -- 样本方差

-- 近似聚合
SELECT APPROX_COUNT_DISTINCT(user_id) FROM orders;   -- 近似去重计数
SELECT NDV(user_id) FROM orders;                     -- 同上（别名）

-- BITMAP 精确去重
SELECT BITMAP_COUNT(BITMAP_UNION(TO_BITMAP(user_id))) FROM orders;
SELECT BITMAP_UNION_COUNT(TO_BITMAP(user_id)) FROM orders;

-- HLL 近似去重
SELECT HLL_UNION_AGG(HLL_HASH(user_id)) FROM orders;

-- 百分位数
SELECT PERCENTILE(amount, 0.5) FROM orders;           -- 中位数
SELECT PERCENTILE_APPROX(amount, 0.95) FROM orders;   -- 近似 P95

-- COLLECT_LIST / COLLECT_SET（收集为数组）
SELECT city, COLLECT_LIST(username) FROM users GROUP BY city;
SELECT city, COLLECT_SET(username) FROM users GROUP BY city;

-- BIT 聚合
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;
SELECT BIT_XOR(flags) FROM settings;

-- 注意：Doris 兼容 MySQL 聚合函数
-- 注意：支持 GROUPING SETS / ROLLUP / CUBE
-- 注意：BITMAP 和 HLL 用于高性能去重聚合
-- 注意：APPROX_COUNT_DISTINCT / NDV 是近似去重
