# IBM Db2: Aggregate Functions

> 参考资料:
> - [Db2 SQL Reference](https://www.ibm.com/docs/en/db2/11.5?topic=sql)
> - [Db2 Built-in Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in)
> - Basic aggregates

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

## GROUPING() function

```sql
SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users
GROUP BY ROLLUP (city);
```

## String aggregation (Db2 11.1+)

```sql
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
SELECT city, LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username)
FROM users GROUP BY city;
```

## LISTAGG with DISTINCT (Db2 11.5+)

```sql
SELECT LISTAGG(DISTINCT city, ', ') WITHIN GROUP (ORDER BY city) FROM users;
```

## Statistical functions

```sql
SELECT STDDEV(amount) FROM orders;              -- sample standard deviation
SELECT STDDEV_SAMP(amount) FROM orders;         -- same as STDDEV
SELECT VARIANCE(amount) FROM orders;            -- sample variance
SELECT VAR_SAMP(amount) FROM orders;            -- same as VARIANCE
SELECT CORR(x, y) FROM data;                   -- correlation
SELECT COVAR_SAMP(x, y) FROM data;             -- sample covariance
SELECT COVAR_POP(x, y) FROM data;              -- population covariance
SELECT REGR_SLOPE(y, x) FROM data;             -- linear regression slope
SELECT REGR_INTERCEPT(y, x) FROM data;
SELECT REGR_R2(y, x) FROM data;
```

## Percentile

```sql
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY age) FROM users;  -- median
SELECT PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY age) FROM users;
SELECT MEDIAN(age) FROM users;                   -- shorthand for median
```

## XML aggregation

```sql
SELECT XMLAGG(XMLELEMENT(NAME "user", username) ORDER BY username) FROM users;
```

## Conditional aggregation (CASE WHEN, no FILTER clause)

```sql
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN age < 30 THEN 1 ELSE 0 END) AS young,
    SUM(CASE WHEN age >= 30 THEN 1 ELSE 0 END) AS senior
FROM users;
```

## ARRAY_AGG (Db2 11.1+)

```sql
SELECT ARRAY_AGG(username ORDER BY username) FROM users;
```

Note: Db2 was an early adopter of OLAP aggregate functions
Note: LISTAGG is the standard string aggregation (Db2 11.1+)
Note: MEDIAN is a convenience function
Note: no FILTER clause; use CASE WHEN inside aggregate
