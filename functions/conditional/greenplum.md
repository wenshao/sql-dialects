# Greenplum: 条件函数

> 参考资料:
> - [Greenplum SQL Reference](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html)
> - [Greenplum Admin Guide](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html)


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


GREATEST / LEAST
```sql
SELECT GREATEST(1, 3, 2);                               -- 3
SELECT LEAST(1, 3, 2);                                  -- 1
```


类型转换
```sql
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;                                   -- PostgreSQL 简写
SELECT CAST('2024-01-15' AS DATE);
SELECT '2024-01-15'::DATE;
```


NULL 判断
```sql
SELECT username FROM users WHERE age IS NULL;
SELECT username FROM users WHERE age IS NOT NULL;
SELECT username FROM users WHERE age IS DISTINCT FROM 0;  -- NULL 安全比较
SELECT username FROM users WHERE age IS NOT DISTINCT FROM 0;
```


布尔运算
```sql
SELECT NOT TRUE;                                         -- FALSE
SELECT TRUE AND FALSE;                                    -- FALSE
SELECT TRUE OR FALSE;                                     -- TRUE
```


条件表达式
```sql
SELECT num_nulls(phone, email, bio) FROM users;          -- 统计 NULL 数量
SELECT num_nonnulls(phone, email, bio) FROM users;       -- 统计非 NULL 数量
```


生成系列
```sql
SELECT generate_series(1, 10);                           -- 1 到 10
```


布尔类型转换
```sql
SELECT CAST(1 AS BOOLEAN);                               -- TRUE
SELECT CAST(0 AS BOOLEAN);                               -- FALSE
```


DECODE（Oracle 兼容，部分版本支持）
SELECT DECODE(status, 0, 'inactive', 1, 'active', 'unknown') FROM users;

注意：Greenplum 兼容 PostgreSQL 条件函数
注意：没有 IF() 函数（使用 CASE WHEN 替代）
注意：IS DISTINCT FROM 是 NULL 安全的比较
注意：:: 是 PostgreSQL 特有的类型转换简写
