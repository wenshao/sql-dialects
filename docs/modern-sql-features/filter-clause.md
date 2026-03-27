# FILTER 子句

聚合函数的条件过滤语法——SQL:2003 标准定义的语法糖，用一行代替 CASE WHEN 的冗长写法，且对优化器更友好。

## 支持矩阵

| 引擎 | 支持 | 版本 | 备注 |
|------|------|------|------|
| PostgreSQL | 完整支持 | 9.4+ (2014) | 最早的主流实现 |
| SQLite | 完整支持 | 3.30+ (2019) | - |
| DuckDB | 完整支持 | 0.3.0+ | - |
| Spark SQL | 完整支持 | 3.0+ (2020) | - |
| Databricks | 完整支持 | Runtime 7.0+ | - |
| CockroachDB | 完整支持 | 20.1+ | 兼容 PostgreSQL |
| H2 | 完整支持 | 2.0+ | - |
| ClickHouse | 不支持 | - | 使用 `-If` 后缀替代（如 `countIf`） |
| MySQL | 不支持 | - | 需 CASE WHEN 改写 |
| Oracle | 不支持 | - | 需 CASE WHEN 改写 |
| SQL Server | 不支持 | - | 需 CASE WHEN 改写 |
| Snowflake | 不支持 | - | 需 CASE WHEN / IFF 改写 |
| BigQuery | 不支持 | - | 需 COUNTIF / IF 改写 |
| Trino | 完整支持 | 早期版本 | - |
| MariaDB | 不支持 | - | 需 CASE WHEN 改写 |

## 设计动机: CASE WHEN 的冗长问题

### 典型需求

统计订单表中各状态的数量和金额——在同一个 GROUP BY 中计算多个条件聚合：

```sql
-- CASE WHEN 写法: 冗长且重复
SELECT
    region,
    COUNT(CASE WHEN status = 'completed' THEN 1 END) AS completed_count,
    COUNT(CASE WHEN status = 'pending'   THEN 1 END) AS pending_count,
    COUNT(CASE WHEN status = 'cancelled' THEN 1 END) AS cancelled_count,
    SUM(CASE WHEN status = 'completed' THEN amount END) AS completed_amount,
    SUM(CASE WHEN status = 'pending'   THEN amount END) AS pending_amount,
    AVG(CASE WHEN status = 'completed' AND amount > 100 THEN amount END) AS avg_large_completed
FROM orders
GROUP BY region;
```

每个条件聚合都需要写 `CASE WHEN ... THEN ... END`，七个字段占了大量视觉空间，且真正的业务逻辑（条件和聚合）被语法噪声淹没。

### FILTER 的解决方案

```sql
-- FILTER 写法: 清晰简洁
SELECT
    region,
    COUNT(*)    FILTER (WHERE status = 'completed') AS completed_count,
    COUNT(*)    FILTER (WHERE status = 'pending')   AS pending_count,
    COUNT(*)    FILTER (WHERE status = 'cancelled') AS cancelled_count,
    SUM(amount) FILTER (WHERE status = 'completed') AS completed_amount,
    SUM(amount) FILTER (WHERE status = 'pending')   AS pending_amount,
    AVG(amount) FILTER (WHERE status = 'completed' AND amount > 100) AS avg_large_completed
FROM orders
GROUP BY region;
```

对比优势：
1. **语义直观**: "对 COUNT 做过滤"而非"计算条件表达式后聚合"
2. **语法紧凑**: 省去了 CASE/WHEN/THEN/END 四个关键字
3. **与 COUNT(*) 兼容**: CASE WHEN 不能直接用于 `COUNT(*)`，必须写成 `COUNT(CASE WHEN ... THEN 1 END)`

## 语法详解

### 基本语法

```sql
aggregate_function(...) FILTER (WHERE condition)
```

FILTER 子句可以附加在任何聚合函数之后：

```sql
-- COUNT
COUNT(*) FILTER (WHERE status = 'active')

-- SUM
SUM(amount) FILTER (WHERE category = 'electronics')

-- AVG
AVG(score) FILTER (WHERE score > 0)

-- MIN / MAX
MIN(price) FILTER (WHERE in_stock = true)

-- ARRAY_AGG
ARRAY_AGG(name ORDER BY name) FILTER (WHERE dept = 'engineering')

-- BOOL_AND / BOOL_OR (PostgreSQL)
BOOL_AND(is_valid) FILTER (WHERE created_at > '2024-01-01')

-- STRING_AGG
STRING_AGG(tag, ', ') FILTER (WHERE tag IS NOT NULL)
```

### 与窗口函数组合

```sql
-- FILTER 也可以用于窗口聚合函数
SELECT
    order_date,
    amount,
    SUM(amount) FILTER (WHERE status = 'completed')
        OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
        AS completed_7day_sum,
    COUNT(*) FILTER (WHERE status = 'cancelled')
        OVER (PARTITION BY region ORDER BY order_date)
        AS running_cancel_count
FROM orders;
```

