# Teradata: CTE

> 参考资料:
> - [Teradata SQL Reference](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates)
> - [Teradata Database Documentation](https://docs.teradata.com/)


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
WITH RECURSIVE nums (n) AS (
    SELECT 1
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;
```


Recursive: hierarchy traversal
```sql
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id, 0 AS lvl,
           CAST(username AS VARCHAR(1000)) AS path
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.lvl + 1,
           t.path || ' > ' || u.username
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;
```


CTE + QUALIFY (Teradata-specific combination)
```sql
WITH ranked_users AS (
    SELECT username, city, age,
        RANK() OVER (PARTITION BY city ORDER BY age DESC) AS rnk
    FROM users
)
SELECT * FROM ranked_users
QUALIFY rnk <= 3;
```


CTE + INSERT
```sql
WITH vip_users AS (
    SELECT id, username, email FROM users
    WHERE id IN (SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000)
)
INSERT INTO vip_list SELECT * FROM vip_users;
```


CTE + UPDATE
```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < DATE '2023-01-01'
)
UPDATE users SET status = 0 WHERE id IN (SELECT id FROM inactive);
```


CTE + DELETE
```sql
WITH old_records AS (
    SELECT id FROM users WHERE created_at < DATE '2020-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM old_records);
```


Note: Teradata supports recursive CTEs
Note: CTEs can be combined with QUALIFY clause
Note: no MATERIALIZED/NOT MATERIALIZED hints
