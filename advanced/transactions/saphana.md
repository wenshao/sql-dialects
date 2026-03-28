# SAP HANA: Transactions

> 参考资料:
> - [SAP HANA SQL Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/)
> - [SAP HANA SQLScript Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/)


## SAP HANA auto-commits by default

Disable auto-commit to use explicit transactions

```sql
SET AUTOCOMMIT OFF;
```

## Basic transaction

```sql
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;
```

## Rollback

```sql
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;
```

## Savepoints

```sql
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TO SAVEPOINT sp1;
RELEASE SAVEPOINT sp1;
COMMIT;
```

## Re-enable auto-commit

```sql
SET AUTOCOMMIT ON;
```

Isolation levels
SAP HANA supports:
READ COMMITTED (default): statement-level consistency
REPEATABLE READ: transaction-level consistency (MVCC snapshot)
SERIALIZABLE: full serializability

```sql
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

## Session-level isolation

```sql
ALTER SESSION SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
```

## Read-only transaction

```sql
SET TRANSACTION READ ONLY;
```

## Locking

```sql
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR SHARE LOCK;
```

## Lock wait timeout

```sql
SET TRANSACTION LOCK WAIT TIMEOUT 10;   -- 10 seconds
```

MVCC (Multi-Version Concurrency Control)
SAP HANA uses MVCC for column store
Readers never block writers, writers never block readers
Each transaction sees a consistent snapshot
Exclusive lock (table level)

```sql
LOCK TABLE accounts IN EXCLUSIVE MODE;
```

In SQLScript (stored procedures):
CREATE PROCEDURE transfer(...)
AS
BEGIN
DECLARE EXIT HANDLER FOR SQLEXCEPTION ROLLBACK;
UPDATE accounts SET balance = balance - :p_amount WHERE id = :p_from;
UPDATE accounts SET balance = balance + :p_amount WHERE id = :p_to;
COMMIT;
END;
Transaction in SQLScript with error handling
BEGIN
DECLARE EXIT HANDLER FOR SQLEXCEPTION
BEGIN
ROLLBACK;
RESIGNAL;
END;
DML statements here
COMMIT;
END;
> **Note**: SAP HANA defaults to auto-commit mode
> **Note**: MVCC provides snapshot isolation for column store
> **Note**: row store uses traditional locking
> **Note**: DDL auto-commits (cannot roll back DDL)
> **Note**: HANA's in-memory architecture makes transactions very fast
