-- Oracle: 窗口函数（8i 开始支持，业界最早）
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Analytic Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Analytic-Functions.html
--   [2] Oracle SQL Language Reference
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/

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

-- NTH_VALUE（11g R2+）
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

-- RATIO_TO_REPORT（Oracle 特有，计算占比）
SELECT username, age,
    RATIO_TO_REPORT(age) OVER () AS age_ratio
FROM users;

-- LISTAGG 作为窗口函数（11g R2+）
SELECT username, city,
    LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) OVER (PARTITION BY city) AS city_users
FROM users;

-- 帧子句
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY created_at RANGE BETWEEN INTERVAL '7' DAY PRECEDING AND CURRENT ROW) AS weekly_avg
FROM users;

-- MODEL 子句（Oracle 特有，电子表格式计算，10g+）
-- 非常强大但语法复杂，很少使用
