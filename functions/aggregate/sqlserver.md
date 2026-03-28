# SQL Server: 聚合函数

> 参考资料:
> - [SQL Server T-SQL - Aggregate Functions](https://learn.microsoft.com/en-us/sql/t-sql/functions/aggregate-functions-transact-sql)

## 基本聚合函数

```sql
SELECT COUNT(*)              FROM users;            -- 总行数
SELECT COUNT(DISTINCT city)  FROM users;            -- 去重计数
SELECT COUNT_BIG(*)          FROM users;            -- 返回 BIGINT（大表必须）
SELECT SUM(amount)           FROM orders;
SELECT AVG(amount)           FROM orders;
SELECT MIN(amount), MAX(amount) FROM orders;
```

COUNT vs COUNT_BIG:
  COUNT(*) 返回 INT（最大 ~21 亿），超过会溢出
  COUNT_BIG(*) 返回 BIGINT（最大 ~922 亿亿）
  索引视图中必须使用 COUNT_BIG（SQL Server 的硬性要求）

横向对比:
  PostgreSQL: count(*) 返回 BIGINT（无此问题）
  MySQL:      COUNT(*) 返回 BIGINT
  Oracle:     COUNT(*) 返回 NUMBER（无此问题）

对引擎开发者的启示:
  聚合函数返回类型应该足够大——INT 返回类型是历史遗留问题。
  现代引擎应该默认返回 BIGINT 或更大的类型。

GROUP BY + HAVING
```sql
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users GROUP BY city HAVING COUNT(*) > 10;
```

## GROUPING SETS / ROLLUP / CUBE（2008+）

GROUPING SETS: 多维度分组（SQL Server 2008+ 引入标准语法）
```sql
SELECT city, status, COUNT(*)
FROM users GROUP BY GROUPING SETS ((city), (status), ());
```

ROLLUP: 层级小计 + 总计
```sql
SELECT city, status, COUNT(*)
FROM users GROUP BY ROLLUP (city, status);
```

CUBE: 所有维度组合
```sql
SELECT city, status, COUNT(*)
FROM users GROUP BY CUBE (city, status);
```

GROUPING() / GROUPING_ID(): 区分 NULL 和"汇总行"
```sql
SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users GROUP BY ROLLUP (city);
```

旧语法（仍然支持但不推荐）:
GROUP BY city, status WITH ROLLUP
GROUP BY city, status WITH CUBE

## STRING_AGG: 字符串聚合（2017+, SQL Server 最晚添加）

```sql
SELECT STRING_AGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
```

设计分析（对引擎开发者）:
  SQL Server 在 2017 才添加 STRING_AGG，比其他数据库晚了很多年:
  MySQL:      GROUP_CONCAT（4.1+, 2004 年）
  PostgreSQL: STRING_AGG（9.0+, 2010 年）
  Oracle:     LISTAGG（11g R2, 2009 年）

  2017 之前的替代方案——FOR XML PATH 技巧（SQL Server 经典 hack）:
```sql
SELECT STUFF(
    (SELECT ', ' + username FROM users ORDER BY username FOR XML PATH('')),
    1, 2, ''
);
```

  这个技巧利用了 FOR XML 将结果集拼接为字符串的能力。
  STUFF 用于去掉开头的 ', '。
  它在 SQL Server 社区中使用了 15+ 年，是 T-SQL 最知名的惯用法之一。

对引擎开发者的启示:
  字符串聚合是一个高频需求——它应该在引擎早期就内置。
  FOR XML PATH 技巧说明: 如果引擎缺少某个功能，用户会找到 hack 方式实现，
  但 hack 方式的性能和可读性都很差。

## JSON 聚合（FOR JSON, 2016+）

SQL Server 没有 JSON_AGG / JSON_ARRAYAGG 聚合函数。
使用 FOR JSON PATH 将结果集转为 JSON 数组:
```sql
SELECT username, age FROM users FOR JSON PATH;
-- [{"username":"alice","age":25},{"username":"bob","age":30}]

SELECT username FROM users FOR JSON PATH, ROOT('users');
```

{"users":[{"username":"alice"},{"username":"bob"}]}

横向对比:
  PostgreSQL: json_agg(), jsonb_agg(), json_object_agg()（真正的聚合函数）
  MySQL:      JSON_ARRAYAGG(), JSON_OBJECTAGG()（5.7.22+）
  SQL Server: FOR JSON（不是聚合函数，是查询子句）

## 统计聚合函数

```sql
SELECT STDEV(amount)   FROM orders;   -- 样本标准差
SELECT STDEVP(amount)  FROM orders;   -- 总体标准差
SELECT VAR(amount)     FROM orders;   -- 样本方差
SELECT VARP(amount)    FROM orders;   -- 总体方差

-- CHECKSUM_AGG: 检测数据变化的校验和
SELECT CHECKSUM_AGG(CHECKSUM(username)) FROM users;
```

## APPROX_COUNT_DISTINCT（2019+）

```sql
SELECT APPROX_COUNT_DISTINCT(city) FROM users;
```

设计分析:
  APPROX_COUNT_DISTINCT 使用 HyperLogLog 算法，误差约 2%。
  对于数十亿行的表，比 COUNT(DISTINCT) 快 10-100x。

横向对比:
  PostgreSQL: 无内置近似函数（需要 pg_hll 扩展）
  MySQL:      无内置近似函数
  ClickHouse: uniq(), uniqHLL12(), uniqExact()（多种近似算法）
  BigQuery:   APPROX_COUNT_DISTINCT（默认行为）

对引擎开发者的启示:
  近似计算是大数据分析的关键能力。HyperLogLog 是最成熟的基数估算算法。
  分析型引擎应默认提供近似函数（ClickHouse 的做法最丰富）。
  2022+: APPROX_PERCENTILE_CONT / APPROX_PERCENTILE_DISC（近似百分位数）

版本演进:
2005+ : COUNT_BIG, GROUPING
2008+ : GROUPING SETS, ROLLUP, CUBE（标准语法）
2016+ : FOR JSON
2017+ : STRING_AGG
2019+ : APPROX_COUNT_DISTINCT
2022+ : APPROX_PERCENTILE_CONT/DISC
