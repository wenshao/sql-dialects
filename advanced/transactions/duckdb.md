# DuckDB: 事务

> 参考资料:
> - [DuckDB - SQL Reference](https://duckdb.org/docs/sql/introduction)
> - [DuckDB - Functions](https://duckdb.org/docs/sql/functions/overview)
> - [DuckDB - Data Types](https://duckdb.org/docs/sql/data_types/overview)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

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

Alternative syntax
```sql
BEGIN;
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
COMMIT;

```

DuckDB uses MVCC (Multi-Version Concurrency Control)
Default isolation level: Snapshot Isolation (similar to REPEATABLE READ)

Auto-commit mode (default)
Each statement is automatically wrapped in a transaction if not explicitly started
```sql
INSERT INTO users (username, email) VALUES ('bob', 'bob@example.com');
```

This is auto-committed

Read-only transactions (optimized for analytical queries)
```sql
BEGIN TRANSACTION READ ONLY;
SELECT * FROM users;
SELECT COUNT(*) FROM orders;
COMMIT;

```

Multiple statements in a transaction
```sql
BEGIN;
CREATE TABLE IF NOT EXISTS backups AS SELECT * FROM users;
INSERT INTO backups SELECT * FROM users WHERE created_at > '2024-01-01';
DELETE FROM users WHERE status = 0;
COMMIT;

```

DDL is transactional (can be rolled back)
```sql
BEGIN;
CREATE TABLE test_table (id INTEGER);
INSERT INTO test_table VALUES (1), (2), (3);
ROLLBACK;
```

test_table does NOT exist after rollback

Transaction behavior notes:
## DuckDB has a single-writer model:

   Only one write transaction can be active at a time
   Multiple read transactions can run concurrently
## Write transactions block other write transactions

## Read transactions see a consistent snapshot


Checkpoint (force write to disk)
```sql
CHECKPOINT;
FORCE CHECKPOINT;

```

WAL (Write-Ahead Log) management
```sql
PRAGMA wal_autocheckpoint = '1GB';    -- Auto-checkpoint threshold

```

Error handling in transactions
If a statement in a transaction fails, the transaction is aborted
All subsequent statements will fail until ROLLBACK
```sql
BEGIN;
INSERT INTO users (id, username) VALUES (1, 'alice');
INSERT INTO users (id, username) VALUES (1, 'bob');   -- Fails (duplicate PK)
```

Transaction is now in aborted state
```sql
ROLLBACK;                                              -- Must rollback

```

Concurrent access patterns
Pattern: Read-modify-write
```sql
BEGIN;
```

DuckDB's snapshot isolation prevents dirty reads
but does NOT prevent write-write conflicts
(second writer will fail, not silently overwrite)
```sql
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;

```

Note: DuckDB supports full ACID transactions
Note: Single-writer model (one write transaction at a time)
Note: Snapshot isolation is the only isolation level
Note: DDL statements (CREATE, DROP, ALTER) are transactional
Note: No SAVEPOINT support
Note: No FOR UPDATE / FOR SHARE row locking
Note: No advisory locks
Note: No SET TRANSACTION ISOLATION LEVEL (always snapshot)
Note: Transactions work on both persistent and in-memory databases
Note: CHECKPOINT forces WAL data to the main database file
