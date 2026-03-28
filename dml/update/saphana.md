# SAP HANA: UPDATE

> 参考资料:
> - [SAP HANA SQL Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/)
> - [SAP HANA SQLScript Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/)


## Basic update

```sql
UPDATE users SET age = 26 WHERE username = 'alice';
```

## Multiple columns

```sql
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';
```

## Update with FROM (join update)

```sql
UPDATE users SET status = 1
FROM orders
WHERE users.id = orders.user_id AND orders.amount > 1000;
```

## Subquery update

```sql
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;
```

## Correlated subquery update

```sql
UPDATE users SET total_orders = (
    SELECT COUNT(*) FROM orders WHERE orders.user_id = users.id
);
```

## CASE expression

```sql
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;
```

## Update with subquery in WHERE

```sql
UPDATE users SET status = 2
WHERE id IN (SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000);
```

## Update with hints

```sql
UPDATE users SET age = 26 WHERE username = 'alice'
WITH HINT (USE_OLAP_PLAN);
```

## REPLACE / UPSERT (updates if PK exists, inserts otherwise)

See upsert module for details

```sql
UPSERT users (id, username, email, age)
VALUES (1, 'alice', 'alice@example.com', 26)
WHERE id = 1;
```

## Update using MERGE

```sql
MERGE INTO users AS t
USING (SELECT 'alice' AS username, 26 AS new_age FROM DUMMY) AS s
ON t.username = s.username
WHEN MATCHED THEN UPDATE SET t.age = s.new_age;
```

## Update with CURRENT_TIMESTAMP

```sql
UPDATE users SET updated_at = CURRENT_TIMESTAMP WHERE id = 1;
```

## Note: column store updates go to delta storage first, then merged

MERGE DELTA OF users;  -- manually trigger delta merge if needed
