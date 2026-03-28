# openGauss/GaussDB: 条件函数

PostgreSQL compatible syntax.

> 参考资料:
> - [openGauss SQL Reference](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html)
> - [GaussDB Documentation](https://support.huaweicloud.com/gaussdb/index.html)


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
SELECT GREATEST(1, 3, 2);                               -- 3
SELECT LEAST(1, 3, 2);                                  -- 1
```

## 类型转换

```sql
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;
SELECT '2024-01-15'::DATE;
SELECT CAST('true' AS BOOLEAN);
```

## DISTINCT FROM（NULL 安全比较）

```sql
SELECT * FROM users WHERE phone IS DISTINCT FROM 'unknown';
SELECT * FROM users WHERE phone IS NOT DISTINCT FROM NULL;
```

## 布尔条件表达式

```sql
SELECT username, (age >= 18) AS is_adult FROM users;
```

## NVL（Oracle 兼容，openGauss 扩展）

```sql
SELECT NVL(phone, 'N/A') FROM users;
```

## NVL2（Oracle 兼容）

```sql
SELECT NVL2(phone, phone, 'N/A') FROM users;
```

## DECODE（Oracle 兼容）

```sql
SELECT DECODE(status, 0, 'inactive', 1, 'active', 'unknown') FROM users;
```

注意事项：
条件函数与 PostgreSQL 兼容
支持 NVL、NVL2、DECODE（Oracle 兼容扩展）
:: 是 PostgreSQL 特有的类型转换语法
IS DISTINCT FROM 是 NULL 安全的比较
