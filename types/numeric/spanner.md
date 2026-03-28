# Spanner: 数值类型

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

```sql
CREATE TABLE Examples (
    Id         INT64 NOT NULL,
    SmallVal   INT64,                          -- only integer type
    Price      NUMERIC,                        -- exact: 29.9 precision
    Ratio      FLOAT64,                        -- approximate
    RatioSmall FLOAT32,                        -- 4-byte float (2023+)
    Active     BOOL DEFAULT (true)
) PRIMARY KEY (Id);

```

Note: No INT, INTEGER, SMALLINT, TINYINT, BIGINT
INT64 is the only integer type
Note: No DECIMAL / NUMERIC(P,S) with precision parameters

Type casting
```sql
SELECT CAST('123' AS INT64);
SELECT CAST('3.14' AS FLOAT64);
SELECT CAST('3.14' AS NUMERIC);
SELECT SAFE_CAST('abc' AS INT64);              -- returns NULL on failure

```

Special values
```sql
SELECT CAST('nan' AS FLOAT64);                 -- NaN
SELECT CAST('inf' AS FLOAT64);                 -- Infinity
SELECT IEEE_DIVIDE(1, 0);                      -- Infinity
SELECT IEEE_DIVIDE(0, 0);                      -- NaN

```

Boolean
```sql
SELECT CAST(1 AS BOOL);                        -- TRUE
SELECT CAST(0 AS BOOL);                        -- FALSE

```

Math functions
```sql
SELECT ABS(-5);                                -- 5
SELECT MOD(10, 3);                             -- 1
SELECT ROUND(3.14159, 2);                      -- 3.14
SELECT TRUNC(3.14159, 2);                      -- 3.14
SELECT CEIL(3.14);                             -- 4
SELECT FLOOR(3.14);                            -- 3
SELECT POWER(2, 10);                           -- 1024
SELECT SQRT(16.0);                             -- 4.0
SELECT LOG(100.0);                             -- ~4.605 (natural log)
SELECT LOG10(100.0);                           -- 2.0
SELECT SIGN(-5);                               -- -1
SELECT DIV(10, 3);                             -- 3 (integer division)

```

Generating unique IDs
```sql
SELECT GENERATE_UUID();                        -- returns STRING (UUID v4)

```

Bit-reversed sequences (for sequential-yet-distributed IDs)
CREATE SEQUENCE MySeq OPTIONS (sequence_kind = 'bit_reversed_positive');
SELECT GET_NEXT_SEQUENCE_VALUE(SEQUENCE MySeq);

Note: INT64 is the only integer type (no smaller variants)
Note: NUMERIC has fixed precision (29 digits before, 9 after decimal)
Note: No NUMERIC(P,S) parameterized form
Note: No SERIAL / AUTO_INCREMENT
Note: No MONEY, UNSIGNED, or BIT types
Note: SAFE_CAST returns NULL on failure (very useful)
Note: IEEE_DIVIDE handles division by zero gracefully
Note: Use GENERATE_UUID() for unique string IDs
