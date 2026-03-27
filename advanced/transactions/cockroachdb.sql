-- CockroachDB: Transactions (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- CockroachDB uses SERIALIZABLE isolation by default (strongest level)
-- Automatic transaction retries on contention

-- Basic transaction
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- Rollback
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;

-- Savepoints
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TO SAVEPOINT sp1;
RELEASE SAVEPOINT sp1;
COMMIT;

-- ============================================================
-- Isolation levels
-- ============================================================

-- CockroachDB only supports SERIALIZABLE (default, strongest)
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- READ COMMITTED is available (v23.1+, opt-in)
-- SET CLUSTER SETTING sql.txn.read_committed_isolation.enabled = true;
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Note: READ UNCOMMITTED and REPEATABLE READ are aliases for SERIALIZABLE

-- Show isolation level
SHOW TRANSACTION ISOLATION LEVEL;

-- ============================================================
-- Read-only transactions
-- ============================================================

BEGIN TRANSACTION READ ONLY;
SELECT * FROM users;
COMMIT;

-- ============================================================
-- AS OF SYSTEM TIME (historical reads, CockroachDB-specific)
-- ============================================================

-- Read data as of a specific time (no contention, no locking)
BEGIN AS OF SYSTEM TIME '-10s';
SELECT * FROM users;
SELECT * FROM orders;
COMMIT;

-- Follower reads (lowest latency, automatic staleness)
BEGIN AS OF SYSTEM TIME follower_read_timestamp();
SELECT * FROM users;
COMMIT;

-- Bounded staleness reads (v22.1+)
BEGIN AS OF SYSTEM TIME with_max_staleness('10s');
SELECT * FROM users;
COMMIT;

-- ============================================================
-- Row locking
-- ============================================================

SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR SHARE;
SELECT * FROM accounts WHERE id = 1 FOR NO KEY UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR KEY SHARE;

-- NOWAIT / SKIP LOCKED
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE SKIP LOCKED;

-- ============================================================
-- Transaction retries (CockroachDB-specific)
-- ============================================================

-- CockroachDB automatically retries transactions on contention
-- For client-side retry handling:
-- Use SAVEPOINT cockroach_restart / RELEASE SAVEPOINT cockroach_restart

BEGIN;
SAVEPOINT cockroach_restart;
-- ... your SQL statements ...
RELEASE SAVEPOINT cockroach_restart;
COMMIT;

-- If a retry error occurs (SQLSTATE 40001):
-- ROLLBACK TO SAVEPOINT cockroach_restart;
-- Re-execute statements
-- RELEASE SAVEPOINT cockroach_restart;

-- ============================================================
-- Transaction priority (CockroachDB-specific)
-- ============================================================

SET TRANSACTION PRIORITY HIGH;
SET TRANSACTION PRIORITY NORMAL;
SET TRANSACTION PRIORITY LOW;

-- ============================================================
-- Implicit transactions
-- ============================================================

-- Single statements are auto-committed
INSERT INTO users (username) VALUES ('alice');  -- auto-committed

-- Note: SERIALIZABLE is the default (and recommended) isolation level
-- Note: Automatic retry on serialization conflicts
-- Note: AS OF SYSTEM TIME for non-blocking historical reads
-- Note: follower_read_timestamp() for lowest-latency stale reads
-- Note: Transaction priority controls conflict resolution
-- Note: DDL is transactional (can rollback CREATE TABLE)
-- Note: No advisory locks (use SELECT FOR UPDATE instead)
