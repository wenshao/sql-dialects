# WITHIN GROUP 有序集合聚合

先收集、再排序、最后计算——SQL:2003 标准引入的有序集合聚合框架，让 PERCENTILE、LISTAGG 等需要排序的聚合函数有了标准化的语法。

## 支持矩阵

### PERCENTILE_CONT / PERCENTILE_DISC

| 引擎 | 支持 | 版本 | 语法风格 | 备注 |
|------|------|------|---------|------|
| Oracle | 完整支持 | 9i+ | `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ...)` | 最早实现 |
| PostgreSQL | 完整支持 | 9.4+ | `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ...)` | 标准语法 |
| SQL Server | 完整支持 | 2012+ | `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ...)` | 仅作窗口函数使用 |
| Snowflake | 完整支持 | GA | `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ...)` | - |
| DuckDB | 完整支持 | 0.5+ | `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ...)` | - |
| Db2 | 完整支持 | 9.7+ | 标准语法 | - |
| MySQL | 不支持 | - | 需窗口函数模拟 | - |
| ClickHouse | 不支持 | - | `quantile(0.5)(col)` — 私有语法 | - |
| BigQuery | 不支持 | - | `PERCENTILE_CONT(col, 0.5) OVER()` — 窗口函数语法 | - |
| Trino | 不支持 | - | `approx_percentile` — 仅近似版本 | - |

### LISTAGG / STRING_AGG / GROUP_CONCAT

| 引擎 | 函数名 | WITHIN GROUP | 版本 | 备注 |
|------|--------|-------------|------|------|
| Oracle | `LISTAGG` | 需要 | 11gR2+ | **标准语法** |
| Snowflake | `LISTAGG` | 需要 | GA | 兼容 Oracle |
| Db2 | `LISTAGG` | 需要 | 9.7+ | 标准语法 |
| PostgreSQL | `STRING_AGG` | 不需要 | 9.0+ | 用 ORDER BY 子句替代 |
| PostgreSQL | `LISTAGG` | 不支持 | 16+ | PG 16 新增，但不用 WITHIN GROUP |
| SQL Server | `STRING_AGG` | 不需要 | 2017+ | WITHIN GROUP 仅用于 ORDER BY |
| MySQL | `GROUP_CONCAT` | 不需要 | 4.1+ | ORDER BY 在函数内部 |
| DuckDB | `STRING_AGG` / `LISTAGG` | 都支持 | 0.6+ | 兼容两种语法 |
| ClickHouse | `groupArray` + `arrayStringConcat` | 不需要 | - | 需两步操作 |
| BigQuery | `STRING_AGG` | 不需要 | GA | ORDER BY 在函数内部 |

### MODE（众数）

| 引擎 | 支持 | 语法 |
|------|------|------|
| PostgreSQL | 支持 | `MODE() WITHIN GROUP (ORDER BY col)` |
| DuckDB | 支持 | `MODE(col)` — 不使用 WITHIN GROUP |
| Oracle | 不支持 | 需 PL/SQL 或分析函数模拟 |
| 其他引擎 | 不支持 | 需 GROUP BY + COUNT + ORDER BY 模拟 |

## 设计动机: 排序依赖的聚合问题

### 为什么聚合函数需要排序？

普通聚合函数（SUM, COUNT, MAX）的结果与输入顺序无关——加法满足交换律。但有些聚合函数的结果依赖输入顺序：

```
PERCENTILE_CONT(0.5): 需要将所有值排序后取中位数
LISTAGG: 需要按指定顺序拼接字符串
MODE: 需要计算频次后找最频繁的值（排序辅助）
```

这些函数需要一个机制来指定"先怎么排序，再怎么计算"。

### WITHIN GROUP 的语义

```sql
PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary)
```

语义拆解：
1. **收集**: 在当前分组内收集所有 salary 值
2. **排序**: 按 ORDER BY salary 排序
3. **计算**: 在排好序的值列表上计算第 50 百分位数

