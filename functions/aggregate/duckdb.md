# DuckDB: 聚合函数

> 参考资料:
> - [DuckDB - SQL Reference](https://duckdb.org/docs/sql/introduction)
> - [DuckDB - Functions](https://duckdb.org/docs/sql/functions/overview)
> - [DuckDB - Data Types](https://duckdb.org/docs/sql/data_types/overview)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

```sql
SELECT COUNT(*) FROM users;
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

GROUP BY ALL (DuckDB-specific: auto-group by all non-aggregate columns)
```sql
SELECT city, status, COUNT(*), AVG(age)
FROM users
GROUP BY ALL;

```

HAVING
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
GROUP BY GROUPING SETS ((city), (status), ());

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

GROUPING() function
```sql
SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users
GROUP BY ROLLUP (city);

```

String aggregation
```sql
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;
SELECT GROUP_CONCAT(username, ', ') FROM users;        -- Alias
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;

```

List / Array aggregation (DuckDB-specific)
```sql
SELECT LIST(username ORDER BY username) FROM users;    -- Returns LIST type
SELECT LIST(DISTINCT city) FROM users;
SELECT ARRAY_AGG(username) FROM users;                 -- Alias for LIST

```

Histogram (DuckDB-specific)
```sql
SELECT HISTOGRAM(city) FROM users;                     -- MAP of value -> count

```

Approximate aggregates (DuckDB-specific)
```sql
SELECT APPROX_COUNT_DISTINCT(city) FROM users;         -- HyperLogLog
SELECT APPROX_QUANTILE(age, 0.5) FROM users;           -- Approximate median
SELECT APPROX_QUANTILE(age, [0.25, 0.5, 0.75]) FROM users; -- Multiple quantiles
SELECT RESERVOIR_QUANTILE(age, 0.5) FROM users;        -- Reservoir sampling quantile

```

Exact quantiles
```sql
SELECT QUANTILE(age, 0.5) FROM users;                  -- Exact median
SELECT QUANTILE_CONT(age, 0.5) FROM users;             -- Continuous (interpolated)
SELECT QUANTILE_DISC(age, 0.5) FROM users;             -- Discrete
SELECT MEDIAN(age) FROM users;                         -- Alias for QUANTILE(0.5)
SELECT MODE(city) FROM users;                          -- Most frequent value

```

Statistical functions
```sql
SELECT STDDEV(amount) FROM orders;                     -- Sample standard deviation
SELECT STDDEV_POP(amount) FROM orders;                 -- Population standard deviation
SELECT STDDEV_SAMP(amount) FROM orders;                -- Sample (alias)
SELECT VARIANCE(amount) FROM orders;                   -- Sample variance
SELECT VAR_POP(amount) FROM orders;                    -- Population variance
SELECT VAR_SAMP(amount) FROM orders;                   -- Sample (alias)
SELECT CORR(x, y) FROM data;                          -- Correlation
SELECT COVAR_SAMP(x, y) FROM data;                    -- Sample covariance
SELECT COVAR_POP(x, y) FROM data;                     -- Population covariance
SELECT REGR_SLOPE(y, x) FROM data;                    -- Linear regression slope
SELECT REGR_INTERCEPT(y, x) FROM data;                -- Linear regression intercept
SELECT REGR_R2(y, x) FROM data;                       -- R-squared
SELECT ENTROPY(city) FROM users;                       -- Shannon entropy
SELECT KURTOSIS(age) FROM users;                       -- Kurtosis
SELECT SKEWNESS(age) FROM users;                       -- Skewness
SELECT MAD(age) FROM users;                            -- Median absolute deviation

```

FILTER (conditional aggregation)
```sql
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young,
    COUNT(*) FILTER (WHERE age >= 30) AS senior,
    SUM(amount) FILTER (WHERE status = 'completed') AS completed_total
FROM users;

```

Boolean aggregates
```sql
SELECT BOOL_AND(active) FROM users;                    -- All TRUE
SELECT BOOL_OR(active) FROM users;                     -- Any TRUE
SELECT EVERY(active) FROM users;                       -- Alias for BOOL_AND

```

Bit aggregates
```sql
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;
SELECT BIT_XOR(flags) FROM settings;
SELECT BITSTRING_AGG(flags) FROM settings;

```

JSON/MAP aggregation
```sql
SELECT MAP(LIST(username), LIST(age)) FROM users;      -- Build MAP from lists

```

ARG_MIN / ARG_MAX (DuckDB-specific: return value at min/max of another column)
```sql
SELECT ARG_MIN(username, age) FROM users;              -- Username of youngest user
SELECT ARG_MAX(username, age) FROM users;              -- Username of oldest user

```

FIRST / LAST (DuckDB-specific: first/last value in group)
```sql
SELECT city, FIRST(username ORDER BY id) FROM users GROUP BY city;
SELECT city, LAST(username ORDER BY id) FROM users GROUP BY city;

```

Note: GROUP BY ALL auto-detects non-aggregate columns (DuckDB-specific)
Note: LIST/ARRAY_AGG returns native list type (not string)
Note: HISTOGRAM returns a MAP of value counts (DuckDB-specific)
Note: ARG_MIN/ARG_MAX are very useful for "value at extreme" queries
Note: FILTER clause is SQL standard for conditional aggregation
Note: Approximate functions (APPROX_*) are faster on large datasets
Note: Rich statistical functions (entropy, kurtosis, skewness, MAD)
