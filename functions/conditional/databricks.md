# Databricks SQL: 条件函数

> 参考资料:
> - [Databricks SQL Language Reference](https://docs.databricks.com/en/sql/language-manual/index.html)
> - [Databricks SQL - Built-in Functions](https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html)
> - [Delta Lake Documentation](https://docs.delta.io/latest/index.html)


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


NVL（兼容 Spark SQL）
```sql
SELECT NVL(phone, 'unknown') FROM users;
```


NVL2（有值返回第一个，NULL 返回第二个）
```sql
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;
```


IF 函数（Spark SQL 特有）
```sql
SELECT IF(age >= 18, 'adult', 'minor') FROM users;
```


IIF（IF 的别名）
```sql
SELECT IIF(age >= 18, 'adult', 'minor') FROM users;
```


IFNULL（COALESCE 的两参数版本）
```sql
SELECT IFNULL(phone, 'unknown') FROM users;
```


NANVL（NaN 安全）
```sql
SELECT NANVL(value, 0.0) FROM measurements;
```


GREATEST / LEAST
```sql
SELECT GREATEST(1, 3, 2);                             -- 3
SELECT LEAST(1, 3, 2);                                -- 1
```


类型转换
```sql
SELECT CAST('123' AS INT);
SELECT INT('123');                                    -- 快捷转换
SELECT STRING(123);
SELECT DOUBLE('3.14');
SELECT BOOLEAN('true');
SELECT CAST('2024-01-15' AS DATE);
```


安全转换
```sql
SELECT TRY_CAST('abc' AS INT);                        -- 返回 NULL
SELECT TRY_CAST('invalid' AS DATE);                   -- 返回 NULL
```


布尔条件（原生 BOOLEAN）
```sql
SELECT username, (age >= 18) AS is_adult FROM users;
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


DECODE（Oracle 风格）
```sql
SELECT DECODE(status, 0, 'inactive', 1, 'active', 2, 'deleted', 'unknown') FROM users;
```


类型检查
```sql
SELECT TYPEOF(123);                                   -- 'int'
SELECT TYPEOF('hello');                               -- 'string'
SELECT TYPEOF(3.14);                                  -- 'decimal(3,2)'
```


NULL 相关
```sql
SELECT ISNULL(phone);                                 -- true/false（检查 NULL）
SELECT ISNOTNULL(phone);                              -- true/false
SELECT ASSERT_TRUE(age > 0);                          -- 条件不满足则报错
```


注意：IF 函数是 Spark SQL 特有的简洁条件表达式
注意：NVL / NVL2 / DECODE 兼容 Oracle 语法
注意：TRY_CAST 是安全转换（不报错）
注意：BOOLEAN 原生支持（不是 BIT）
注意：IS DISTINCT FROM 是 NULL 安全比较
注意：TYPEOF 可以检查表达式的数据类型
注意：ASSERT_TRUE 在数据质量检查中很有用
