-- MariaDB: 窗口函数 (10.2+)
-- 比 MySQL 8.0 更早支持窗口函数
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - Window Functions
--       https://mariadb.com/kb/en/window-functions/

-- ============================================================
-- 1. 基本语法
-- ============================================================
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;

SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;

-- 聚合窗口函数
SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER (PARTITION BY city) AS city_avg_age,
    COUNT(*)   OVER (PARTITION BY city) AS city_count
FROM users;

-- 偏移函数
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age,
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest
FROM users;

-- NTILE
SELECT username, age, NTILE(4) OVER (ORDER BY age) AS quartile FROM users;

-- ============================================================
-- 2. 命名窗口
-- ============================================================
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    SUM(age)     OVER w AS running_sum,
    LAG(age)     OVER w AS prev_age
FROM users
WINDOW w AS (ORDER BY age);

-- ============================================================
-- 3. 帧子句
-- ============================================================
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

-- RANGE 帧
SELECT username, age,
    COUNT(*) OVER (ORDER BY age RANGE BETWEEN 5 PRECEDING AND 5 FOLLOWING) AS nearby_count
FROM users;

-- ============================================================
-- 4. MariaDB 窗口函数 vs MySQL 窗口函数
-- ============================================================
-- 时间线: MariaDB 10.2 (2017) vs MySQL 8.0 (2018)
-- MariaDB 更早引入, 但两者的实现独立:
--   相同点: 都支持 ROW_NUMBER/RANK/DENSE_RANK/LAG/LEAD/NTILE 等
--   相同点: 都支持 ROWS/RANGE 帧, 命名窗口
--   不同点: 内部实现和优化策略不同 (各自独立开发)
--   不同点: 都不支持 GROUPS 帧, QUALIFY, IGNORE NULLS
--
-- 对引擎开发者的启示:
--   窗口函数是 SQL 标准化程度很高的特性
--   但内部实现差异导致: 相同查询的性能特征可能不同
--   排序策略和帧计算的增量优化是性能关键
