# DamengDB (达梦): 条件函数

Oracle compatible syntax.

> 参考资料:
> - [DamengDB SQL Reference](https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html)
> - [DamengDB System Admin Manual](https://eco.dameng.com/document/dm/zh-cn/pm/index.html)
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

## DECODE（Oracle 特有，功能类似 CASE）

```sql
SELECT username,
    DECODE(status, 0, 'inactive', 1, 'active', 2, 'deleted', 'unknown') AS status_name
FROM users;
```

## NVL（Oracle 特有，NULL 替换）

```sql
SELECT NVL(phone, 'N/A') FROM users;
```

## NVL2

```sql
SELECT NVL2(phone, phone, 'N/A') FROM users;
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
SELECT GREATEST(1, 3, 2) FROM DUAL;                    -- 3
SELECT LEAST(1, 3, 2) FROM DUAL;                       -- 1
```

## 类型转换

```sql
SELECT CAST('123' AS INT) FROM DUAL;
SELECT CAST('2024-01-15' AS DATE) FROM DUAL;
SELECT TO_NUMBER('123') FROM DUAL;
SELECT TO_CHAR(123) FROM DUAL;
```

## SIGN（返回数值的符号）

```sql
SELECT SIGN(-5) FROM DUAL;                             -- -1
SELECT SIGN(0) FROM DUAL;                              -- 0
SELECT SIGN(5) FROM DUAL;                              -- 1
```

注意事项：
条件函数与 Oracle 兼容
DECODE 是 Oracle 特有的条件函数
NVL/NVL2 是 Oracle 特有的 NULL 处理函数
支持 TO_NUMBER、TO_CHAR 等 Oracle 转换函数
