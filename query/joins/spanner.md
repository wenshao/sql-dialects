# Spanner: JOIN 连接查询

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

```sql
SELECT u.Username, o.Amount
FROM Users u
INNER JOIN Orders o ON u.UserId = o.UserId;

```

LEFT JOIN
```sql
SELECT u.Username, o.Amount
FROM Users u
LEFT JOIN Orders o ON u.UserId = o.UserId;

```

RIGHT JOIN
```sql
SELECT u.Username, o.Amount
FROM Users u
RIGHT JOIN Orders o ON u.UserId = o.UserId;

```

FULL OUTER JOIN
```sql
SELECT u.Username, o.Amount
FROM Users u
FULL OUTER JOIN Orders o ON u.UserId = o.UserId;

```

CROSS JOIN
```sql
SELECT u.Username, r.RoleName
FROM Users u
CROSS JOIN Roles r;

```

Self join
```sql
SELECT e.Username AS employee, m.Username AS manager
FROM Users e
LEFT JOIN Users m ON e.ManagerId = m.UserId;

```

USING
```sql
SELECT * FROM Users JOIN Orders USING (UserId);

```

Multi-table JOIN
```sql
SELECT u.Username, o.Amount, p.ProductName
FROM Users u
JOIN Orders o ON u.UserId = o.UserId
JOIN OrderItems oi ON o.OrderId = oi.OrderId
JOIN Products p ON oi.ProductId = p.ProductId;

```

UNNEST (array expansion)
```sql
SELECT u.Username, tag
FROM Users u
CROSS JOIN UNNEST(u.Tags) AS tag;

```

UNNEST with OFFSET
```sql
SELECT u.Username, tag, pos
FROM Users u
CROSS JOIN UNNEST(u.Tags) AS tag WITH OFFSET AS pos;

```

JOIN hint: FORCE_JOIN_ORDER
```sql
SELECT /*@FORCE_JOIN_ORDER=TRUE*/ u.Username, o.Amount
FROM Users u
JOIN Orders o ON u.UserId = o.UserId;

```

JOIN hint: JOIN_METHOD
```sql
SELECT /*@JOIN_METHOD=HASH_JOIN*/ u.Username, o.Amount
FROM Users u
JOIN Orders o ON u.UserId = o.UserId;

```

JOIN hint: JOIN_METHOD=APPLY_JOIN (nested loop)
```sql
SELECT /*@JOIN_METHOD=APPLY_JOIN*/ u.Username, o.Amount
FROM Users u
JOIN Orders o ON u.UserId = o.UserId;

```

Interleaved table join (very efficient, data is co-located)
```sql
SELECT o.OrderId, oi.ItemId, oi.Price
FROM Orders o
JOIN OrderItems oi ON o.OrderId = oi.OrderId;
```

OrderItems INTERLEAVED IN PARENT Orders: data is physically co-located

Subquery in JOIN
```sql
SELECT u.Username, stats.TotalAmount
FROM Users u
JOIN (
    SELECT UserId, SUM(Amount) AS TotalAmount FROM Orders GROUP BY UserId
) stats ON u.UserId = stats.UserId;

```

TABLESAMPLE
```sql
SELECT u.Username, o.Amount
FROM Users u TABLESAMPLE BERNOULLI (10)
JOIN Orders o ON u.UserId = o.UserId;

```

Note: LATERAL JOIN is not supported
Note: NATURAL JOIN is not supported
Note: Interleaved table joins are extremely efficient (no network hop)
Note: JOIN hints use SQL comments syntax /*@ ... */
Note: FORCE_JOIN_ORDER forces tables to be joined in query order
