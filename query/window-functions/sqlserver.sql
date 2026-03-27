-- SQL Server: 窗口函数（2005+）
--
-- 参考资料:
--   [1] SQL Server T-SQL - Window Functions
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/select-over-clause-transact-sql
--   [2] SQL Server T-SQL - Ranking Functions
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/ranking-functions-transact-sql
--   [3] SQL Server T-SQL - Analytic Functions
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/analytic-functions-transact-sql

-- ROW_NUMBER / RANK / DENSE_RANK
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;

-- 分区
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;

-- 聚合窗口函数
SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER () AS avg_age,
    COUNT(*)   OVER () AS total_count,
    MIN(age)   OVER (PARTITION BY city) AS city_min_age,
    MAX(age)   OVER (PARTITION BY city) AS city_max_age
FROM users;

-- 2012+: 偏移函数
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age,
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    LAST_VALUE(username)  OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM users;

-- NTILE
SELECT username, age,
    NTILE(4) OVER (ORDER BY age) AS quartile
FROM users;

-- PERCENT_RANK / CUME_DIST（2012+）
SELECT username, age,
    PERCENT_RANK() OVER (ORDER BY age) AS pct_rank,
    CUME_DIST()    OVER (ORDER BY age) AS cume_dist
FROM users;

-- 2012+: 帧子句（ROWS / RANGE）
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

-- 注意：SQL Server 不支持命名窗口（WINDOW 子句）
-- 注意：SQL Server 不支持 NTH_VALUE
-- 注意：2005-2008 不支持 ROWS/RANGE 帧子句（仅支持排名和聚合窗口函数）

-- 2022+: WINDOW 子句（终于支持命名窗口）
-- SELECT ... OVER w FROM users WINDOW w AS (ORDER BY age);
