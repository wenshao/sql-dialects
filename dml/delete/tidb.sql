-- TiDB: DELETE
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- Basic delete (same as MySQL)
DELETE FROM users WHERE username = 'alice';

-- DELETE with LIMIT / ORDER BY (same as MySQL)
DELETE FROM users WHERE status = 0 ORDER BY created_at LIMIT 100;

-- Multi-table delete (same as MySQL)
DELETE u FROM users u
JOIN blacklist b ON u.email = b.email;

-- DELETE with CTE (same as MySQL 8.0)
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE u FROM users u JOIN inactive i ON u.id = i.id;

-- TRUNCATE (same as MySQL, resets AUTO_INCREMENT)
TRUNCATE TABLE users;
-- Note: TRUNCATE also resets AUTO_RANDOM counter

-- DELETE IGNORE (same as MySQL)
DELETE IGNORE FROM users WHERE id = 1;

-- Transaction size limit:
-- Large deletes that affect many rows may hit txn-total-size-limit (default 100MB)
-- Recommended: batch deletes for large datasets

-- Batch delete pattern (recommended)
DELETE FROM users WHERE status = 0 AND id BETWEEN 1 AND 10000;
-- Repeat for next batch...

-- Non-transactional DML (6.0+): auto-batches large deletes
-- TiDB splits the operation into multiple small transactions internally
BATCH ON id LIMIT 1000 DELETE FROM users WHERE status = 0;
-- This is a TiDB-specific extension that avoids "transaction too large" errors

-- TiDB-specific optimizer hints
DELETE /*+ USE_INDEX(users, idx_status) */ FROM users WHERE status = 0;

-- GC (Garbage Collection) considerations:
-- Deleted data is not immediately removed from TiKV
-- TiDB GC runs periodically (default tidb_gc_life_time = 10m)
-- During GC window, MVCC versions are retained for snapshot reads

-- Subquery delete (same as MySQL)
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- Limitations:
-- Large deletes may fail with "transaction too large"
-- Use BATCH ON ... LIMIT for non-transactional batch deletes (6.0+)
-- DELETE ... ORDER BY ... LIMIT may not be fully deterministic across TiKV regions
-- Cannot delete from a view
-- TRUNCATE TABLE resets both AUTO_INCREMENT and AUTO_RANDOM counters
