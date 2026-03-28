# Vertica: 聚合函数

> 参考资料:
> - [Vertica SQL Reference](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm)
> - [Vertica Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm)


基本聚合
```sql
SELECT COUNT(*) FROM users;
SELECT COUNT(email) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;
```


GROUP BY
```sql
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city;
```


GROUP BY + HAVING
```sql
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > 10;
```


GROUPING SETS
```sql
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS ((city), (status), (city, status), ());
```


ROLLUP
```sql
SELECT city, status, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);
```


CUBE
```sql
SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE (city, status);
```


GROUPING 函数
```sql
SELECT city, status,
    GROUPING(city) AS city_is_total,
    GROUPING(status) AS status_is_total,
    COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);
```


字符串聚合
```sql
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
```


统计函数
```sql
SELECT STDDEV(amount) FROM orders;
SELECT STDDEV_POP(amount) FROM orders;
SELECT STDDEV_SAMP(amount) FROM orders;
SELECT VARIANCE(amount) FROM orders;
SELECT VAR_POP(amount) FROM orders;
SELECT VAR_SAMP(amount) FROM orders;
SELECT CORR(age, balance) FROM users;
SELECT COVAR_POP(age, balance) FROM users;
SELECT COVAR_SAMP(age, balance) FROM users;
SELECT REGR_SLOPE(balance, age) FROM users;
SELECT REGR_INTERCEPT(balance, age) FROM users;
SELECT REGR_R2(balance, age) FROM users;
```


百分位数
```sql
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) FROM orders;
SELECT PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY amount) FROM orders;
SELECT MEDIAN(amount) FROM orders;            -- Vertica 特有
```


近似聚合
```sql
SELECT APPROXIMATE_COUNT_DISTINCT(user_id) FROM orders;
SELECT APPROXIMATE_PERCENTILE(amount USING PARAMETERS percentile=0.95) FROM orders;
SELECT APPROXIMATE_MEDIAN(amount) FROM orders;
```


BIT 聚合
```sql
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;
SELECT BIT_XOR(flags) FROM settings;
```


BOOL 聚合
```sql
SELECT BOOL_AND(active) FROM users;
SELECT BOOL_OR(active) FROM users;
```


条件聚合（CASE）
```sql
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) AS active,
    SUM(CASE WHEN age >= 18 THEN 1 ELSE 0 END) AS adults,
    AVG(CASE WHEN status = 1 THEN age END) AS avg_active_age
FROM users;
```


ML 聚合函数（Vertica 内置机器学习）
SELECT LINEAR_REG(balance, age) OVER () FROM users;

注意：Vertica 聚合函数非常丰富
注意：支持 GROUPING SETS / ROLLUP / CUBE
注意：LISTAGG 用于字符串聚合
注意：MEDIAN 是 Vertica 特有的便捷函数
注意：APPROXIMATE_* 系列函数用于大数据近似聚合
注意：支持回归分析函数（REGR_*）
