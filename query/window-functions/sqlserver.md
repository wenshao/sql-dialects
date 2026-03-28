# SQL Server: 窗口函数

> 参考资料:
> - [SQL Server T-SQL - OVER Clause](https://learn.microsoft.com/en-us/sql/t-sql/queries/select-over-clause-transact-sql)
> - [SQL Server T-SQL - Analytic Functions](https://learn.microsoft.com/en-us/sql/t-sql/functions/analytic-functions-transact-sql)

## 排名函数（SQL Server 2005+ 首批支持）

```sql
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,       -- 跳号排名 (1,2,2,4)
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk,  -- 不跳号 (1,2,2,3)
    NTILE(4)     OVER (ORDER BY age) AS quartile
FROM users;
```

分区排名
```sql
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;
```

## 聚合窗口函数

```sql
SELECT username, age,
    SUM(age) OVER ()                          AS total_age,
    AVG(age) OVER ()                          AS avg_age,
    COUNT(*) OVER ()                          AS total_count,
    MIN(age) OVER (PARTITION BY city)         AS city_min,
    MAX(age) OVER (PARTITION BY city)         AS city_max
FROM users;
```

## 偏移函数（SQL Server 2012+）

```sql
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LAG(age, 1, 0) OVER (ORDER BY id) AS prev_age_or_zero,  -- 第3参数=默认值
    LEAD(age, 1) OVER (ORDER BY id) AS next_age,
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    LAST_VALUE(username)  OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM users;
```

SQL Server 不支持 NTH_VALUE（PostgreSQL 支持）
替代方案: ROW_NUMBER + CTE
```sql
;WITH ranked AS (
    SELECT username, city, age,
           ROW_NUMBER() OVER (PARTITION BY city ORDER BY age) AS rn
    FROM users
)
SELECT city, username AS second_youngest
FROM ranked WHERE rn = 2;
```

## 帧子句: ROWS vs RANGE（2012+）

```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;
```

设计分析（对引擎开发者）:
  ROWS vs RANGE 的关键区别:
  ROWS: 物理行偏移（第 2 行之前）
  RANGE: 逻辑值偏移（值相同的行视为同一组）

  SQL Server 的默认帧（当只有 ORDER BY 没有显式帧时）:
  RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  这个默认值有性能陷阱——RANGE 比 ROWS 慢得多（需要处理重复值的分组）。

  最佳实践: 总是显式指定 ROWS 帧。
  SUM(x) OVER (ORDER BY id)  -- 隐式 RANGE, 较慢
  SUM(x) OVER (ORDER BY id ROWS UNBOUNDED PRECEDING)  -- 显式 ROWS, 更快

SQL Server 不支持 RANGE + 数值偏移:
  PostgreSQL: RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW（支持）
  SQL Server: 不支持——必须用 ROWS 或自连接实现日期范围窗口

## PERCENTILE_CONT / PERCENTILE_DISC（2012+）

SQL Server 中这两个函数只能用作窗口函数（不能用作聚合函数）
必须使用 WITHIN GROUP ... OVER (PARTITION BY ...)
```sql
SELECT DISTINCT department,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary)
        OVER (PARTITION BY department) AS median_salary,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY salary)
        OVER (PARTITION BY department) AS median_discrete
FROM employees;
```

横向对比:
  PostgreSQL: 支持 PERCENTILE_CONT 作为聚合函数（GROUP BY 中使用）
  Oracle:     两种模式都支持
  SQL Server: 只支持窗口模式（必须用 DISTINCT + OVER）——设计较不灵活

## PERCENT_RANK / CUME_DIST（2012+）

```sql
SELECT username, age,
    PERCENT_RANK() OVER (ORDER BY age) AS pct_rank,   -- (rank-1)/(n-1)
    CUME_DIST()    OVER (ORDER BY age) AS cume_dist    -- rank/n
FROM users;
```

## 不支持 WINDOW 子句（2022+ 预览）

SQL 标准的命名窗口（WINDOW 子句）在 SQL Server 2022 预览中才开始支持:
```sql
SELECT ... OVER w FROM users WINDOW w AS (ORDER BY age);
```

此前，每个窗口函数都必须重复写 OVER 子句。

当前的冗余写法:
```sql
SELECT username, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age) AS rn,
    LAG(age)     OVER (PARTITION BY city ORDER BY age) AS prev,
    SUM(age)     OVER (PARTITION BY city ORDER BY age ROWS UNBOUNDED PRECEDING) AS running
FROM users;
```

(PARTITION BY city ORDER BY age) 重复了 3 次

横向对比:
  PostgreSQL: 8.4+ 支持 WINDOW 子句（最早的主流实现）
  MySQL:      8.0+ 支持 WINDOW 子句
  Oracle:     不支持 WINDOW 子句
  SQL Server: 2022+ 预览

对引擎开发者的启示:
  WINDOW 子句的实现相对简单（解析器在预处理阶段展开即可），
  但对用户体验提升很大。应该优先支持。

## 窗口函数的执行计划（对引擎开发者）

SQL Server 的窗口函数执行使用两种模式:
  (1) Row Mode: 逐行处理（2005-2016 默认）
  (2) Batch Mode: 批处理（2016+ 对列存索引表自动启用）

2019+: Batch Mode on Rowstore——即使没有列存索引也使用批处理模式
这使得窗口函数性能提升 2-10x（尤其是多窗口函数的查询）。

对引擎开发者的启示:
  窗口函数是批处理执行的最佳受益者——批处理减少了逐行函数调用的开销。
  SQL Server 将批处理模式从列存专属扩展到所有表是一个重要的优化决策。
  现代引擎应该默认使用向量化执行来处理窗口函数。
