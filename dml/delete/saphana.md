# SAP HANA: DELETE

> 参考资料:
> - [SAP HANA SQL Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/)
> - [SAP HANA SQLScript Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/)


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

## Delete with join (using subquery)

```sql
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist WHERE blacklist.email = users.email);
```

## Delete all rows

```sql
DELETE FROM users;
```

## TRUNCATE (faster than DELETE, DDL operation)

```sql
TRUNCATE TABLE users;
```

## Delete with hints

```sql
DELETE FROM users WHERE status = 0
WITH HINT (USE_OLAP_PLAN);
```

## Archive then delete

```sql
INSERT INTO users_archive SELECT * FROM users WHERE status = 0;
DELETE FROM users WHERE status = 0;
```

## Delete using subquery with aggregation

```sql
DELETE FROM users
WHERE id IN (
    SELECT user_id FROM orders
    GROUP BY user_id
    HAVING COUNT(*) = 0
);
```

## Delete from history table (system-versioned)

Cannot directly delete from history; must drop versioning first

```sql
ALTER TABLE employees DROP SYSTEM VERSIONING;
DELETE FROM employees_history WHERE valid_to < ADD_DAYS(CURRENT_TIMESTAMP, -365);
ALTER TABLE employees ADD SYSTEM VERSIONING;
```

Note: column store deletes mark rows in delta storage
Actual removal happens during delta merge
MERGE DELTA OF users;  -- trigger manual delta merge
Note: SAP HANA does not support RETURNING on DELETE
Note: for large deletes, consider batch processing to avoid memory pressure
