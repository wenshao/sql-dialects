-- TDSQL: JOIN
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

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

-- CROSS JOIN
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

-- USING
SELECT * FROM users JOIN orders USING (user_id);

-- NATURAL JOIN
SELECT * FROM users NATURAL JOIN orders;

-- 模拟 FULL OUTER JOIN
SELECT * FROM users u LEFT JOIN orders o ON u.id = o.user_id
UNION
SELECT * FROM users u RIGHT JOIN orders o ON u.id = o.user_id;

-- 注意事项：
-- 同 shardkey 的表 JOIN 是本地操作（性能最好）
-- 不同 shardkey 的表 JOIN 需要跨分片查询（代理层协调）
-- 广播表与分片表 JOIN 无需跨分片
-- 建议将经常 JOIN 的表使用相同的 shardkey
-- 不支持 FULL OUTER JOIN（需用 UNION 模拟）
