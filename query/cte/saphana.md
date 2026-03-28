# SAP HANA: CTE

> 参考资料:
> - [SAP HANA SQL Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/)
> - [SAP HANA SQLScript Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/)


## Basic CTE

```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;
```

## Multiple CTEs

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

## Recursive CTE

```sql
WITH RECURSIVE nums (n) AS (
    SELECT 1 FROM DUMMY
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;
```

## Recursive: hierarchy traversal

```sql
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id, 0 AS lvl,
           TO_NVARCHAR(username) AS path
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.lvl + 1,
           t.path || ' > ' || u.username
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;
```

## CTE + INSERT

```sql
WITH vip_users AS (
    SELECT id, username, email FROM users
    WHERE id IN (SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000)
)
INSERT INTO vip_list SELECT * FROM vip_users;
```

## CTE + UPDATE

```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
UPDATE users SET status = 0 WHERE id IN (SELECT id FROM inactive);
```

## CTE + DELETE

```sql
WITH old_records AS (
    SELECT id FROM users WHERE created_at < '2020-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM old_records);
```

## CTE with hierarchy functions (SAP HANA-specific)

```sql
WITH dept_tree AS (
    SELECT * FROM HIERARCHY (
        SOURCE departments
        START WHERE parent_id IS NULL
    )
)
SELECT node_id, parent_id, hierarchy_level FROM dept_tree;
```

## Recursive: graph traversal with cycle detection

```sql
WITH RECURSIVE search_graph AS (
    SELECT id, username, manager_id, 0 AS depth,
           TO_NVARCHAR(id) AS path
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, s.depth + 1,
           s.path || ',' || TO_NVARCHAR(u.id)
    FROM users u JOIN search_graph s ON u.manager_id = s.id
    WHERE LOCATE(s.path, TO_NVARCHAR(u.id)) = 0
)
SELECT * FROM search_graph;
```

Note: SAP HANA uses DUMMY instead of DUAL for single-row base case
Note: HIERARCHY function is an alternative to recursive CTEs for tree structures
Note: CTEs are optimized in-memory in SAP HANA
