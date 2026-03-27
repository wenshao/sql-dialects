-- TiDB: UPDATE
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- Basic update (same as MySQL)
UPDATE users SET age = 26 WHERE username = 'alice';

-- Multi-column update (same as MySQL)
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- UPDATE with LIMIT (same as MySQL)
UPDATE users SET status = 0 WHERE status = 1 ORDER BY created_at LIMIT 100;

-- Multi-table update (same as MySQL)
UPDATE users u
JOIN orders o ON u.id = o.user_id
SET u.status = 1
WHERE o.amount > 1000;

-- WITH CTE (same as MySQL 8.0)
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users u JOIN vip v ON u.id = v.user_id SET u.status = 2;

-- Transaction size limit:
-- Large updates that modify many rows may hit txn-total-size-limit (default 100MB)
-- Split into smaller batches for large updates

-- Batch update pattern (recommended for large datasets)
-- Instead of: UPDATE users SET status = 0 WHERE last_login < '2023-01-01';
-- Use batched approach:
UPDATE users SET status = 0
WHERE last_login < '2023-01-01' AND id BETWEEN 1 AND 10000;
-- Then repeat for next batch...

-- TiDB-specific optimizer hints
UPDATE /*+ USE_INDEX(users, idx_status) */ users
SET age = age + 1
WHERE status = 1;

-- UPDATE with subquery (same as MySQL)
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- CASE expression (same as MySQL)
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- Limitations:
-- Large transactions may fail with "transaction too large" error
-- UPDATE ... ORDER BY ... LIMIT may behave differently in distributed context
-- Self-referencing updates are supported but may have performance implications
-- Updating columns used in shard key may cause data movement across TiKV regions
-- Cannot update AUTO_RANDOM column (unless allow_auto_random_explicit_insert is ON)
