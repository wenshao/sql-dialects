-- Azure Synapse: 窗口函数
--
-- 参考资料:
--   [1] Synapse SQL Features
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features
--   [2] Synapse T-SQL Differences
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

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

-- 偏移函数
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age,
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    LAST_VALUE(username)  OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM users;

-- NTH_VALUE（Synapse 可能不支持，取决于版本）
-- 用 ROW_NUMBER + 子查询替代

-- NTILE
SELECT username, age,
    NTILE(4) OVER (ORDER BY age) AS quartile
FROM users;

-- PERCENT_RANK / CUME_DIST
SELECT username, age,
    PERCENT_RANK() OVER (ORDER BY age) AS pct_rank,
    CUME_DIST()    OVER (ORDER BY age) AS cume_dist
FROM users;

-- 帧子句
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

-- ROWS vs RANGE
SELECT order_date, amount,
    SUM(amount) OVER (ORDER BY order_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total_rows,
    SUM(amount) OVER (ORDER BY order_date
        RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total_range
FROM orders;

-- 百分位
SELECT city,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY age) OVER (PARTITION BY city) AS median_age,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY age) OVER (PARTITION BY city) AS median_disc
FROM users;

-- STRING_AGG（窗口不支持，仅聚合函数）
-- 需要用 GROUP BY + STRING_AGG：
SELECT city, STRING_AGG(username, ', ') WITHIN GROUP (ORDER BY username) AS user_list
FROM users
GROUP BY city;

-- 窗口函数 + TOP（替代 QUALIFY）
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t
WHERE t.rn = 1;

-- 窗口函数 + CTE
WITH ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn,
        SUM(age) OVER (PARTITION BY city) AS city_total_age
    FROM users
)
SELECT username, city, age, city_total_age
FROM ranked
WHERE rn <= 3;

-- 注意：Synapse 支持大部分 T-SQL 窗口函数
-- 注意：不支持 QUALIFY 子句（需要子查询或 CTE 过滤）
-- 注意：不支持命名窗口（WINDOW ... AS）
-- 注意：某些高级函数（NTH_VALUE 等）可能不完全支持
-- 注意：窗口函数在 MPP 架构下可能导致数据移动
-- 注意：Serverless 池也支持窗口函数
