# CockroachDB: 事务

> 参考资料:
> - [CockroachDB - SQL Statements](https://www.cockroachlabs.com/docs/stable/sql-statements)
> - [CockroachDB - Functions and Operators](https://www.cockroachlabs.com/docs/stable/functions-and-operators)
> - [CockroachDB - Data Types](https://www.cockroachlabs.com/docs/stable/data-types)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

```sql
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

```

Rollback
```sql
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;

```

Savepoints
```sql
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TO SAVEPOINT sp1;
RELEASE SAVEPOINT sp1;
COMMIT;

```

## Isolation levels


CockroachDB only supports SERIALIZABLE (default, strongest)
```sql
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

READ COMMITTED is available (v23.1+, opt-in)
SET CLUSTER SETTING sql.txn.read_committed_isolation.enabled = true;
```sql
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;

```

Note: READ UNCOMMITTED and REPEATABLE READ are aliases for SERIALIZABLE

Show isolation level
```sql
SHOW TRANSACTION ISOLATION LEVEL;

```

## Read-only transactions


```sql
BEGIN TRANSACTION READ ONLY;
SELECT * FROM users;
COMMIT;

```

## AS OF SYSTEM TIME (historical reads, CockroachDB-specific)


Read data as of a specific time (no contention, no locking)
```sql
BEGIN AS OF SYSTEM TIME '-10s';
SELECT * FROM users;
SELECT * FROM orders;
COMMIT;

```

Follower reads (lowest latency, automatic staleness)
```sql
BEGIN AS OF SYSTEM TIME follower_read_timestamp();
SELECT * FROM users;
COMMIT;

```

Bounded staleness reads (v22.1+)
```sql
BEGIN AS OF SYSTEM TIME with_max_staleness('10s');
SELECT * FROM users;
COMMIT;

```

## Row locking


```sql
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR SHARE;
SELECT * FROM accounts WHERE id = 1 FOR NO KEY UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR KEY SHARE;

```

NOWAIT / SKIP LOCKED
```sql
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE SKIP LOCKED;

```

## Transaction retries (CockroachDB-specific)


CockroachDB automatically retries transactions on contention
For client-side retry handling:
Use SAVEPOINT cockroach_restart / RELEASE SAVEPOINT cockroach_restart

```sql
BEGIN;
SAVEPOINT cockroach_restart;
```

... your SQL statements ...
```sql
RELEASE SAVEPOINT cockroach_restart;
COMMIT;

```

If a retry error occurs (SQLSTATE 40001):
ROLLBACK TO SAVEPOINT cockroach_restart;
Re-execute statements
RELEASE SAVEPOINT cockroach_restart;

## Transaction priority (CockroachDB-specific)


```sql
SET TRANSACTION PRIORITY HIGH;
SET TRANSACTION PRIORITY NORMAL;
SET TRANSACTION PRIORITY LOW;

```

## Implicit transactions


Single statements are auto-committed
```sql
INSERT INTO users (username) VALUES ('alice');  -- auto-committed

```

Note: SERIALIZABLE is the default (and recommended) isolation level
Note: Automatic retry on serialization conflicts
Note: AS OF SYSTEM TIME for non-blocking historical reads
Note: follower_read_timestamp() for lowest-latency stale reads
Note: Transaction priority controls conflict resolution
Note: DDL is transactional (can rollback CREATE TABLE)
Note: No advisory locks (use SELECT FOR UPDATE instead)
