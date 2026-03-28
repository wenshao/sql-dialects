-- Snowflake: 视图 (Views)
--
-- 参考资料:
--   [1] Snowflake SQL Reference - CREATE VIEW
--       https://docs.snowflake.com/en/sql-reference/sql/create-view
--   [2] Snowflake SQL Reference - CREATE MATERIALIZED VIEW
--       https://docs.snowflake.com/en/sql-reference/sql/create-materialized-view
--   [3] Snowflake SQL Reference - Secure Views
--       https://docs.snowflake.com/en/user-guide/views-secure

-- ============================================================
-- 1. 基本视图
-- ============================================================

CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

CREATE OR REPLACE VIEW user_summary AS
SELECT u.id, u.username, COUNT(o.id) AS order_count, SUM(o.amount) AS total_spent
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.username;

CREATE VIEW IF NOT EXISTS order_overview
    COMMENT = 'Order aggregation by user'
AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 Secure View: Snowflake 的安全视图设计
-- Secure View 隐藏视图定义（DDL 文本）和查询优化细节，
-- 防止通过推断视图逻辑绕过数据访问控制。
CREATE SECURE VIEW customer_data AS
SELECT id, username, email FROM users WHERE region = 'US';
-- 效果:
--   (a) SHOW VIEWS / GET_DDL 不返回视图定义（除非调用者是 OWNER）
--   (b) 查询计划 (EXPLAIN) 不暴露视图内部的表和过滤条件
--   (c) 优化器限制: 某些优化（如谓词下推到视图内部）被禁用，防止信息泄露
--
-- 设计 trade-off:
--   安全性 > 性能: Secure View 可能比普通视图慢（优化器受限）
--   典型场景: Data Sharing 中共享给外部账户的视图必须是 Secure View
--
-- 对比:
--   PostgreSQL:   无 Secure View（通过 RLS + 权限控制）
--   Oracle:       无 Secure View（通过 VPD/FGAC 实现细粒度访问控制）
--   SQL Server:   WITH SCHEMABINDING 防止底层表变更，但不隐藏定义
--   BigQuery:     Authorized Views（授权视图，可跨数据集访问）
--   Redshift:     无 Secure View
--
-- 对引擎开发者的启示:
--   Secure View 的核心挑战是防止"侧信道攻击": 用户通过查询性能差异、
--   报错信息、优化器行为推断出视图内部的数据和过滤条件。
--   Snowflake 的方案是牺牲优化能力换取安全性。
--   如果引擎支持多租户数据共享，类似机制是必要的。

-- 2.2 视图与物化视图的架构差异
-- 普通视图: 纯逻辑定义，查询时展开（与其他数据库一致）
-- 物化视图: 物理存储 + 自动增量刷新（Snowflake 特有的自动维护）
--
-- 物化视图的限制:
--   - 只能基于单表（不支持 JOIN）
--   - 不支持窗口函数、UDF
--   - 不支持 HAVING / LIMIT / ORDER BY
--   - 需要 Enterprise 版
--
-- 对比:
--   Oracle:     物化视图功能最强（多表 JOIN、FAST REFRESH、查询重写）
--   PostgreSQL: 物化视图不自动刷新（需要 REFRESH MATERIALIZED VIEW）
--   BigQuery:   物化视图自动维护 + 自动查询重写（与 Snowflake 类似）
--   Redshift:   物化视图支持 AUTO REFRESH

-- ============================================================
-- 3. 物化视图 (Enterprise+)
-- ============================================================

CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT order_date,
       SUM(amount)  AS total_amount,
       COUNT(*)     AS order_count
FROM orders
GROUP BY order_date;

CREATE SECURE MATERIALIZED VIEW mv_secure_summary AS
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id;

-- 自动维护: 源表数据变更后 Snowflake 自动增量更新物化视图
-- 自动查询重写: 优化器自动判断是否使用物化视图回答查询
-- 不需要用户显式 REFRESH

