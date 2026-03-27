-- CockroachDB: DELETE (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- CockroachDB uses PostgreSQL-compatible DELETE syntax

-- Basic delete
DELETE FROM users WHERE username = 'alice';

-- Delete all rows
DELETE FROM users;

-- Subquery delete
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- EXISTS subquery
DELETE FROM users u
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = u.email);

-- CTE + DELETE
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

-- USING clause (multi-table delete, same as PostgreSQL)
DELETE FROM orders
USING users
WHERE orders.user_id = users.id AND users.status = 0;

-- DELETE ... RETURNING (same as PostgreSQL)
DELETE FROM users WHERE status = 0
RETURNING id, username, email;

-- Delete with LIMIT (CockroachDB-specific, useful for large deletes)
DELETE FROM events WHERE ts < '2023-01-01' LIMIT 10000;
-- Run in a loop to avoid large transactions

-- Delete from multi-region table
DELETE FROM regional_users WHERE id = 1 AND region = 'us-east1';

-- TRUNCATE (faster than DELETE for all rows)
TRUNCATE TABLE users;
TRUNCATE TABLE users CASCADE;                  -- also truncate dependent tables
TRUNCATE TABLE users, orders;                  -- truncate multiple tables

-- Delete with time-based TTL (CockroachDB v22.2+)
-- Automatic row expiration:
-- ALTER TABLE events SET (ttl_expiration_expression = 'created_at + INTERVAL ''90 days''');
-- ALTER TABLE events SET (ttl_job_cron = '0 * * * *');  -- run every hour

-- Note: DELETE is transactional with automatic retries
-- Note: DELETE ... LIMIT helps batch large deletes
-- Note: TRUNCATE is faster but not transactional
-- Note: TTL for automatic row expiration (v22.2+)
-- Note: No DML rate limits
-- Note: CASCADE on TRUNCATE follows foreign key relationships
