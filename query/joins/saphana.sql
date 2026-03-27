-- SAP HANA: JOIN
--
-- 参考资料:
--   [1] SAP HANA SQL Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/

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

-- Self join
SELECT e.username AS employee, m.username AS manager
FROM users e
LEFT JOIN users m ON e.manager_id = m.id;

-- USING
SELECT * FROM users JOIN orders USING (user_id);

-- NATURAL JOIN
SELECT * FROM users NATURAL JOIN orders;

-- LATERAL (correlated subquery in FROM)
SELECT u.username, latest.amount
FROM users u
CROSS APPLY (
    SELECT TOP 1 amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC
) AS latest;

-- LEFT LATERAL
SELECT u.username, latest.amount
FROM users u
OUTER APPLY (
    SELECT TOP 1 amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC
) AS latest;

-- Multi-table join
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id;

-- Join with hierarchy function
SELECT p.name, h.level
FROM products p
JOIN HIERARCHY (
    SOURCE products_hier
    START WHERE parent_id IS NULL
) AS h ON p.id = h.node_id;

-- Join hints
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
WITH HINT (NO_CS_JOIN);

-- Note: SAP HANA column store uses join engine optimized for in-memory
-- Note: CROSS APPLY / OUTER APPLY are SAP HANA equivalents of LATERAL
-- Note: join order can be influenced with hints
