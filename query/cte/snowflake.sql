-- Snowflake: CTE（公共表表达式）
--
-- 参考资料:
--   [1] Snowflake SQL Reference - WITH (CTE)
--       https://docs.snowflake.com/en/sql-reference/constructs/with

-- ============================================================
-- 1. 基本语法
-- ============================================================

WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;

-- 多个 CTE（后面的可以引用前面的）
WITH
active_users AS (
    SELECT * FROM users WHERE status = 1
),
user_orders AS (
    SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT u.username, o.cnt, o.total
FROM active_users u JOIN user_orders o ON u.id = o.user_id;

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 CTE 物化策略: Snowflake 的自动决策
-- Snowflake 不支持 MATERIALIZED / NOT MATERIALIZED 提示:
--   PostgreSQL 12+: WITH cte AS MATERIALIZED (...) / NOT MATERIALIZED (...)
--   Snowflake:      优化器自行决定是否物化 CTE
--
-- 优化器的决策逻辑:
--   CTE 只被引用一次 → 通常内联展开（等价于子查询）
--   CTE 被多次引用   → 可能物化到临时存储以避免重复计算
--
-- 对比:
--   PostgreSQL 12+: 用户可以控制物化策略（MATERIALIZED / NOT MATERIALIZED）
--   MySQL 8.0:      CTE 被引用多次时自动物化
--   Oracle:         /*+ MATERIALIZE */ 提示
--   BigQuery:       类似 Snowflake（自动决策）
--
-- 对引擎开发者的启示:
--   CTE 物化是经典的优化决策: 物化避免重复计算，但增加临时存储和写入开销。
--   PostgreSQL 允许用户控制是更灵活的设计（专家用户可以覆盖优化器决策）。

-- 2.2 CTE + QUALIFY: Snowflake 的优雅组合
-- 传统方案（需要嵌套子查询）:
WITH ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
)
SELECT * FROM ranked WHERE rn = 1;

-- Snowflake QUALIFY 方案（无需嵌套）:
SELECT * FROM users
QUALIFY ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) = 1;
-- QUALIFY 消除了大量 CTE + 子查询的使用场景

-- ============================================================
-- 3. 递归 CTE
-- ============================================================

-- 数字序列
WITH RECURSIVE nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;

-- 层级结构遍历
WITH RECURSIVE org_tree AS (
    -- 锚点: 顶层节点
    SELECT id, username, manager_id, 0 AS level,
           username AS path
    FROM users WHERE manager_id IS NULL
    UNION ALL
    -- 递归: 子节点
    SELECT u.id, u.username, u.manager_id, t.level + 1,
           t.path || ' > ' || u.username
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;

-- 递归 CTE 的限制:
--   Snowflake 有最大迭代次数限制（防止无限递归）
--   对比 Oracle: CONNECT BY ... LEVEL <= N（专用层级查询语法）
--   对比 PostgreSQL: 无内置限制（需用户确保终止条件）

-- ============================================================
-- 4. CTE + DML
-- ============================================================

-- CTE + INSERT
WITH new_data AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email
)
INSERT INTO users (username, email)
SELECT username, email FROM new_data;

-- CTE + CTAS
CREATE TABLE users_archive AS
WITH inactive AS (
    SELECT * FROM users WHERE last_login < '2023-01-01'
)
SELECT * FROM inactive;

-- ============================================================
-- 5. CTE + FLATTEN（半结构化数据展开）
-- ============================================================

WITH expanded AS (
    SELECT username, f.value::STRING AS tag
    FROM users, LATERAL FLATTEN(input => tags) f
)
SELECT tag, COUNT(*) AS cnt FROM expanded GROUP BY tag;

-- ============================================================
-- 6. RESULT_SCAN: CTE 的替代方案
-- ============================================================

-- 引用上一次查询结果（无需 CTE 或临时表）:
SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
-- 适合交互式分析: 执行查询 → 检查结果 → 基于结果继续分析

-- ============================================================
-- 横向对比: CTE 能力矩阵
-- ============================================================
-- 能力              | Snowflake  | BigQuery  | PostgreSQL | MySQL 8.0
-- 基本 CTE          | 支持       | 支持      | 支持       | 支持
-- 递归 CTE          | 支持       | 支持      | 支持       | 支持
-- CTE + DML         | 支持       | 支持      | 支持       | 部分
-- MATERIALIZED 提示 | 不支持     | 不支持    | 支持(12+)  | 自动
-- CTE + QUALIFY      | 支持       | 支持      | 不支持     | 不支持
-- RESULT_SCAN       | 支持       | 不支持    | 不支持     | 不支持