-- 控制物化视图
ALTER MATERIALIZED VIEW mv_daily_sales SUSPEND;
ALTER MATERIALIZED VIEW mv_daily_sales RESUME;

-- 查看物化视图状态:
SHOW MATERIALIZED VIEWS LIKE 'MV_DAILY%';

-- 对引擎开发者的启示:
--   物化视图自动维护需要增量更新能力: 检测源表变更增量并应用到物化视图。
--   Snowflake 利用内部变更追踪（类似 Stream）实现增量刷新。
--   自动查询重写需要优化器能识别查询与物化视图的等价关系（视图匹配问题）。
--   Oracle 在这方面技术最成熟，Snowflake 和 BigQuery 的实现相对简单。

-- ============================================================
-- 4. Secure View 详细行为
-- ============================================================

-- 转换普通视图为 Secure View:
ALTER VIEW active_users SET SECURE;
ALTER VIEW active_users UNSET SECURE;

-- Secure View 的优化器限制示例:
-- 普通视图: SELECT * FROM active_users WHERE username = 'alice'
--   → 优化器将 WHERE 下推到视图内部 → 高效
-- Secure View: 相同查询
--   → 优化器不下推外部谓词 → 先执行视图逻辑再过滤 → 可能较慢

-- Secure View 用于 Data Sharing:
-- 提供方创建 Secure View 控制共享的数据范围
-- 消费方只能查询，不能看到视图定义或底层表结构

-- ============================================================
-- 5. 递归视图
-- ============================================================

CREATE VIEW employee_hierarchy AS
WITH RECURSIVE hierarchy AS (
    SELECT id, name, manager_id, 1 AS level
    FROM employees WHERE manager_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.manager_id, h.level + 1
    FROM employees e JOIN hierarchy h ON e.manager_id = h.id
)
SELECT * FROM hierarchy;

-- ============================================================
-- 6. 视图管理
-- ============================================================

SELECT GET_DDL('VIEW', 'ACTIVE_USERS');   -- 非 Secure View 可查看
SHOW VIEWS IN SCHEMA PUBLIC;
DESCRIBE VIEW active_users;

DROP VIEW IF EXISTS active_users;
DROP MATERIALIZED VIEW IF EXISTS mv_daily_sales;

-- ============================================================
-- 7. Dynamic Tables (2024): 物化视图的演进
-- ============================================================

-- Dynamic Table 是声明式 ETL，支持 JOIN、窗口函数等复杂查询
-- CREATE DYNAMIC TABLE daily_summary
--     TARGET_LAG = '1 hour'    -- 数据新鲜度目标
--     WAREHOUSE = compute_wh
-- AS
-- SELECT order_date, SUM(amount) AS total FROM orders GROUP BY order_date;
--
-- 与物化视图的区别:
--   支持 JOIN、窗口函数 | TARGET_LAG 控制刷新频率
--   可基于其他 Dynamic Table 构建 DAG | 替代 Stream + Task
--
-- 对引擎开发者的启示:
--   Dynamic Table 本质上是"声明式 ETL"——用户声明目标数据形态，
--   引擎自动计算增量更新策略。Databricks Delta Live Tables 是类似概念。

-- ============================================================
-- 横向对比: 视图能力矩阵
-- ============================================================
-- 能力             | Snowflake   | BigQuery     | Redshift  | Databricks | Oracle
-- 普通视图         | 完整        | 完整         | 完整      | 完整       | 完整
-- Secure View      | 原生支持    | Authorized   | 不支持    | 不支持     | VPD替代
-- 物化视图         | 自动维护    | 自动维护     | AUTO REF  | 不支持     | 功能最强
-- 自动查询重写     | 支持        | 支持         | 支持      | 不支持     | 支持
-- 物化视图 JOIN    | 不支持      | 不支持       | 支持      | N/A        | 支持
-- 可更新视图       | 不支持      | 不支持       | 不支持    | 不支持     | 支持
-- 声明式管道       | Dynamic Tbl | N/A          | N/A       | DLT        | N/A
