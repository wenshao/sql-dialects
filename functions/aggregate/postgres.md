# PostgreSQL: 聚合函数

> 参考资料:
> - [PostgreSQL Documentation - Aggregate Functions](https://www.postgresql.org/docs/current/functions-aggregate.html)
> - [PostgreSQL Documentation - FILTER Clause](https://www.postgresql.org/docs/current/sql-expressions.html#SYNTAX-AGGREGATES)
> - [PostgreSQL Source - nodeAgg.c](https://github.com/postgres/postgres/blob/master/src/backend/executor/nodeAgg.c)

## 基本聚合

```sql
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount), AVG(amount), MIN(amount), MAX(amount) FROM orders;
```

GROUP BY + HAVING
```sql
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users GROUP BY city HAVING COUNT(*) > 10;
```

## FILTER 子句 (9.4+): PostgreSQL 的聚合革命

FILTER 让条件聚合更简洁、更高效
```sql
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young,
    COUNT(*) FILTER (WHERE age >= 30 AND age < 60) AS middle,
    COUNT(*) FILTER (WHERE age >= 60) AS senior,
    SUM(amount) FILTER (WHERE status = 'completed') AS completed_revenue
FROM users;
```

对比传统 CASE WHEN 写法:
COUNT(CASE WHEN age < 30 THEN 1 END) AS young   -- 旧方式
COUNT(*) FILTER (WHERE age < 30) AS young        -- FILTER 方式

设计分析:
  FILTER 是 SQL:2003 标准，但大多数数据库不支持。
  内部实现: FILTER 条件在聚合函数的 transition function 之前评估，
  不满足条件的行直接跳过（不进入聚合状态机）。
  性能: 与 CASE WHEN 理论上等价，但优化器可能对 FILTER 做特殊优化。

对比:
  PostgreSQL: FILTER 子句（9.4+，SQL 标准）
  MySQL:      不支持 FILTER（只能用 CASE WHEN）
  Oracle:     不支持 FILTER（只能用 CASE WHEN 或 DECODE）
  SQL Server: 不支持 FILTER（只能用 CASE WHEN 或 IIF）
  BigQuery:   COUNTIF(), SUMIF()（专用函数，非标准）
  ClickHouse: -If 后缀函数（如 countIf, sumIf）

## GROUPING SETS / ROLLUP / CUBE (9.5+)

GROUPING SETS: 在一个查询中计算多种分组
```sql
SELECT city, status, COUNT(*)
FROM users GROUP BY GROUPING SETS ((city), (status), ());
```

等价于 3 个 GROUP BY 的 UNION ALL

ROLLUP: 层级汇总（小计+总计）
```sql
SELECT city, status, COUNT(*)
FROM users GROUP BY ROLLUP (city, status);
```

生成: (city,status), (city), () 三级汇总

CUBE: 所有维度组合
```sql
SELECT city, status, COUNT(*)
FROM users GROUP BY CUBE (city, status);
```

生成: (city,status), (city), (status), () 四种组合

GROUPING() 函数: 判断是否是汇总行
```sql
SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users GROUP BY ROLLUP (city);
```

GROUPING(city)=1 表示该行是 city 维度的汇总

实现: 优化器将 GROUPING SETS 转换为多个 Agg 节点（Mixed/Hashed/Sorted）

## 字符串 / 数组 / JSON 聚合

STRING_AGG (9.0+): 字符串聚合
```sql
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;
SELECT STRING_AGG(DISTINCT city, ', ') FROM users;
```

ARRAY_AGG: 聚合为数组
```sql
SELECT ARRAY_AGG(username ORDER BY username) FROM users;
SELECT department, ARRAY_AGG(DISTINCT name) FROM employees GROUP BY department;
```

JSON/JSONB 聚合
```sql
SELECT JSON_AGG(username) FROM users;                       -- JSON 数组
SELECT JSONB_AGG(ROW_TO_JSON(users.*)) FROM users;          -- JSONB 对象数组
SELECT JSON_OBJECT_AGG(username, age) FROM users;           -- JSON 对象

-- 设计对比:
--   PostgreSQL: STRING_AGG + ARRAY_AGG + JSON_AGG（三种聚合并存）
--   MySQL:      GROUP_CONCAT（唯一的字符串聚合，无 ARRAY/JSON 聚合）
--   Oracle:     LISTAGG (11gR2+)
--   SQL Server: STRING_AGG (2017+)
```

## 有序集聚合 (Ordered-Set Aggregates)

PERCENTILE_CONT / PERCENTILE_DISC: 百分位数
```sql
SELECT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) AS p25,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) AS p75
FROM employee_salaries;
```

MODE(): 众数
```sql
SELECT MODE() WITHIN GROUP (ORDER BY city) FROM users;
```

WITHIN GROUP 的设计:
  有序集聚合需要对输入排序后计算（如中位数需要排序）。
  WITHIN GROUP (ORDER BY ...) 指定排序规则。
  这与普通聚合的 ORDER BY 不同——普通聚合的 ORDER BY 影响输出顺序，
  有序集聚合的 ORDER BY 影响计算语义。

## 统计聚合函数

```sql
SELECT STDDEV(amount) FROM orders;                      -- 样本标准差
SELECT STDDEV_POP(amount) FROM orders;                  -- 总体标准差
SELECT VARIANCE(amount) FROM orders;                    -- 样本方差
SELECT CORR(x, y) FROM data;                           -- 相关系数
SELECT REGR_SLOPE(y, x), REGR_INTERCEPT(y, x) FROM data; -- 线性回归

-- 布尔聚合
SELECT BOOL_AND(active) FROM users;                     -- 所有为 TRUE
SELECT BOOL_OR(active) FROM users;                      -- 任一为 TRUE
SELECT EVERY(active) FROM users;                        -- SQL 标准的 BOOL_AND

-- 位聚合
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;
```

## 聚合内部实现: 哈希聚合 vs 排序聚合

PostgreSQL 聚合有两种执行策略:
  HashAggregate: 用哈希表按 GROUP BY 键分桶，每桶维护聚合状态
    优点: O(n) 时间，不需要排序
    缺点: 内存消耗大（哈希表可能溢出到磁盘）
  GroupAggregate: 先排序，然后顺序扫描合并
    优点: 内存可控（流式处理）
    缺点: 需要排序 O(n log n)

work_mem 参数决定哈希表的内存上限。超过后:
  13+ 哈希聚合支持磁盘溢出（disk-based hash aggregate）
  13 之前超过 work_mem 会切换到排序聚合

```sql
EXPLAIN SELECT city, COUNT(*) FROM users GROUP BY city;
```

观察使用 HashAggregate 还是 GroupAggregate

## 横向对比: 聚合能力

### FILTER 子句

  PostgreSQL: 原生支持（9.4+，SQL 标准）
  其他主流数据库: 均不支持（MySQL/Oracle/SQL Server）

### GROUPING SETS

  PostgreSQL: 9.5+
  MySQL:      8.0+（WITH ROLLUP 早就有，GROUPING SETS 更晚）
  Oracle:     9i+（最早支持）
  SQL Server: 2008+

### 自定义聚合函数

  PostgreSQL: CREATE AGGREGATE（可用 SQL/PL 定义新聚合）
  Oracle:     CREATE AGGREGATE FUNCTION（需要对象类型）
  MySQL:      UDF（C/C++ 编写，复杂）
  ClickHouse: -State/-Merge 组合函数（独特但强大）

## 对引擎开发者的启示

(1) FILTER 子句的实现成本很低（只需在 transition function 前加条件判断），
    但对用户体验提升巨大。新引擎应该从第一天就支持。

(2) 哈希聚合的磁盘溢出（13+）是关键改进:
    之前 work_mem 不够时只能回退到排序聚合，现在可以优雅降级。

(3) PostgreSQL 的 CREATE AGGREGATE 允许用 SQL 定义自定义聚合:
    不需要 C 代码，只需提供 sfunc（状态转移函数）和 finalfunc（最终函数）。
    这种可扩展性是 PostgreSQL 生态丰富的原因之一。

## 版本演进

PostgreSQL 9.0:  STRING_AGG
PostgreSQL 9.4:  FILTER 子句, 有序集聚合（PERCENTILE_CONT 等）
PostgreSQL 9.5:  GROUPING SETS / ROLLUP / CUBE
PostgreSQL 10:   并行聚合（Parallel HashAggregate/GroupAggregate）
PostgreSQL 13:   HashAggregate 磁盘溢出
PostgreSQL 14:   改进 GroupAggregate 的增量排序支持
PostgreSQL 16:   ANY_VALUE() 聚合函数（SQL 标准）
