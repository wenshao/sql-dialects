-- H2: JOIN
--
-- 参考资料:
--   [1] H2 SQL Reference - Commands
--       https://h2database.com/html/commands.html
--   [2] H2 - Data Types
--       https://h2database.com/html/datatypes.html
--   [3] H2 - Functions
--       https://h2database.com/html/functions.html

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
-- H2 不直接支持 FULL OUTER JOIN，使用 UNION 模拟
SELECT u.username, o.amount FROM users u LEFT JOIN orders o ON u.id = o.user_id
UNION
SELECT u.username, o.amount FROM users u RIGHT JOIN orders o ON u.id = o.user_id;

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

-- 多表 JOIN
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;

-- 条件 JOIN
SELECT u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id AND o.amount > 100;

-- 非等值 JOIN
SELECT u.username, p.name AS product
FROM users u
JOIN products p ON u.balance >= p.price;

-- ============================================================
-- CSVREAD JOIN（H2 特有）
-- ============================================================

-- 与 CSV 文件 JOIN
SELECT u.username, c.extra_info
FROM users u
JOIN CSVREAD('/path/to/extra_data.csv') c ON u.id = c.user_id;

-- 注意：H2 支持大部分标准 SQL JOIN
-- 注意：FULL OUTER JOIN 支持可能因版本而异
-- 注意：支持 NATURAL JOIN
-- 注意：可以与 CSVREAD 返回的虚拟表 JOIN
-- 注意：在兼容模式下 JOIN 行为可能略有不同
