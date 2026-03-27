-- Derby: JOIN
--
-- 参考资料:
--   [1] Derby SQL Reference
--       https://db.apache.org/derby/docs/10.16/ref/
--   [2] Derby Developer Guide
--       https://db.apache.org/derby/docs/10.16/devguide/

-- INNER JOIN
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;

-- LEFT OUTER JOIN
SELECT u.username, o.amount
FROM users u
LEFT OUTER JOIN orders o ON u.id = o.user_id;

-- RIGHT OUTER JOIN
SELECT u.username, o.amount
FROM users u
RIGHT OUTER JOIN orders o ON u.id = o.user_id;

-- CROSS JOIN
SELECT u.username, r.role_name
FROM users u
CROSS JOIN roles r;

-- 自连接
SELECT e.username AS employee, m.username AS manager
FROM users e
LEFT OUTER JOIN users m ON e.manager_id = m.id;

-- 多表 JOIN
SELECT u.username, o.amount, p.product_name
FROM users u
INNER JOIN orders o ON u.id = o.user_id
INNER JOIN order_items oi ON o.id = oi.order_id
INNER JOIN products p ON oi.product_id = p.id;

-- 条件 JOIN
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id AND o.amount > 100;

-- 非等值 JOIN
SELECT u.username, p.product_name
FROM users u
INNER JOIN products p ON u.balance >= p.price;

-- 隐式 JOIN（逗号语法）
SELECT u.username, o.amount
FROM users u, orders o
WHERE u.id = o.user_id;

-- ============================================================
-- FULL OUTER JOIN（不直接支持，使用 UNION 模拟）
-- ============================================================

SELECT u.username, o.amount
FROM users u LEFT OUTER JOIN orders o ON u.id = o.user_id
UNION
SELECT u.username, o.amount
FROM users u RIGHT OUTER JOIN orders o ON u.id = o.user_id;

-- ============================================================
-- 不支持的 JOIN 类型
-- ============================================================

-- 不支持 NATURAL JOIN
-- 不支持 USING 子句
-- 不支持 FULL OUTER JOIN（需 UNION 模拟）
-- 不支持 LATERAL JOIN

-- 注意：Derby 支持 INNER、LEFT、RIGHT、CROSS JOIN
-- 注意：不支持 NATURAL JOIN 和 USING 子句
-- 注意：FULL OUTER JOIN 需要用 UNION 模拟
-- 注意：JOIN 中建议使用明确的表别名
-- 注意：LEFT JOIN 需要写完整 LEFT OUTER JOIN
