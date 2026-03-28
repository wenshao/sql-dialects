# SAP HANA: Window Functions

> 参考资料:
> - [SAP HANA SQL Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/)
> - [SAP HANA SQLScript Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/)
> - ROW_NUMBER / RANK / DENSE_RANK

```sql
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;
```

## Partition

```sql
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;
```

## Aggregate window functions

```sql
SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER () AS avg_age,
    COUNT(*)   OVER () AS total_count,
    MIN(age)   OVER (PARTITION BY city) AS city_min_age,
    MAX(age)   OVER (PARTITION BY city) AS city_max_age
FROM users;
```

## Offset functions

```sql
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age,
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    LAST_VALUE(username)  OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM users;
```

## NTH_VALUE

```sql
SELECT username, age,
    NTH_VALUE(username, 2) OVER (ORDER BY age) AS second_youngest
FROM users;
```

## NTILE

```sql
SELECT username, age,
    NTILE(4) OVER (ORDER BY age) AS quartile
FROM users;
```

## PERCENT_RANK / CUME_DIST

```sql
SELECT username, age,
    PERCENT_RANK() OVER (ORDER BY age) AS pct_rank,
    CUME_DIST()    OVER (ORDER BY age) AS cume_dist
FROM users;
```

## Named window

```sql
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(age)     OVER w AS prev_age
FROM users
WINDOW w AS (ORDER BY age);
```

## Frame clause

```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_avg
FROM users;
```

## WEIGHTED_AVG (SAP HANA-specific)

```sql
SELECT product_id, month, sales,
    WEIGHTED_AVG(sales, 3) OVER (PARTITION BY product_id ORDER BY month) AS weighted_avg
FROM monthly_sales;
```

## SERIES_GENERATE (window over time series)

```sql
SELECT ts, value,
    AVG(value) OVER (ORDER BY ts ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS moving_avg_7
FROM sensor_data
WHERE sensor_id = 'S001';
```

## Filtering window results (subquery approach)

```sql
SELECT * FROM (
    SELECT username, city, age,
        ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn = 1;
```

## BINNING (SAP HANA-specific window extension)

```sql
SELECT username, age,
    BINNING(VALUE => age, BIN_COUNT => 5) OVER () AS age_bin
FROM users;
```

Note: SAP HANA window functions leverage in-memory columnar processing
Note: no QUALIFY clause; use subquery wrapper
Note: SERIES_ functions provide specialized time series windowing
