# Firebird: Conditional Functions

> 参考资料:
> - [Firebird SQL Reference](https://firebirdsql.org/en/reference-manuals/)
> - [Firebird Release Notes](https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html)
> - CASE WHEN

```sql
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;
```

## Simple CASE

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

## COALESCE

```sql
SELECT COALESCE(phone, email, 'unknown') FROM users;
```

## NULLIF

```sql
SELECT NULLIF(age, 0) FROM users;
```

## IIF (Firebird-specific: inline if, 2.0+)

```sql
SELECT IIF(age >= 18, 'adult', 'minor') FROM users;
SELECT IIF(status = 1, 'active', IIF(status = 0, 'inactive', 'deleted')) FROM users;
```

## DECODE (2.1+, Oracle-compatible)

```sql
SELECT DECODE(status, 0, 'inactive', 1, 'active', 2, 'deleted', 'unknown') FROM users;
```

## MAXVALUE / MINVALUE (Firebird-specific: like GREATEST/LEAST, 2.1+)

```sql
SELECT MAXVALUE(1, 3, 2) FROM RDB$DATABASE;                -- 3
SELECT MINVALUE(1, 3, 2) FROM RDB$DATABASE;                -- 1
SELECT MAXVALUE(a, b, c) FROM table1;
```

## Type casting

```sql
SELECT CAST('123' AS INTEGER) FROM RDB$DATABASE;
SELECT CAST('2024-01-15' AS DATE) FROM RDB$DATABASE;
SELECT CAST(123 AS VARCHAR(10)) FROM RDB$DATABASE;
```

## Boolean expressions (3.0+)

```sql
SELECT username, (age >= 18) AS is_adult FROM users;
```

## IS [NOT] NULL

```sql
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;
```

## BETWEEN

```sql
SELECT * FROM users WHERE age BETWEEN 18 AND 65;
```

## IN

```sql
SELECT * FROM users WHERE status IN (1, 2, 3);
```

## IS [NOT] DISTINCT FROM (4.0+)

```sql
SELECT * FROM users WHERE phone IS DISTINCT FROM 'unknown';
SELECT * FROM users WHERE phone IS NOT DISTINCT FROM NULL;   -- same as IS NULL
```

## SIMILAR TO (regex conditional, 2.5+)

```sql
SELECT CASE WHEN email SIMILAR TO '%@%.%' THEN 'valid' ELSE 'invalid' END
FROM users;
```

## Nested CASE

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

## GEN_UUID (generate UUID, 2.1+)

```sql
SELECT GEN_UUID() FROM RDB$DATABASE;
```

Note: IIF is Firebird-specific inline if (more concise than CASE)
Note: MAXVALUE/MINVALUE are Firebird's GREATEST/LEAST equivalents
Note: DECODE added in 2.1 for Oracle compatibility
Note: no GREATEST/LEAST keywords; use MAXVALUE/MINVALUE
Note: RDB$DATABASE is the single-row system table
