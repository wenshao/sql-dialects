# YugabyteDB: CTE 公共表表达式

> 参考资料:
> - [YugabyteDB YSQL Reference](https://docs.yugabyte.com/stable/api/ysql/)
> - [YugabyteDB PostgreSQL Compatibility](https://docs.yugabyte.com/stable/explore/ysql-language-features/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;

```

Multiple CTEs
```sql
WITH
active_users AS (
    SELECT * FROM users WHERE status = 1
),
user_orders AS (
    SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT u.username, o.cnt, o.total
FROM active_users u
JOIN user_orders o ON u.id = o.user_id;

```

CTE referencing previous CTE
```sql
WITH
base AS (SELECT * FROM users WHERE status = 1),
enriched AS (
    SELECT b.*, COUNT(o.id) AS order_count
    FROM base b LEFT JOIN orders o ON b.id = o.user_id
    GROUP BY b.id, b.username, b.status, b.age, b.city
)
SELECT * FROM enriched WHERE order_count > 5;

```

Recursive CTE
```sql
WITH RECURSIVE nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;

```

Recursive: hierarchy traversal
```sql
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id, 0 AS level
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;

```

Recursive: path building with cycle detection
```sql
WITH RECURSIVE paths AS (
    SELECT id, ARRAY[id] AS path, false AS cycle
    FROM nodes WHERE id = 1
    UNION ALL
    SELECT e.target, p.path || e.target, e.target = ANY(p.path)
    FROM paths p JOIN edges e ON p.id = e.source
    WHERE NOT p.cycle
)
SELECT * FROM paths WHERE NOT cycle;

```

CTE + INSERT
```sql
INSERT INTO users_archive
WITH inactive AS (
    SELECT * FROM users WHERE last_login < '2023-01-01'
)
SELECT * FROM inactive;

```

CTE + UPDATE
```sql
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users SET status = 2
FROM vip WHERE users.id = vip.user_id;

```

CTE + DELETE
```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

```

CTE in UPSERT
```sql
WITH new_data AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age
)
INSERT INTO users (username, email, age)
SELECT * FROM new_data
ON CONFLICT (username) DO UPDATE SET email = EXCLUDED.email;

```

Note: Recursive CTEs supported (same as PostgreSQL)
Note: CTEs can be used with INSERT, UPDATE, DELETE
Note: Based on PostgreSQL 11.2 CTE implementation
Note: CTEs are materialized by default (PG 11 behavior)
Note: MATERIALIZED / NOT MATERIALIZED hints not supported (PG 12+ feature)
Note: Recursive CTEs work across distributed tablets
