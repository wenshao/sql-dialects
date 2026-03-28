# KingbaseES (人大金仓): 聚合函数

PostgreSQL compatible syntax.

> 参考资料:
> - [KingbaseES SQL Reference](https://help.kingbase.com.cn/v8/index.html)
> - [KingbaseES Documentation](https://help.kingbase.com.cn/v8/index.html)
> - 基本聚合

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

## GROUPING SETS

```sql
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS ((city), (status), ());
```

## ROLLUP

```sql
SELECT city, status, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);
```

## CUBE

```sql
SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE (city, status);
```

## 字符串聚合

```sql
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;
```

## JSON 聚合

```sql
SELECT JSON_AGG(username) FROM users;
SELECT JSONB_AGG(username) FROM users;
SELECT JSON_OBJECT_AGG(username, age) FROM users;
```

## 数组聚合

```sql
SELECT ARRAY_AGG(username ORDER BY username) FROM users;
```

## 统计函数

```sql
SELECT STDDEV(amount) FROM orders;
SELECT VARIANCE(amount) FROM orders;
```

## FILTER

```sql
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young,
    COUNT(*) FILTER (WHERE age >= 30) AS senior
FROM users;
```

## 布尔聚合

```sql
SELECT BOOL_AND(active) FROM users;
SELECT BOOL_OR(active) FROM users;
```

注意事项：
聚合函数与 PostgreSQL 完全兼容
支持 GROUPING SETS / ROLLUP / CUBE
支持 FILTER 子句
Oracle 兼容模式下也支持 LISTAGG
