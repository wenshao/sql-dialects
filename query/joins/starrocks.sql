-- StarRocks: JOIN
--
-- 参考资料:
--   [1] StarRocks - SELECT (JOIN)
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/query/SELECT/
--   [2] StarRocks SQL Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/

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

-- USING
SELECT * FROM users JOIN orders USING (user_id);

-- SEMI JOIN（左半连接）
SELECT u.*
FROM users u
LEFT SEMI JOIN orders o ON u.id = o.user_id;

-- ANTI JOIN（反连接）
SELECT u.*
FROM users u
LEFT ANTI JOIN orders o ON u.id = o.user_id;

-- BUCKET SHUFFLE JOIN hint（利用数据分布优化）
SELECT u.username, o.amount
FROM users u
JOIN [bucket] orders o ON u.id = o.user_id;

-- BROADCAST JOIN hint（广播小表）
SELECT u.username, o.amount
FROM users u
JOIN [broadcast] orders o ON u.id = o.user_id;

-- SHUFFLE JOIN hint（重分布连接）
SELECT u.username, o.amount
FROM users u
JOIN [shuffle] orders o ON u.id = o.user_id;

-- COLOCATE JOIN（利用 Colocate Group 本地连接）
-- 前提：两表属于同一 Colocate Group 且按 JOIN 列分桶
SELECT u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

-- 多表 JOIN
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;

-- 注意：StarRocks 兼容 MySQL 协议，支持标准 JOIN 语法
-- 注意：StarRocks 不支持 NATURAL JOIN
-- 注意：StarRocks 不支持 LATERAL JOIN
