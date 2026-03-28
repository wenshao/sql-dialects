# Spanner: 子查询

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

```sql
SELECT Username, (SELECT COUNT(*) FROM Orders WHERE UserId = Users.UserId) AS OrderCount
FROM Users;

```

WHERE subquery
```sql
SELECT * FROM Users WHERE UserId IN (SELECT UserId FROM Orders WHERE Amount > 100);
SELECT * FROM Users WHERE UserId NOT IN (SELECT UserId FROM Blacklist);

```

EXISTS
```sql
SELECT * FROM Users u
WHERE EXISTS (SELECT 1 FROM Orders o WHERE o.UserId = u.UserId);
SELECT * FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Orders o WHERE o.UserId = u.UserId);

```

Comparison operators + subquery
```sql
SELECT * FROM Users WHERE Age > (SELECT AVG(Age) FROM Users);

```

FROM subquery (derived table)
```sql
SELECT t.City, t.Cnt FROM (
    SELECT City, COUNT(*) AS Cnt FROM Users GROUP BY City
) t WHERE t.Cnt > 10;

```

Correlated subquery
```sql
SELECT u.Username,
    (SELECT MAX(Amount) FROM Orders o WHERE o.UserId = u.UserId) AS MaxOrder
FROM Users u;

```

CTE (preferred over deeply nested subqueries)
```sql
WITH HighValueOrders AS (
    SELECT UserId, SUM(Amount) AS Total
    FROM Orders GROUP BY UserId HAVING SUM(Amount) > 1000
)
SELECT u.Username, h.Total
FROM Users u JOIN HighValueOrders h ON u.UserId = h.UserId;

```

ARRAY subquery (Spanner-specific)
```sql
SELECT Username,
    ARRAY(SELECT Amount FROM Orders WHERE UserId = Users.UserId ORDER BY Amount DESC) AS OrderAmounts
FROM Users;

```

ARRAY with STRUCT
```sql
SELECT Username,
    ARRAY(SELECT AS STRUCT OrderId, Amount FROM Orders WHERE UserId = Users.UserId) AS OrderDetails
FROM Users;

```

IN with UNNEST (search in array)
```sql
SELECT * FROM Users
WHERE 'admin' IN UNNEST(Tags);

```

Subquery in UPDATE
```sql
UPDATE Users SET Status = 2
WHERE UserId IN (SELECT UserId FROM Orders GROUP BY UserId HAVING SUM(Amount) > 10000);

```

Subquery in DELETE
```sql
DELETE FROM Users
WHERE UserId NOT IN (SELECT DISTINCT UserId FROM Orders);

```

Subquery with STRUCT
```sql
SELECT Username,
    (SELECT AS STRUCT COUNT(*) AS Cnt, SUM(Amount) AS Total
     FROM Orders WHERE UserId = Users.UserId) AS OrderInfo
FROM Users;

```

Note: No LATERAL subquery
Note: No ANY / ALL / SOME operators
Note: ARRAY subqueries return arrays directly
Note: SELECT AS STRUCT returns a STRUCT from a subquery
Note: IN UNNEST is used to search within ARRAY columns
Note: Correlated subqueries are supported but may be slow on large tables