WITHIN GROUP 告诉引擎："在执行这个聚合函数之前，先把数据按指定方式排序。"

## 语法详解

### PERCENTILE_CONT（连续分位数）

```sql
-- 语义: 如果分位点落在两个值之间，线性插值
PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary)
-- salary: [30000, 50000, 70000, 90000]
-- 中位数: 0.5 位于第 2 和第 3 个值之间
-- 结果: (50000 + 70000) / 2 = 60000

-- 分位点参数: 0 到 1 之间的小数
PERCENTILE_CONT(0.25) -- 第 25 百分位（Q1）
PERCENTILE_CONT(0.5)  -- 第 50 百分位（中位数）
PERCENTILE_CONT(0.75) -- 第 75 百分位（Q3）
PERCENTILE_CONT(0.99) -- 第 99 百分位（P99）
```

### PERCENTILE_DISC（离散分位数）

```sql
-- 语义: 返回排序后第一个累积比例 >= 分位点的实际值（不插值）
PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY salary)
-- salary: [30000, 50000, 70000, 90000]
-- 累积比例: [0.25, 0.5, 0.75, 1.0]
-- 0.5 百分位: 第一个 >= 0.5 的值 → 50000
-- 结果: 50000（实际存在的值）
```

### CONT vs DISC 的区别

```
数据: [10, 20, 30, 40]

PERCENTILE_CONT(0.3):
  位置 = 0.3 * (4-1) = 0.9
  在第 1 个和第 2 个值之间
  结果 = 10 + 0.9 * (20 - 10) = 19.0  ← 插值结果，可能不在原数据中

PERCENTILE_DISC(0.3):
  累积比例: [0.25, 0.5, 0.75, 1.0]
  第一个 >= 0.3 的位置: 0.5 对应值 20
  结果 = 20  ← 原数据中的实际值
```

## 各引擎语法对比

### Oracle（标准 WITHIN GROUP）

```sql
-- PERCENTILE_CONT: 连续分位数
SELECT dept_id,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median_salary,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY salary) AS p90_salary
FROM employees
GROUP BY dept_id;

-- LISTAGG: 字符串拼接
SELECT dept_id,
    LISTAGG(emp_name, ', ') WITHIN GROUP (ORDER BY hire_date) AS emp_list
FROM employees
GROUP BY dept_id;

-- LISTAGG 去重（Oracle 19c+）
SELECT dept_id,
    LISTAGG(DISTINCT job_title, ', ') WITHIN GROUP (ORDER BY job_title) AS titles
FROM employees
GROUP BY dept_id;

-- LISTAGG 截断溢出（Oracle 12cR2+）
SELECT dept_id,
    LISTAGG(emp_name, ', ' ON OVERFLOW TRUNCATE '...' WITHOUT COUNT)
        WITHIN GROUP (ORDER BY emp_name) AS emp_list
FROM employees
GROUP BY dept_id;
```

### PostgreSQL

```sql
-- PERCENTILE_CONT / PERCENTILE_DISC（9.4+ 支持）
SELECT
    dept_id,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY salary) AS median_disc
FROM employees
GROUP BY dept_id;

-- MODE: 众数（PostgreSQL 独有的有序集合聚合函数）
SELECT
    dept_id,
    MODE() WITHIN GROUP (ORDER BY job_title) AS most_common_title
FROM employees
GROUP BY dept_id;

-- STRING_AGG: PostgreSQL 不用 WITHIN GROUP
-- 排序在函数内部指定
SELECT dept_id,
    STRING_AGG(emp_name, ', ' ORDER BY hire_date) AS emp_list
FROM employees
GROUP BY dept_id;

-- PostgreSQL 16 新增 LISTAGG（但不使用 WITHIN GROUP）
SELECT dept_id,
    LISTAGG(emp_name, ', ') AS emp_list  -- 不支持 WITHIN GROUP
FROM employees
GROUP BY dept_id;
```

### SQL Server

