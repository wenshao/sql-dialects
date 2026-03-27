-- Snowflake: 窗口函数
--
-- 参考资料:
--   [1] Snowflake SQL Reference - Window Functions
--       https://docs.snowflake.com/en/sql-reference/functions-analytic
--   [2] Snowflake SQL Reference - Functions Reference
--       https://docs.snowflake.com/en/sql-reference/functions-reference

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

-- NTH_VALUE
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

-- 命名窗口
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(age)     OVER w AS prev_age
FROM users
WINDOW w AS (ORDER BY age);

-- 帧子句
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

-- QUALIFY（Snowflake 特有，直接过滤窗口函数结果，无需子查询）
SELECT username, city, age
FROM users
QUALIFY ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) = 1;

-- QUALIFY + 聚合窗口
SELECT username, city, age
FROM users
QUALIFY SUM(age) OVER (PARTITION BY city) > 100;

-- QUALIFY + WHERE + HAVING 组合
SELECT city, COUNT(*) AS cnt
FROM users
WHERE status = 1
GROUP BY city
HAVING cnt > 5
QUALIFY ROW_NUMBER() OVER (ORDER BY cnt DESC) <= 3;

-- CONDITIONAL_TRUE_EVENT（条件变化计数）
SELECT username, city,
    CONDITIONAL_TRUE_EVENT(city != LAG(city) OVER (ORDER BY id)) OVER (ORDER BY id) AS city_group
FROM users;

-- 注意：Snowflake 窗口函数支持完善
-- 注意：QUALIFY 是 Snowflake 的独特扩展，其他数据库（Trino 等）已开始支持
-- 注意：Snowflake 不支持 GROUPS 帧模式
-- 注意：Snowflake 不支持 FILTER 子句
