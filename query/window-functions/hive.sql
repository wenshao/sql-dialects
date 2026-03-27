-- Hive: 窗口函数（0.11+）
--
-- 参考资料:
--   [1] Apache Hive - Windowing Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+WindowingAndAnalytics
--   [2] Apache Hive Language Manual - SELECT
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select

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

-- NTH_VALUE（2.1+）
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

-- 帧子句（ROWS）
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

-- RANGE 帧（2.1+）
SELECT username, age,
    COUNT(*) OVER (ORDER BY age RANGE BETWEEN 5 PRECEDING AND 5 FOLLOWING) AS age_range_count
FROM users;

-- DISTRIBUTE BY + SORT BY（Hive 特有数据分发语义）
-- PARTITION BY 在窗口函数中等价于 DISTRIBUTE BY + SORT BY

-- 窗口函数去重
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY created_at DESC) AS rn
    FROM users
) t WHERE t.rn = 1;

-- 注意：Hive 0.11 引入窗口函数，但功能逐步完善
-- 注意：Hive 不支持命名窗口（WINDOW 子句）
-- 注意：Hive 不支持 GROUPS 帧模式
-- 注意：Hive 不支持 FILTER 子句
-- 注意：Hive 不支持 QUALIFY 子句
-- 注意：早期版本 OVER() 中必须有 PARTITION BY 或 ORDER BY
