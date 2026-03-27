-- YugabyteDB: Transactions (YSQL, v2.x+)
--
-- 参考资料:
--   [1] YugabyteDB YSQL Reference
--       https://docs.yugabyte.com/stable/api/ysql/
--   [2] YugabyteDB PostgreSQL Compatibility
--       https://docs.yugabyte.com/stable/explore/ysql-language-features/

-- YugabyteDB supports PostgreSQL-compatible distributed transactions
-- Default isolation: SNAPSHOT (similar to REPEATABLE READ)

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

-- SERIALIZABLE (strongest, uses pessimistic locking)
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- REPEATABLE READ / SNAPSHOT (default in YugabyteDB)
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- YugabyteDB maps this to SNAPSHOT isolation

-- READ COMMITTED (v2.13+)
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Session-level isolation
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SET default_transaction_isolation = 'serializable';

-- Show current isolation level
SHOW transaction_isolation;

-- Note: READ UNCOMMITTED is treated as READ COMMITTED

-- ============================================================
-- Read-only transactions
-- ============================================================

BEGIN TRANSACTION READ ONLY;
SELECT * FROM users;
SELECT * FROM orders;
COMMIT;

SET TRANSACTION READ ONLY;

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
-- Distributed transactions
-- ============================================================

-- Transactions can span multiple tablets across nodes
-- YugabyteDB uses 2-phase commit for multi-tablet transactions

-- Single-tablet transactions (faster, no 2PC needed)
-- Operations touching only one tablet are optimized

-- Geo-distributed transactions
BEGIN;
UPDATE geo_orders SET amount = 100 WHERE id = 1 AND region = 'us';
UPDATE geo_orders SET amount = 200 WHERE id = 2 AND region = 'eu';
COMMIT;
-- Distributed across regions, consistent

-- ============================================================
-- Transaction retries
-- ============================================================

-- Serializable transactions may fail with SQLSTATE 40001
-- Application should retry the entire transaction

-- SNAPSHOT isolation reduces retry likelihood
-- READ COMMITTED eliminates most retry scenarios

-- ============================================================
-- Advisory locks (same as PostgreSQL)
-- ============================================================

SELECT pg_advisory_lock(12345);                -- acquire
SELECT pg_advisory_unlock(12345);              -- release
SELECT pg_try_advisory_lock(12345);            -- non-blocking acquire

-- ============================================================
-- Implicit transactions
-- ============================================================

-- Single statements are auto-committed
INSERT INTO users (username) VALUES ('alice');  -- auto-committed

-- Note: Default isolation is SNAPSHOT (REPEATABLE READ equivalent)
-- Note: SERIALIZABLE uses pessimistic locking
-- Note: READ COMMITTED available (v2.13+)
-- Note: Distributed transactions use 2-phase commit
-- Note: Single-tablet transactions are optimized (faster)
-- Note: Advisory locks supported (same as PostgreSQL)
-- Note: DDL is transactional (can rollback CREATE TABLE)
-- Note: Transaction retries handled at application level
