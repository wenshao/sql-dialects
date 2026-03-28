# IBM Db2: CTE (Common Table Expressions)

> 参考资料:
> - [Db2 SQL Reference](https://www.ibm.com/docs/en/db2/11.5?topic=sql)
> - [Db2 Built-in Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in)


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

## Recursive CTE (Db2 was an early adopter)

```sql
WITH nums (n) AS (
    VALUES 1
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;
```

## Recursive: hierarchy traversal

```sql
WITH org_tree (id, username, manager_id, lvl, path) AS (
    SELECT id, username, manager_id, 0,
           CAST(username AS VARCHAR(1000))
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
WITH new_vips AS (
    SELECT id, username, email FROM users
    WHERE id IN (SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000)
)
INSERT INTO vip_list SELECT * FROM new_vips;
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

## CTE with data change (return modified rows)

```sql
WITH updated AS (
    SELECT id, username, age FROM FINAL TABLE (
        UPDATE users SET age = age + 1 WHERE status = 1
    )
)
SELECT * FROM updated;
```

## Recursive: bill of materials

```sql
WITH bom (part_id, sub_part_id, quantity, lvl) AS (
    SELECT part_id, sub_part_id, quantity, 1
    FROM parts WHERE part_id = 'ASSEMBLY_A'
    UNION ALL
    SELECT p.part_id, p.sub_part_id, p.quantity, b.lvl + 1
    FROM parts p JOIN bom b ON p.part_id = b.sub_part_id
)
SELECT * FROM bom;
```

Note: Db2 was one of the first databases to support recursive queries
Note: Db2 uses VALUES for single-row base case (not SELECT ... FROM SYSIBM.SYSDUMMY1)
Note: no MATERIALIZED/NOT MATERIALIZED hints
