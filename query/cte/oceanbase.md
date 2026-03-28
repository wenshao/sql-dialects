# OceanBase: CTE 公共表表达式

> 参考资料:
> - [OceanBase SQL Reference (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase SQL Reference (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL Mode (same as MySQL 8.0)


Basic CTE
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

Recursive hierarchy
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

CTE with DML
```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

```

## Oracle Mode


Basic CTE (Oracle-style, no RECURSIVE keyword)
```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;

```

Recursive CTE (Oracle mode: no RECURSIVE keyword needed)
```sql
WITH org_tree (id, username, manager_id, lvl) AS (
    SELECT id, username, manager_id, 0 AS lvl
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.lvl + 1
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;

```

Oracle CONNECT BY (legacy hierarchical query, Oracle mode)
```sql
SELECT id, username, manager_id, LEVEL
FROM users
START WITH manager_id IS NULL
CONNECT BY PRIOR id = manager_id
ORDER SIBLINGS BY username;

```

CONNECT BY with SYS_CONNECT_BY_PATH
```sql
SELECT id, username,
    SYS_CONNECT_BY_PATH(username, '/') AS path,
    CONNECT_BY_ROOT username AS root_user,
    CONNECT_BY_ISLEAF AS is_leaf
FROM users
START WITH manager_id IS NULL
CONNECT BY PRIOR id = manager_id;

```

Oracle-mode CTE with column aliases
```sql
WITH user_stats (uid, order_count, total_amount) AS (
    SELECT user_id, COUNT(*), SUM(amount)
    FROM orders GROUP BY user_id
)
SELECT * FROM user_stats WHERE order_count > 5;

```

CTE with DML (Oracle mode)
```sql
WITH inactive AS (
    SELECT id FROM users WHERE status = 0
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

```

Subquery factoring (WITH clause used in subqueries, Oracle mode)
```sql
SELECT * FROM (
    WITH ranked AS (
        SELECT username, age, ROW_NUMBER() OVER (ORDER BY age DESC) AS rn
        FROM users
    )
    SELECT * FROM ranked WHERE rn <= 10
);

```

Limitations:
MySQL mode: standard MySQL 8.0 CTE behavior
Oracle mode: CONNECT BY supported for legacy hierarchical queries
Oracle mode: RECURSIVE keyword not required (auto-detected)
Recursion depth limits apply (configurable)
CTE materialization supported in both modes
