# PolarDB: 条件函数

PolarDB-X (distributed, MySQL compatible).

> 参考资料:
> - [PolarDB-X SQL Reference](https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/)
> - [PolarDB MySQL Documentation](https://help.aliyun.com/zh/polardb/polardb-for-mysql/)
> - CASE WHEN

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

## IF（MySQL 特有）

```sql
SELECT username, IF(age >= 18, 'adult', 'minor') AS category FROM users;
```

## IFNULL

```sql
SELECT IFNULL(phone, 'N/A') FROM users;
```

## COALESCE

```sql
SELECT COALESCE(phone, email, 'unknown') FROM users;
```

## NULLIF

```sql
SELECT NULLIF(age, 0) FROM users;
```

## 类型转换

```sql
SELECT CAST('123' AS SIGNED);
SELECT CAST('2024-01-15' AS DATE);
SELECT CONVERT('123', SIGNED);
```

## ELT / FIELD

```sql
SELECT ELT(2, 'a', 'b', 'c');                          -- 'b'
SELECT FIELD('b', 'a', 'b', 'c');                       -- 2
```

## GREATEST / LEAST

```sql
SELECT GREATEST(1, 3, 2);                               -- 3
SELECT LEAST(1, 3, 2);                                  -- 1
```

## ISNULL

```sql
SELECT ISNULL(phone) FROM users;
```

## 注意事项：

条件函数与 MySQL 完全兼容
