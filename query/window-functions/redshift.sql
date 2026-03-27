-- Redshift: 窗口函数
--
-- 参考资料:
--   [1] Redshift SQL Reference
--       https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html
--   [2] Redshift SQL Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html
--   [3] Redshift Data Types
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html

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

-- 命名窗口（Redshift 支持）
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
        RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW) AS weekly_sum
FROM orders;

-- RATIO_TO_REPORT（Redshift 特有，计算占比）
SELECT username, age,
    RATIO_TO_REPORT(age) OVER () AS age_ratio,
    RATIO_TO_REPORT(age) OVER (PARTITION BY city) AS city_age_ratio
FROM users;

-- PERCENTILE_CONT / PERCENTILE_DISC（窗口聚合）
SELECT city,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY age) OVER (PARTITION BY city) AS median_age,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY age) OVER (PARTITION BY city) AS median_disc
FROM users;

-- MEDIAN（Redshift 特有快捷方式）
SELECT city, MEDIAN(age) OVER (PARTITION BY city) AS median_age
FROM users;

-- LISTAGG（窗口聚合）
SELECT city,
    LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) OVER (PARTITION BY city) AS user_list
FROM users;

-- 注意：Redshift 支持大部分 SQL 标准窗口函数
-- 注意：RATIO_TO_REPORT 是 Redshift 特有的占比计算函数
-- 注意：MEDIAN 是 PERCENTILE_CONT(0.5) 的快捷方式
-- 注意：不支持 QUALIFY 子句（需要用子查询过滤窗口结果）
-- 注意：GROUPS 帧模式在较新版本中可能已支持
-- 注意：不支持 FILTER 子句
