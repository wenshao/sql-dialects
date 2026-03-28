# MaxCompute (ODPS): 聚合函数

> 参考资料:
> - [1] MaxCompute SQL - Aggregate Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/aggregate-functions
> - [2] MaxCompute Built-in Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/built-in-functions-overview


## 1. 基本聚合函数


```sql
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount), MAX(amount) FROM orders;

```

GROUP BY

```sql
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users GROUP BY city;

```

HAVING

```sql
SELECT city, COUNT(*) AS cnt
FROM users GROUP BY city HAVING COUNT(*) > 10;

```

## 2. GROUPING SETS / ROLLUP / CUBE（2.0+）


GROUPING SETS: 多维聚合（一次扫描，多组 GROUP BY）

```sql
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS ((city), (status), ());

```

ROLLUP: 层级汇总（从细到粗）

```sql
SELECT city, status, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);
```

等价于 GROUPING SETS ((city, status), (city), ())

CUBE: 所有组合

```sql
SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE (city, status);
```

等价于 GROUPING SETS ((city, status), (city), (status), ())

GROUPING 函数: 判断是否为汇总行

```sql
SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users GROUP BY ROLLUP (city);
```

 GROUPING(city) = 0: 按 city 分组的行
 GROUPING(city) = 1: 汇总行（city = NULL）

 设计分析: GROUPING SETS 在 ETL 中的价值
   传统做法: 写 3 个 SQL 分别计算 city 级、status 级、总计级聚合
   GROUPING SETS: 一次扫描计算所有级别 → 减少 2/3 的数据读取
   对比:
     Hive:       支持（MaxCompute 继承）
     BigQuery:   支持 GROUPING SETS / ROLLUP / CUBE
     Snowflake:  支持
     ClickHouse: 支持 WITH ROLLUP / WITH CUBE（语法略不同）
     MySQL 8.0:  支持 WITH ROLLUP（不支持 GROUPING SETS / CUBE）

## 3. 字符串聚合: WM_CONCAT


WM_CONCAT: MaxCompute/Oracle 特有的字符串聚合函数

```sql
SELECT WM_CONCAT(',', username) FROM users;

```

 重要限制: 不保证顺序，不支持 ORDER BY
 对比:
   MaxCompute: WM_CONCAT(',', col)（无序）
   Oracle:     WM_CONCAT(col)（已废弃）→ LISTAGG(col, ',') WITHIN GROUP (ORDER BY col)
   PostgreSQL: STRING_AGG(col, ',' ORDER BY col)
   MySQL:      GROUP_CONCAT(col ORDER BY col SEPARATOR ',')
   BigQuery:   STRING_AGG(col, ',' ORDER BY col)
   Snowflake:  LISTAGG(col, ',') WITHIN GROUP (ORDER BY col)
   Hive:       不支持原生字符串聚合（需要 UDF）

   MaxCompute WM_CONCAT 的最大缺陷: 无法指定排序
   替代方案: COLLECT_LIST + 排序 + CONCAT_WS

## 4. 数组聚合: COLLECT_LIST / COLLECT_SET


```sql
SELECT COLLECT_LIST(username) FROM users;   -- 收集为数组（含重复）
SELECT COLLECT_SET(city) FROM users;        -- 收集为去重数组

```

分组聚合

```sql
SELECT city, COLLECT_LIST(username) AS names
FROM users GROUP BY city;

```

 与 WM_CONCAT 的对比:
   COLLECT_LIST → ARRAY<STRING>（后续可以 SORT_ARRAY + CONCAT_WS）
   WM_CONCAT → STRING（直接是字符串，但无序）

## 5. 统计函数


