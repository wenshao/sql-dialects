# SQL 标准: 条件函数

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [Modern SQL - CASE Expression](https://modern-sql.com/feature/case)

SQL-86 (SQL1):
无条件函数（仅有 WHERE 条件和 LIKE）

SQL-92 (SQL2):
CASE WHEN（搜索形式和简单形式）
COALESCE
NULLIF
CAST

CASE WHEN（SQL-92，搜索形式）
```sql
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;
```

CASE（SQL-92，简单形式）
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

COALESCE（SQL-92）
```sql
SELECT COALESCE(phone, email, 'unknown') FROM users;
```

NULLIF（SQL-92）
```sql
SELECT NULLIF(age, 0) FROM users;
```

CAST（SQL-92）
```sql
SELECT CAST('123' AS INTEGER);
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST(123 AS CHARACTER VARYING(10));
```

IS NULL / IS NOT NULL（SQL-92）
```sql
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;
```

IN（SQL-92）
```sql
SELECT * FROM users WHERE city IN ('Beijing', 'Shanghai');
```

BETWEEN（SQL-92）
```sql
SELECT * FROM orders WHERE amount BETWEEN 100 AND 1000;
```

SQL:1999 (SQL3):
IS DISTINCT FROM（NULL 安全比较）
IS NOT DISTINCT FROM
```sql
SELECT * FROM users WHERE phone IS DISTINCT FROM 'unknown';    -- NULL 安全
SELECT * FROM users WHERE phone IS NOT DISTINCT FROM NULL;     -- 等同 IS NULL
```

SQL:2003:
GREATEST / LEAST（部分文档归于此版本）

SQL:2008:
无条件函数重大变化

SQL:2011:
无条件函数重大变化

SQL:2016:
无条件函数重大变化

SQL:2023:
ANY_VALUE（任意值，与聚合中的 ANY_VALUE 一致）

- **注意：标准中没有 IF / IFF 函数（使用 CASE WHEN）**
- **注意：标准中没有 IFNULL / NVL 函数（使用 COALESCE）**
- **注意：标准中没有 DECODE 函数（Oracle 扩展）**
- **注意：标准中没有 TRY_CAST / SAFE_CAST（各厂商扩展）**
- **注意：标准中没有 :: 转换语法（PostgreSQL 扩展）**
- **注意：IS DISTINCT FROM 是标准的 NULL 安全比较方式**
- **注意：CASE WHEN 是标准中最重要的条件表达式**
