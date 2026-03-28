-- Spark SQL: CTE (Common Table Expressions)
--
-- 参考资料:
--   [1] Spark SQL - CTE
--       https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-cte.html

-- ============================================================
-- 1. 基本 CTE
-- ============================================================
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;

-- 多 CTE
WITH
active_users AS (
    SELECT * FROM users WHERE status = 1
),
user_orders AS (
    SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT u.username, o.cnt, o.total
FROM active_users u
JOIN user_orders o ON u.id = o.user_id;

-- CTE 引用另一个 CTE
WITH
base AS (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
),
ranked AS (
    SELECT city, cnt, ROW_NUMBER() OVER (ORDER BY cnt DESC) AS rn
    FROM base
)
SELECT * FROM ranked WHERE rn <= 5;

-- ============================================================
-- 2. CTE 与 DML 结合
-- ============================================================

-- CTE + INSERT（Spark 3.0+）
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email
)
INSERT INTO users (username, email)
SELECT username, email FROM new_users;

-- CTE + CTAS
CREATE TABLE top_cities AS
WITH city_stats AS (
    SELECT city, COUNT(*) AS user_count, AVG(age) AS avg_age
    FROM users GROUP BY city
)
SELECT * FROM city_stats WHERE user_count > 100;

-- ============================================================
-- 3. CTE 与复杂查询
-- ============================================================

-- CTE + LATERAL VIEW
WITH user_data AS (
    SELECT id, username, tags FROM users WHERE tags IS NOT NULL
)
SELECT username, tag
FROM user_data
LATERAL VIEW EXPLODE(tags) t AS tag;

-- CTE + 窗口函数
WITH daily_sales AS (
    SELECT CAST(order_time AS DATE) AS order_date,
           SUM(amount) AS daily_total
    FROM orders
    GROUP BY CAST(order_time AS DATE)
)
SELECT order_date, daily_total,
    SUM(daily_total) OVER (ORDER BY order_date) AS running_total
FROM daily_sales;

-- CTE + UNION
WITH combined AS (
    SELECT username, email, 'active' AS source FROM active_users
    UNION ALL
    SELECT username, email, 'inactive' AS source FROM inactive_users
)
SELECT * FROM combined;

-- ============================================================
-- 4. 递归 CTE（Spark 3.4+, 实验性）
-- ============================================================

-- Spark 3.4+ 开始实验性支持递归 CTE:
-- SET spark.sql.legacy.ctePrecedencePolicy = CORRECTED;
-- WITH RECURSIVE emp_hierarchy AS (
--     SELECT id, name, parent_id, 1 AS level
--     FROM employees WHERE parent_id IS NULL
--     UNION ALL
--     SELECT e.id, e.name, e.parent_id, h.level + 1
--     FROM employees e
--     JOIN emp_hierarchy h ON e.parent_id = h.id
-- )
-- SELECT * FROM emp_hierarchy;

-- 设计分析: 递归 CTE 的缺失（Spark 3.4 之前）
--   这是 Spark SQL 最大的功能缺失之一:
--   - 层次查询（组织架构、BOM 展开）无法在纯 SQL 中实现
--   - 必须使用 DataFrame API 的迭代循环或 GraphFrames 替代
--
-- 对比:
--   PostgreSQL: WITH RECURSIVE 从 8.4 (2009) 开始支持
--   MySQL:      WITH RECURSIVE 从 8.0 (2018) 开始支持
--   Oracle:     CONNECT BY 从 7.0 开始 + WITH RECURSIVE 从 11g R2 开始
--   SQL Server: WITH RECURSIVE 从 2005 开始（支持 MAXRECURSION 限制深度）
--   Hive:       不支持递归 CTE
--   Flink SQL:  不支持递归 CTE
--   BigQuery:   WITH RECURSIVE 支持（有迭代次数限制）
--   Trino:      不支持递归 CTE（计划中）

-- ============================================================
-- 5. CTE 的优化行为
-- ============================================================

-- Spark 的 CTE 不保证物化（与临时表不同）:
--   - Catalyst 优化器可能将 CTE 内联（inline）到引用位置
--   - 也可能将多次引用的 CTE 物化为一次计算
--   - 用户无法通过 MATERIALIZED/NOT MATERIALIZED 控制
--
-- 对比:
--   PostgreSQL 12+: WITH ... AS MATERIALIZED / NOT MATERIALIZED（用户可控制）
--   Oracle:         /*+ MATERIALIZE */ hint
--   Spark:          无控制手段——完全由 Catalyst 决定
--
-- 如果需要强制物化，使用 CACHE TABLE:
-- CREATE TEMP VIEW my_cte AS SELECT ...;
-- CACHE TABLE my_cte;

-- ============================================================
-- 6. 版本演进
-- ============================================================
-- Spark 2.1: 基本 CTE（WITH ... AS）
-- Spark 3.0: CTE + INSERT INTO
-- Spark 3.4: 递归 CTE（实验性）, CTE 优化改进
-- Spark 4.0: 递归 CTE 稳定性改进
--
-- 限制:
--   递归 CTE 仅 Spark 3.4+（且为实验性功能）
--   无 MATERIALIZED / NOT MATERIALIZED 提示
--   无 DML CTE（WITH d AS (DELETE ... RETURNING *) SELECT * FROM d）
--   CTE 不能直接被缓存（需要先创建 TEMP VIEW 再 CACHE）
--   Spark 可能内联 CTE（如果只引用一次），导致计划与预期不同
