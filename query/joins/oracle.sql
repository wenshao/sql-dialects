-- Oracle: JOIN
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Joins
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Joins.html
--   [2] Oracle SQL Language Reference - SELECT
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html

-- INNER JOIN（SQL 标准语法，9i+）
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;

-- 传统 Oracle 语法（所有版本）
SELECT u.username, o.amount
FROM users u, orders o
WHERE u.id = o.user_id;

-- LEFT JOIN
SELECT u.username, o.amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id;
-- 传统语法（(+) 放在可能为 NULL 的一侧）
SELECT u.username, o.amount
FROM users u, orders o
WHERE u.id = o.user_id(+);

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

-- USING
SELECT * FROM users JOIN orders USING (user_id);

-- NATURAL JOIN
SELECT * FROM users NATURAL JOIN orders;

-- 12c+: LATERAL
SELECT u.username, latest.amount
FROM users u
CROSS JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC FETCH FIRST 1 ROW ONLY
) latest;

-- 12c+: CROSS APPLY / OUTER APPLY
SELECT u.username, latest.amount
FROM users u
CROSS APPLY (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC FETCH FIRST 1 ROW ONLY
) latest;

SELECT u.username, latest.amount
FROM users u
OUTER APPLY (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC FETCH FIRST 1 ROW ONLY
) latest;
