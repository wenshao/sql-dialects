# Redshift: 条件函数

> 参考资料:
> - [Redshift SQL Reference](https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html)
> - [Redshift SQL Functions](https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html)
> - [Redshift Data Types](https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html)


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


NVL（Redshift 特有，同 COALESCE 但只接受两个参数）
```sql
SELECT NVL(phone, 'unknown') FROM users;
```


NVL2（有值返回第一个，NULL 返回第二个）
```sql
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;
```


DECODE（类似简单 CASE，Oracle 风格）
```sql
SELECT DECODE(status, 0, 'inactive', 1, 'active', 2, 'deleted', 'unknown') FROM users;
```


GREATEST / LEAST
```sql
SELECT GREATEST(1, 3, 2);                             -- 3
SELECT LEAST(1, 3, 2);                                -- 1
```


类型转换
```sql
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;                                -- :: 语法
SELECT '2024-01-15'::DATE;
SELECT CAST('true' AS BOOLEAN);
SELECT CAST(123 AS VARCHAR);
```


条件表达式用于更新
```sql
UPDATE users SET status = CASE WHEN age >= 18 THEN 1 ELSE 0 END;
```


IS NULL / IS NOT NULL
```sql
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;
```


IS DISTINCT FROM（NULL 安全比较）
```sql
SELECT * FROM users WHERE phone IS DISTINCT FROM 'unknown';
SELECT * FROM users WHERE phone IS NOT DISTINCT FROM NULL;
```


BETWEEN
```sql
SELECT * FROM users WHERE age BETWEEN 18 AND 65;
```


IN / NOT IN
```sql
SELECT * FROM users WHERE status IN (0, 1, 2);
SELECT * FROM users WHERE city NOT IN ('Beijing', 'Shanghai');
```


注意：NVL / NVL2 / DECODE 是 Redshift 特有（兼容 Oracle）
注意：COALESCE 是 SQL 标准，推荐使用
注意：IS DISTINCT FROM 是 NULL 安全的比较运算符
注意：没有 TRY_CAST（转换失败会报错）
注意：BOOLEAN 支持 TRUE / FALSE / NULL