```sql
-- PERCENTILE_CONT: SQL Server 中仅作为窗口函数使用
-- 注意: 不能直接用 GROUP BY，必须用 OVER (PARTITION BY)
SELECT DISTINCT dept_id,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary)
        OVER (PARTITION BY dept_id) AS median_salary
FROM employees;
-- SQL Server 的 PERCENTILE_CONT 必须搭配 OVER 子句
-- 这与标准略有偏差（标准允许纯聚合用法）

-- STRING_AGG (2017+): 不使用 WITHIN GROUP
SELECT dept_id,
    STRING_AGG(emp_name, ', ') WITHIN GROUP (ORDER BY hire_date) AS emp_list
FROM employees
GROUP BY dept_id;
-- SQL Server 的 STRING_AGG WITHIN GROUP 仅用于 ORDER BY
```

### Snowflake

```sql
-- PERCENTILE_CONT / PERCENTILE_DISC: 标准语法
SELECT dept_id,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median
FROM employees
GROUP BY dept_id;

-- LISTAGG: 与 Oracle 兼容
SELECT dept_id,
    LISTAGG(emp_name, ', ') WITHIN GROUP (ORDER BY hire_date) AS emp_list
FROM employees
GROUP BY dept_id;

-- LISTAGG DISTINCT (Snowflake 支持)
SELECT dept_id,
    LISTAGG(DISTINCT skill, ', ') WITHIN GROUP (ORDER BY skill) AS skills
FROM employee_skills
GROUP BY dept_id;
```

### 等价改写: 不支持 WITHIN GROUP 的引擎

#### MySQL

```sql
-- 中位数: 窗口函数方案
-- MySQL 无 PERCENTILE 函数，需要手动实现
WITH ranked AS (
    SELECT salary,
           ROW_NUMBER() OVER (ORDER BY salary) AS rn,
           COUNT(*) OVER () AS total
    FROM employees WHERE dept_id = 1
)
SELECT AVG(salary) AS median
FROM ranked
WHERE rn IN (FLOOR((total + 1) / 2.0), CEIL((total + 1) / 2.0));

-- 字符串拼接: GROUP_CONCAT
SELECT dept_id,
    GROUP_CONCAT(emp_name ORDER BY hire_date SEPARATOR ', ') AS emp_list
FROM employees
GROUP BY dept_id;
-- GROUP_CONCAT 有长度限制: group_concat_max_len（默认 1024）
```

#### ClickHouse

```sql
-- 分位数: quantile 函数（不使用 WITHIN GROUP）
SELECT
    dept_id,
    quantile(0.5)(salary) AS median,
    quantiles(0.25, 0.5, 0.75)(salary) AS quartiles
FROM employees
GROUP BY dept_id;

-- 字符串拼接: groupArray + arrayStringConcat
SELECT dept_id,
    arrayStringConcat(groupArray(emp_name), ', ') AS emp_list
FROM employees
GROUP BY dept_id;

-- 带排序的拼接
SELECT dept_id,
    arrayStringConcat(
        arrayMap(x -> x.2,
            arraySort(x -> x.1, groupArray((hire_date, emp_name)))
        ), ', '
    ) AS emp_list
FROM employees
GROUP BY dept_id;
```

#### BigQuery

```sql
-- PERCENTILE_CONT: BigQuery 使用窗口函数语法
SELECT DISTINCT dept_id,
    PERCENTILE_CONT(salary, 0.5) OVER (PARTITION BY dept_id) AS median
FROM employees;
-- 注意参数顺序: BigQuery 是 PERCENTILE_CONT(col, fraction)
-- 标准是 PERCENTILE_CONT(fraction) WITHIN GROUP (ORDER BY col)

-- STRING_AGG: 内部 ORDER BY
SELECT dept_id,
    STRING_AGG(emp_name, ', ' ORDER BY hire_date) AS emp_list
FROM employees
GROUP BY dept_id;
```

## STRING_AGG vs LISTAGG vs GROUP_CONCAT 演进

