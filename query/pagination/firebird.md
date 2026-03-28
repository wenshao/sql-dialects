# Firebird: Pagination

> 参考资料:
> - [Firebird SQL Reference](https://firebirdsql.org/en/reference-manuals/)
> - [Firebird Release Notes](https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html)


## FIRST / SKIP (Firebird legacy syntax, all versions)

```sql
SELECT FIRST 10 SKIP 20 * FROM users ORDER BY id;
```

## FIRST only

```sql
SELECT FIRST 10 * FROM users ORDER BY id;
```

## SKIP only (skip first N rows)

```sql
SELECT SKIP 20 * FROM users ORDER BY id;
```

## SQL standard syntax (4.0+)

```sql
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;
```

## FETCH FIRST (4.0+)

```sql
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;
```

## FETCH with ties (4.0+, include tied rows)

```sql
SELECT * FROM users ORDER BY age FETCH FIRST 10 ROWS WITH TIES;
```

## Window function for pagination (3.0+)

```sql
SELECT * FROM (
    SELECT u.*, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users u
) t
WHERE t.rn BETWEEN 21 AND 30;
```

## Top-N per group (3.0+)

```sql
SELECT * FROM (
    SELECT username, city, age,
        ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE t.rn <= 3;
```

## Keyset pagination (cursor-based)

```sql
SELECT FIRST 10 * FROM users WHERE id > 100 ORDER BY id;
SELECT * FROM users WHERE id > 100 ORDER BY id FETCH FIRST 10 ROWS ONLY;
```

## ROWS clause on DELETE (paginated delete, 2.0+)

```sql
DELETE FROM logs ORDER BY created_at ROWS 1000;
```

Note: FIRST/SKIP is Firebird's original syntax (before SQL standard OFFSET/FETCH)
Note: FIRST/SKIP appear between SELECT and column list
Note: 4.0+ supports both syntaxes; OFFSET/FETCH is preferred for new code
Note: FIRST/SKIP work with parameters: SELECT FIRST ? SKIP ? * FROM users
