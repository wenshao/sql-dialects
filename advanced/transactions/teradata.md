# Teradata: Transactions

> 参考资料:
> - [Teradata SQL Reference](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates)
> - [Teradata Database Documentation](https://docs.teradata.com/)


Teradata supports two transaction modes:
1. ANSI mode: explicit BEGIN/COMMIT (like standard SQL)
2. Teradata (BTET) mode: each statement is auto-committed

In ANSI session mode:
```sql
BEGIN TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;
```


Rollback
```sql
BEGIN TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;
```


In Teradata (BTET) session mode:
Each request (statement) is a transaction
Multi-statement transactions use BT/ET
```sql
BT;  -- Begin Transaction
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ET;  -- End Transaction (commit)
```


Rollback in BTET mode
```sql
BT;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ABORT;  -- Rollback
```


Set session mode
```sql
SET SESSION TRANSACTION ANSI;
SET SESSION TRANSACTION BTET;
```


Isolation levels (Teradata supports READ UNCOMMITTED through SERIALIZABLE)
```sql
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```


Locking
```sql
LOCKING TABLE users FOR ACCESS;         -- no lock (dirty read)
LOCKING TABLE users FOR READ;           -- shared lock
LOCKING TABLE users FOR WRITE;          -- exclusive lock
LOCKING TABLE users FOR EXCLUSIVE;      -- exclusive lock (DDL)
```


Row-level locking
```sql
LOCKING ROW FOR ACCESS
SELECT * FROM users WHERE id = 1;

LOCKING ROW FOR WRITE
SELECT * FROM users WHERE id = 1;
```


Locking with query
```sql
LOCKING TABLE orders FOR READ
SELECT u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;
```


In-place locking (within query)
```sql
SELECT * FROM users WHERE id = 1 FOR UPDATE;  -- ANSI mode
```


Savepoints (not supported in Teradata)
Note: Teradata does not support SAVEPOINT

Note: Teradata default is BTET mode (auto-commit per statement)
Note: ANSI mode requires explicit BT/COMMIT or BEGIN TRANSACTION/COMMIT
Note: LOCKING modifiers are Teradata-specific access control
Note: ACCESS lock allows dirty reads (fastest, no blocking)
