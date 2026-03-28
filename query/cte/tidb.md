# TiDB: CTE 公共表表达式

> 参考资料:
> - [TiDB SQL Reference](https://docs.pingcap.com/tidb/stable/sql-statement-overview)
> - [TiDB - MySQL Compatibility](https://docs.pingcap.com/tidb/stable/mysql-compatibility)
> - [TiDB - Functions and Operators](https://docs.pingcap.com/tidb/stable/functions-and-operators-overview)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;

```

Multiple CTEs (same as MySQL 8.0)
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

Recursive CTE (same as MySQL 8.0)
```sql
WITH RECURSIVE nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;

```

Recursive: hierarchy traversal (same as MySQL 8.0)
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

CTE with DML (same as MySQL 8.0)
```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

```

Recursion depth limit
Default: cte_max_recursion_depth = 1000 (same as MySQL)
```sql
SET cte_max_recursion_depth = 5000;

```

CTE merge optimization
TiDB may merge CTE into the outer query or materialize it
Use hints to control behavior

TiDB-specific: CTE inline hint (7.0+)
```sql
WITH active_users AS (
    SELECT /*+ MERGE() */ * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;
```

MERGE(): inline the CTE into the outer query (avoid materialization)

Non-recursive CTE is referenced multiple times: TiDB may materialize it
```sql
WITH user_stats AS (
    SELECT user_id, COUNT(*) AS cnt FROM orders GROUP BY user_id
)
SELECT * FROM user_stats WHERE cnt > 5
UNION ALL
SELECT * FROM user_stats WHERE cnt <= 5;
```

TiDB evaluates the CTE once and reuses the result

CTE in TiFlash MPP mode
CTEs in analytical queries can be pushed down to TiFlash
```sql
SELECT /*+ READ_FROM_STORAGE(TIFLASH[users, orders]) */
    city, total
FROM (
    WITH city_totals AS (
        SELECT u.city, SUM(o.amount) AS total
        FROM users u JOIN orders o ON u.id = o.user_id
        GROUP BY u.city
    )
    SELECT * FROM city_totals WHERE total > 10000
) t;

```

Limitations:
Same recursion depth limits as MySQL
CTE materialization may use significant memory for large results
Recursive CTEs cannot use aggregate functions in recursive part
CTE cannot reference itself in a non-recursive CTE
