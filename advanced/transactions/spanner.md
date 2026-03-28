# Spanner: 事务

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## Read-write transactions


Spanner transactions are managed via client libraries
SQL-level transaction control is limited

In a read-write transaction:
BEGIN TRANSACTION;
```sql
UPDATE Accounts SET Balance = Balance - 100 WHERE AccountId = 1;
UPDATE Accounts SET Balance = Balance + 100 WHERE AccountId = 2;
```

COMMIT;

Rollback
BEGIN TRANSACTION;
UPDATE Accounts SET Balance = Balance - 100 WHERE AccountId = 1;
ROLLBACK;

## Transaction types


## Read-write transactions

   - Strongly consistent
   - Locks rows on read (pessimistic)
   - Automatic retry on abort
   - Maximum duration: 10 seconds (soft limit)

## Read-only transactions

   - No locks
   - Strongly consistent snapshot
   - Can read at a specific timestamp
   - No duration limit

## Partitioned DML (for large-scale updates)

   - Executes DML across partitions in parallel
   - No transaction guarantees across partitions

## Read-only transactions (strong read)


Read at current time (strong read)
SET TRANSACTION READ ONLY;
```sql
SELECT * FROM Users;
SELECT * FROM Orders;
```

COMMIT;

## Stale reads (lower latency, Spanner-specific)


Configured at transaction level via client API:

Exact staleness: read data as of exactly 15 seconds ago
client.readOnlyTransaction().setExactStaleness(15, TimeUnit.SECONDS)

Bounded staleness: read data no older than 15 seconds
client.readOnlyTransaction().setMaxStaleness(15, TimeUnit.SECONDS)

Read at specific timestamp
client.readOnlyTransaction().setReadTimestamp(Timestamp.parseTimestamp("..."))

## Partitioned DML (large-scale mutations)


For large updates/deletes that would exceed transaction limits
Runs as multiple independent transactions across partitions

Example: delete old events (partitioned DML)
client.executePartitionedUpdate(
    Statement.of("DELETE FROM Events WHERE EventTime < '2023-01-01'")
);

## Locking


Spanner uses pessimistic locking in read-write transactions
Reads in read-write transactions acquire shared locks
Writes acquire exclusive locks

Hint: force read lock on specific rows
```sql
SELECT * FROM Accounts WHERE AccountId = 1;
```

In a read-write transaction, this acquires a shared lock

## Transaction limits


Maximum mutations per transaction: 80,000
Maximum transaction duration: 10 seconds (soft, configurable)
Maximum columns per mutation: 100
Maximum payload: 100 MB per transaction

## Commit timestamps


PENDING_COMMIT_TIMESTAMP() returns the exact commit time
```sql
UPDATE AuditLog SET CommitTs = PENDING_COMMIT_TIMESTAMP()
WHERE LogId = 1;
```

Timestamp is set at commit time, globally ordered

## Batch DML


Execute multiple DML statements in a single RPC call
Reduces round trips but all in same transaction
Configured via client API (executeBatchUpdate)

Note: Externally consistent (stronger than serializable)
Note: No isolation level configuration (always external consistency)
Note: Stale reads configured via client API, not SQL
Note: Partitioned DML for large-scale mutations
Note: 80,000 mutation limit per transaction
Note: No SAVEPOINT support
Note: No advisory locks
Note: Transactions are distributed and globally consistent
