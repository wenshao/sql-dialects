-- MariaDB: JOIN
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- All standard MySQL JOIN types are supported:
-- INNER JOIN, LEFT JOIN, RIGHT JOIN, CROSS JOIN, NATURAL JOIN, USING

-- INNER JOIN (same as MySQL)
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;

-- LEFT JOIN / RIGHT JOIN (same as MySQL)
SELECT u.username, o.amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id;

-- LATERAL join (11.0+, later than MySQL 8.0.14)
SELECT u.username, latest.amount
FROM users u
JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest ON TRUE;

-- Note: FULL OUTER JOIN not supported (same as MySQL)

-- Block Nested Loop (BNL) / Batched Key Access (BKA) join optimization
-- MariaDB uses BNL and BKA by default; slightly different behavior than MySQL
-- MariaDB has hash join since 10.4+

-- Hash join (10.4+, optimizer decides automatically)
-- MariaDB introduced hash join independently of MySQL 8.0
SET join_cache_level = 6;  -- enable hash join
SELECT u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

-- Join buffer size affects join performance
SET join_buffer_size = 4194304;  -- 4MB (per-session)
-- MariaDB supports join_buffer_space_limit to cap total join buffer usage
SET join_buffer_space_limit = 16777216;  -- 16MB total for all join buffers

-- Optimizer hints (MariaDB syntax, different from MySQL 8.0 hint syntax)
-- MariaDB does not support MySQL 8.0-style /*+ HASH_JOIN() */ hints
-- Instead, use optimizer_switch:
SET optimizer_switch = 'join_cache_hashed=on';
SET optimizer_switch = 'join_cache_bka=on';

-- STRAIGHT_JOIN (same as MySQL)
SELECT u.username, o.amount
FROM users u
STRAIGHT_JOIN orders o ON u.id = o.user_id;

-- Index hints for joins (same as MySQL)
SELECT * FROM users u
FORCE INDEX FOR JOIN (idx_city)
JOIN orders o ON u.id = o.user_id
WHERE u.city = 'Beijing';

-- Spider engine for distributed/sharded joins (10.0+)
-- Spider engine can push JOIN operations down to remote shards
-- when both tables are on the same shard

-- Optimizer differences from MySQL:
-- MariaDB's optimizer often produces better plans for complex multi-table joins
-- MariaDB has cost-based optimizer with histogram statistics (10.0+)
-- Subquery materialization and semi-join strategies differ from MySQL 8.0

-- Differences from MySQL 8.0:
-- LATERAL supported from 11.0+ (MySQL from 8.0.14+)
-- Hash join from 10.4+ (MySQL from 8.0.18+)
-- Different optimizer hint syntax
-- No /*+ HASH_JOIN() */ or /*+ MERGE_JOIN() */ style hints
-- Different join_cache_level settings for BNL/BKA
-- join_buffer_space_limit is MariaDB-specific
