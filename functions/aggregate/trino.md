# Trino: 聚合函数

> 参考资料:
> - [Trino - Aggregate Functions](https://trino.io/docs/current/functions/aggregate.html)
> - [Trino - Functions and Operators](https://trino.io/docs/current/functions.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

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

HAVING
```sql
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > 10;

```

GROUPING SETS / ROLLUP / CUBE
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

FILTER 子句（SQL 标准）
```sql
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young,
    COUNT(*) FILTER (WHERE age >= 30) AS senior,
    SUM(amount) FILTER (WHERE status = 'active') AS active_amount
FROM users;

```

字符串聚合
```sql
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
SELECT ARRAY_JOIN(ARRAY_AGG(username ORDER BY username), ', ') FROM users;

```

数组聚合
```sql
SELECT ARRAY_AGG(username ORDER BY username) FROM users;
SELECT ARRAY_AGG(DISTINCT city) FROM users;

```

MAP 聚合
```sql
SELECT MAP_AGG(username, age) FROM users;                -- 构造 MAP
SELECT MULTIMAP_AGG(city, username) FROM users;          -- 一对多 MAP

```

近似聚合
```sql
SELECT APPROX_DISTINCT(user_id) FROM events;             -- HyperLogLog 近似去重
SELECT APPROX_PERCENTILE(amount, 0.5) FROM orders;       -- 近似中位数
SELECT APPROX_PERCENTILE(amount, ARRAY[0.25, 0.5, 0.75]) FROM orders;
SELECT APPROX_MOST_FREQUENT(10, city, 1000) FROM users;  -- 近似最频繁值
SELECT APPROX_SET(user_id) FROM events;                  -- HyperLogLog 集合

```

T-Digest
```sql
SELECT TDIGEST_AGG(amount) FROM orders;                  -- 构建 T-Digest
SELECT VALUE_AT_QUANTILE(TDIGEST_AGG(amount), 0.5) FROM orders;

```

统计函数
```sql
SELECT STDDEV(amount) FROM orders;                       -- 样本标准差
SELECT STDDEV_POP(amount) FROM orders;                   -- 总体标准差
SELECT STDDEV_SAMP(amount) FROM orders;                  -- 样本标准差
SELECT VARIANCE(amount) FROM orders;                     -- 样本方差
SELECT VAR_POP(amount) FROM orders;                      -- 总体方差
SELECT CORR(x, y) FROM data;                             -- 相关系数
SELECT COVAR_SAMP(x, y) FROM data;                       -- 样本协方差
SELECT COVAR_POP(x, y) FROM data;                        -- 总体协方差
SELECT REGR_SLOPE(y, x) FROM data;                       -- 线性回归斜率
SELECT REGR_INTERCEPT(y, x) FROM data;                   -- 线性回归截距
SELECT KURTOSIS(amount) FROM orders;                     -- 峰度
SELECT SKEWNESS(amount) FROM orders;                     -- 偏度

```

布尔聚合
```sql
SELECT BOOL_AND(active) FROM users;                      -- 所有为 TRUE
SELECT BOOL_OR(active) FROM users;                       -- 任一为 TRUE
SELECT EVERY(active) FROM users;                         -- 同 BOOL_AND

```

位聚合
```sql
SELECT BITWISE_AND_AGG(flags) FROM settings;
SELECT BITWISE_OR_AGG(flags) FROM settings;

```

其他
```sql
SELECT ANY_VALUE(name) FROM users;                       -- 任意值
SELECT MAX_BY(name, age) FROM users;                     -- 按 age 最大值取 name
SELECT MIN_BY(name, age) FROM users;                     -- 按 age 最小值取 name
SELECT MAX_BY(name, age, 3) FROM users;                  -- TOP 3
SELECT HISTOGRAM(city) FROM users;                       -- 直方图（MAP）
SELECT CHECKSUM(city) FROM users;                        -- 校验和

```

集合聚合
```sql
SELECT SET_AGG(city) FROM users;                         -- 去重集合
SELECT SET_UNION(set_col) FROM t;                        -- 集合合并

```

**注意:** FILTER 子句是 SQL 标准特性
**注意:** APPROX_DISTINCT 使用 HyperLogLog 算法
**注意:** LISTAGG 是标准字符串聚合函数
**注意:** MAP_AGG / SET_AGG 是 Trino 特色功能
**注意:** MAX_BY/MIN_BY 支持返回 TOP N
