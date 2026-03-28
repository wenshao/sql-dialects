# Spanner: 索引

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## Secondary indexes


Basic index
```sql
CREATE INDEX idx_users_email ON Users (Email);

```

Unique index
```sql
CREATE UNIQUE INDEX idx_users_email_uniq ON Users (Email);

```

NULL_FILTERED index (exclude NULL values, saves storage)
```sql
CREATE NULL_FILTERED INDEX idx_users_phone ON Users (Phone);

```

Multi-column index
```sql
CREATE INDEX idx_users_region_city ON Users (Region, City);

```

Descending index
```sql
CREATE INDEX idx_users_age_desc ON Users (Age DESC);

```

## STORING clause (cover additional columns)


Include extra columns in index to avoid table lookups
```sql
CREATE INDEX idx_users_email_storing ON Users (Email)
    STORING (Username, Age);

```

Unique index with STORING
```sql
CREATE UNIQUE INDEX idx_users_email_full ON Users (Email)
    STORING (Username, CreatedAt);

```

## Interleaved indexes (Spanner-specific)


Interleave index in a table for co-location
```sql
CREATE INDEX idx_order_items_product ON OrderItems (ProductId),
    INTERLEAVE IN Orders;
```

Index data is co-located with parent table rows

## Index on interleaved tables


Index on child table
```sql
CREATE INDEX idx_items_by_product ON OrderItems (ProductId)
    STORING (Quantity, Price);

```

## Search indexes (full-text, 2024+)


```sql
CREATE SEARCH INDEX idx_search_articles ON Articles (Content_Tokens);
```

Requires a TOKENLIST column generated from content

## Vector indexes (2024+)


For approximate nearest neighbor search
CREATE VECTOR INDEX idx_embedding ON Items (Embedding)
    OPTIONS (distance_type = 'COSINE', tree_depth = 2);

## Index management


Drop index
```sql
DROP INDEX idx_users_email;

```

IF NOT EXISTS / IF EXISTS
```sql
CREATE INDEX IF NOT EXISTS idx_users_email ON Users (Email);
DROP INDEX IF EXISTS idx_users_email;

```

Note: Index creation is a schema change and runs in the background
Note: NULL_FILTERED indexes are unique to Spanner (saves space)
Note: INTERLEAVE IN for indexes co-locates index with parent data
Note: No partial indexes (WHERE clause in CREATE INDEX)
Note: No expression indexes (cannot index on function results)
Note: No GIN, GiST, or B-tree variants; Spanner manages index type internally
Note: Indexes are globally consistent (no eventual consistency)
Note: Maximum 128 secondary indexes per table