## 各引擎语法对比

### PostgreSQL 9.4+ / DuckDB / SQLite 3.30+

```sql
-- 标准 FILTER 语法
SELECT
    dept,
    COUNT(*) FILTER (WHERE salary > 10000) AS high_salary_count,
    AVG(salary) FILTER (WHERE hire_date >= '2023-01-01') AS new_hire_avg_salary
FROM employees
GROUP BY dept;
```

### Spark SQL 3.0+

```sql
-- Spark 使用相同语法
SELECT
    dept,
    COUNT(*) FILTER (WHERE salary > 10000) AS high_salary_count,
    AVG(salary) FILTER (WHERE hire_date >= '2023-01-01') AS new_hire_avg_salary
FROM employees
GROUP BY dept;
```

### ClickHouse: -If 后缀（等价但私有语法）

```sql
-- ClickHouse 用函数名后缀替代 FILTER
SELECT
    dept,
    countIf(salary > 10000) AS high_salary_count,
    avgIf(salary, hire_date >= '2023-01-01') AS new_hire_avg_salary,
    sumIf(bonus, status = 'active') AS active_bonus_sum
FROM employees
GROUP BY dept;

-- -If 后缀可以与其他后缀组合
-- countDistinctIf, sumMergeIf, quantileIf 等
-- 这是 ClickHouse 的组合子（combinator）机制，非常灵活
```

### BigQuery: COUNTIF / IF 函数

```sql
-- BigQuery 使用 COUNTIF（仅 COUNT 有专用函数）
SELECT
    dept,
    COUNTIF(salary > 10000) AS high_salary_count,
    -- 其他聚合需要 IF 函数
    AVG(IF(hire_date >= '2023-01-01', salary, NULL)) AS new_hire_avg_salary,
    SUM(IF(status = 'active', bonus, NULL)) AS active_bonus_sum
FROM employees
GROUP BY dept;
```

### 等价改写: MySQL / Oracle / SQL Server

```sql
-- CASE WHEN 改写（通用方案）
SELECT
    dept,
    COUNT(CASE WHEN salary > 10000 THEN 1 END) AS high_salary_count,
    AVG(CASE WHEN hire_date >= '2023-01-01' THEN salary END) AS new_hire_avg_salary,
    SUM(CASE WHEN status = 'active' THEN bonus END) AS active_bonus_sum
FROM employees
GROUP BY dept;

-- Oracle 额外选项: DECODE（仅限等值条件）
SELECT dept,
    COUNT(DECODE(status, 'active', 1)) AS active_count
FROM employees GROUP BY dept;

-- Snowflake: IFF 函数
SELECT dept,
    COUNT(IFF(salary > 10000, 1, NULL)) AS high_salary_count
FROM employees GROUP BY dept;
```

## 实际用例

### 用例 1: 多维度统计报表

```sql
-- 一条 SQL 生成完整报表
SELECT
    DATE_TRUNC('month', order_date) AS month,
    COUNT(*)                                          AS total_orders,
    COUNT(*) FILTER (WHERE status = 'completed')      AS completed,
    COUNT(*) FILTER (WHERE status = 'refunded')       AS refunded,
    SUM(amount) FILTER (WHERE status = 'completed')   AS revenue,
    SUM(amount) FILTER (WHERE status = 'refunded')    AS refund_amount,
    ROUND(COUNT(*) FILTER (WHERE status = 'refunded')::numeric
        / NULLIF(COUNT(*), 0) * 100, 2)               AS refund_rate_pct
FROM orders
GROUP BY 1
ORDER BY 1;
```

### 用例 2: 用户行为漏斗

```sql
-- 计算注册漏斗的每步转化率
SELECT
    DATE_TRUNC('week', created_at) AS week,
    COUNT(*) FILTER (WHERE step >= 1) AS visited,
    COUNT(*) FILTER (WHERE step >= 2) AS signed_up,
    COUNT(*) FILTER (WHERE step >= 3) AS activated,
    COUNT(*) FILTER (WHERE step >= 4) AS paid,
    ROUND(COUNT(*) FILTER (WHERE step >= 4)::numeric
        / NULLIF(COUNT(*) FILTER (WHERE step >= 1), 0) * 100, 1)
        AS overall_conversion_pct
FROM user_funnel
GROUP BY 1;
```

### 用例 3: 滑动窗口中的条件统计

```sql
-- 过去 7 天内成功和失败的请求数
SELECT
    request_time,
    endpoint,
    COUNT(*) FILTER (WHERE status_code BETWEEN 200 AND 299)
        OVER w AS success_7d,
    COUNT(*) FILTER (WHERE status_code >= 500)
        OVER w AS error_7d
FROM api_requests
WINDOW w AS (
    PARTITION BY endpoint
    ORDER BY request_time
    RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW
);
```

