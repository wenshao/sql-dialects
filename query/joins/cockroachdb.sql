-- CockroachDB: JOIN (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- CockroachDB supports all PostgreSQL JOIN types

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
SELECT * FROM users NATURAL JOIN profiles;

-- LATERAL JOIN (same as PostgreSQL)
SELECT u.username, top_order.amount
FROM users u
LEFT JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY amount DESC LIMIT 1
) top_order ON true;

-- Multi-table JOIN
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;

-- UNNEST (array expansion, same as PostgreSQL)
SELECT u.username, tag
FROM users u
CROSS JOIN UNNEST(u.tags) AS tag;

-- JOIN with JSONB
SELECT u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.metadata @> '{"premium": true}'::JSONB;

-- Lookup join hint (CockroachDB-specific)
SELECT u.username, o.amount
FROM users u
INNER LOOKUP JOIN orders o ON u.id = o.user_id;
-- Forces index-based lookup join (good for small driving tables)

-- Merge join hint
SELECT u.username, o.amount
FROM users u
INNER MERGE JOIN orders o ON u.id = o.user_id;

-- Hash join hint
SELECT u.username, o.amount
FROM users u
INNER HASH JOIN orders o ON u.id = o.user_id;

-- AS OF SYSTEM TIME join (historical data)
SELECT u.username, o.amount
FROM users AS OF SYSTEM TIME '-10s' u
JOIN orders AS OF SYSTEM TIME '-10s' o ON u.id = o.user_id;

-- Note: All PostgreSQL JOIN types supported
-- Note: LOOKUP JOIN, MERGE JOIN, HASH JOIN hints are CockroachDB-specific
-- Note: AS OF SYSTEM TIME enables follower reads (lower latency)
-- Note: JOIN performance depends on data locality (co-located tables)
-- Note: LATERAL JOIN supported (unlike BigQuery)
