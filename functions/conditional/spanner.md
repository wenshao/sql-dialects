# Spanner: 条件函数

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

```sql
SELECT Username,
    CASE
        WHEN Age < 18 THEN 'minor'
        WHEN Age < 65 THEN 'adult'
        ELSE 'senior'
    END AS Category
FROM Users;

```

Simple CASE
```sql
SELECT Username,
    CASE Status
        WHEN 0 THEN 'inactive'
        WHEN 1 THEN 'active'
        WHEN 2 THEN 'deleted'
        ELSE 'unknown'
    END AS StatusName
FROM Users;

```

COALESCE
```sql
SELECT COALESCE(Phone, Email, 'unknown') FROM Users;

```

NULLIF
```sql
SELECT NULLIF(Age, 0) FROM Users;              -- returns NULL if Age = 0

```

IFNULL (Spanner-specific, like COALESCE with 2 args)
```sql
SELECT IFNULL(Phone, 'N/A') FROM Users;

```

IF (Spanner-specific, concise conditional)
```sql
SELECT IF(Age >= 18, 'adult', 'minor') FROM Users;

```

IFF (alias for IF)
```sql
SELECT IFF(Age >= 18, 'adult', 'minor') FROM Users;

```

GREATEST / LEAST
```sql
SELECT GREATEST(1, 3, 2);                      -- 3
SELECT LEAST(1, 3, 2);                         -- 1

```

Type casting
```sql
SELECT CAST('123' AS INT64);
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('true' AS BOOL);
SELECT SAFE_CAST('abc' AS INT64);              -- returns NULL on failure

```

SAFE_CAST (Spanner-specific, returns NULL instead of error)
```sql
SELECT SAFE_CAST('not_a_number' AS INT64);     -- NULL
SELECT SAFE_CAST('not_a_date' AS DATE);        -- NULL
SELECT SAFE_CAST(NULL AS STRING);              -- NULL

```

SAFE prefix for functions (returns NULL instead of error)
```sql
SELECT SAFE_DIVIDE(1, 0);                      -- NULL instead of error
SELECT SAFE_ADD(9223372036854775807, 1);       -- NULL instead of overflow

```

Boolean expressions
```sql
SELECT Username, (Age >= 18) AS IsAdult FROM Users;

```

IS DISTINCT FROM
```sql
SELECT * FROM Users WHERE Phone IS DISTINCT FROM 'unknown';
SELECT * FROM Users WHERE Phone IS NOT DISTINCT FROM NULL;

```

STRUCT conditionals
```sql
SELECT
    CASE WHEN Age < 18 THEN STRUCT('minor' AS category, FALSE AS allowed)
         ELSE STRUCT('adult' AS category, TRUE AS allowed)
    END AS info
FROM Users;

```

Note: IF() and IFNULL() are built-in (not CASE wrappers)
Note: SAFE_CAST returns NULL on failure (very useful)
Note: SAFE_ prefix available for many functions (SAFE_DIVIDE, etc.)
Note: No :: casting syntax (use CAST or SAFE_CAST)
Note: No num_nulls / num_nonnulls functions
Note: GREATEST/LEAST return NULL if any argument is NULL