## 对引擎开发者的实现分析

### 1. 极低的实现成本

FILTER 子句的实现非常简单——本质上是在聚合累加器（accumulator）的 update 方法中加一个条件判断：

```
-- 无 FILTER 的 SUM:
accumulator.update(value):
    sum += value

-- 有 FILTER 的 SUM:
accumulator.update(value, filter_result):
    if filter_result:
        sum += value
```

总实现量：
- Parser: 在聚合函数后识别 `FILTER (WHERE ...)` 语法 ~50 行
- Planner: 将 FILTER 条件附加到聚合节点 ~30 行
- 执行器: 在 accumulator 中加条件判断 ~10 行
- 总计: 不到 100 行代码变更

这使得不支持 FILTER 的引擎（如 MySQL）更令人费解——实现成本几乎为零。

### 2. 优化器处理

FILTER 对优化器有明确好处：

**语义清晰**
```sql
-- CASE WHEN: 优化器需要识别 "CASE WHEN cond THEN val END" 是条件聚合模式
COUNT(CASE WHEN status = 'active' THEN 1 END)
-- 这是一个普通聚合包裹条件表达式，优化器可能无法识别其特殊语义

-- FILTER: 语义直接编码在 AST 中
COUNT(*) FILTER (WHERE status = 'active')
-- 优化器明确知道这是条件聚合，可以做专门优化
```

**优化机会**
- 多个 FILTER 共享相同条件时，条件只需评估一次
- FILTER 条件可以与 WHERE 条件合并做谓词推导
- 在向量化引擎中，FILTER 可以用位图（bitmap）高效实现

### 3. CASE WHEN 到 FILTER 的自动改写

优化器可以在 planner 阶段将 CASE WHEN 模式自动改写为 FILTER，从而统一后续优化：

```
识别模式:
AGG(CASE WHEN cond THEN expr END)
→ 改写为:
AGG(expr) FILTER (WHERE cond)

更严格的识别:
COUNT(CASE WHEN cond THEN 1 END)  → COUNT(*) FILTER (WHERE cond)
SUM(CASE WHEN cond THEN x END)   → SUM(x) FILTER (WHERE cond)
AVG(CASE WHEN cond THEN x END)   → AVG(x) FILTER (WHERE cond)
```

### 4. 向量化执行

在向量化引擎中，FILTER 子句天然适合批量处理：

```
1. 评估 FILTER 条件，生成选择向量（selection vector）
2. 仅对选中的行执行聚合累加
3. 多个 FILTER 条件可以并行评估

相比 CASE WHEN 需要计算条件表达式并生成中间列，
FILTER 的选择向量方式避免了中间值的物化。
```

### 5. NULL 语义

FILTER 与 CASE WHEN 在 NULL 处理上等价：

```sql
-- FILTER: 条件不满足 → 行被跳过（不参与聚合）
COUNT(*) FILTER (WHERE x > 5)

-- CASE WHEN: 条件不满足 → 返回 NULL → 被 COUNT 忽略（NULL 不计数）
COUNT(CASE WHEN x > 5 THEN 1 END)

-- 两者对 SUM/AVG 也等价: NULL 不参与 SUM/AVG 计算
```

## 设计讨论

### 为什么 MySQL 不支持？

MySQL 的 SQL 解析器基于 Bison 生成的 LALR(1) parser，在聚合函数调用后追加新关键字可能引入语法冲突。但技术上这不是无法解决的问题——更可能的原因是优先级：MySQL 团队有更紧迫的特性需求。

### FILTER 应该支持哪些函数？

标准定义 FILTER 仅用于聚合函数。但有些引擎将其扩展到窗口聚合函数。是否进一步扩展到所有窗口函数（如 ROW_NUMBER FILTER）是一个开放问题——多数引擎选择不扩展，因为语义不太自然。

### ClickHouse 的 -If 方案更好？

ClickHouse 的 `countIf(cond)` 比 `COUNT(*) FILTER (WHERE cond)` 更简洁，且组合子机制（-If, -Array, -Map, -Merge）提供了更灵活的扩展性。但它不是标准 SQL，且学习成本更高（需要记住每个聚合函数的 -If 变体名称）。

## 参考资料

- ISO/IEC 9075-2:2003 Section 10.9 (aggregate function - FILTER clause)
- PostgreSQL: [Aggregate Expressions - FILTER](https://www.postgresql.org/docs/current/sql-expressions.html#SYNTAX-AGGREGATES)
- SQLite: [Aggregate Functions - FILTER](https://www.sqlite.org/lang_aggfunc.html)
- DuckDB: [Aggregate Functions](https://duckdb.org/docs/sql/aggregates)
- ClickHouse: [Aggregate Function Combinators](https://clickhouse.com/docs/en/sql-reference/aggregate-functions/combinators)
