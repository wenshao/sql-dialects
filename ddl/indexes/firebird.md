# Firebird: Indexes

> 参考资料:
> - [Firebird SQL Reference](https://firebirdsql.org/en/reference-manuals/)
> - [Firebird Release Notes](https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html)


## Basic index (ascending, default)

```sql
CREATE INDEX idx_age ON users (age);
```

## Unique index

```sql
CREATE UNIQUE INDEX uk_email ON users (email);
```

## Composite index

```sql
CREATE INDEX idx_city_age ON users (city, age);
```

## Descending index

```sql
CREATE DESCENDING INDEX idx_age_desc ON users (age);
```

## Ascending index (explicit)

```sql
CREATE ASCENDING INDEX idx_age_asc ON users (age);
```

## Expression index (3.0+)

```sql
CREATE INDEX idx_lower_email ON users (LOWER(email));
CREATE INDEX idx_year ON events (EXTRACT(YEAR FROM created_at));
```

## Partial index (5.0+)

```sql
CREATE INDEX idx_active ON users (username) WHERE status = 1;
```

Computed column index
First create computed column, then index references it automatically
Or index the expression directly (3.0+)
PLAN clause (view query plan to verify index usage)

```sql
SELECT * FROM users
WHERE age > 25
PLAN (users INDEX (idx_age));
```

## Drop index

```sql
DROP INDEX idx_age;
```

## Recreate index (atomically drop and recreate)

Note: no built-in REINDEX; use SET STATISTICS or recreate

```sql
ALTER INDEX idx_age ACTIVE;
ALTER INDEX idx_age INACTIVE;
```

## Deactivate/reactivate index (useful during bulk loads)

```sql
ALTER INDEX idx_city_age INACTIVE;
ALTER INDEX idx_city_age ACTIVE;
```

## Set index statistics (selectivity)

```sql
SET STATISTICS INDEX idx_age;
```

## View indexes

```sql
SELECT * FROM RDB$INDICES WHERE RDB$RELATION_NAME = 'USERS';
SELECT i.RDB$INDEX_NAME, s.RDB$FIELD_NAME
FROM RDB$INDICES i
JOIN RDB$INDEX_SEGMENTS s ON i.RDB$INDEX_NAME = s.RDB$INDEX_NAME
WHERE i.RDB$RELATION_NAME = 'USERS';
```

Note: maximum 1 index on a set of columns in the same order
Note: maximum key size is limited by page size (e.g., ~1/4 of page size)
Note: indexes are automatically created for PRIMARY KEY and UNIQUE constraints
Note: foreign key columns should be manually indexed for performance
