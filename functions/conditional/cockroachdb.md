# CockroachDB: 条件函数

> 参考资料:
> - [CockroachDB - SQL Statements](https://www.cockroachlabs.com/docs/stable/sql-statements)
> - [CockroachDB - Functions and Operators](https://www.cockroachlabs.com/docs/stable/functions-and-operators)
> - [CockroachDB - Data Types](https://www.cockroachlabs.com/docs/stable/data-types)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

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
SELECT NULLIF(age, 0) FROM users;              -- returns NULL if age = 0

```

GREATEST / LEAST
```sql
SELECT GREATEST(1, 3, 2);                      -- 3
SELECT LEAST(1, 3, 2);                         -- 1

```

Type casting (PostgreSQL syntax)
```sql
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;                          -- :: syntax
SELECT '2024-01-15'::DATE;
SELECT CAST('true' AS BOOLEAN);

```

IF (CockroachDB-specific function, not in PostgreSQL)
```sql
SELECT IF(age >= 18, 'adult', 'minor') FROM users;
```

Same as: CASE WHEN age >= 18 THEN 'adult' ELSE 'minor' END

IFNULL (CockroachDB-specific, same as COALESCE with 2 args)
```sql
SELECT IFNULL(phone, 'N/A') FROM users;
```

Same as: COALESCE(phone, 'N/A')

NVL (CockroachDB-specific alias for IFNULL)
```sql
SELECT NVL(phone, 'N/A') FROM users;

```

Boolean expression as value (same as PostgreSQL)
```sql
SELECT username, (age >= 18) AS is_adult FROM users;

```

IS DISTINCT FROM (NULL-safe comparison)
```sql
SELECT * FROM users WHERE phone IS DISTINCT FROM 'unknown';
SELECT * FROM users WHERE phone IS NOT DISTINCT FROM NULL;

```

num_nulls / num_nonnulls
```sql
SELECT num_nulls(phone, email, city) FROM users;
SELECT num_nonnulls(phone, email, city) FROM users;

```

IFERROR (CockroachDB-specific)
SELECT IFERROR(1/0, -1);  -- returns -1 instead of error

ISERROR (CockroachDB-specific)
SELECT ISERROR(1/0);  -- returns TRUE

Note: IF(), IFNULL(), NVL() are CockroachDB-specific
Note: :: casting syntax supported (PostgreSQL-compatible)
Note: IS DISTINCT FROM for NULL-safe comparisons
Note: GREATEST/LEAST return NULL if any argument is NULL
Note: No TRY_CAST (use conditional logic)
