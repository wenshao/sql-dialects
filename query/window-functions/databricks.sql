-- Databricks SQL: 窗口函数
--
-- 参考资料:
--   [1] Databricks SQL Language Reference
--       https://docs.databricks.com/en/sql/language-manual/index.html
--   [2] Databricks SQL - Built-in Functions
--       https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html
--   [3] Delta Lake Documentation
--       https://docs.delta.io/latest/index.html

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

-- RANGE 帧
SELECT order_date, amount,
    SUM(amount) OVER (ORDER BY order_date
        RANGE BETWEEN INTERVAL 7 DAYS PRECEDING AND CURRENT ROW) AS weekly_sum
FROM orders;

-- QUALIFY（Databricks 2023+，直接过滤窗口函数结果）
SELECT username, city, age
FROM users
QUALIFY ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) = 1;

-- QUALIFY + 聚合窗口
SELECT username, city, age
FROM users
QUALIFY SUM(age) OVER (PARTITION BY city) > 100;

-- QUALIFY + WHERE + GROUP BY + HAVING 组合
SELECT city, COUNT(*) AS cnt
FROM users
WHERE status = 1
GROUP BY city
HAVING cnt > 5
QUALIFY ROW_NUMBER() OVER (ORDER BY cnt DESC) <= 3;

-- 百分位（聚合函数，不是窗口函数）
SELECT city,
    PERCENTILE_APPROX(age, 0.5) AS approx_median,
    PERCENTILE(age, 0.5) AS exact_median
FROM users
GROUP BY city;

-- 数组聚合窗口
SELECT username, city,
    COLLECT_LIST(username) OVER (PARTITION BY city) AS city_users,
    COLLECT_SET(status) OVER (PARTITION BY city) AS city_statuses
FROM users;

-- 窗口函数 + 数组展开
SELECT username, city, age, rn
FROM (
    SELECT username, city, age,
        ROW_NUMBER() OVER (PARTITION BY city ORDER BY age) AS rn
    FROM users
)
WHERE rn <= 3;

-- 注意：Databricks 支持完善的 SQL 标准窗口函数
-- 注意：QUALIFY 子句可以直接过滤窗口函数结果
-- 注意：命名窗口（WINDOW ... AS）已支持
-- 注意：COLLECT_LIST / COLLECT_SET 可以在窗口中收集数组
-- 注意：Photon 引擎对窗口函数有显著性能优化
-- 注意：支持 ROWS 和 RANGE 帧模式
