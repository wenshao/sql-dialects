# IBM Db2: DELETE

> 参考资料:
> - [Db2 SQL Reference](https://www.ibm.com/docs/en/db2/11.5?topic=sql)
> - [Db2 Built-in Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in)


## Basic delete

```sql
DELETE FROM users WHERE username = 'alice';
```

## Delete with subquery

```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);
```

## Correlated subquery delete

```sql
DELETE FROM users
WHERE NOT EXISTS (SELECT 1 FROM orders WHERE orders.user_id = users.id);
```

## Return deleted rows (Db2 specific: SELECT FROM OLD TABLE)

```sql
SELECT * FROM OLD TABLE (
    DELETE FROM users WHERE status = 0
);
```

## CTE + DELETE

```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);
```

## Archive then delete using data change statement

```sql
INSERT INTO users_archive
SELECT * FROM OLD TABLE (
    DELETE FROM users WHERE status = 0
);
```

## Delete all rows

```sql
DELETE FROM users;
```

## TRUNCATE (Db2 9.7+)

```sql
TRUNCATE TABLE users IMMEDIATE;
TRUNCATE TABLE users REUSE STORAGE IMMEDIATE;
TRUNCATE TABLE users DROP STORAGE IMMEDIATE;
```

## TRUNCATE with identity restart

```sql
TRUNCATE TABLE users RESTART IDENTITY IMMEDIATE;
```

## Delete with isolation level

```sql
DELETE FROM users WHERE status = 0 WITH CS;
```

Positioned delete (cursor-based, in stored procedure)
DELETE FROM users WHERE CURRENT OF cursor_name;
After large deletes

```sql
REORG TABLE users;
RUNSTATS ON TABLE schema.users WITH DISTRIBUTION AND DETAILED INDEXES ALL;
```
