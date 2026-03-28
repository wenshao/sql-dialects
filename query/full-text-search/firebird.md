# Firebird: Full-Text Search

> 参考资料:
> - [Firebird SQL Reference](https://firebirdsql.org/en/reference-manuals/)
> - [Firebird Release Notes](https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html)


Firebird does not have built-in full-text search
Options: LIKE, SIMILAR TO, CONTAINING, or external libraries
CONTAINING (Firebird-specific: case-insensitive substring match)

```sql
SELECT * FROM articles WHERE content CONTAINING 'database';
```

## CONTAINING is case-insensitive (unlike LIKE)

```sql
SELECT * FROM articles WHERE title CONTAINING 'Database';  -- matches 'database', 'DATABASE', etc.
```

## LIKE (case-sensitive pattern matching)

```sql
SELECT * FROM articles WHERE content LIKE '%database%';
```

## LIKE with wildcards

```sql
SELECT * FROM articles WHERE title LIKE 'SQL%';     -- starts with SQL
SELECT * FROM articles WHERE title LIKE '%Guide';    -- ends with Guide
SELECT * FROM articles WHERE title LIKE '_QL%';      -- second and third chars are 'QL'
```

## SIMILAR TO (SQL standard regex, 2.5+)

```sql
SELECT * FROM articles
WHERE content SIMILAR TO '%database[[:space:]]+(performance|tuning)%';
```

## SIMILAR TO regex patterns

```sql
SELECT * FROM articles
WHERE title SIMILAR TO '[A-Z]%';  -- starts with uppercase letter
```

## STARTING WITH (prefix match, uses index if available)

```sql
SELECT * FROM articles WHERE title STARTING WITH 'SQL';
```

## Multiple conditions for pseudo-full-text search

```sql
SELECT * FROM articles
WHERE content CONTAINING 'database'
  AND content CONTAINING 'performance';
```

## Manual relevance scoring with CASE

```sql
SELECT title,
    (CASE WHEN title CONTAINING 'database' THEN 2 ELSE 0 END +
     CASE WHEN content CONTAINING 'database' THEN 1 ELSE 0 END) AS relevance
FROM articles
WHERE title CONTAINING 'database'
   OR content CONTAINING 'database'
ORDER BY relevance DESC;
```

Using UDF for full-text (external library approach)
Third-party solutions like Lucene can be integrated via UDF
Note: CONTAINING is unique to Firebird (case-insensitive substring)
Note: SIMILAR TO supports SQL standard regular expressions
Note: STARTING WITH can use indexes efficiently
Note: for serious full-text search, consider external search engines
Note: Firebird does not support REGEXP_LIKE; use SIMILAR TO instead
