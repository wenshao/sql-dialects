-- YugabyteDB: JOIN (YSQL, v2.x+)
--
-- 参考资料:
--   [1] YugabyteDB YSQL Reference
--       https://docs.yugabyte.com/stable/api/ysql/
--   [2] YugabyteDB PostgreSQL Compatibility
--       https://docs.yugabyte.com/stable/explore/ysql-language-features/

-- YugabyteDB supports all PostgreSQL JOIN types

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

-- UNNEST (array expansion)
SELECT u.username, tag
FROM users u
CROSS JOIN UNNEST(u.tags) AS tag;

-- Colocated table join (YugabyteDB-specific optimization)
-- Tables in the same tablegroup are co-located for faster joins
-- CREATE TABLEGROUP order_group;
-- CREATE TABLE orders (...) TABLEGROUP order_group;
-- CREATE TABLE order_items (...) TABLEGROUP order_group;
SELECT o.id, oi.product_id
FROM orders o
JOIN order_items oi ON o.id = oi.order_id;
-- Co-located tables avoid cross-node communication

-- JOIN with hash/range sharding awareness
-- Joins on hash-sharded columns are more efficient when both tables
-- are sharded on the join key
SELECT u.username, o.amount
FROM users u                                   -- sharded on id
JOIN orders o ON u.id = o.user_id;             -- sharded on user_id

-- JOIN with geo-partitioned tables
SELECT u.username, o.amount
FROM geo_users u
JOIN geo_orders o ON u.id = o.user_id AND u.region = o.region;
-- Partition-wise join: each region processes its own data

-- JOIN with JSONB
SELECT u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.metadata @> '{"premium": true}'::JSONB;

-- Note: All PostgreSQL JOIN types supported
-- Note: Co-located tables (via tablegroups) have faster joins
-- Note: Joins on sharding keys are more efficient
-- Note: Geo-partitioned joins can be partition-wise (region-local)
-- Note: LATERAL JOIN supported (same as PostgreSQL)
-- Note: Batched nested loop join optimization for distributed queries
