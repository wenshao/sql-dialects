# CockroachDB: DELETE

> 参考资料:
> - [CockroachDB - SQL Statements](https://www.cockroachlabs.com/docs/stable/sql-statements)
> - [CockroachDB - Functions and Operators](https://www.cockroachlabs.com/docs/stable/functions-and-operators)
> - [CockroachDB - Data Types](https://www.cockroachlabs.com/docs/stable/data-types)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

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

Delete with LIMIT (CockroachDB-specific, useful for large deletes)
```sql
DELETE FROM events WHERE ts < '2023-01-01' LIMIT 10000;
```

Run in a loop to avoid large transactions

Delete from multi-region table
```sql
DELETE FROM regional_users WHERE id = 1 AND region = 'us-east1';

```

TRUNCATE (faster than DELETE for all rows)
```sql
TRUNCATE TABLE users;
TRUNCATE TABLE users CASCADE;                  -- also truncate dependent tables
TRUNCATE TABLE users, orders;                  -- truncate multiple tables

```

Delete with time-based TTL (CockroachDB v22.2+)
Automatic row expiration:
ALTER TABLE events SET (ttl_expiration_expression = 'created_at + INTERVAL ''90 days''');
ALTER TABLE events SET (ttl_job_cron = '0 * * * *');  -- run every hour

Note: DELETE is transactional with automatic retries
Note: DELETE ... LIMIT helps batch large deletes
Note: TRUNCATE is faster but not transactional
Note: TTL for automatic row expiration (v22.2+)
Note: No DML rate limits
Note: CASCADE on TRUNCATE follows foreign key relationships
