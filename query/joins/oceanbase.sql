-- OceanBase: JOIN
-- OceanBase has dual mode: MySQL mode and Oracle mode. Both shown where relevant.
--
-- 参考资料:
--   [1] OceanBase SQL Reference (MySQL Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase SQL Reference (Oracle Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- MySQL Mode (same as MySQL)
-- ============================================================

-- INNER JOIN
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;

-- LEFT / RIGHT JOIN
SELECT u.username, o.amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id;

-- CROSS JOIN
SELECT u.username, r.role_name
FROM users u
CROSS JOIN roles r;

-- NATURAL JOIN
SELECT * FROM users NATURAL JOIN orders;

-- USING
SELECT * FROM users JOIN orders USING (user_id);

-- LATERAL (4.0+)
SELECT u.username, latest.amount
FROM users u
JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest ON TRUE;

-- Note: FULL OUTER JOIN not supported in MySQL mode (same as MySQL)

-- ============================================================
-- Oracle Mode
-- ============================================================

-- INNER JOIN (ANSI syntax)
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;

-- Oracle legacy join syntax (comma join with WHERE)
SELECT u.username, o.amount
FROM users u, orders o
WHERE u.id = o.user_id;

-- LEFT OUTER JOIN (Oracle (+) syntax)
SELECT u.username, o.amount
FROM users u, orders o
WHERE u.id = o.user_id(+);
-- Equivalent to: LEFT JOIN orders o ON u.id = o.user_id

-- RIGHT OUTER JOIN (Oracle (+) syntax)
SELECT u.username, o.amount
FROM users u, orders o
WHERE u.id(+) = o.user_id;

-- FULL OUTER JOIN (supported in Oracle mode!)
SELECT u.username, o.amount
FROM users u
FULL OUTER JOIN orders o ON u.id = o.user_id;

-- CROSS APPLY / OUTER APPLY (Oracle mode, 4.0+)
SELECT u.username, t.amount
FROM users u
CROSS APPLY (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC FETCH FIRST 1 ROWS ONLY
) t;

-- OceanBase-specific optimizer hints
-- Parallel query
SELECT /*+ PARALLEL(4) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

-- Join order hint
SELECT /*+ LEADING(o u) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

-- Use specific join method
SELECT /*+ USE_HASH(u o) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

SELECT /*+ USE_MERGE(u o) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

SELECT /*+ USE_NL(o) */ u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

-- Partition-wise join: when both tables are partitioned by join key
-- OceanBase automatically performs partition-wise joins for co-located data

-- Limitations:
-- MySQL mode: no FULL OUTER JOIN (same as MySQL)
-- Oracle mode: FULL OUTER JOIN supported
-- Oracle mode: both ANSI and legacy (+) join syntax supported
-- Distributed joins across multiple zones have network latency overhead
