# Spanner: DELETE

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

```sql
DELETE FROM Users WHERE Username = 'alice';

```

Delete all rows (WHERE true required)
```sql
DELETE FROM Users WHERE true;

```

Subquery delete
```sql
DELETE FROM Users WHERE UserId IN (SELECT UserId FROM Blacklist);

```

EXISTS subquery
```sql
DELETE FROM Users
WHERE EXISTS (SELECT 1 FROM Blacklist b WHERE b.Email = Users.Email);

```

CTE + DELETE
```sql
WITH Inactive AS (
    SELECT UserId FROM Users WHERE LastLogin < '2023-01-01'
)
DELETE FROM Users WHERE UserId IN (SELECT UserId FROM Inactive);

```

DELETE with THEN RETURN (Spanner-specific)
```sql
DELETE FROM Users WHERE Status = 0
THEN RETURN UserId, Username, Email;

```

Delete from interleaved child table
```sql
DELETE FROM OrderItems WHERE OrderId = 100 AND ItemId = 1;

```

Delete parent with CASCADE (if INTERLEAVE IN PARENT ... ON DELETE CASCADE)
```sql
DELETE FROM Orders WHERE OrderId = 100;
```

Child rows in OrderItems are automatically deleted

Delete by primary key range
```sql
DELETE FROM Events WHERE EventId BETWEEN 1000 AND 2000;

```

Conditional delete with subquery
```sql
DELETE FROM Orders
WHERE UserId IN (SELECT UserId FROM Users WHERE Status = 0);

```

Row deletion policy (automatic TTL, alternative to manual DELETE)
Set at table creation or via ALTER TABLE:
ALTER TABLE Events ADD ROW DELETION POLICY (OLDER_THAN(EventTime, INTERVAL 90 DAY));

Note: DELETE requires WHERE clause (use WHERE true for all rows)
Note: THEN RETURN replaces PostgreSQL's RETURNING
Note: Deleting a parent row cascades to interleaved children (if configured)
Note: No TRUNCATE statement
Note: No DELETE ... USING (multi-table delete)
Note: No DELETE ... LIMIT
Note: Single transaction limit: 80,000 mutations
Note: Row deletion policy provides automatic TTL-based cleanup
