# IBM Db2: Transactions

> 参考资料:
> - [Db2 SQL Reference](https://www.ibm.com/docs/en/db2/11.5?topic=sql)
> - [Db2 Built-in Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in)
> - Db2 auto-commits by default (CLI/ODBC)
> - In CLP: use +c flag to disable auto-commit
> - db2 +c "UPDATE accounts SET balance = balance - 100 WHERE id = 1"
> - Explicit transaction control
> - Note: no explicit BEGIN TRANSACTION in Db2
> - A transaction starts implicitly with the first SQL statement

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
SAVEPOINT sp1 ON ROLLBACK RETAIN CURSORS;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TO SAVEPOINT sp1;
RELEASE SAVEPOINT sp1;
COMMIT;
```

Isolation levels
Db2 uses terminology: UR, CS, RS, RR
UR = Uncommitted Read (READ UNCOMMITTED)
CS = Cursor Stability (READ COMMITTED, default)
RS = Read Stability (REPEATABLE READ)
RR = Repeatable Read (SERIALIZABLE)
Set isolation level for session

```sql
SET CURRENT ISOLATION = CS;
SET CURRENT ISOLATION = UR;
```

## Set isolation level per statement

```sql
SELECT * FROM users WITH UR;     -- uncommitted read
SELECT * FROM users WITH CS;     -- cursor stability (default)
SELECT * FROM users WITH RS;     -- read stability
SELECT * FROM users WITH RR;     -- repeatable read
```

Currently committed (Db2 9.7+, avoids lock waits for CS)
Readers see committed version instead of waiting for lock
ALTER DATABASE mydb USING CUR_COMMIT ON;
Locking

```sql
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR READ ONLY;
```

## Skip locked rows (Db2 9.7+)

```sql
SELECT * FROM accounts WHERE status = 0 FOR UPDATE SKIP LOCKED DATA;
```

## Lock timeout

```sql
SET CURRENT LOCK TIMEOUT = 10;          -- 10 seconds
SET CURRENT LOCK TIMEOUT = WAIT;        -- wait indefinitely
SET CURRENT LOCK TIMEOUT = NOT WAIT;    -- error immediately
```

## Check lock waits

```sql
SELECT * FROM SYSIBMADM.MON_LOCKWAITS;
```

## Read-only transaction

```sql
SET CURRENT ACCESS MODE = READ ONLY;
```

Autonomous transactions (in stored procedures, Db2 11.1+)
Commit independent of calling transaction
Note: Db2 uses implicit transactions (no BEGIN TRANSACTION)
Note: COMMIT/ROLLBACK end the transaction
Note: UR/CS/RS/RR are Db2's isolation level abbreviations
Note: DDL is auto-committed (cannot roll back DDL in Db2)
