# QUALIFY 子句

窗口函数结果过滤的专用子句——省去嵌套子查询的语法糖，但对引擎优化器意义重大。

## 支持矩阵

| 引擎 | 支持 | 版本 | 备注 |
|------|------|------|------|
| Teradata | 完整支持 | 早期版本 | **首创者** |
| Snowflake | 完整支持 | GA | - |
| BigQuery | 完整支持 | GA | - |
| DuckDB | 完整支持 | 0.3.0+ | - |
| Databricks | 完整支持 | Runtime 11.0+ | Spark SQL 原生不支持 |
| StarRocks | 完整支持 | 2.5+ | - |
| H2 | 完整支持 | 2.0+ | - |
| ClickHouse | 完整支持 | 22.7+ | - |
| MySQL | 不支持 | - | 需子查询改写 |
| PostgreSQL | 不支持 | - | 需子查询改写 |
| Oracle | 不支持 | - | 需子查询改写 |
| SQL Server | 不支持 | - | 需子查询改写 |
| Trino | 不支持 | - | 有社区 PR 但未合入 |

## 设计动机: 为什么需要 QUALIFY

### 问题场景

最常见的需求："每个部门薪资最高的员工"——需要 ROW_NUMBER 窗口函数后过滤 `rn = 1`。

传统写法必须包一层子查询：

```sql
-- 传统写法: 子查询包装
SELECT * FROM (
    SELECT
        emp_id, dept_id, salary,
        ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) AS rn
    FROM employees
) t
WHERE rn = 1;
```

问题在哪？

1. **嵌套层级增加**: 每次窗口函数过滤都要多一层子查询
2. **可读性下降**: 尤其是多个窗口函数组合过滤时，嵌套可达 3-4 层
3. **逻辑不对称**: WHERE 过滤行、HAVING 过滤分组，但窗口函数结果没有对应的过滤子句

### QUALIFY 的解决方案

```sql
-- QUALIFY 写法: 扁平化
SELECT emp_id, dept_id, salary
FROM employees
QUALIFY ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) = 1;
```

SQL 子句的逻辑执行顺序变为：

```
FROM → WHERE → GROUP BY → HAVING → WINDOW → QUALIFY → ORDER BY → LIMIT
```

QUALIFY 之于窗口函数，正如 HAVING 之于聚合函数。

## 语法对比

### Snowflake / BigQuery / DuckDB / Databricks（标准写法）

```sql
-- 基本用法
SELECT dept_id, emp_name, salary
FROM employees
QUALIFY ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) = 1;

-- 可以引用 SELECT 中的别名（部分引擎支持）
SELECT
    dept_id, emp_name, salary,
    ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) AS rn
FROM employees
QUALIFY rn = 1;

-- 与 WHERE / HAVING 组合
SELECT dept_id, emp_name, salary
FROM employees
WHERE hire_date >= '2020-01-01'
GROUP BY dept_id, emp_name, salary
HAVING salary > 50000
QUALIFY RANK() OVER (PARTITION BY dept_id ORDER BY salary DESC) <= 3;
```

### Teradata（首创语法）

```sql
-- Teradata 原始语法（与后来者语法一致）
SELECT dept_id, emp_name, salary
FROM employees
QUALIFY ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) = 1;
```

### 等价改写: 不支持 QUALIFY 的引擎

#### PostgreSQL / MySQL / Oracle / SQL Server

```sql
-- 方案 1: 子查询 + ROW_NUMBER（最通用）
SELECT * FROM (
    SELECT
        dept_id, emp_name, salary,
        ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) AS rn
    FROM employees
) sub
WHERE rn = 1;

-- 方案 2: CTE（可读性更好）
WITH ranked AS (
    SELECT
        dept_id, emp_name, salary,
        ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) AS rn
    FROM employees
)
SELECT dept_id, emp_name, salary
FROM ranked
WHERE rn = 1;

-- 方案 3: 相关子查询（小数据量可用，不推荐大表）
SELECT e.dept_id, e.emp_name, e.salary
FROM employees e
WHERE e.salary = (
    SELECT MAX(e2.salary) FROM employees e2 WHERE e2.dept_id = e.dept_id
);
```

