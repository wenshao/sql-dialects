-- TiDB: Transactions
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- Basic transaction (same as MySQL)
START TRANSACTION;  -- or BEGIN
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- Rollback (same as MySQL)
START TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;

-- Savepoint (same as MySQL)
START TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TO SAVEPOINT sp1;
COMMIT;

-- Auto-commit (same as MySQL)
SELECT @@autocommit;
SET autocommit = 0;

-- Isolation levels
-- TiDB default: REPEATABLE READ (using Snapshot Isolation, different from MySQL!)
-- TiDB actually implements Snapshot Isolation (SI) for REPEATABLE READ
-- This means NO phantom reads (unlike MySQL's REPEATABLE READ with gap locks)
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;  -- default (Snapshot Isolation)
-- SERIALIZABLE: maps to REPEATABLE READ in TiDB (not true serializable!)
-- READ UNCOMMITTED: maps to READ COMMITTED in TiDB

-- Check isolation level
SELECT @@transaction_isolation;

-- Key difference from MySQL:
-- MySQL REPEATABLE READ: uses gap locks to prevent phantoms (within InnoDB)
-- TiDB REPEATABLE READ: uses Snapshot Isolation (MVCC-based, no gap locks)
-- TiDB Snapshot Isolation prevents phantom reads but NOT write skew
-- Write skew is possible under SI (a known limitation vs true serializability)

-- Read-only transaction (same as MySQL)
START TRANSACTION READ ONLY;

-- Locking reads
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;       -- pessimistic lock
SELECT * FROM accounts WHERE id = 1 FOR SHARE;        -- shared lock (8.0 syntax)
SELECT * FROM accounts WHERE id = 1 LOCK IN SHARE MODE; -- shared lock (5.7 syntax)

-- NOWAIT / SKIP LOCKED (same as MySQL 8.0)
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE SKIP LOCKED;

-- Optimistic vs Pessimistic transactions (TiDB-specific):
-- Pessimistic mode (default since 4.0): locks on write, similar to MySQL InnoDB
-- Optimistic mode: no locks until commit, detects conflicts at commit time

-- Pessimistic (default)
SET tidb_txn_mode = 'pessimistic';
START TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;  -- acquires lock
COMMIT;

-- Optimistic (legacy, before 4.0 default)
SET tidb_txn_mode = 'optimistic';
START TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;  -- no lock yet
COMMIT;  -- conflict detection happens here, may fail with "write conflict"

-- Transaction size limits (TiDB-specific):
-- txn-total-size-limit: max total size of a transaction (default 100MB)
-- stmt-count-limit: max number of statements in a transaction (default 5000)
-- If exceeded, transaction is aborted

-- Stale read transactions (5.1+, TiDB-specific):
-- Read historical data without waiting for latest replication
SET TRANSACTION READ ONLY AS OF TIMESTAMP NOW() - INTERVAL 5 SECOND;
START TRANSACTION;
SELECT * FROM users;  -- reads from 5 seconds ago
COMMIT;

-- Or per-statement:
SELECT * FROM users AS OF TIMESTAMP '2024-01-15 10:00:00';

-- Causal consistency (TiDB-specific):
-- Ensure read-after-write consistency across TiDB servers
-- @@tidb_enable_async_commit and @@tidb_guarantee_linearizability

-- DDL and transactions:
-- DDL statements cause implicit commit (same as MySQL)
-- DDL operations are transactional within TiDB's online DDL framework

-- Distributed transaction internals:
-- TiDB uses Percolator-based 2PC (two-phase commit)
-- Coordinator: TiDB server
-- Participants: TiKV nodes holding the affected key-value pairs
-- TSO (Timestamp Oracle) from PD for global ordering

-- Limitations:
-- SERIALIZABLE isolation not truly supported (mapped to REPEATABLE READ)
-- READ UNCOMMITTED not truly supported (mapped to READ COMMITTED)
-- Transaction size limits (100MB default, configurable)
-- Optimistic transactions may fail at commit time on conflict
-- Long-running transactions may be rolled back by GC
-- XA transactions: limited support
-- No two-phase commit across different TiDB clusters
