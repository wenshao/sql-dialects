-- OceanBase: Transactions
-- OceanBase has dual mode: MySQL mode and Oracle mode. Both shown where relevant.
--
-- 参考资料:
--   [1] OceanBase SQL Reference (MySQL Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase SQL Reference (Oracle Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- MySQL Mode (mostly same as MySQL)
-- ============================================================

-- Basic transaction
START TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- Rollback
START TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;

-- Savepoint
START TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TO SAVEPOINT sp1;
COMMIT;

-- Auto-commit
SELECT @@autocommit;
SET autocommit = 0;

-- Isolation levels (MySQL mode)
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;      -- commonly used
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;     -- default
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- READ UNCOMMITTED: maps to READ COMMITTED

-- Check isolation level
SELECT @@transaction_isolation;

-- Read-only transaction
START TRANSACTION READ ONLY;

-- Locking reads
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR SHARE;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE SKIP LOCKED;

-- ============================================================
-- Oracle Mode
-- ============================================================

-- Basic transaction (implicit begin in Oracle mode)
-- Transactions start implicitly with the first DML statement
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- Rollback
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;

-- Savepoint
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TO SAVEPOINT sp1;
COMMIT;

-- Isolation levels (Oracle mode)
-- Default: READ COMMITTED (different from MySQL mode!)
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- Note: REPEATABLE READ not standard in Oracle mode

-- Oracle mode: SET TRANSACTION
SET TRANSACTION READ ONLY;
SET TRANSACTION READ WRITE;

-- Locking (Oracle mode)
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE WAIT 5;  -- wait up to 5 seconds

-- FOR UPDATE OF (Oracle mode, specify which table to lock)
SELECT a.*, b.* FROM accounts a JOIN users b ON a.user_id = b.id
FOR UPDATE OF a.balance;
-- Only locks the accounts table

-- Autonomous transactions (Oracle mode, 4.0+)
-- Execute independent transaction within another transaction
-- Used in PL/SQL procedures for logging, etc.

-- ============================================================
-- Distributed Transaction Strengths
-- ============================================================

-- OceanBase has strong distributed transaction support:
-- Full ACID compliance across all nodes
-- Paxos-based consensus protocol for data replication
-- Two-phase commit for distributed transactions
-- Global timestamp service for transaction ordering

-- Multi-partition transaction
START TRANSACTION;
-- These may touch different partitions/nodes, all handled atomically
UPDATE orders SET status = 'shipped' WHERE region = 'US';
UPDATE inventory SET qty = qty - 1 WHERE product_id = 100;
UPDATE accounts SET balance = balance - 99.99 WHERE user_id = 1;
COMMIT;
-- All succeed or all fail, even across different OBServer nodes

-- Global Timestamp Service (GTS)
-- OceanBase uses GTS for global transaction ordering
-- Ensures consistency across all zones and nodes
-- Controlled by ob_timestamp_service

-- Transaction timeout
SET ob_trx_timeout = 100000000;   -- transaction timeout in microseconds (100s)
SET ob_trx_idle_timeout = 120000000;  -- idle transaction timeout (120s)

-- Parallel DML in transactions (4.0+)
-- Enable parallel execution within a transaction
SET _enable_parallel_dml = TRUE;

-- Limitations:
-- MySQL mode: same transaction semantics as MySQL
-- Oracle mode: READ COMMITTED default (not REPEATABLE READ)
-- Oracle mode: FOR UPDATE WAIT N supported
-- Oracle mode: FOR UPDATE OF column supported
-- Strong distributed transaction support (full ACID across nodes)
-- XA transactions supported in MySQL mode
-- Transaction size limits depend on memory configuration
