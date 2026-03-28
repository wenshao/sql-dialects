# Azure Synapse: 聚合函数

> 参考资料:
> - [Synapse SQL Features](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)
> - [Synapse T-SQL Differences](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


基本聚合
```sql
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;
```


COUNT_BIG（返回 BIGINT）
```sql
SELECT COUNT_BIG(*) FROM events;
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


字符串聚合
```sql
SELECT STRING_AGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
SELECT city, STRING_AGG(username, ', ') WITHIN GROUP (ORDER BY username) AS user_list
FROM users GROUP BY city;
```


近似计数
```sql
SELECT APPROX_COUNT_DISTINCT(user_id) FROM events;
```


统计函数
```sql
SELECT STDEV(amount) FROM orders;                    -- 样本标准差（T-SQL 名称）
SELECT STDEVP(amount) FROM orders;                   -- 总体标准差
SELECT VAR(amount) FROM orders;                      -- 样本方差
SELECT VARP(amount) FROM orders;                     -- 总体方差
```


百分位
```sql
SELECT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY age) OVER () AS median_age,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY age) OVER () AS median_disc
FROM users;
-- 注意：Synapse 中 PERCENTILE_CONT / PERCENTILE_DISC 是窗口函数
-- 需要 OVER 子句
```


CHECKSUM_AGG
```sql
SELECT CHECKSUM_AGG(CAST(id AS INT)) FROM users;    -- 校验和聚合
```


条件聚合（用 CASE WHEN 模拟 FILTER）
```sql
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN age < 30 THEN 1 ELSE 0 END) AS young,
    SUM(CASE WHEN age >= 30 THEN 1 ELSE 0 END) AS senior
FROM users;
```


注意：STRING_AGG 是推荐的字符串聚合函数
注意：STDEV / STDEVP / VAR / VARP 是 T-SQL 命名（不是 STDDEV）
注意：PERCENTILE_CONT / PERCENTILE_DISC 需要 OVER 子句
注意：不支持 FILTER 子句（用 CASE WHEN 替代）
注意：COUNT_BIG 返回 BIGINT，适合大表
注意：APPROX_COUNT_DISTINCT 是近似计数
