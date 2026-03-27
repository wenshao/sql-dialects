-- Oracle: CTE 公共表表达式（9i R2+）
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - SELECT (Subquery Factoring)
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html

-- ============================================================
-- 1. 基本 CTE（子查询分解，Subquery Factoring）
-- ============================================================

WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;

-- 多个 CTE
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
-- 2. 递归 CTE（11g R2+）
-- ============================================================

-- 注意: Oracle 不需要 RECURSIVE 关键字（与 PostgreSQL/MySQL 不同）
WITH nums (n) AS (
    SELECT 1 FROM DUAL                        -- 锚成员（需要 FROM DUAL）
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10       -- 递归成员
)
SELECT n FROM nums;

-- 递归: 组织树遍历
WITH org_tree (id, username, manager_id, lvl) AS (
    SELECT id, username, manager_id, 0
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.lvl + 1
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;

-- ============================================================
-- 3. CONNECT BY vs 递归 CTE（Oracle 的双层次查询体系）
-- ============================================================

-- CONNECT BY（所有版本，Oracle 独有的层次查询语法）
SELECT id, username, manager_id, LEVEL AS lvl,
    SYS_CONNECT_BY_PATH(username, '/') AS path
FROM users
START WITH manager_id IS NULL
CONNECT BY PRIOR id = manager_id
ORDER SIBLINGS BY username;

-- 设计对比:
--   CONNECT BY 的优势:
--     - 语法简洁（一条语句，无需 CTE 包装）
--     - 内置伪列: LEVEL, CONNECT_BY_ROOT, CONNECT_BY_ISLEAF
--     - SYS_CONNECT_BY_PATH 直接构建路径
--     - ORDER SIBLINGS BY 在同级节点间排序
--     - 比递归 CTE 早 10+ 年（8i vs 11g R2）
--
--   CONNECT BY 的劣势:
--     - Oracle 独有语法（可移植性为零）
--     - 不能表达非层次的递归（如图遍历、传递闭包）
--     - 不能在递归中做聚合
--
-- 对引擎开发者的启示:
--   实现递归 CTE（SQL 标准）而不是 CONNECT BY。
--   递归 CTE 更通用，且所有主流数据库都支持。
--   如果需要 Oracle 兼容性，可以将 CONNECT BY 翻译为递归 CTE 执行。

-- ============================================================
-- 4. SEARCH / CYCLE 子句（11g R2+，Oracle 独有扩展）
-- ============================================================

-- SEARCH: 控制递归遍历顺序（深度优先 / 广度优先）
WITH org_tree (id, username, manager_id) AS (
    SELECT id, username, manager_id FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SEARCH DEPTH FIRST BY id SET order_col
SELECT * FROM org_tree ORDER BY order_col;

-- CYCLE: 检测循环引用
WITH org_tree (id, username, manager_id) AS (
    SELECT id, username, manager_id FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
CYCLE id SET is_cycle TO 1 DEFAULT 0
SELECT * FROM org_tree;

-- 横向对比:
--   Oracle:     SEARCH / CYCLE 子句（声明式）
--   PostgreSQL: 14+ 支持 CYCLE 子句（受 Oracle 启发）
--               SEARCH BREADTH/DEPTH FIRST 也在 14+ 支持
--   MySQL:      CTE_MAX_RECURSION_DEPTH 限制（无 CYCLE 检测）
--   SQL Server: OPTION (MAXRECURSION n) 限制递归深度

-- ============================================================
-- 5. CTE 物化控制（Oracle 优化器特性）
-- ============================================================

-- Oracle 优化器自动决定是否物化 CTE 结果:
-- 如果 CTE 被多次引用，可能会物化到临时段。
-- 可以通过 Hint 控制:

-- 强制物化
WITH active_users AS (
    SELECT /*+ MATERIALIZE */ * FROM users WHERE status = 1
)
SELECT * FROM active_users;

-- 强制内联（不物化）
WITH active_users AS (
    SELECT /*+ INLINE */ * FROM users WHERE status = 1
)
SELECT * FROM active_users;

-- 设计分析:
--   物化: 计算一次存入临时段，多次读取（适合复杂计算被多次引用）
--   内联: 将 CTE 展开为子查询（适合简单 CTE，避免临时段开销）
--
-- 横向对比:
--   Oracle:     自动决策 + Hint 手动控制（最灵活）
--   PostgreSQL: 12+ 自动决策，MATERIALIZED/NOT MATERIALIZED 关键字控制
--   MySQL:      总是内联展开（不物化），merge/no_merge Hint
--   SQL Server: 总是内联展开

-- ============================================================
-- 6. CONNECT BY 的独有伪列与函数
-- ============================================================

-- LEVEL: 当前行的层级深度
-- CONNECT_BY_ROOT col: 根节点的列值
-- CONNECT_BY_ISLEAF: 是否是叶子节点（0 或 1）
-- SYS_CONNECT_BY_PATH(col, sep): 从根到当前节点的路径
-- CONNECT_BY_ISCYCLE: 是否形成循环（需要 NOCYCLE）

-- CONNECT BY 检测循环
SELECT * FROM users
START WITH manager_id IS NULL
CONNECT BY NOCYCLE PRIOR id = manager_id;

-- CONNECT BY 生成序列（Oracle 最常用的技巧之一）
SELECT LEVEL AS n FROM DUAL CONNECT BY LEVEL <= 100;
-- 生成 1 到 100 的序列，不需要任何表

-- ============================================================
-- 7. 对引擎开发者的总结
-- ============================================================
-- 1. Oracle 有双层次查询体系: CONNECT BY（传统）和递归 CTE（标准）。
-- 2. SEARCH/CYCLE 子句是 Oracle 对递归 CTE 的重要扩展，PostgreSQL 14+ 跟进。
-- 3. CTE 物化控制（MATERIALIZE/INLINE）对查询性能有显著影响。
-- 4. CONNECT BY LEVEL 是 Oracle 最经典的序列生成技巧，其他数据库用 generate_series。
-- 5. 新引擎应优先实现递归 CTE + CYCLE 检测，而不是 CONNECT BY。
