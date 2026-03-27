-- MySQL: 聚合函数
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - Aggregate Functions
--       https://dev.mysql.com/doc/refman/8.0/en/aggregate-functions.html
--   [2] MySQL 8.0 Reference Manual - GROUP BY
--       https://dev.mysql.com/doc/refman/8.0/en/group-by-handling.html

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
SELECT city, COUNT(*) FROM users GROUP BY 1;           -- 按第 1 列分组

-- MySQL 不支持 GROUPING SETS（需要用 UNION ALL 模拟）

-- WITH ROLLUP（层级汇总）
SELECT city, COUNT(*) FROM users GROUP BY city WITH ROLLUP;

-- 字符串聚合
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;
SELECT GROUP_CONCAT(DISTINCT city SEPARATOR ', ') FROM users;
-- 注意：GROUP_CONCAT 默认最大长度 1024 字节，超出会被截断
-- SET SESSION group_concat_max_len = 1048576;  -- 可调大

-- JSON 聚合（5.7.22+）
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(username, age) FROM users;

-- 统计函数
SELECT STD(amount) FROM orders;                        -- 标准差
SELECT STDDEV(amount) FROM orders;                     -- 同 STD
SELECT VARIANCE(amount) FROM orders;                   -- 方差

-- BIT 聚合
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;
SELECT BIT_XOR(flags) FROM settings;

-- 注意：ONLY_FULL_GROUP_BY（5.7.5+ 默认启用）
-- 要求 SELECT 的非聚合列必须出现在 GROUP BY 中，否则报错
-- 5.7.5 之前默认关闭，允许非确定性查询
