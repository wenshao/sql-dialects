# MySQL: 条件函数

> 参考资料:
> - [MySQL 8.0 Reference Manual - Flow Control Functions](https://dev.mysql.com/doc/refman/8.0/en/flow-control-functions.html)
> - [MySQL 8.0 Reference Manual - CASE Expression](https://dev.mysql.com/doc/refman/8.0/en/flow-control-functions.html#operator_case)

CASE WHEN（SQL 标准）
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

IF（MySQL 特有）
```sql
SELECT username, IF(age >= 18, 'adult', 'minor') AS category FROM users;
```

IFNULL（两参数，NULL 替换）
```sql
SELECT IFNULL(phone, 'N/A') FROM users;
```

COALESCE（SQL 标准，返回第一个非 NULL 值）
```sql
SELECT COALESCE(phone, email, 'unknown') FROM users;
```

NULLIF（两值相等返回 NULL）
```sql
SELECT NULLIF(age, 0) FROM users;                       -- age=0 时返回 NULL

-- 类型转换
SELECT CAST('123' AS SIGNED);
SELECT CAST('2024-01-15' AS DATE);
SELECT CONVERT('123', SIGNED);                          -- MySQL 特有语法
```

8.0.17+: CAST 支持 ARRAY
```sql
SELECT CAST(data->'$.tags' AS CHAR ARRAY);
```

ELT（按位置返回字符串）
```sql
SELECT ELT(2, 'a', 'b', 'c');                          -- 'b'

-- FIELD（返回值的位置）
SELECT FIELD('b', 'a', 'b', 'c');                       -- 2

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                               -- 3
SELECT LEAST(1, 3, 2);                                  -- 1

-- ISNULL（判断是否为 NULL，返回 0 或 1）
SELECT ISNULL(phone) FROM users;                        -- 注意：和 SQL Server 的 ISNULL 不同！
```
