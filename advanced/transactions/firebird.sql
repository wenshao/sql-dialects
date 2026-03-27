-- Firebird: Transactions
--
-- 参考资料:
--   [1] Firebird SQL Reference
--       https://firebirdsql.org/en/reference-manuals/
--   [2] Firebird Release Notes
--       https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html

-- Firebird requires explicit transaction management
-- Every statement runs within a transaction
-- isql auto-starts transactions; API clients must manage explicitly

-- Basic transaction (isql)
-- Transactions are auto-started; use COMMIT/ROLLBACK to end
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- Rollback
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;

-- Explicit transaction start with options (API level)
SET TRANSACTION;
SET TRANSACTION READ WRITE;
SET TRANSACTION READ ONLY;

-- Savepoints (2.0+)
SAVEPOINT sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TO SAVEPOINT sp1;
RELEASE SAVEPOINT sp1;
COMMIT;

-- Isolation levels
-- SNAPSHOT (default): transaction sees data as of transaction start (MVCC)
-- READ COMMITTED: sees committed data (variants below)
-- SNAPSHOT TABLE STABILITY: table-level locks (serializable)

SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL SNAPSHOT TABLE STABILITY;

-- READ COMMITTED variants (Firebird-specific fine-tuning)
SET TRANSACTION READ COMMITTED RECORD_VERSION;
-- RECORD_VERSION: reads latest committed version (default for READ COMMITTED)
SET TRANSACTION READ COMMITTED NO RECORD_VERSION;
-- NO RECORD_VERSION: waits for uncommitted changes to commit/rollback

-- 4.0+: READ COMMITTED READ CONSISTENCY
SET TRANSACTION READ COMMITTED READ CONSISTENCY;
-- READ CONSISTENCY: statement-level snapshot within READ COMMITTED

-- Locking
-- Firebird uses optimistic locking by default (MVCC)
-- Pessimistic locking via reservations:
SET TRANSACTION
    RESERVING accounts FOR PROTECTED WRITE;
-- PROTECTED WRITE: other transactions can read but not write
-- SHARED READ: other transactions can read (default)
-- SHARED WRITE: other transactions can read and write
-- PROTECTED READ: exclusive read access

-- Row-level locking (via SELECT ... WITH LOCK, 1.5+)
SELECT * FROM accounts WHERE id = 1 WITH LOCK;

-- Lock timeout (wait for locks)
SET TRANSACTION LOCK TIMEOUT 10;   -- wait up to 10 seconds
SET TRANSACTION NO WAIT;           -- error immediately on lock conflict
SET TRANSACTION WAIT;              -- wait indefinitely (default)

-- EXECUTE BLOCK within transaction
SET TERM !! ;
EXECUTE BLOCK
AS
    DECLARE v_balance DECIMAL(12,2);
BEGIN
    SELECT balance FROM accounts WHERE id = 1 INTO :v_balance;
    IF (v_balance >= 100) THEN
    BEGIN
        UPDATE accounts SET balance = balance - 100 WHERE id = 1;
        UPDATE accounts SET balance = balance + 100 WHERE id = 2;
    END
    ELSE
        EXCEPTION insufficient_balance;
END!!
SET TERM ; !!
COMMIT;

-- COMMIT RETAIN (commit but keep transaction context)
COMMIT RETAIN;    -- commits and starts new transaction with same snapshot
ROLLBACK RETAIN;  -- rollback and starts new transaction

-- Note: Firebird uses MVCC (Multi-Version Concurrency Control)
-- Note: SNAPSHOT is the default isolation (repeatable read via MVCC)
-- Note: record versions are garbage collected by sweep
-- Note: WITH LOCK provides pessimistic row locking
-- Note: COMMIT RETAIN / ROLLBACK RETAIN keep the transaction handle open
-- Note: no implicit auto-commit; all operations are within transactions
