-- H2: 聚合函数

-- 基本聚合
SELECT COUNT(*), COUNT(DISTINCT city), SUM(age),
       AVG(age), MIN(age), MAX(age)
FROM users;

-- GROUP BY
SELECT city, COUNT(*), AVG(age)
FROM users GROUP BY city;

-- GROUP BY + HAVING
SELECT city, COUNT(*) AS cnt
FROM users GROUP BY city HAVING cnt > 10;

-- GROUP BY 位置引用
SELECT city, COUNT(*) FROM users GROUP BY 1;

-- WITH ROLLUP
SELECT city, COUNT(*) FROM users GROUP BY ROLLUP (city);

-- GROUPING SETS
SELECT city, age, COUNT(*)
FROM users GROUP BY GROUPING SETS ((city), (age), ());

-- CUBE
SELECT city, age, COUNT(*)
FROM users GROUP BY CUBE (city, age);

-- 字符串聚合
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;

-- JSON 聚合
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(username: age) FROM users;

-- 数组聚合
SELECT ARRAY_AGG(username ORDER BY id) FROM users;

-- 统计函数
SELECT STDDEV_POP(age), STDDEV_SAMP(age),
       VAR_POP(age), VAR_SAMP(age)
FROM users;

-- PERCENTILE
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY age) FROM users;
SELECT PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY age) FROM users;

-- BOOL 聚合
SELECT BOOL_AND(active), BOOL_OR(active), EVERY(active) FROM users;

-- BIT 聚合
SELECT BIT_AND(flags), BIT_OR(flags), BIT_XOR(flags) FROM settings;

-- 注意：H2 支持完整的 SQL 标准聚合
-- 注意：支持 GROUPING SETS / ROLLUP / CUBE
-- 注意：支持 GROUP_CONCAT 和 LISTAGG
-- 注意：支持 PERCENTILE_CONT / PERCENTILE_DISC
