-- DamengDB (达梦): JOIN
-- Oracle compatible syntax.
--
-- 参考资料:
--   [1] DamengDB SQL Reference
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html
--   [2] DamengDB System Admin Manual
--       https://eco.dameng.com/document/dm/zh-cn/pm/index.html

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

-- Oracle 传统语法（逗号连接 + WHERE）
SELECT u.username, o.amount
FROM users u, orders o
WHERE u.id = o.user_id;

-- Oracle 外连接语法（(+)）
SELECT u.username, o.amount
FROM users u, orders o
WHERE u.id = o.user_id(+);  -- 等同于 LEFT JOIN

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

-- USING
SELECT * FROM users JOIN orders USING (user_id);

-- NATURAL JOIN
SELECT * FROM users NATURAL JOIN orders;

-- 注意事项：
-- 语法与 Oracle 兼容
-- 支持 FULL OUTER JOIN
-- 支持 Oracle 传统的 (+) 外连接语法
-- 支持 NATURAL JOIN 和 USING
