# Teradata: Conditional Functions

> 参考资料:
> - [Teradata SQL Reference](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates)
> - [Teradata Database Documentation](https://docs.teradata.com/)


CASE WHEN
```sql
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;
```


Simple CASE
```sql
SELECT username,
    CASE status
        WHEN 0 THEN 'inactive'
        WHEN 1 THEN 'active'
        WHEN 2 THEN 'deleted'
        ELSE 'unknown'
    END AS status_name
FROM users;
```


COALESCE
```sql
SELECT COALESCE(phone, email, 'unknown') FROM users;
```


NULLIF
```sql
SELECT NULLIF(age, 0) FROM users;
```


NULLIFZERO (Teradata-specific: return NULL if zero)
```sql
SELECT NULLIFZERO(age) FROM users;
```


ZEROIFNULL (Teradata-specific: return 0 if NULL)
```sql
SELECT ZEROIFNULL(age) FROM users;
```


NVL (Oracle-compatible, similar to COALESCE but two args)
```sql
SELECT NVL(phone, 'N/A') FROM users;
```


NVL2 (Oracle-compatible: different values for NULL/NOT NULL)
```sql
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;
```


GREATEST / LEAST (14.10+)
```sql
SELECT GREATEST(1, 3, 2);                                  -- 3
SELECT LEAST(1, 3, 2);                                     -- 1
```


Type casting
```sql
SELECT CAST('123' AS INTEGER);
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST(123 AS VARCHAR(10));
```


TRYCAST (16.20+, returns NULL instead of error)
```sql
SELECT TRYCAST('abc' AS INTEGER);  -- NULL instead of error
```


DECODE (Oracle-compatible, Teradata 14.10+)
```sql
SELECT DECODE(status, 0, 'inactive', 1, 'active', 2, 'deleted', 'unknown') FROM users;
```


QUALIFY + conditional (unique to Teradata)
```sql
SELECT username, age
FROM users
QUALIFY RANK() OVER (ORDER BY age DESC) <= 10;
```


IS [NOT] NULL
```sql
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;
```


Nested CASE
```sql
SELECT username,
    CASE
        WHEN age IS NULL THEN 'unknown age'
        WHEN age < 18 THEN
            CASE status WHEN 1 THEN 'active minor' ELSE 'inactive minor' END
        ELSE 'adult'
    END AS description
FROM users;
```


Note: NULLIFZERO / ZEROIFNULL are Teradata-specific
Note: NVL / NVL2 are Teradata-specific (Oracle-compatible)
Note: DECODE is Oracle-compatible shorthand for CASE
Note: no BOOLEAN type; use BYTEINT or CASE expressions
