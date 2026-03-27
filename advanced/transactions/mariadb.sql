-- MariaDB: Transactions
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

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

-- Isolation levels (same as MySQL)
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;  -- default (InnoDB)
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- Check isolation level
SELECT @@transaction_isolation;  -- 10.5.2+
SELECT @@tx_isolation;           -- older versions

-- Read-only transaction (same as MySQL)
START TRANSACTION READ ONLY;

-- Locking reads (same as MySQL)
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR SHARE;      -- 10.3.0+ (same as MySQL 8.0)
SELECT * FROM accounts WHERE id = 1 LOCK IN SHARE MODE;

-- NOWAIT (10.3+) / SKIP LOCKED (10.6+)
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;       -- 10.3+
SELECT * FROM accounts WHERE id = 1 FOR UPDATE SKIP LOCKED;  -- 10.6+

-- WAIT N (MariaDB-specific, 10.3+)
-- Wait up to N seconds for a lock (not in MySQL)
SELECT * FROM accounts WHERE id = 1 FOR UPDATE WAIT 5;
-- Returns error if lock not acquired within 5 seconds

-- START TRANSACTION WITH CONSISTENT SNAPSHOT (same as MySQL)
START TRANSACTION WITH CONSISTENT SNAPSHOT;

-- System-versioned table transactions (10.3.4+):
-- DML on system-versioned tables automatically records history
START TRANSACTION;
UPDATE products SET price = 29.99 WHERE id = 1;
-- Old row version automatically preserved with row_start/row_end timestamps
COMMIT;
-- After commit, both current and historical versions exist

-- XA Transactions (same as MySQL, for distributed two-phase commit)
XA START 'txn_001';
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
XA END 'txn_001';
XA PREPARE 'txn_001';
XA COMMIT 'txn_001';

-- Galera Cluster transactions (MariaDB Galera Cluster):
-- Virtually synchronous replication using certification-based replication
-- All nodes can accept writes; conflicts detected at commit time

-- Galera-specific: wsrep_sync_wait
-- Control what operations wait for cluster synchronization
SET wsrep_sync_wait = 1;  -- wait for reads to be consistent
SET wsrep_sync_wait = 7;  -- wait for reads, updates, and inserts

-- Galera-specific: wsrep_trx_fragment_size
-- Stream large transactions in fragments (10.4+)
SET wsrep_trx_fragment_size = 10000;  -- fragment every 10000 bytes
-- Prevents large transactions from blocking the cluster

-- Galera limitations:
-- No table-level LOCK TABLES inside transactions
-- MyISAM not fully supported (InnoDB required)
-- Certification-based conflict detection may roll back transactions

-- DDL and transactions:
-- DDL causes implicit commit (same as MySQL)

-- Differences from MySQL 8.0:
-- FOR UPDATE WAIT N (MariaDB-specific, 10.3+)
-- NOWAIT from 10.3+, SKIP LOCKED from 10.6+ (MySQL both from 8.0)
-- Galera Cluster for multi-master synchronous replication
-- Galera streaming replication for large transactions (10.4+)
-- System-versioned table automatic history tracking in transactions
-- Same InnoDB transaction engine and isolation level behavior
-- Same XA transaction support
