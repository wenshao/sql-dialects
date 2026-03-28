# Hologres: 聚合函数

Hologres 兼容 PostgreSQL 聚合函数

> 参考资料:
> - [Hologres - Aggregate Functions](https://help.aliyun.com/zh/hologres/user-guide/aggregate-functions)
> - [Hologres Built-in Functions](https://help.aliyun.com/zh/hologres/user-guide/built-in-functions)


## 基本聚合

```sql
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;
```

## GROUP BY

```sql
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city;
```

## HAVING

```sql
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > 10;
```

## GROUPING SETS / ROLLUP / CUBE

```sql
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS ((city), (status), ());

SELECT city, status, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);

SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE (city, status);

SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users
GROUP BY ROLLUP (city);
```

## 字符串聚合

```sql
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;
SELECT STRING_AGG(DISTINCT city, ', ') FROM users;
```

## 数组聚合

```sql
SELECT ARRAY_AGG(username ORDER BY username) FROM users;
SELECT ARRAY_AGG(DISTINCT city) FROM users;
```

## JSON 聚合

```sql
SELECT JSON_AGG(username) FROM users;
SELECT JSONB_AGG(username) FROM users;
SELECT JSON_OBJECT_AGG(username, age) FROM users;
```

## 统计函数

```sql
SELECT STDDEV(amount) FROM orders;                       -- 样本标准差
SELECT STDDEV_POP(amount) FROM orders;                   -- 总体标准差
SELECT VARIANCE(amount) FROM orders;                     -- 样本方差
SELECT VAR_POP(amount) FROM orders;                      -- 总体方差
SELECT CORR(x, y) FROM data;                             -- 相关系数
SELECT COVAR_SAMP(x, y) FROM data;                       -- 样本协方差
```

## FILTER（聚合条件过滤）

```sql
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young,
    COUNT(*) FILTER (WHERE age >= 30) AS senior
FROM users;
```

## 布尔聚合

```sql
SELECT BOOL_AND(active) FROM users;                      -- 所有为 TRUE
SELECT BOOL_OR(active) FROM users;                       -- 任一为 TRUE
SELECT EVERY(active) FROM users;                         -- 同 BOOL_AND
```

## 位聚合

```sql
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;
```

## 近似去重

```sql
SELECT APPROX_COUNT_DISTINCT(user_id) FROM events;       -- HyperLogLog
```

## 条件聚合

```sql
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN age < 30 THEN 1 ELSE 0 END) AS young
FROM users;
```

注意：与 PostgreSQL 聚合函数基本一致
注意：FILTER 子句受支持（PostgreSQL 语法）
注意：部分高级统计函数可能不支持（如 REGR_SLOPE）
注意：不支持 WITHIN GROUP 语法（如 PERCENTILE_CONT）
注意：性能特征与 PostgreSQL 不同（列存引擎优化聚合查询）
