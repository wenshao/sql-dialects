-- SQL Server: CTE（2005+）
--
-- 参考资料:
--   [1] SQL Server T-SQL - WITH (CTE)
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/with-common-table-expression-transact-sql
--   [2] SQL Server T-SQL - SELECT
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/select-transact-sql

-- 基本 CTE
-- 注意：CTE 前面如果有语句，必须以分号结尾
;WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;

-- 多个 CTE
;WITH
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

-- 递归 CTE（不需要 RECURSIVE 关键字）
;WITH nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;
-- 默认最大递归 100 次，可以用 OPTION 修改
-- SELECT n FROM nums OPTION (MAXRECURSION 1000);
-- OPTION (MAXRECURSION 0) 表示无限制

-- 递归：层级结构
;WITH org_tree AS (
    SELECT id, username, manager_id, 0 AS level,
           CAST(username AS NVARCHAR(MAX)) AS path
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1,
           t.path + N' > ' + u.username
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;

-- CTE + DML
;WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

-- CTE + UPDATE
;WITH ranked AS (
    SELECT id, status, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age) AS rn
    FROM users
)
UPDATE ranked SET status = 1 WHERE rn = 1;

-- 注意：SQL Server 的 CTE 不支持 MATERIALIZED / NOT MATERIALIZED 提示