## 对引擎开发者的实现建议

1. 语法解析

QUALIFY 作为 SELECT 语句的一个新子句，在 parser 中位于 HAVING 之后、ORDER BY 之前：

```
SELECT ... FROM ... WHERE ... GROUP BY ... HAVING ... QUALIFY ... ORDER BY ... LIMIT ...
```

需要在 AST 的 SelectStatement 节点中新增 `qualify` 字段，类型与 `where`、`having` 相同（表达式节点）。

2. 语义分析

- QUALIFY 中的表达式**必须**包含至少一个窗口函数调用（直接或通过别名引用）
- 是否允许引用 SELECT 列别名？建议允许——Snowflake、DuckDB 都允许，用户体验更好
- QUALIFY 中不能包含聚合函数（除非嵌套在窗口函数内）

3. 执行计划

QUALIFY 在执行计划中的位置非常直观：

```
TableScan
  → Filter (WHERE)
    → Aggregate (GROUP BY)
      → Filter (HAVING)
        → WindowCompute (窗口函数计算)
          → Filter (QUALIFY)    ← 新增节点
            → Sort (ORDER BY)
              → Limit
```

实现步骤：
1. 窗口函数计算节点正常执行，产出包含窗口函数结果的行
2. QUALIFY Filter 节点对窗口函数结果做过滤
3. 过滤后的行传给下游（ORDER BY / LIMIT）

4. 优化器考量

- **谓词下推**: QUALIFY 中的条件**不能**下推到 WHERE——因为窗口函数需要全量数据才能计算
- **投影裁剪**: 如果 QUALIFY 引用的窗口函数不在 SELECT 列表中，计算后可以裁剪
- **窗口函数合并**: 如果 QUALIFY 和 SELECT 中有相同的窗口函数定义，应合并为一次计算

5. 无 QUALIFY 时的自动改写

如果引擎要做 MySQL/PostgreSQL 兼容层，可以在 planner 阶段自动将 QUALIFY 改写为子查询：

```
-- 输入
SELECT a, b, ROW_NUMBER() OVER (ORDER BY a) AS rn FROM t QUALIFY rn = 1

-- 改写输出
SELECT a, b, rn FROM (
    SELECT a, b, ROW_NUMBER() OVER (ORDER BY a) AS rn FROM t
) __qualify_sub WHERE rn = 1
```

## 设计争议

### 为什么 PostgreSQL 至今未支持？

PostgreSQL 社区对新语法持保守态度，主要考虑：

1. 子查询/CTE 已经能完成同样的事
2. QUALIFY 不在 SQL 标准中（截至 SQL:2023）
3. 引入新关键字可能破坏已有使用 `qualify` 作为标识符的代码

但社区讨论中支持者众多，理由是用户体验和 SQL 简洁性的显著提升。

### 是否应该进入 SQL 标准？

QUALIFY 目前不是 ISO SQL 标准的一部分。但鉴于 Teradata 首创后已被多个主流引擎采纳，且语义明确、实现简单，有望在未来标准中被收录。

## 实际场景

```sql
-- 场景 1: 去重保留最新记录
SELECT *
FROM events
QUALIFY ROW_NUMBER() OVER (PARTITION BY user_id, event_type ORDER BY event_time DESC) = 1;

-- 场景 2: Top-N per group
SELECT *
FROM sales
QUALIFY RANK() OVER (PARTITION BY region ORDER BY amount DESC) <= 5;

-- 场景 3: 过滤窗口计算的百分比
SELECT product_id, category, revenue,
       revenue / SUM(revenue) OVER (PARTITION BY category) AS pct
FROM products
QUALIFY pct > 0.1;
```

## 参考资料

- Teradata 文档: QUALIFY Clause
- Snowflake: [QUALIFY](https://docs.snowflake.com/en/sql-reference/constructs/qualify)
- BigQuery: [QUALIFY clause](https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#qualify_clause)
- DuckDB: [QUALIFY clause](https://duckdb.org/docs/sql/query_syntax/qualify)
