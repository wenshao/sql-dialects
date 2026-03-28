# CockroachDB: 分页查询

> 参考资料:
> - [CockroachDB - SQL Statements](https://www.cockroachlabs.com/docs/stable/sql-statements)
> - [CockroachDB - Functions and Operators](https://www.cockroachlabs.com/docs/stable/functions-and-operators)
> - [CockroachDB - Data Types](https://www.cockroachlabs.com/docs/stable/data-types)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

```sql
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

```

SQL standard syntax (FETCH FIRST)
```sql
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

```

Keyset pagination (cursor-based, recommended for distributed systems)
```sql
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
```

More efficient than OFFSET for large datasets

Keyset pagination with multiple columns
```sql
SELECT * FROM users
WHERE (created_at, id) > ('2024-01-15 10:00:00', 100)
ORDER BY created_at, id
LIMIT 10;

```

Window function pagination
```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

```

AS OF SYSTEM TIME for consistent pagination (CockroachDB-specific)
Prevents phantom reads across pages
```sql
SELECT * FROM users AS OF SYSTEM TIME '-10s'
WHERE id > 100 ORDER BY id LIMIT 10;
```

Using follower reads for lower latency

Pagination with total count
```sql
SELECT *, COUNT(*) OVER () AS total_count
FROM users
ORDER BY id
LIMIT 10 OFFSET 20;

```

Note: OFFSET is inefficient for large values (must scan skipped rows)
Note: Keyset (cursor) pagination is preferred for distributed databases
Note: AS OF SYSTEM TIME provides consistent snapshots across pages
Note: FETCH FIRST ... ROWS ONLY is SQL standard syntax
