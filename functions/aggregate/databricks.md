# Databricks SQL: 聚合函数

> 参考资料:
> - [Databricks SQL Language Reference](https://docs.databricks.com/en/sql/language-manual/index.html)
> - [Databricks SQL - Built-in Functions](https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html)
> - [Delta Lake Documentation](https://docs.delta.io/latest/index.html)


基本聚合
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


GROUPING() 函数
```sql
SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users
GROUP BY ROLLUP (city);
```


GROUPING_ID()
```sql
SELECT city, status, GROUPING_ID(city, status) AS grp_id, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);
```


数组/集合聚合
```sql
SELECT COLLECT_LIST(username) FROM users;             -- 保留重复
SELECT COLLECT_SET(city) FROM users;                  -- 去重
```


字符串聚合
```sql
SELECT ARRAY_JOIN(COLLECT_LIST(username), ', ') FROM users;
SELECT CONCAT_WS(', ', COLLECT_LIST(username)) FROM users;
SELECT city, ARRAY_JOIN(COLLECT_LIST(username), ', ') AS user_list
FROM users GROUP BY city;
```


近似聚合
```sql
SELECT APPROX_COUNT_DISTINCT(user_id) FROM events;
SELECT APPROX_PERCENTILE(age, 0.5) FROM users;       -- 近似中位数
SELECT APPROX_PERCENTILE(age, ARRAY(0.25, 0.5, 0.75)) FROM users;  -- 四分位
```


精确百分位
```sql
SELECT PERCENTILE(age, 0.5) FROM users;               -- 精确中位数
SELECT PERCENTILE_APPROX(age, 0.5, 10000) FROM users; -- 更高精度
```


统计函数
```sql
SELECT STDDEV(amount) FROM orders;                   -- 样本标准差
SELECT STDDEV_POP(amount) FROM orders;               -- 总体标准差
SELECT STDDEV_SAMP(amount) FROM orders;              -- 同 STDDEV
SELECT VARIANCE(amount) FROM orders;                 -- 样本方差
SELECT VAR_POP(amount) FROM orders;                  -- 总体方差
SELECT VAR_SAMP(amount) FROM orders;                 -- 同 VARIANCE
SELECT CORR(x, y) FROM data;                        -- 相关系数
SELECT COVAR_POP(x, y) FROM data;                   -- 总体协方差
SELECT COVAR_SAMP(x, y) FROM data;                  -- 样本协方差
SELECT REGR_SLOPE(y, x) FROM data;                  -- 线性回归斜率
SELECT REGR_INTERCEPT(y, x) FROM data;              -- 线性回归截距
SELECT REGR_R2(y, x) FROM data;                     -- R-squared
```


FILTER 子句
```sql
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young,
    COUNT(*) FILTER (WHERE age >= 30) AS senior,
    SUM(amount) FILTER (WHERE status = 1) AS active_total
FROM users;
```


布尔聚合
```sql
SELECT BOOL_AND(active) FROM users;                  -- 所有为 TRUE
SELECT BOOL_OR(active) FROM users;                   -- 任一为 TRUE
SELECT EVERY(active) FROM users;                     -- 同 BOOL_AND
SELECT SOME(active) FROM users;                      -- 同 BOOL_OR
SELECT ANY(active) FROM users;                       -- 同 BOOL_OR
```


位聚合
```sql
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;
SELECT BIT_XOR(flags) FROM settings;
```


直方图
```sql
SELECT HISTOGRAM_NUMERIC(age, 10) FROM users;        -- 10 个桶的直方图
```


首尾值
```sql
SELECT FIRST(username) FROM users;                   -- 第一个值（非确定性）
SELECT LAST(username) FROM users;                    -- 最后一个值（非确定性）
SELECT FIRST_VALUE(username) IGNORE NULLS FROM users; -- 忽略 NULL
```


注意：COLLECT_LIST / COLLECT_SET 收集值为数组
注意：FILTER 子句可以对不同条件分别聚合
注意：APPROX_PERCENTILE 比 PERCENTILE 更高效
注意：EVERY / SOME / ANY 是布尔聚合的 SQL 标准名
注意：Photon 引擎对聚合操作有显著性能优化
注意：HISTOGRAM_NUMERIC 直接生成直方图
