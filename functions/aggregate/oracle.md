# Oracle: 聚合函数

> 参考资料:
> - [Oracle SQL Language Reference - Aggregate Functions](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Aggregate-Functions.html)

## 基本聚合

```sql
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount), MAX(amount) FROM orders;
```

GROUP BY / HAVING
```sql
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users GROUP BY city HAVING COUNT(*) > 10;
```

## GROUPING SETS / ROLLUP / CUBE（9i+，Oracle 最早实现）

GROUPING SETS: 多维度聚合
```sql
SELECT city, status, COUNT(*)
FROM users GROUP BY GROUPING SETS ((city), (status), ());
```

ROLLUP: 层级汇总（总计 → 分类 → 小计）
```sql
SELECT city, status, COUNT(*)
FROM users GROUP BY ROLLUP (city, status);
```

CUBE: 所有组合的交叉汇总
```sql
SELECT city, status, COUNT(*)
FROM users GROUP BY CUBE (city, status);
```

GROUPING() / GROUPING_ID(): 识别汇总行
```sql
SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users GROUP BY ROLLUP (city);
```

设计分析:
  Oracle 9i 首创 GROUPING SETS / ROLLUP / CUBE，后被 SQL:1999 标准化。
  这些操作在一次扫描中完成多维度聚合，替代多个 UNION ALL。
  GROUPING() 函数返回 0 或 1，标识当前行是否是汇总行。

## 字符串聚合: LISTAGG（11g R2+）

```sql
SELECT LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
```

12c R2+: 防溢出（避免结果超过 4000 字节报错）
```sql
SELECT LISTAGG(username, ', ' ON OVERFLOW TRUNCATE '...' WITHOUT COUNT)
    WITHIN GROUP (ORDER BY username) FROM users;
```

19c+: LISTAGG DISTINCT
```sql
SELECT LISTAGG(DISTINCT city, ', ') WITHIN GROUP (ORDER BY city) FROM users;
```

横向对比:
  Oracle:     LISTAGG (11g R2+)，语法独特的 WITHIN GROUP
  PostgreSQL: STRING_AGG(col, sep ORDER BY col)（9.0+）
  MySQL:      GROUP_CONCAT(col ORDER BY col SEPARATOR sep)
  SQL Server: STRING_AGG(col, sep) WITHIN GROUP (ORDER BY col)（2017+）

对引擎开发者的启示:
  字符串聚合是最常请求的缺失功能之一。LISTAGG 的 ON OVERFLOW TRUNCATE
  是 Oracle 从实际痛点中学到的: 结果超长时应优雅处理而非报错。

## Oracle 独有的聚合函数

MEDIAN: 中位数（Oracle 独有的便捷函数）
```sql
SELECT MEDIAN(age) FROM users;
```

其他数据库需要: PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY age)

KEEP (DENSE_RANK FIRST/LAST): 按排序取极值行的聚合
```sql
SELECT
    MIN(age) KEEP (DENSE_RANK FIRST ORDER BY created_at) AS first_user_age,
    MIN(age) KEEP (DENSE_RANK LAST ORDER BY created_at) AS last_user_age
FROM users;
```

含义: "按 created_at 排序，取第一行/最后一行的 age"
其他数据库需要子查询或窗口函数才能实现

APPROX_COUNT_DISTINCT: 近似去重计数（12c+，HyperLogLog 算法）
```sql
SELECT APPROX_COUNT_DISTINCT(city) FROM users;
```

大数据量下比 COUNT(DISTINCT) 快 10-100 倍，误差 < 5%

## JSON 聚合（12c R2+）

```sql
SELECT JSON_ARRAYAGG(username ORDER BY username) FROM users;
SELECT JSON_OBJECTAGG(username VALUE age) FROM users;
```

## 统计聚合函数

```sql
SELECT STDDEV(amount) FROM orders;              -- 样本标准差
SELECT STDDEV_POP(amount) FROM orders;          -- 总体标准差
SELECT VARIANCE(amount) FROM orders;
SELECT CORR(x, y) FROM data;                   -- 相关系数
SELECT REGR_SLOPE(y, x) FROM data;             -- 线性回归斜率
```

## COLLECT: 聚合为嵌套表（10g+，Oracle 独有）

COLLECT 将值聚合为 Oracle 集合类型（类似 ARRAY_AGG）
```sql
SELECT COLLECT(username) FROM users;
```

返回嵌套表类型，需要预先定义类型

## '' = NULL 对聚合的影响

COUNT(col) 不计算 NULL 值
由于 '' = NULL，空字符串也不被 COUNT(col) 计算!
COUNT(*) 不受影响（计算所有行）

SUM/AVG 忽略 NULL:
如果列中有空字符串，它们被当作 NULL 而忽略
这可能导致 AVG 的分母比预期小

LISTAGG 也忽略 NULL:
空字符串不会出现在聚合结果中（因为是 NULL）

## 对引擎开发者的总结

1. GROUPING SETS/ROLLUP/CUBE 是 Oracle 首创的多维聚合，已成为 SQL 标准。
2. LISTAGG 的 ON OVERFLOW TRUNCATE 是优秀的容错设计，值得借鉴。
3. KEEP (DENSE_RANK) 在 GROUP BY 中解决"取排名行的值"问题，独一无二。
4. MEDIAN 是简单但高频的需求，内置函数比 PERCENTILE_CONT 更易用。
5. APPROX_COUNT_DISTINCT 使用 HyperLogLog，大数据场景必备。
6. '' = NULL 影响所有聚合函数的 NULL 处理逻辑。
