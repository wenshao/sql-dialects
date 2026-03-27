-- TiDB: JOIN
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- All standard MySQL JOIN types are supported:
-- INNER JOIN, LEFT JOIN, RIGHT JOIN, CROSS JOIN, NATURAL JOIN, USING

-- INNER JOIN (same as MySQL)
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;

-- LEFT JOIN (same as MySQL)
SELECT u.username, o.amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id;

-- LATERAL join (7.0+, same as MySQL 8.0.14+)
SELECT u.username, latest.amount
FROM users u
JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest ON TRUE;

-- Note: FULL OUTER JOIN not supported (same as MySQL)
-- Simulate with UNION of LEFT and RIGHT JOIN

-- TiDB-specific JOIN optimizer hints
-- Hash join: force the optimizer to use hash join algorithm
SELECT /*+ HASH_JOIN(u, o) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

-- Merge join (sort-merge join)
SELECT /*+ MERGE_JOIN(u, o) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

-- Index nested loop join
SELECT /*+ INL_JOIN(o) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

-- Index hash join
SELECT /*+ INL_HASH_JOIN(o) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

-- Index merge join
SELECT /*+ INL_MERGE_JOIN(o) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

-- Broadcast join (5.0+): replicate small table to all TiDB nodes
SELECT /*+ BROADCAST_JOIN(r) */ u.username, r.role_name
FROM users u
JOIN roles r ON u.role_id = r.id;

-- MPP mode (5.0+): push joins down to TiFlash for analytical queries
-- When TiFlash replicas exist, TiDB can use MPP framework
SELECT /*+ READ_FROM_STORAGE(TIFLASH[u, o]) */ u.city, SUM(o.amount)
FROM users u
JOIN orders o ON u.id = o.user_id
GROUP BY u.city;

-- Join order hint
SELECT /*+ LEADING(o, u) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

-- Straight join (same as MySQL, force left-to-right join order)
SELECT u.username, o.amount
FROM users u
STRAIGHT_JOIN orders o ON u.id = o.user_id;

-- Limitations:
-- Join algorithms differ from MySQL (hash join is more common in TiDB)
-- Correlated subqueries in joins may have different performance characteristics
-- Very large joins benefit from TiFlash MPP mode
-- No FULL OUTER JOIN (same as MySQL)
