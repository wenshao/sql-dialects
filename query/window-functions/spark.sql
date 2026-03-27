-- Spark SQL: Window Functions (Spark 1.4+)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- ROW_NUMBER / RANK / DENSE_RANK
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;

-- Partition
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;

-- Aggregate window functions
SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER () AS avg_age,
    COUNT(*)   OVER () AS total_count,
    MIN(age)   OVER (PARTITION BY city) AS city_min_age,
    MAX(age)   OVER (PARTITION BY city) AS city_max_age
FROM users;

-- Offset functions
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age,
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    LAST_VALUE(username)  OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM users;

-- NTH_VALUE (Spark 3.1+)
SELECT username, age,
    NTH_VALUE(username, 2) OVER (ORDER BY age) AS second_youngest
FROM users;

-- NTILE
SELECT username, age,
    NTILE(4) OVER (ORDER BY age) AS quartile
FROM users;

-- PERCENT_RANK / CUME_DIST
SELECT username, age,
    PERCENT_RANK() OVER (ORDER BY age) AS pct_rank,
    CUME_DIST()    OVER (ORDER BY age) AS cume_dist
FROM users;

-- Named window (Spark 3.0+)
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(age)     OVER w AS prev_age
FROM users
WINDOW w AS (ORDER BY age);

-- Frame clauses
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

-- RANGE frame
SELECT username, age,
    COUNT(*) OVER (ORDER BY age RANGE BETWEEN 5 PRECEDING AND 5 FOLLOWING) AS nearby_count
FROM users;

-- Unbounded frames
SELECT username, age,
    SUM(age) OVER (ORDER BY age ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total,
    SUM(age) OVER (ORDER BY age ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS remaining_total
FROM users;

-- Top-N per group (common pattern)
SELECT * FROM (
    SELECT username, city, age,
        ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t
WHERE rn <= 3;

-- Running aggregates
SELECT order_date, amount,
    SUM(amount) OVER (ORDER BY order_date) AS cumulative_sum,
    AVG(amount) OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS weekly_avg
FROM daily_sales;

-- Window function with DISTRIBUTE BY and SORT BY (Hive-compatible)
-- These control physical distribution, not logical partitioning
-- SELECT username, age, ROW_NUMBER() OVER (ORDER BY age)
-- FROM users
-- DISTRIBUTE BY city SORT BY age;

-- CLUSTER BY (combination of DISTRIBUTE BY and SORT BY on same columns)
-- SELECT * FROM users CLUSTER BY city;

-- Note: Spark supports all standard SQL window functions
-- Note: No QUALIFY clause (must use subquery pattern for filtering)
-- Note: No FILTER clause on window functions
-- Note: GROUPS frame mode supported from Spark 3.0+
-- Note: RANGE frame with INTERVAL not directly supported (use numeric range)
-- Note: Named windows supported from Spark 3.0+
