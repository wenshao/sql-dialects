# Spanner: UPDATE

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

```sql
UPDATE Users SET Age = 26 WHERE Username = 'alice';

```

Multiple columns
```sql
UPDATE Users SET Email = 'new@example.com', Age = 26 WHERE Username = 'alice';

```

Update all rows (WHERE true required)
```sql
UPDATE Users SET Status = 0 WHERE true;

```

Subquery update
```sql
UPDATE Users SET Age = (SELECT CAST(AVG(Age) AS INT64) FROM Users) WHERE Age IS NULL;

```

FROM clause (multi-table update)
```sql
UPDATE Users u
SET u.Status = 1
FROM Orders o
WHERE u.UserId = o.UserId AND o.Amount > 1000;

```

CTE + UPDATE
```sql
WITH VipUsers AS (
    SELECT UserId FROM Orders GROUP BY UserId HAVING SUM(Amount) > 10000
)
UPDATE Users u
SET u.Status = 2
FROM VipUsers v
WHERE u.UserId = v.UserId;

```

CASE expression
```sql
UPDATE Users SET Status = CASE
    WHEN Age < 18 THEN 0
    WHEN Age >= 65 THEN 2
    ELSE 1
END
WHERE true;

```

UPDATE with THEN RETURN (Spanner-specific)
```sql
UPDATE Users SET Age = 26 WHERE Username = 'alice'
THEN RETURN UserId, Username, Age;

```

Update JSON field
```sql
UPDATE Events SET Data = JSON_SET(Data, '$.status', 'processed')
WHERE EventId = 1;

```

Update with commit timestamp
```sql
UPDATE AuditLog SET CommitTs = PENDING_COMMIT_TIMESTAMP()
WHERE LogId = 1;

```

Update interleaved child rows
```sql
UPDATE OrderItems SET Quantity = 5
WHERE OrderId = 100 AND ItemId = 1;

```

Update with ARRAY operations
```sql
UPDATE Profiles SET Tags = ARRAY_CONCAT(Tags, ['premium'])
WHERE UserId = 1;

```

Conditional update with subquery
```sql
UPDATE Orders
SET Status = 'shipped'
WHERE OrderId IN (SELECT OrderId FROM Shipments WHERE ShippedAt IS NOT NULL);

```

Note: UPDATE requires WHERE clause (use WHERE true for all rows)
Note: THEN RETURN replaces PostgreSQL's RETURNING
Note: Spanner uses PENDING_COMMIT_TIMESTAMP() for commit timestamps
Note: Updates on interleaved tables are efficient (data co-located)
Note: Single transaction limit: 80,000 mutations
Note: UPDATE is strongly consistent globally
