# Vertica: 条件函数

> 参考资料:
> - [Vertica SQL Reference](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm)
> - [Vertica Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm)


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


COALESCE（返回第一个非 NULL 值）
```sql
SELECT COALESCE(phone, email, 'unknown') FROM users;
```


NULLIF（两值相等返回 NULL）
```sql
SELECT NULLIF(age, 0) FROM users;
```


NVL（Oracle 兼容）
```sql
SELECT NVL(phone, 'N/A') FROM users;
```


NVL2
```sql
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;
```


DECODE（Oracle 兼容）
```sql
SELECT DECODE(status, 0, 'inactive', 1, 'active', 'unknown') FROM users;
```


GREATEST / LEAST
```sql
SELECT GREATEST(1, 3, 2);                               -- 3
SELECT LEAST(1, 3, 2);                                  -- 1
```


类型转换
```sql
SELECT CAST('123' AS INT);
SELECT '123'::INT;                                       -- 简写
SELECT TO_NUMBER('1,234.56', '9,999.99');
SELECT TO_CHAR(123, '999');
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
```


NULL 判断
```sql
SELECT username FROM users WHERE age IS NULL;
SELECT username FROM users WHERE age IS NOT NULL;
SELECT username FROM users WHERE age IS DISTINCT FROM 0;
```


ZEROIFNULL（NULL 转为 0）
```sql
SELECT ZEROIFNULL(age) FROM users;
```


IFNULL
```sql
SELECT IFNULL(phone, 'N/A') FROM users;
```


布尔运算
```sql
SELECT NOT TRUE;
SELECT TRUE AND FALSE;
SELECT TRUE OR FALSE;
```


ISNULL（判断是否为 NULL）
SELECT username FROM users WHERE ISNULL(phone);

条件判断函数
```sql
SELECT HASH(username) FROM users;             -- Hash 值
SELECT LEAST(age, 100) FROM users;            -- 限制最大值
SELECT GREATEST(age, 0) FROM users;           -- 限制最小值
```


注意：Vertica 同时支持 PostgreSQL 和 Oracle 风格的条件函数
注意：没有 IF() 函数（使用 CASE WHEN 替代）
注意：支持 DECODE（Oracle 兼容）
注意：支持 NVL / NVL2
注意：ZEROIFNULL 是 Vertica 特有函数
注意：:: 是类型转换简写
