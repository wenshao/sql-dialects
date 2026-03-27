-- Oracle: CTE（9i R2+）
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - SELECT (Subquery Factoring)
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html
--   [2] Oracle SQL Language Reference
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/

-- 基本 CTE（子查询分解）
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
FROM active_users u
JOIN user_orders o ON u.id = o.user_id;

-- 递归 CTE（11g R2+）
-- 注意：Oracle 不需要 RECURSIVE 关键字！
WITH nums (n) AS (
    SELECT 1 FROM dual
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;

-- 递归：层级结构
WITH org_tree (id, username, manager_id, lvl) AS (
    SELECT id, username, manager_id, 0
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.lvl + 1
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;

-- 传统层级查询（CONNECT BY，所有版本，Oracle 特有）
SELECT id, username, manager_id, LEVEL AS lvl,
    SYS_CONNECT_BY_PATH(username, '/') AS path
FROM users
START WITH manager_id IS NULL
CONNECT BY PRIOR id = manager_id
ORDER SIBLINGS BY username;

-- CONNECT BY 检测循环
SELECT * FROM users
START WITH manager_id IS NULL
CONNECT BY NOCYCLE PRIOR id = manager_id;

-- SEARCH / CYCLE 子句（11g R2+）
WITH org_tree (id, username, manager_id) AS (
    SELECT id, username, manager_id FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SEARCH DEPTH FIRST BY id SET order_col
CYCLE id SET is_cycle TO 1 DEFAULT 0
SELECT * FROM org_tree;

-- 12c+: CTE 物化提示
WITH active_users AS (
    SELECT /*+ MATERIALIZE */ * FROM users WHERE status = 1
)
SELECT * FROM active_users;

-- 不物化
WITH active_users AS (
    SELECT /*+ INLINE */ * FROM users WHERE status = 1
)
SELECT * FROM active_users;