字符串拼接聚合的历史演进：

```
1990s: Oracle 使用 WM_CONCAT（未文档化，不推荐）
2003:  MySQL 4.1 引入 GROUP_CONCAT（非标准但实用）
2009:  Oracle 11gR2 引入 LISTAGG WITHIN GROUP（SQL:2016 前的标准化尝试）
2010:  PostgreSQL 9.0 引入 STRING_AGG（函数内 ORDER BY）
2016:  SQL:2016 标准化 LISTAGG
2017:  SQL Server 引入 STRING_AGG
2024:  PostgreSQL 16 增加 LISTAGG
```

| 特性 | GROUP_CONCAT (MySQL) | STRING_AGG (PG/MSSQL) | LISTAGG (Oracle/SF) |
|------|---------------------|----------------------|---------------------|
| 排序语法 | `ORDER BY` 在函数内 | `ORDER BY` 在函数内 | `WITHIN GROUP (ORDER BY)` |
| 分隔符 | `SEPARATOR ','` | `','` 参数 | `','` 参数 |
| DISTINCT | 支持 | 不支持 (PG 18之前) | 支持 (Oracle 19c+) |
| 溢出处理 | `group_concat_max_len` | 无限制 | `ON OVERFLOW TRUNCATE` |
| NULL 处理 | 忽略 NULL | 忽略 NULL | 忽略 NULL |

## 实际用例

### 用例 1: 薪资分位数报告

```sql
-- Oracle / PostgreSQL / Snowflake
SELECT
    dept_id,
    COUNT(*) AS headcount,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) AS q1,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY salary) AS median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) AS q3,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY salary) AS p90,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) -
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) AS iqr
FROM employees
GROUP BY dept_id;
```

### 用例 2: 标签聚合展示

```sql
-- Oracle / Snowflake
SELECT product_id, product_name,
    LISTAGG(tag, ' | ') WITHIN GROUP (ORDER BY tag) AS tags
FROM product_tags
GROUP BY product_id, product_name;
-- 结果: "product_1 | 电子产品 | 手机 | 智能设备"
```

### 用例 3: 众数计算

```sql
-- PostgreSQL: 最常见的职位
SELECT dept_id,
    MODE() WITHIN GROUP (ORDER BY job_title) AS most_common_job
FROM employees
GROUP BY dept_id;

-- 其他引擎: 手动实现众数
SELECT dept_id, job_title AS most_common_job
FROM (
    SELECT dept_id, job_title,
           ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY COUNT(*) DESC) AS rn
    FROM employees
    GROUP BY dept_id, job_title
) t WHERE rn = 1;
```

## 对引擎开发者的实现分析

### 1. 有序集合聚合框架

有序集合聚合与普通聚合的核心区别：普通聚合可以增量计算（每来一行更新一次），有序集合聚合必须**先收集所有值，再排序，最后计算**。

```
普通聚合 (SUM):
  accumulator.update(10)  → sum = 10
  accumulator.update(20)  → sum = 30
  accumulator.update(30)  → sum = 60
  accumulator.result()    → 60

有序集合聚合 (PERCENTILE_CONT):
  accumulator.collect(30)   → buffer = [30]
  accumulator.collect(10)   → buffer = [30, 10]
  accumulator.collect(20)   → buffer = [30, 10, 20]
  accumulator.sort()        → buffer = [10, 20, 30]
  accumulator.result(0.5)   → 20
```

### 2. 内存压力

有序集合聚合需要在内存中保存**当前分组的所有值**：

```
场景: 100 万员工，100 个部门
每个部门约 1 万人
PERCENTILE_CONT 需要缓存 1 万个 salary 值
内存占用: ~80 KB/组 * 100 组 = ~8 MB（可控）

场景: 1 亿行日志，1 个分组
PERCENTILE_CONT 需要缓存 1 亿个值
内存占用: ~800 MB（可能需要 spill to disk）
```

