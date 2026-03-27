-- IBM Db2: JOIN
--
-- 参考资料:
--   [1] Db2 SQL Reference
--       https://www.ibm.com/docs/en/db2/11.5?topic=sql
--   [2] Db2 Built-in Functions
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in

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

-- LATERAL (Db2 9.1+, subquery can reference outer table)
SELECT u.username, latest.amount
FROM users u,
LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id
    ORDER BY created_at DESC
    FETCH FIRST 1 ROW ONLY
) AS latest;

-- LEFT JOIN LATERAL
SELECT u.username, latest.amount
FROM users u
LEFT JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id
    ORDER BY created_at DESC
    FETCH FIRST 1 ROW ONLY
) AS latest ON 1=1;

-- EXCEPTION JOIN (Db2-specific: return non-matching rows)
SELECT u.* FROM users u
EXCEPTION JOIN blacklist b ON u.email = b.email;
-- Returns rows from users that have NO match in blacklist

-- Multi-table join
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id;

-- Join with XMLTABLE (join relational with XML data)
SELECT u.username, x.phone
FROM users u,
XMLTABLE('$d/phones/phone' PASSING u.contact_xml AS "d"
    COLUMNS phone VARCHAR(20) PATH '.') AS x;

-- Note: Db2 optimizer chooses join method (nested loop, merge, hash)
-- Note: RUNSTATS helps optimizer choose best join strategy
