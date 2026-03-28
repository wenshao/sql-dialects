# MySQL: 窗口函数

> 参考资料:
> - [MySQL 8.0 Reference Manual - Window Functions](https://dev.mysql.com/doc/refman/8.0/en/window-functions.html)
> - [MySQL 8.0 Reference Manual - Window Function Concepts](https://dev.mysql.com/doc/refman/8.0/en/window-functions-usage.html)
> - [MySQL 8.0 Reference Manual - Window Function Frame Specification](https://dev.mysql.com/doc/refman/8.0/en/window-functions-frames.html)

## 基本语法

ROW_NUMBER / RANK / DENSE_RANK
```sql
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;
```

分区
```sql
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;
```

聚合窗口函数
```sql
SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER () AS avg_age,
    COUNT(*)   OVER () AS total_count,
    MIN(age)   OVER (PARTITION BY city) AS city_min_age,
    MAX(age)   OVER (PARTITION BY city) AS city_max_age
FROM users;
```

偏移函数
```sql
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age,
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    LAST_VALUE(username)  OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM users;
```

NTILE（分桶）
```sql
SELECT username, age,
    NTILE(4) OVER (ORDER BY age) AS quartile
FROM users;
```

PERCENT_RANK / CUME_DIST
```sql
SELECT username, age,
    PERCENT_RANK() OVER (ORDER BY age) AS pct_rank,
    CUME_DIST()    OVER (ORDER BY age) AS cume_dist
FROM users;
```

## 窗口函数的执行模型（对引擎开发者关键）

### 执行流程（三阶段模型）

窗口函数在 SELECT 计算阶段执行，位于 WHERE/GROUP BY/HAVING 之后、ORDER BY 之前:

阶段 1: 排序（Sort）
  将结果集按 PARTITION BY + ORDER BY 排序
  如果多个窗口函数有不同的 PARTITION BY / ORDER BY，可能需要多次排序
  排序是窗口函数的主要性能瓶颈（O(n log n)）

阶段 2: 分区扫描（Partition Scan）
  按分区边界划分数据组，每个分区独立计算
  分区边界检测: 当排序后的 PARTITION BY 列值变化时，开始新分区

阶段 3: 帧计算（Frame Computation）
  在每个分区内，对每一行计算其帧范围，然后在帧上执行聚合
  帧类型决定计算方式:
    ROWS: 物理行偏移（精确到行）
    RANGE: 逻辑值范围（相同值的行归入同一帧位置）
    GROUPS (SQL 标准，MySQL 不支持): 按 peer group 偏移

### MySQL 的内部实现

MySQL 8.0 的窗口函数实现基于 "buffered window frame":
  (1) 排序后的结果存入临时表（内存或磁盘）
  (2) 对每一行，通过移动帧边界指针计算聚合值
  (3) 优化: 如果帧是累积的（如 UNBOUNDED PRECEDING AND CURRENT ROW），
      使用增量计算（不重复计算整个帧，只加减边界行）

性能影响:
  - PARTITION BY 列没有索引: 全量排序（filesort）
  - 多个窗口函数不同的 ORDER BY: 多次排序（每次 O(n log n)）
  - 帧范围大: 每行的计算代价与帧大小成正比（除非增量计算）

优化建议:
  (1) 尽量让多个窗口函数共享相同的 PARTITION BY + ORDER BY
  (2) 使用命名窗口 WINDOW 子句（见第 4 节）确保共享
  (3) 对 PARTITION BY 列建索引可能帮助排序（但不一定，取决于优化器）
  (4) 减少 SELECT 的行数（WHERE 过滤在窗口计算之前）

## 默认帧的陷阱（最常见的窗口函数 Bug）

### 默认帧规则（SQL 标准）

当窗口函数有 ORDER BY 时，默认帧是:
  RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
当窗口函数没有 ORDER BY 时，默认帧是:
  RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING（即整个分区）

### RANGE vs ROWS 的关键区别

RANGE CURRENT ROW: 包含所有与当前行 ORDER BY 值相同的行（peer group）
ROWS CURRENT ROW:  仅包含当前物理行

陷阱示例:
```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY age) AS running_sum
FROM users;
```

默认帧: RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
如果有多行 age=25: 这些行的 running_sum 全部相同（包含了所有 age<=25 的行）
如果期望的是"严格的逐行累积"，应该用 ROWS:
```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY age ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
    AS strict_running_sum
FROM users;
```

### NTH_VALUE / LAST_VALUE 的默认帧陷阱

NTH_VALUE 和 LAST_VALUE 受默认帧影响最严重:
```sql
SELECT username, age,
    LAST_VALUE(username) OVER (ORDER BY age) AS last_user
FROM users;
```

直觉: last_user 应该是年龄最大的用户
实际: 默认帧只到 CURRENT ROW，所以 LAST_VALUE 返回当前行自己！
修正: 必须显式指定完整帧:
```sql
SELECT username, age,
    LAST_VALUE(username) OVER (ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_user
FROM users;
```

NTH_VALUE 同理:
```sql
SELECT username, age,
    NTH_VALUE(username, 2) OVER (ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS second_youngest
FROM users;
```

没有显式帧: 第一行看不到第 2 行，返回 NULL（因为帧只到 CURRENT ROW）

### LAG/LEAD/ROW_NUMBER/RANK 不受帧影响

这些函数忽略帧子句（按整个分区计算），所以没有默认帧陷阱

## 命名窗口 WINDOW 子句（减少重复和错误）

命名窗口: 定义一次，多处引用
```sql
SELECT username, age, city,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(age)     OVER w AS prev_age,
    SUM(age)     OVER w AS running_sum
FROM users
WINDOW w AS (PARTITION BY city ORDER BY age);
```

命名窗口 + 帧覆盖（在引用时添加帧子句）
```sql
SELECT username, age,
    SUM(age) OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumsum,
    AVG(age) OVER (w ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS moving_avg
FROM users
WINDOW w AS (ORDER BY id);
```

w 定义了排序，具体帧在使用时指定
限制: 引用时不能修改 PARTITION BY 或 ORDER BY（只能添加帧子句）

命名窗口的设计价值:
  (1) 减少重复代码（DRY 原则）
  (2) 确保多个窗口函数共享相同的排序（优化器只排一次）
  (3) 减少默认帧错误（帧定义集中管理）

## 帧子句详解

ROWS 帧（物理行偏移）
```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
    AS rolling_sum_3,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING)
    AS moving_avg_3
FROM users;
```

RANGE 帧（逻辑值范围）
示例: 计算前后 5 岁范围内的平均年龄
```sql
SELECT username, age,
    AVG(age) OVER (ORDER BY age RANGE BETWEEN 5 PRECEDING AND 5 FOLLOWING)
    AS avg_age_within_5
FROM users;
```

MySQL 不支持的帧类型:
  GROUPS 帧（SQL:2011 标准）: 按 peer group 偏移
  PG 11+ 支持 GROUPS，MySQL 8.0 不支持
  EXCLUDE 子句（EXCLUDE CURRENT ROW / EXCLUDE TIES）: MySQL 不支持

## 横向对比: 窗口函数的方言差异

### QUALIFY 子句（Snowflake/Teradata/BigQuery/DuckDB）

> **问题**: 如何过滤窗口函数的结果（如取每组 Top-1）?

MySQL（需要子查询包装）:
```sql
SELECT * FROM (
    SELECT username, city, age,
           ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) ranked WHERE rn = 1;
```

Snowflake/BigQuery（QUALIFY 直接过滤，不需要子查询）:
```sql
SELECT username, city, age
```

FROM users
QUALIFY ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) = 1;

QUALIFY 的设计价值:
  (1) 消除嵌套子查询（更简洁）
  (2) 减少临时表物化（可能更高效）
  (3) 语义清晰: WHERE 过滤行 → GROUP BY 分组 → HAVING 过滤组 → QUALIFY 过滤窗口结果

对引擎开发者的启示:
  QUALIFY 实现简单（在窗口函数计算后加一层过滤），但价值很大。
  如果引擎已有窗口函数支持，建议添加 QUALIFY（几乎无额外实现成本）。

### 各引擎窗口函数支持对比

| 特性                | MySQL 8.0 | PG 14+ | Oracle | SQL Server | ClickHouse |
|--------------------|-----------|--------|--------|------------|------------|
| ROW_NUMBER/RANK    | Yes       | Yes    | Yes    | Yes        | Yes        |
| QUALIFY            | No        | No     | No     | No         | No         |
| GROUPS 帧          | No        | 11+    | Yes    | No         | No         |
| EXCLUDE 子句       | No        | 11+    | Yes    | No         | No         |
| 命名窗口 WINDOW     | Yes       | Yes    | No     | No         | No         |
| RANGE INTERVAL      | No        | Yes    | Yes    | No         | No         |
| RESPECT/IGNORE NULLS| No       | Yes    | Yes    | Yes        | No         |

### 窗口函数 vs CTE vs 子查询的方案选择

> **问题**: "每个部门工资最高的员工"

方案 A: 窗口函数（最标准）
```sql
SELECT * FROM (SELECT *, RANK() OVER (PARTITION BY dept ORDER BY salary DESC) AS rn FROM emp) t WHERE rn = 1;
```

优点: 标准 SQL，一次扫描
缺点: 需要物化全部结果（带 rn）再过滤

方案 B: 关联子查询
```sql
SELECT * FROM emp e WHERE salary = (SELECT MAX(salary) FROM emp WHERE dept = e.dept);
```

优点: 不需要物化临时结果
缺点: 对每行执行子查询（无优化时 O(n*m)）

方案 C: CTE（PostgreSQL 风格）
```sql
WITH ranked AS (...) SELECT * FROM ranked WHERE rn = 1;
```

MySQL 8.0: CTE 总是物化（性能可能比子查询差，见 cte/mysql.sql）

## 对引擎开发者: 窗口函数的实现要点

(1) 排序优化是核心
  窗口函数的主要开销在排序。如果 ORDER BY 能利用已有索引，性能提升巨大。
  多个窗口函数共享相同的排序时，应只排序一次（MySQL 8.0 已实现）。
  排序溢出到磁盘时的性能退化需要关注（tmp_table_size / max_heap_table_size）。

(2) 帧计算的增量优化
  SUM/COUNT/AVG 等可结合的聚合函数: 帧滑动时只加减边界行（O(1) per row）
  MIN/MAX: 需要维护有序结构（如堆）或退化为扫描帧（O(k) per row）
  NTH_VALUE: 需要随机访问帧中的第 N 行（O(1) 如果有缓冲，否则 O(k)）

(3) 内存管理
  每个分区的数据需要缓存（用于帧计算）
  大分区可能导致内存溢出 → 需要溢出到磁盘的机制
  MySQL 使用内部临时表（MEMORY 或 InnoDB）存储排序后的数据

(4) 并行执行
  不同分区之间可以并行计算（分区间独立）
  MySQL 8.0 尚未实现窗口函数的并行执行
  PG 的 parallel window 从 11 开始部分支持

## 版本演进

MySQL 8.0:    窗口函数首次引入（ROW_NUMBER, RANK, DENSE_RANK, LAG, LEAD,
              FIRST_VALUE, LAST_VALUE, NTH_VALUE, NTILE, PERCENT_RANK,
              CUME_DIST, 命名窗口 WINDOW 子句）
MySQL 8.0:    聚合函数（SUM/AVG/COUNT/MIN/MAX）可用作窗口函数
MySQL 8.0:    支持 ROWS 和 RANGE 帧（不支持 GROUPS）
MySQL 8.0:    不支持 QUALIFY（目前无计划）
MySQL 8.0:    不支持 RESPECT NULLS / IGNORE NULLS