实现建议：
- 设置每组最大缓存行数（超过则报错或使用近似算法）
- 支持 spill to disk（当内存不足时）
- 提供近似替代函数（APPROX_PERCENTILE）

### 3. PERCENTILE_CONT 的精确计算

```
算法: 线性插值
输入: 排好序的值数组 V[0..N-1], 分位点 p

位置 = p * (N - 1)
下标_低 = floor(位置)
下标_高 = ceil(位置)
权重 = 位置 - 下标_低

结果 = V[下标_低] * (1 - 权重) + V[下标_高] * 权重
```

### 4. 分布式执行的挑战

有序集合聚合**不能做两阶段聚合**——部分排序无法合并为全局排序后的分位数：

```
节点 1: salary = [10, 30, 50]    P50 = 30
节点 2: salary = [20, 40, 60]    P50 = 40
全局 P50: merge(30, 40) = ?      ← 无法从两个 P50 推导全局 P50
全局正确结果: [10, 20, 30, 40, 50, 60] → P50 = 35
```

解决方案：
- 将同一分组的所有数据 shuffle 到同一节点（代价高）
- 使用近似算法（t-digest、KLL 可以合并）
- 对于 LISTAGG，可以分段拼接后二次合并

### 5. LISTAGG 的溢出处理

LISTAGG 的结果长度不可预测——如果拼接 100 万行的文本，结果可能超出 VARCHAR 最大长度。

```sql
-- Oracle 的溢出处理语法（最完善）
LISTAGG(name, ','
    ON OVERFLOW TRUNCATE '...' WITH COUNT
) WITHIN GROUP (ORDER BY name)
-- 超长时截断为: "张三,李四,王五,... (997 more)"

-- ON OVERFLOW ERROR: 超长时报错（默认行为）
```

建议实现：
- 设置默认最大结果长度（如 64KB）
- 提供 ON OVERFLOW TRUNCATE / ERROR 选项
- 流式拼接，到达长度限制时停止

### 6. WITHIN GROUP vs 函数内 ORDER BY

```sql
-- 方式 1: WITHIN GROUP (SQL:2003 标准)
LISTAGG(name, ',') WITHIN GROUP (ORDER BY name)

-- 方式 2: 函数内 ORDER BY (PostgreSQL 风格)
STRING_AGG(name, ',' ORDER BY name)
```

引擎如果两种都支持，在解析器中需要处理 ORDER BY 出现在不同位置的情况。建议在 AST 层统一为相同的节点结构。

## 设计讨论

### WITHIN GROUP 是否过于冗长？

```sql
-- 标准写法
PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary)

-- 如果简化为
PERCENTILE_CONT(salary, 0.5)  -- BigQuery 风格

-- 或
MEDIAN(salary)  -- Oracle / Snowflake 的快捷方式
```

BigQuery 的参数化风格更简洁，但丢失了"有序集合"的语义表达。WITHIN GROUP 虽然冗长，但明确传达了"先排序再计算"的意图，且可以支持多列排序：

```sql
PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary DESC NULLS LAST)
```

### MEDIAN 函数

Oracle 和 Snowflake 提供 `MEDIAN(col)` 作为 `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY col)` 的快捷方式。这是实用的语法糖——中位数是最常用的分位数。

## 参考资料

- ISO/IEC 9075-2:2003 Section 10.10 (ordered set function)
- Oracle: [LISTAGG](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/LISTAGG.html)
- Oracle: [PERCENTILE_CONT](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/PERCENTILE_CONT.html)
- PostgreSQL: [Ordered-Set Aggregate Functions](https://www.postgresql.org/docs/current/functions-aggregate.html#FUNCTIONS-ORDEREDSET-TABLE)
- SQL Server: [PERCENTILE_CONT](https://learn.microsoft.com/en-us/sql/t-sql/functions/percentile-cont-transact-sql)
- Snowflake: [LISTAGG](https://docs.snowflake.com/en/sql-reference/functions/listagg)
