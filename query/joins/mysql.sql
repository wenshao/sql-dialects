-- MySQL: JOIN
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - JOIN Clause
--       https://dev.mysql.com/doc/refman/8.0/en/join.html
--   [2] MySQL 8.0 Reference Manual - SELECT
--       https://dev.mysql.com/doc/refman/8.0/en/select.html

-- INNER JOIN
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;

-- LEFT JOIN（LEFT OUTER JOIN）
SELECT u.username, o.amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id;

-- RIGHT JOIN
SELECT u.username, o.amount
FROM users u
RIGHT JOIN orders o ON u.id = o.user_id;

-- CROSS JOIN（笛卡尔积）
SELECT u.username, r.role_name
FROM users u
CROSS JOIN roles r;

-- 自连接
SELECT e.username AS employee, m.username AS manager
FROM users e
LEFT JOIN users m ON e.manager_id = m.id;

-- 多表 JOIN
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;

-- USING（连接列同名时简写）
SELECT * FROM users JOIN orders USING (user_id);

-- NATURAL JOIN（自动匹配同名列，不推荐）
SELECT * FROM users NATURAL JOIN orders;

-- 8.0.14+: LATERAL（侧向连接，类似 SQL Server 的 CROSS APPLY）
SELECT u.username, latest.amount
FROM users u
JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest ON TRUE;

-- 注意：MySQL 不支持 FULL OUTER JOIN
-- 模拟 FULL OUTER JOIN（UNION ALL + 排除重复）:
SELECT * FROM users u LEFT JOIN orders o ON u.id = o.user_id
UNION ALL
SELECT * FROM users u RIGHT JOIN orders o ON u.id = o.user_id
WHERE u.id IS NULL;
