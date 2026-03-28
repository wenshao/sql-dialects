# YugabyteDB: DELETE

> 参考资料:
> - [YugabyteDB YSQL Reference](https://docs.yugabyte.com/stable/api/ysql/)
> - [YugabyteDB PostgreSQL Compatibility](https://docs.yugabyte.com/stable/explore/ysql-language-features/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

```sql
DELETE FROM users WHERE username = 'alice';

```

Delete all rows
```sql
DELETE FROM users;

```

Subquery delete
```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

```

EXISTS subquery
```sql
DELETE FROM users u
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = u.email);

```

CTE + DELETE
```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

```

USING clause (multi-table delete, same as PostgreSQL)
```sql
DELETE FROM orders
USING users
WHERE orders.user_id = users.id AND users.status = 0;

```

DELETE ... RETURNING (same as PostgreSQL)
```sql
DELETE FROM users WHERE status = 0
RETURNING id, username, email;

```

Delete from partitioned table
```sql
DELETE FROM geo_orders WHERE id = 1 AND region = 'us';

```

Delete partition data (efficient for range deletes)
```sql
DELETE FROM events WHERE ts < '2023-01-01';

```

TRUNCATE (faster than DELETE for all rows)
```sql
TRUNCATE TABLE users;
TRUNCATE TABLE users CASCADE;                  -- also truncate dependent tables
TRUNCATE TABLE users, orders;                  -- truncate multiple tables
TRUNCATE TABLE users RESTART IDENTITY;         -- reset sequences

```

Delete with subquery in WHERE
```sql
DELETE FROM orders
WHERE user_id IN (
    SELECT id FROM users WHERE status = 0
);

```

Note: DELETE is transactional across distributed tablets
Note: RETURNING clause works the same as PostgreSQL
Note: USING clause for multi-table deletes (same as PostgreSQL)
Note: TRUNCATE is faster but acquires an exclusive lock
Note: Deletes on hash-sharded tables are distributed across tablets
Note: No DML rate limits
Note: CASCADE follows foreign key relationships
