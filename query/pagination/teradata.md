# Teradata: Pagination

> 参考资料:
> - [Teradata SQL Reference](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates)
> - [Teradata Database Documentation](https://docs.teradata.com/)


TOP (Teradata-specific)
```sql
SELECT TOP 10 * FROM users ORDER BY id;
```


TOP with PERCENT
```sql
SELECT TOP 10 PERCENT * FROM users ORDER BY age DESC;
```


SAMPLE (Teradata-specific: random sample, not ordered)
```sql
SELECT * FROM users SAMPLE 10;         -- 10 rows (random)
SELECT * FROM users SAMPLE 0.1;        -- 10% of rows (random)
```


SAMPLE with SAMPLEID (repeatable)
```sql
SELECT * FROM users SAMPLE 10 RANDOMIZED ALLOCATION;
```


Window function for pagination
```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;
```


QUALIFY for top-N (Teradata-specific)
```sql
SELECT *
FROM users
QUALIFY ROW_NUMBER() OVER (ORDER BY id) BETWEEN 21 AND 30;
```


QUALIFY for top-N per group
```sql
SELECT username, city, age
FROM users
QUALIFY ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) <= 3;
```


Keyset pagination (cursor-based)
```sql
SELECT * FROM users WHERE id > 100 ORDER BY id
QUALIFY ROW_NUMBER() OVER (ORDER BY id) <= 10;
```


SQL standard syntax (Teradata 16.20+)
```sql
SELECT * FROM users ORDER BY id
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;
```


Note: SAMPLE returns random rows, not deterministic
Note: TOP does not support OFFSET directly
Note: QUALIFY + ROW_NUMBER is the idiomatic Teradata pagination
Note: for large offsets, consider keyset/cursor pagination
