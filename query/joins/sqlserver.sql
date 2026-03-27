-- SQL Server: JOIN
--
-- 参考资料:
--   [1] SQL Server T-SQL - Joins
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/from-transact-sql
--   [2] SQL Server T-SQL - SELECT
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/select-transact-sql

-- INNER JOIN
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;

-- LEFT JOIN
SELECT u.username, o.amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id;

-- RIGHT JOIN
SELECT u.username, o.amount
FROM users u
RIGHT JOIN orders o ON u.id = o.user_id;

-- FULL OUTER JOIN
SELECT u.username, o.amount
FROM users u
FULL OUTER JOIN orders o ON u.id = o.user_id;

-- CROSS JOIN
SELECT u.username, r.role_name
FROM users u
CROSS JOIN roles r;

-- 自连接
SELECT e.username AS employee, m.username AS manager
FROM users e
LEFT JOIN users m ON e.manager_id = m.id;

-- USING —— 注意：SQL Server 不支持 USING

-- CROSS APPLY（类似 LATERAL，2005+）
SELECT u.username, latest.amount
FROM users u
CROSS APPLY (
    SELECT TOP 1 amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC
) latest;

-- OUTER APPLY（LEFT JOIN 版本的 CROSS APPLY）
SELECT u.username, latest.amount
FROM users u
OUTER APPLY (
    SELECT TOP 1 amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC
) latest;

-- 带锁提示的 JOIN
SELECT u.username, o.amount
FROM users u WITH (NOLOCK)
JOIN orders o WITH (NOLOCK) ON u.id = o.user_id;
