# BigQuery: 条件函数

> 参考资料:
> - [1] BigQuery SQL Reference - Conditional Expressions
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/conditional_expressions
> - [2] BigQuery SQL Reference - Functions Reference
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/functions-and-operators


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

简单 CASE

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

IF（BigQuery 特有）

```sql
SELECT IF(age >= 18, 'adult', 'minor') FROM users;
SELECT IF(amount > 0, amount, 0) FROM orders;

```

IFNULL（COALESCE 的两参数版本）

```sql
SELECT IFNULL(phone, 'no phone') FROM users;

```

GREATEST / LEAST

```sql
SELECT GREATEST(1, 3, 2);                                -- 3
SELECT LEAST(1, 3, 2);                                   -- 1

```

类型转换

```sql
SELECT CAST('123' AS INT64);
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST(TRUE AS STRING);

```

安全转换（BigQuery 特色）

```sql
SELECT SAFE_CAST('abc' AS INT64);                         -- NULL（不报错）
SELECT SAFE_CAST('2024-13-01' AS DATE);                   -- NULL
SELECT SAFE_CAST('true' AS BOOL);                         -- TRUE

```

安全函数系列

```sql
SELECT SAFE_DIVIDE(10, 0);                                -- NULL（不报错）
SELECT SAFE_MULTIPLY(9999999999, 9999999999);             -- NULL（溢出返回 NULL）
SELECT SAFE_NEGATE(-9223372036854775808);                  -- NULL
SELECT SAFE_ADD(9223372036854775807, 1);                   -- NULL
SELECT SAFE_SUBTRACT(-9223372036854775808, 1);             -- NULL

```

IS 判断

```sql
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;
SELECT * FROM users WHERE TRUE IS TRUE;
SELECT * FROM users WHERE FALSE IS NOT TRUE;

```

IN

```sql
SELECT * FROM users WHERE city IN ('Beijing', 'Shanghai');
SELECT * FROM users WHERE city NOT IN ('Beijing', 'Shanghai');
SELECT * FROM users WHERE city IN UNNEST(['Beijing', 'Shanghai']);  -- 数组

```

BETWEEN

```sql
SELECT * FROM orders WHERE amount BETWEEN 100 AND 1000;

```

注意：IF 函数是 SQL 标准的扩展（BigQuery、MySQL 等支持）
注意：SAFE_CAST 是 BigQuery 的重要特性
注意：SAFE_* 系列函数避免运行时错误
注意：没有 :: 类型转换语法
注意：没有 TRY_CAST（使用 SAFE_CAST）