```sql
SELECT STDDEV(amount) FROM orders;          -- 样本标准差
SELECT STDDEV_POP(amount) FROM orders;      -- 总体标准差
SELECT STDDEV_SAMP(amount) FROM orders;     -- 样本标准差（同 STDDEV）
SELECT VARIANCE(amount) FROM orders;        -- 样本方差
SELECT VAR_POP(amount) FROM orders;         -- 总体方差
SELECT COVAR_SAMP(x, y) FROM data;          -- 样本协方差
SELECT COVAR_POP(x, y) FROM data;           -- 总体协方差
SELECT CORR(x, y) FROM data;               -- 相关系数

```

## 6. 百分位与近似聚合


```sql
SELECT MEDIAN(amount) FROM orders;          -- 中位数
SELECT PERCENTILE(amount, 0.5) FROM orders; -- 百分位（精确）
SELECT PERCENTILE_APPROX(amount, 0.5) FROM orders;  -- 近似百分位（大数据推荐）

```

近似去重（HyperLogLog 算法）

```sql
SELECT APPROX_DISTINCT(user_id) FROM events;

```

 设计分析: APPROX_DISTINCT 的实现
   精确 COUNT(DISTINCT): 需要全量去重（Hash Set 或 Sort）→ O(N) 内存
   APPROX_DISTINCT: HyperLogLog 算法 → O(1) 内存，误差 ~2%
   对 TB 级数据: 精确去重可能 OOM，近似去重是唯一选择

   对比:
     BigQuery:   APPROX_COUNT_DISTINCT（默认使用，精确去重也会优化）
     ClickHouse: uniq / uniqExact / uniqHLL12（多种精度选择）
     Snowflake:  APPROX_COUNT_DISTINCT（HLL 算法）
     PostgreSQL: 无内置近似去重（需要 hll 扩展）

## 7. 其他高级聚合


```sql
SELECT ANY_VALUE(name) FROM users;          -- 任意值（2.0+，非确定性）
SELECT MAX_BY(name, age) FROM users;        -- 按 age 最大值取 name
SELECT MIN_BY(name, age) FROM users;        -- 按 age 最小值取 name

```

条件聚合（使用 CASE/IF，因为不支持 FILTER）

```sql
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN age < 30 THEN 1 ELSE 0 END) AS young,
    SUM(IF(status = 'active', amount, 0)) AS active_amount
FROM users;

```

 不支持 FILTER 子句:
 标准 SQL: COUNT(*) FILTER (WHERE status = 'active')
 MaxCompute: SUM(IF(status = 'active', 1, 0))

## 8. 横向对比: 聚合函数


 字符串聚合:
MaxCompute: WM_CONCAT（无序）    | PostgreSQL: STRING_AGG（有序）
MySQL:      GROUP_CONCAT（有序） | BigQuery: STRING_AGG（有序）
Oracle:     LISTAGG（有序）      | Hive: 无原生支持

 数组聚合:
MaxCompute: COLLECT_LIST/SET     | Hive: COLLECT_LIST/SET
BigQuery:   ARRAY_AGG           | PostgreSQL: ARRAY_AGG
ClickHouse: groupArray          | Snowflake: ARRAY_AGG

 FILTER 子句:
MaxCompute: 不支持（用 CASE）    | PostgreSQL: 支持
BigQuery:   不支持               | Snowflake: 不支持
   ClickHouse: 支持 -If 后缀（countIf, sumIf）

 WITHIN GROUP:
MaxCompute: 不支持               | Oracle: LISTAGG ... WITHIN GROUP
PostgreSQL: 支持                  | SQL Server: 支持

## 9. 对引擎开发者的启示


1. GROUPING SETS 是 OLAP 引擎的核心能力 — 一次扫描多维聚合

2. 字符串聚合应支持 ORDER BY（WM_CONCAT 的无序是重大缺陷）

3. 近似聚合（HLL/APPROX）在大数据场景中是必需品而非可选

4. FILTER 子句简化条件聚合 — 值得支持（替代 CASE WHEN 样板代码）

5. MAX_BY/MIN_BY 是非常实用的函数 — 避免了子查询或窗口函数

6. COLLECT_LIST + SORT_ARRAY + CONCAT_WS 是有序字符串聚合的通用方案

