# Hologres: 条件函数

Hologres 兼容 PostgreSQL 条件函数

> 参考资料:
> - [Hologres - Conditional Functions](https://help.aliyun.com/zh/hologres/user-guide/conditional-functions)
> - [Hologres Built-in Functions](https://help.aliyun.com/zh/hologres/user-guide/built-in-functions)


## CASE WHEN

```sql
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;
```

## 简单 CASE

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

## GREATEST / LEAST

```sql
SELECT GREATEST(1, 3, 2);                                -- 3
SELECT LEAST(1, 3, 2);                                   -- 1
```

## 类型转换

```sql
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;                                   -- :: 转换语法
SELECT '2024-01-15'::DATE;
SELECT CAST('true' AS BOOLEAN);
```

## 注意：没有 TRY_CAST / SAFE_CAST

可以用正则判断后再转换

```sql
SELECT CASE WHEN '123a' ~ '^\d+$' THEN '123a'::INTEGER ELSE NULL END;
```

## IS 判断

```sql
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;
```

## DISTINCT FROM（NULL 安全比较，PostgreSQL 语法）

```sql
SELECT * FROM users WHERE phone IS DISTINCT FROM 'unknown';
SELECT * FROM users WHERE phone IS NOT DISTINCT FROM NULL;
```

## IN

```sql
SELECT * FROM users WHERE city IN ('Beijing', 'Shanghai');
SELECT * FROM users WHERE city NOT IN ('Beijing', 'Shanghai');
```

## BETWEEN

```sql
SELECT * FROM orders WHERE amount BETWEEN 100 AND 1000;
```

## 布尔条件表达式

```sql
SELECT username, (age >= 18) AS is_adult FROM users;
```

注意：与 PostgreSQL 条件函数基本一致
注意：支持 :: 转换语法
注意：IS DISTINCT FROM 是 NULL 安全比较
注意：不支持 IF 函数（使用 CASE WHEN）
注意：不支持 DECODE 函数（使用 CASE WHEN）
注意：不支持 NVL / IFNULL（使用 COALESCE）
注意：不支持 num_nulls / num_nonnulls
