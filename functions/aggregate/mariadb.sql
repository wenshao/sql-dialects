-- MariaDB: Aggregate Functions
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- Basic aggregates (same as MySQL)
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;

-- GROUP BY (same as MySQL)
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city;

-- GROUP BY + HAVING (same as MySQL)
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING cnt > 10;

-- WITH ROLLUP (same as MySQL)
SELECT city, COUNT(*) FROM users GROUP BY city WITH ROLLUP;

-- GROUP_CONCAT (same as MySQL, with MariaDB extensions)
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;
SELECT GROUP_CONCAT(DISTINCT city SEPARATOR ', ') FROM users;

-- GROUP_CONCAT with LIMIT (10.3.3+, MariaDB-specific)
-- Limit the number of values concatenated
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ' LIMIT 5) FROM users;
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ' LIMIT 3 OFFSET 2) FROM users;
-- Not available in MySQL

-- JSON aggregation (10.5+)
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(username, age) FROM users;

-- Statistical functions (same as MySQL)
SELECT STD(amount) FROM orders;
SELECT STDDEV(amount) FROM orders;
SELECT STDDEV_POP(amount) FROM orders;
SELECT STDDEV_SAMP(amount) FROM orders;
SELECT VARIANCE(amount) FROM orders;
SELECT VAR_POP(amount) FROM orders;
SELECT VAR_SAMP(amount) FROM orders;

-- BIT aggregates (same as MySQL)
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;
SELECT BIT_XOR(flags) FROM settings;

-- PERCENTILE_CONT / PERCENTILE_DISC (10.3.3+, MariaDB-specific)
-- Not available as aggregate functions in MySQL
-- Can be used as both aggregate and window functions
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY age) FROM users;   -- median
SELECT PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY age) FROM users;   -- median (discrete)

-- PERCENTILE with GROUP BY
SELECT city,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY age) AS median_age,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY age) AS p95_age
FROM users
GROUP BY city;

-- MEDIAN (10.3.3+, MariaDB-specific)
-- Shorthand for PERCENTILE_CONT(0.5)
SELECT MEDIAN(age) FROM users;
SELECT city, MEDIAN(age) FROM users GROUP BY city;

-- Optimizer differences for aggregation:
-- MariaDB often uses different execution strategies for GROUP BY
-- Hash-based aggregation available in certain cases

-- GROUPING SETS: not directly supported (same limitation as MySQL)
-- Use UNION ALL or WITH ROLLUP instead

-- Differences from MySQL 8.0:
-- GROUP_CONCAT ... LIMIT (MariaDB-specific, 10.3.3+)
-- PERCENTILE_CONT / PERCENTILE_DISC aggregate functions (10.3.3+)
-- MEDIAN aggregate function (10.3.3+)
-- JSON_ARRAYAGG / JSON_OBJECTAGG from 10.5+ (MySQL from 5.7.22+)
-- No GROUPING SETS or CUBE (same limitation as MySQL)
-- Same core aggregate functions (COUNT, SUM, AVG, MIN, MAX, etc.)
