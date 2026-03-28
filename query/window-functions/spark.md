# Spark SQL: 窗口函数 (Window Functions)

> 参考资料:
> - [1] Spark SQL - Window Functions
>   https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-window.html


## 1. 排名函数

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

## 2. 聚合窗口函数

```sql
SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER () AS avg_age,
    COUNT(*)   OVER () AS total_count,
    MIN(age)   OVER (PARTITION BY city) AS city_min_age,
    MAX(age)   OVER (PARTITION BY city) AS city_max_age
FROM users;

```

## 3. 偏移函数

```sql
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age,
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    LAST_VALUE(username) OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM users;

```

NTH_VALUE（Spark 3.1+）

```sql
SELECT username, age,
    NTH_VALUE(username, 2) OVER (ORDER BY age) AS second_youngest
FROM users;

```

 LAST_VALUE 的陷阱:
   默认窗口帧是 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
   这意味着 LAST_VALUE 返回的是"到当前行为止的最后值"，而非分区的最后值
   必须显式指定 ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
   这是所有 SQL 引擎的共同陷阱（MySQL/PostgreSQL/Oracle 都一样）

## 4. 分布函数

```sql
SELECT username, age,
    NTILE(4)       OVER (ORDER BY age) AS quartile,
    PERCENT_RANK() OVER (ORDER BY age) AS pct_rank,
    CUME_DIST()    OVER (ORDER BY age) AS cume_dist
FROM users;

```

## 5. 命名窗口（Spark 3.0+）

```sql
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(age)     OVER w AS prev_age
FROM users
WINDOW w AS (ORDER BY age);

```

 命名窗口减少了重复的窗口定义:
 对比: PostgreSQL 9.0+ 也支持 WINDOW 子句（SQL 标准语法）

## 6. 帧子句（Frame Clause）


ROWS 帧（物理行偏移）

```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

```

RANGE 帧（逻辑值范围）

```sql
SELECT username, age,
    COUNT(*) OVER (ORDER BY age RANGE BETWEEN 5 PRECEDING AND 5 FOLLOWING) AS nearby_count
FROM users;

```

无界帧

```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY age ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total,
    SUM(age) OVER (ORDER BY age ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS remaining
FROM users;

```

 ROWS vs RANGE:
   ROWS: 基于物理行位置（第 N 行前/后）
   RANGE: 基于排序值的逻辑范围（值在 [current - N, current + N] 内的行）
   GROUPS: 基于分组位置（Spark 3.0+）

## 7. Top-N 分组（最常用的窗口函数模式）

```sql
SELECT * FROM (
    SELECT username, city, age,
        ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t
WHERE rn <= 3;

```

 无 QUALIFY 子句:
   Spark 不支持 QUALIFY（必须用子查询包装）
   对比: BigQuery/Snowflake 支持 QUALIFY 直接过滤窗口函数结果
   推荐方案: 子查询 + WHERE rn <= N

## 8. 累计与滚动计算

```sql
SELECT order_date, amount,
    SUM(amount) OVER (ORDER BY order_date) AS cumulative_sum,
    AVG(amount) OVER (ORDER BY order_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS weekly_avg
FROM daily_sales;

```

## 9. Spark 窗口函数的分布式执行


 窗口函数的执行机制:
### 1. PARTITION BY 决定数据如何 Shuffle（每个分区在一个 Executor 上计算）

### 2. ORDER BY 在每个分区内排序

### 3. 窗口帧在排序后的数据上滑动计算


 无 PARTITION BY 的窗口函数（如 OVER (ORDER BY id)）:
   所有数据 Shuffle 到单个分区——性能瓶颈！
   在大数据集上应尽量避免全局排序窗口

## 10. 版本演进

Spark 1.4: 基本窗口函数（ROW_NUMBER, RANK, LAG, LEAD, SUM/AVG OVER）
Spark 3.0: 命名窗口（WINDOW w AS），GROUPS 帧模式
Spark 3.1: NTH_VALUE
Spark 3.2: 窗口函数优化

限制:
无 QUALIFY 子句（必须用子查询过滤窗口函数结果）
无 FILTER 子句（不能在窗口函数上使用 FILTER）
RANGE 帧不支持 INTERVAL（只支持数值范围）
无 PARTITION BY 的窗口函数导致单分区全排序（性能问题）
GROUPS 帧模式 Spark 3.0+

