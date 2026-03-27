-- DuckDB: Transactions (v0.8+)
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- Basic transaction
BEGIN TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- Rollback
BEGIN TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;

-- Alternative syntax
BEGIN;
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
COMMIT;

-- DuckDB uses MVCC (Multi-Version Concurrency Control)
-- Default isolation level: Snapshot Isolation (similar to REPEATABLE READ)

-- Auto-commit mode (default)
-- Each statement is automatically wrapped in a transaction if not explicitly started
INSERT INTO users (username, email) VALUES ('bob', 'bob@example.com');
-- This is auto-committed

-- Read-only transactions (optimized for analytical queries)
BEGIN TRANSACTION READ ONLY;
SELECT * FROM users;
SELECT COUNT(*) FROM orders;
COMMIT;

-- Multiple statements in a transaction
BEGIN;
CREATE TABLE IF NOT EXISTS backups AS SELECT * FROM users;
INSERT INTO backups SELECT * FROM users WHERE created_at > '2024-01-01';
DELETE FROM users WHERE status = 0;
COMMIT;

-- DDL is transactional (can be rolled back)
BEGIN;
CREATE TABLE test_table (id INTEGER);
INSERT INTO test_table VALUES (1), (2), (3);
ROLLBACK;
-- test_table does NOT exist after rollback

-- Transaction behavior notes:
-- 1. DuckDB has a single-writer model:
--    Only one write transaction can be active at a time
--    Multiple read transactions can run concurrently
-- 2. Write transactions block other write transactions
-- 3. Read transactions see a consistent snapshot

-- Checkpoint (force write to disk)
CHECKPOINT;
FORCE CHECKPOINT;

-- WAL (Write-Ahead Log) management
PRAGMA wal_autocheckpoint = '1GB';    -- Auto-checkpoint threshold

-- Error handling in transactions
-- If a statement in a transaction fails, the transaction is aborted
-- All subsequent statements will fail until ROLLBACK
BEGIN;
INSERT INTO users (id, username) VALUES (1, 'alice');
INSERT INTO users (id, username) VALUES (1, 'bob');   -- Fails (duplicate PK)
-- Transaction is now in aborted state
ROLLBACK;                                              -- Must rollback

-- Concurrent access patterns
-- Pattern: Read-modify-write
BEGIN;
-- DuckDB's snapshot isolation prevents dirty reads
-- but does NOT prevent write-write conflicts
-- (second writer will fail, not silently overwrite)
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;

-- Note: DuckDB supports full ACID transactions
-- Note: Single-writer model (one write transaction at a time)
-- Note: Snapshot isolation is the only isolation level
-- Note: DDL statements (CREATE, DROP, ALTER) are transactional
-- Note: No SAVEPOINT support
-- Note: No FOR UPDATE / FOR SHARE row locking
-- Note: No advisory locks
-- Note: No SET TRANSACTION ISOLATION LEVEL (always snapshot)
-- Note: Transactions work on both persistent and in-memory databases
-- Note: CHECKPOINT forces WAL data to the main database file
