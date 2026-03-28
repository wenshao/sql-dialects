# Oracle: 窗口函数

> 参考资料:
> - [Oracle SQL Language Reference - Analytic Functions](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Analytic-Functions.html)

## 历史背景: Oracle 开创了窗口函数

Oracle 8i (1999) 是第一个实现分析函数（Analytic Functions）的数据库。
这些函数后来被纳入 SQL:2003 标准，命名为"窗口函数"（Window Functions）。
Oracle 的术语"分析函数"至今仍在使用。

时间线:
  Oracle 8i (1999):   首创 OVER()、ROW_NUMBER、RANK、LAG/LEAD 等
  SQL:2003:           标准化为 Window Functions
  PostgreSQL 8.4 (2009): 实现窗口函数
  SQL Server 2005:    实现窗口函数（部分）
  MySQL 8.0 (2018):   才实现窗口函数（落后近 20 年）

## 排名函数

```sql
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
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
    SUM(age) OVER () AS total_age,
    AVG(age) OVER () AS avg_age,
    COUNT(*) OVER () AS total_count,
    MIN(age) OVER (PARTITION BY city) AS city_min,
    MAX(age) OVER (PARTITION BY city) AS city_max
FROM users;
```

## 偏移函数

```sql
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age,
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    LAST_VALUE(username)  OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM users;
```

NTH_VALUE（11g R2+）
```sql
SELECT username, age,
    NTH_VALUE(username, 2) OVER (ORDER BY age) AS second_youngest
FROM users;
```

NTILE（分桶）
```sql
SELECT username, age, NTILE(4) OVER (ORDER BY age) AS quartile FROM users;
```

## Oracle 独有的分析函数

### RATIO_TO_REPORT: 计算占比（Oracle 独有）

```sql
SELECT username, age,
    RATIO_TO_REPORT(age) OVER () AS age_ratio
FROM users;
```

其他数据库需要: age * 1.0 / SUM(age) OVER ()

### KEEP (DENSE_RANK FIRST/LAST): 组内取特定排名的聚合值

```sql
SELECT city,
    MIN(age) KEEP (DENSE_RANK FIRST ORDER BY created_at) AS first_user_age,
    MIN(age) KEEP (DENSE_RANK LAST ORDER BY created_at) AS last_user_age
FROM users GROUP BY city;
```

KEEP 是聚合函数（GROUP BY 中使用），不是窗口函数
但它解决的是典型的窗口函数场景: "每组中按某排序取值"

### LISTAGG 作为窗口函数（11g R2+）

```sql
SELECT username, city,
    LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username)
        OVER (PARTITION BY city) AS city_users
FROM users;
```

## 帧子句（Window Frame，Oracle 的实现最完善）

ROWS 帧（按物理行数）
```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum
FROM users;
```

RANGE 帧（按值范围，Oracle 独有的 INTERVAL 支持）
```sql
SELECT username, age,
    AVG(age) OVER (ORDER BY created_at
        RANGE BETWEEN INTERVAL '7' DAY PRECEDING AND CURRENT ROW) AS weekly_avg
FROM users;
```

设计分析: ROWS vs RANGE vs GROUPS
  ROWS:   按物理行偏移（最常用，性能最好）
  RANGE:  按值范围偏移（需要排序列的值计算）
  GROUPS: 按排序键分组偏移（21c+，SQL:2011 标准）

Oracle 对 RANGE + INTERVAL 的支持是独有的:
  RANGE BETWEEN INTERVAL '7' DAY PRECEDING
这在其他数据库中需要:
  PostgreSQL: 也支持 RANGE + INTERVAL（9.0+）
  MySQL:      RANGE 只支持数值，不支持 INTERVAL
  SQL Server: RANGE 只支持 UNBOUNDED/CURRENT ROW

## PERCENT_RANK / CUME_DIST

```sql
SELECT username, age,
    PERCENT_RANK() OVER (ORDER BY age) AS pct_rank,
    CUME_DIST()    OVER (ORDER BY age) AS cume_dist
FROM users;
```

## IGNORE NULLS（Oracle 首创，极其实用）

LAG/LEAD/FIRST_VALUE/LAST_VALUE 都支持 IGNORE NULLS
```sql
SELECT username,
    LAG(age IGNORE NULLS) OVER (ORDER BY id) AS prev_non_null_age,
    LAST_VALUE(age IGNORE NULLS) OVER (
        ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS last_non_null_age
FROM users;
```

场景: 数据间隙填充（用最近的非 NULL 值填充）
由于 '' = NULL，空字符串也会被 IGNORE NULLS 跳过

横向对比:
  Oracle:     IGNORE NULLS（8i+，最早支持）
  PostgreSQL: 不支持 IGNORE NULLS（需要复杂的子查询替代）
  SQL Server: 不支持 IGNORE NULLS（2022 才加入）
  MySQL:      不支持 IGNORE NULLS

## MODEL 子句（Oracle 10g+ 独有，电子表格式计算）

Oracle 还有一个独特的 MODEL 子句，可以实现类似 Excel 的行间引用计算。
语法极其复杂，实际使用率低，但展示了 Oracle 在 SQL 表达能力上的极限追求。
详见 window-analytics 场景文件。

## 对引擎开发者的总结

1. Oracle 是窗口函数的发明者（8i, 1999），其他数据库是跟随者。
2. RATIO_TO_REPORT、KEEP (DENSE_RANK)、IGNORE NULLS 是 Oracle 独有且实用的特性。
3. RANGE + INTERVAL 帧支持使时间序列分析更自然。
### 窗口函数是现代 SQL 引擎的必备功能，至少需要实现

   ROW_NUMBER, RANK, DENSE_RANK, LAG, LEAD, FIRST_VALUE, LAST_VALUE,
   SUM/AVG/COUNT/MIN/MAX OVER(), NTILE, PERCENT_RANK, CUME_DIST
5. IGNORE NULLS 对数据填充场景价值极大，建议优先实现。
