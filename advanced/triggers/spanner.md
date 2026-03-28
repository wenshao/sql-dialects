# Spanner: 触发器

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## No trigger support


The following syntax is NOT supported:
CREATE TRIGGER ...
DROP TRIGGER ...
No BEFORE/AFTER row-level triggers
No statement-level triggers

## Alternative 1: Computed / generated columns


Use generated columns for derived values
```sql
CREATE TABLE Products (
    ProductId  INT64 NOT NULL,
    Price      NUMERIC,
    TaxRate    NUMERIC,
    TotalPrice NUMERIC AS (Price * (1 + TaxRate)) STORED
) PRIMARY KEY (ProductId);

```

Commit timestamp for auto-recording modification time
```sql
CREATE TABLE AuditableUsers (
    UserId    INT64 NOT NULL,
    Username  STRING(100),
    UpdatedAt TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true)
) PRIMARY KEY (UserId);

```

On update, set commit timestamp:
```sql
UPDATE AuditableUsers SET Username = 'alice', UpdatedAt = PENDING_COMMIT_TIMESTAMP()
WHERE UserId = 1;

```

## Alternative 2: Change streams (Spanner-specific, 2022+)


Change streams capture data changes and emit them to consumers
This is the closest alternative to triggers

Watch all changes to a table
```sql
CREATE CHANGE STREAM UserChanges FOR Users;

```

Watch specific columns
```sql
CREATE CHANGE STREAM OrderAmountChanges FOR Orders (Amount, Status);

```

Watch all tables
```sql
CREATE CHANGE STREAM AllChanges FOR ALL;

```

Change streams with retention
```sql
CREATE CHANGE STREAM UserChanges FOR Users
    OPTIONS (retention_period = '7d', value_capture_type = 'NEW_AND_OLD_VALUES');

```

Drop change stream
```sql
DROP CHANGE STREAM UserChanges;

```

Change stream data is consumed via:
- Dataflow (Apache Beam) connectors
- SpannerIO in Dataflow
- Custom gRPC API consumers

## Alternative 3: Row deletion policies (TTL)


Automatic cleanup (like a scheduled delete trigger)
```sql
CREATE TABLE TempEvents (
    EventId   INT64 NOT NULL,
    CreatedAt TIMESTAMP NOT NULL
) PRIMARY KEY (EventId),
  ROW DELETION POLICY (OLDER_THAN(CreatedAt, INTERVAL 30 DAY));

```

## Alternative 4: Application-level logic


Implement trigger-like behavior in application code:
## Use transactions to group related operations

## Wrap complex logic in application service methods

## Use Cloud Functions triggered by change streams


Example application-level audit pattern (in transaction):
BEGIN TRANSACTION;
UPDATE Users SET Email = @newEmail WHERE UserId = @id;
INSERT INTO AuditLog (LogId, TableName, Action, UserId, CommitTs)
  - VALUES (@logId, 'Users', 'UPDATE', @id, PENDING_COMMIT_TIMESTAMP());
COMMIT;

> **Note**: Triggers are NOT supported in Spanner
> **Note**: Change streams are the primary alternative (async, external)
> **Note**: PENDING_COMMIT_TIMESTAMP() provides auto-timestamp (like update trigger)
> **Note**: Row deletion policies provide TTL-based cleanup
> **Note**: Application code handles complex business logic
> **Note**: Cloud Functions can react to change stream events
