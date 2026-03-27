-- TiDB: Window Functions
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- All standard MySQL 8.0 window functions are supported:
-- ROW_NUMBER, RANK, DENSE_RANK, NTILE, LAG, LEAD,
-- FIRST_VALUE, LAST_VALUE, NTH_VALUE, PERCENT_RANK, CUME_DIST

-- ROW_NUMBER / RANK / DENSE_RANK (same as MySQL 8.0)
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;

-- PARTITION BY (same as MySQL 8.0)
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;

-- Aggregate window functions (same as MySQL 8.0)
SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER (PARTITION BY city) AS city_avg
FROM users;

-- LAG / LEAD (same as MySQL 8.0)
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age
FROM users;

-- Named window (same as MySQL 8.0)
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(age)     OVER w AS prev_age
FROM users
WINDOW w AS (ORDER BY age);

-- Frame clause (same as MySQL 8.0)
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

-- TiFlash MPP mode for window functions (5.0+)
-- Window functions can be pushed down to TiFlash for parallel execution
-- Much faster for large analytical queries
SELECT /*+ READ_FROM_STORAGE(TIFLASH[users]) */ username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;

-- Performance considerations:
-- Window functions in TiDB may use more memory for sorting
-- Consider adding ORDER BY indexes for window function columns
-- In MPP mode, window functions are parallelized across TiFlash nodes

-- Limitations:
-- All MySQL 8.0 window functions are supported
-- Window functions cannot be used in UPDATE or DELETE (same as MySQL)
-- Performance may differ from MySQL due to distributed execution
-- For very large windows, memory consumption may be higher than MySQL
