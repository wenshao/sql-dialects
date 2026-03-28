# Teradata: UPSERT

> 参考资料:
> - [Teradata SQL Reference](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates)
> - [Teradata Database Documentation](https://docs.teradata.com/)


MERGE (SQL standard, primary upsert mechanism)
```sql
MERGE INTO users AS t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age) AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);
```


MERGE with source table
```sql
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age, t.updated_at = CURRENT_TIMESTAMP
WHEN NOT MATCHED THEN
    INSERT (id, username, email, age) VALUES (s.id, s.username, s.email, s.age);
```


MERGE with conditional update
```sql
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED AND s.age > t.age THEN
    UPDATE SET t.age = s.age
WHEN MATCHED AND s.age <= t.age THEN
    DELETE
WHEN NOT MATCHED THEN
    INSERT (id, username, email, age) VALUES (s.id, s.username, s.email, s.age);
```


MERGE with aggregated source
```sql
MERGE INTO city_stats AS t
USING (
    SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
    FROM users GROUP BY city
) AS s
ON t.city = s.city
WHEN MATCHED THEN
    UPDATE SET cnt = s.cnt, avg_age = s.avg_age
WHEN NOT MATCHED THEN
    INSERT (city, cnt, avg_age) VALUES (s.city, s.cnt, s.avg_age);
```


Alternative: DELETE + INSERT pattern (common in Teradata ETL)
```sql
DELETE FROM target_table WHERE load_date = CURRENT_DATE;
INSERT INTO target_table
SELECT * FROM staging_table WHERE load_date = CURRENT_DATE;
```


Note: MERGE is a single SQL statement and is atomic
Note: MERGE performs well when PRIMARY INDEX aligns between source and target
Note: for large-scale upserts, consider MultiLoad utility
