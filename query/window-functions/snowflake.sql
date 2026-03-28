-- Snowflake: 窗口函数
--
-- 参考资料:
--   [1] Snowflake SQL Reference - Window Functions
--       https://docs.snowflake.com/en/sql-reference/functions-analytic

-- ============================================================
-- 1. 排名函数
-- ============================================================

SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;

-- 分区排名
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;

-- ============================================================
-- 2. QUALIFY: Snowflake 的核心创新
-- ============================================================

-- 直接过滤窗口函数结果（无需子查询）:
SELECT username, city, age
FROM users
QUALIFY ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) = 1;

-- QUALIFY 在 SQL 执行顺序中的位置:
-- FROM → WHERE → GROUP BY → HAVING → SELECT → QUALIFY → ORDER BY → LIMIT
-- QUALIFY 在 HAVING 之后、ORDER BY 之前执行

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

-- 对比:
--   PostgreSQL: 不支持 QUALIFY（必须用子查询包装）
--   MySQL:      不支持 QUALIFY
--   BigQuery:   支持 QUALIFY（与 Snowflake 一致）
--   Databricks: 支持 QUALIFY
--   Teradata:   QUALIFY 的原创者
--
-- 对引擎开发者的启示:
--   QUALIFY 实现简单（在 HAVING 之后增加一个过滤步骤），
--   但极大提升了窗口函数的易用性。
--   没有 QUALIFY，窗口函数过滤必须嵌套子查询（增加 SQL 复杂度和嵌套层级）。
--   这是 ROI 最高的语法扩展之一。

-- ============================================================
-- 3. 聚合窗口函数
-- ============================================================

SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER () AS avg_age,
    COUNT(*)   OVER () AS total_count,
    MIN(age)   OVER (PARTITION BY city) AS city_min,
    MAX(age)   OVER (PARTITION BY city) AS city_max
FROM users;

-- ============================================================
-- 4. 偏移函数
-- ============================================================

SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age,
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    LAST_VALUE(username) OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest,
    NTH_VALUE(username, 2) OVER (ORDER BY age) AS second_youngest
FROM users;

-- NTILE（分桶）
SELECT username, age, NTILE(4) OVER (ORDER BY age) AS quartile FROM users;

-- PERCENT_RANK / CUME_DIST
SELECT username, age,
    PERCENT_RANK() OVER (ORDER BY age) AS pct_rank,
    CUME_DIST()    OVER (ORDER BY age) AS cume_dist
FROM users;

-- ============================================================
-- 5. 命名窗口 (WINDOW 子句)
-- ============================================================

SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(age)     OVER w AS prev_age
FROM users
WINDOW w AS (ORDER BY age);

-- 命名窗口减少了窗口定义的重复，提高了可读性
-- 对比: PostgreSQL/BigQuery 也支持 WINDOW 子句

-- ============================================================
-- 6. 帧子句 (Frame Clause)
-- ============================================================

SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

-- Snowflake 支持 ROWS 和 RANGE 帧模式，不支持 GROUPS 帧模式
-- 对比: PostgreSQL 13+ 支持 GROUPS 模式

-- ============================================================
-- 7. Snowflake 特有窗口函数
-- ============================================================

-- CONDITIONAL_TRUE_EVENT: 条件变化计数
SELECT username, city,
    CONDITIONAL_TRUE_EVENT(city != LAG(city) OVER (ORDER BY id))
        OVER (ORDER BY id) AS city_group
FROM users;
-- 每当条件为 TRUE 时计数器 +1（用于分组连续相同值的行）

-- ============================================================
-- 8. 限制
-- ============================================================
-- 不支持 GROUPS 帧模式（PostgreSQL 13+ 支持）
-- 不支持 FILTER 子句: SUM(age) FILTER (WHERE ...) OVER (...)
-- 不支持 EXCLUDE 帧选项: ROWS BETWEEN ... EXCLUDE CURRENT ROW

-- ============================================================
-- 横向对比: 窗口函数能力矩阵
-- ============================================================
-- 能力             | Snowflake  | BigQuery  | PostgreSQL | MySQL 8.0
-- QUALIFY          | 支持(核心) | 支持      | 不支持     | 不支持
-- WINDOW 命名子句  | 支持       | 支持      | 支持       | 支持
-- ROWS/RANGE 帧   | 支持       | 支持      | 支持       | 支持
-- GROUPS 帧        | 不支持     | 不支持    | 13+        | 不支持
-- FILTER 子句      | 不支持     | 不支持    | 支持       | 不支持
-- NTH_VALUE        | 支持       | 支持      | 支持       | 支持
-- CONDITIONAL_TRUE | 独有       | 不支持    | 不支持     | 不支持
