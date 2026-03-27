-- TDSQL: 聚合函数
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

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

-- GROUP BY + HAVING
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING cnt > 10;

-- WITH ROLLUP
SELECT city, COUNT(*) FROM users GROUP BY city WITH ROLLUP;

-- 字符串聚合
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;
SELECT GROUP_CONCAT(DISTINCT city SEPARATOR ', ') FROM users;

-- JSON 聚合
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(username, age) FROM users;

-- 统计函数
SELECT STD(amount) FROM orders;
SELECT STDDEV(amount) FROM orders;
SELECT VARIANCE(amount) FROM orders;

-- BIT 聚合
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;

-- 注意事项：
-- 聚合函数在分布式环境下需要合并各分片结果
-- COUNT(DISTINCT) 需要全局去重（可能性能较差）
-- GROUP BY 对齐 shardkey 时性能最好
-- GROUP_CONCAT 有默认长度限制（group_concat_max_len）
