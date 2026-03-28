# IBM Db2: UPSERT

> 参考资料:
> - [Db2 SQL Reference](https://www.ibm.com/docs/en/db2/11.5?topic=sql)
> - [Db2 Built-in Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in)


## MERGE (primary upsert mechanism)

```sql
MERGE INTO users AS t
USING (VALUES ('alice', 'alice@example.com', 25)) AS s(username, email, age)
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);
```

## MERGE with source table

```sql
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age, t.updated_at = CURRENT TIMESTAMP
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);
```

## MERGE with conditional update and delete

```sql
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED AND s.status = 0 THEN
    DELETE
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);
```

## MERGE with FINAL TABLE (return affected rows)

```sql
SELECT * FROM FINAL TABLE (
    MERGE INTO users AS t
    USING (VALUES ('alice', 'alice@example.com', 25)) AS s(username, email, age)
    ON t.username = s.username
    WHEN MATCHED THEN
        UPDATE SET email = s.email, age = s.age
    WHEN NOT MATCHED THEN
        INSERT (username, email, age) VALUES (s.username, s.email, s.age)
);
```

## MERGE with multiple source rows

```sql
MERGE INTO users AS t
USING (
    VALUES ('alice', 'alice@example.com', 25),
           ('bob', 'bob@example.com', 30)
) AS s(username, email, age)
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);
```

Note: Db2 MERGE is fully SQL standard compliant
Note: MERGE is atomic (single statement)
Note: MERGE can reference the same table as both source and target
