# Spanner: 分页查询

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

```sql
SELECT * FROM Users ORDER BY UserId LIMIT 10 OFFSET 20;

```

LIMIT only
```sql
SELECT * FROM Users ORDER BY UserId LIMIT 10;

```

Keyset pagination (cursor-based, recommended)
```sql
SELECT * FROM Users WHERE UserId > 100 ORDER BY UserId LIMIT 10;
```

More efficient than OFFSET for large tables

Keyset pagination with multiple columns
```sql
SELECT * FROM Users
WHERE (CreatedAt, UserId) > ('2024-01-15T10:00:00Z', 100)
ORDER BY CreatedAt, UserId
LIMIT 10;

```

Keyset pagination on interleaved tables
```sql
SELECT * FROM OrderItems
WHERE OrderId = 100 AND ItemId > 5
ORDER BY ItemId
LIMIT 10;
```

Very efficient because data is physically sorted by primary key

Window function pagination
```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY UserId) AS rn
    FROM Users
) WHERE rn BETWEEN 21 AND 30;

```

Stale read for consistent pagination (Spanner-specific)
Bounded staleness: read data no older than 15 seconds
In client API: read_timestamp or max_staleness options
No SQL syntax for stale reads; configured at transaction level

Pagination with total count
```sql
SELECT *, COUNT(*) OVER () AS total_count
FROM Users
ORDER BY UserId
LIMIT 10 OFFSET 20;

```

Note: OFFSET is inefficient for large offsets (must scan skipped rows)
Note: Keyset (cursor) pagination is preferred
Note: Interleaved table scans are very efficient (data co-located and sorted)
Note: No FETCH FIRST ... ROWS ONLY syntax
Note: Stale reads configured at transaction level, not in SQL
Note: Primary key ordering determines physical data layout
