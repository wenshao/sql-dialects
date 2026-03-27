-- Materialize: 窗口函数
--
-- 参考资料:
--   [1] Materialize SQL Reference
--       https://materialize.com/docs/sql/
--   [2] Materialize SQL Functions
--       https://materialize.com/docs/sql/functions/

-- Materialize 支持标准 SQL 窗口函数（兼容 PostgreSQL）

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

-- NTH_VALUE / NTILE
SELECT username, age,
    NTH_VALUE(username, 2) OVER (ORDER BY age) AS second_youngest,
    NTILE(4) OVER (ORDER BY age) AS quartile
FROM users;

-- PERCENT_RANK / CUME_DIST
SELECT username, age,
    PERCENT_RANK() OVER (ORDER BY age) AS pct_rank,
    CUME_DIST()    OVER (ORDER BY age) AS cume_dist
FROM users;

-- 命名窗口
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    LAG(age) OVER w AS prev_age
FROM users
WINDOW w AS (ORDER BY age);

-- 帧子句
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

-- ============================================================
-- 物化视图中的窗口函数
-- ============================================================

-- 窗口函数在物化视图中会增量维护
CREATE MATERIALIZED VIEW ranked_users AS
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age DESC) AS rank
FROM users;

-- Top-N 查询
CREATE MATERIALIZED VIEW top_10_users AS
SELECT * FROM (
    SELECT username, age,
        ROW_NUMBER() OVER (ORDER BY age DESC) AS rn
    FROM users
) WHERE rn <= 10;

-- 注意：Materialize 支持完整的 SQL 窗口函数
-- 注意：窗口函数在物化视图中会增量维护
-- 注意：支持命名窗口和帧子句
-- 注意：兼容 PostgreSQL 的窗口函数语法
