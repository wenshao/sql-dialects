# DuckDB: CTE 公共表表达式

> 参考资料:
> - [DuckDB - SQL Reference](https://duckdb.org/docs/sql/introduction)
> - [DuckDB - Functions](https://duckdb.org/docs/sql/functions/overview)
> - [DuckDB - Data Types](https://duckdb.org/docs/sql/data_types/overview)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

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
    SELECT id, username, manager_id, 0 AS level,
           username AS path
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1,
           t.path || ' > ' || u.username
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;

```

Recursive: graph traversal with cycle detection
```sql
WITH RECURSIVE search AS (
    SELECT id, username, manager_id, [id] AS path, false AS cycle
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id,
           list_append(s.path, u.id),
           list_contains(s.path, u.id)
    FROM users u JOIN search s ON u.manager_id = s.id
    WHERE NOT s.cycle
)
SELECT * FROM search;

```

CTE + DML (writable CTE)
```sql
WITH deleted AS (
    DELETE FROM users WHERE status = 0 RETURNING *
)
INSERT INTO users_archive SELECT * FROM deleted;

```

CTE + UPDATE
```sql
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users SET status = 2
FROM vip WHERE users.id = vip.user_id;

```

CTE referencing another CTE
```sql
WITH
base AS (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
),
ranked AS (
    SELECT city, cnt, ROW_NUMBER() OVER (ORDER BY cnt DESC) AS rn
    FROM base
)
SELECT * FROM ranked WHERE rn <= 5;

```

CTE with complex types
```sql
WITH user_tags AS (
    SELECT username, UNNEST(tags) AS tag FROM complex_data
)
SELECT tag, COUNT(*) AS cnt FROM user_tags GROUP BY tag;

```

CTE with UNION
```sql
WITH combined AS (
    SELECT username, email FROM users_active
    UNION ALL
    SELECT username, email FROM users_inactive
)
SELECT * FROM combined;

```

Note: DuckDB supports recursive and non-recursive CTEs
Note: Writable CTEs (CTE + INSERT/UPDATE/DELETE) are supported
Note: No MATERIALIZED / NOT MATERIALIZED hints (DuckDB auto-optimizes)
Note: No SEARCH DEPTH/BREADTH FIRST clause
Note: CTEs can reference complex types (LIST, STRUCT, MAP)
Note: DuckDB optimizes CTEs by inlining when beneficial
