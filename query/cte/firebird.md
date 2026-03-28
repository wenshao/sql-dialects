# Firebird: CTE (2.1+)

> 参考资料:
> - [Firebird SQL Reference](https://firebirdsql.org/en/reference-manuals/)
> - [Firebird Release Notes](https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html)


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

## Recursive CTE (2.1+)

```sql
WITH RECURSIVE nums AS (
    SELECT 1 AS n FROM RDB$DATABASE
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;
```

## Recursive: hierarchy traversal

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

## Recursive: date series generation

```sql
WITH RECURSIVE date_series AS (
    SELECT CAST('2024-01-01' AS DATE) AS d FROM RDB$DATABASE
    UNION ALL
    SELECT d + 1 FROM date_series WHERE d < CAST('2024-01-31' AS DATE)
)
SELECT d FROM date_series;
```

## CTE + INSERT

```sql
WITH vip_users AS (
    SELECT id, username, email FROM users
    WHERE id IN (SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000)
)
INSERT INTO vip_list SELECT * FROM vip_users;
```

## CTE + UPDATE (3.0+)

```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
UPDATE users SET status = 0 WHERE id IN (SELECT id FROM inactive);
```

## CTE + DELETE (3.0+)

```sql
WITH old_records AS (
    SELECT id FROM users WHERE created_at < '2020-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM old_records);
```

## CTE in EXECUTE BLOCK

```sql
SET TERM !! ;
EXECUTE BLOCK
RETURNS (username VARCHAR(64), total_orders INTEGER)
AS
BEGIN
    FOR
        WITH user_stats AS (
            SELECT u.username, COUNT(o.order_id) AS cnt
            FROM users u
            LEFT JOIN orders o ON u.id = o.user_id
            GROUP BY u.username
        )
        SELECT username, cnt FROM user_stats WHERE cnt > 5
        INTO :username, :total_orders
    DO SUSPEND;
END!!
SET TERM ; !!
```

Note: CTEs added in Firebird 2.1
Note: recursive CTEs supported since 2.1
Note: writable CTEs (CTE + DML) supported since 3.0
Note: RDB$DATABASE is the single-row system table for base case
