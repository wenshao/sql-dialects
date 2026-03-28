# GROUP BY ALL / ORDER BY ALL

自动推断 GROUP BY 列——DuckDB 引领的"减少 SQL 冗余"运动。

## 支持矩阵

| 引擎 | GROUP BY ALL | ORDER BY ALL | 版本 | 备注 |
|------|-------------|-------------|------|------|
| DuckDB | 支持 | 支持 | 0.6.0+ | **首创者** |
| Databricks | 支持 | 不支持 | Runtime 12.0+ | - |
| ClickHouse | 不支持 | 不支持 | - | - |
| Snowflake | 不支持 | 不支持 | - | - |
| BigQuery | 不支持 | 不支持 | - | - |
| PostgreSQL | 不支持 | 不支持 | - | - |
| MySQL | 不支持 | 不支持 | - | - |
| Oracle | 不支持 | 不支持 | - | `GROUP BY ALL` 有不同含义(已废弃) |
| SQL Server | 不支持 | 不支持 | - | `GROUP BY ALL` 曾有不同含义(已废弃) |

> 注意: SQL Server 和 Oracle 历史上有 `GROUP BY ALL` 语法，但含义完全不同（包含不满足 WHERE 条件的分组，已被废弃）。DuckDB 的 `GROUP BY ALL` 是全新语义。

## 设计动机: SQL 的冗余之痛

### 问题

写 GROUP BY 查询时，非聚合列必须同时出现在 SELECT 和 GROUP BY 中——这是纯粹的重复：

```sql
-- 典型的冗余: SELECT 中的非聚合列必须在 GROUP BY 中重复
SELECT
    region,
    country,
    city,
    product_category,
    EXTRACT(YEAR FROM order_date) AS order_year,
    SUM(amount) AS total_amount,
    COUNT(*) AS order_count
FROM orders
GROUP BY
    region,          -- 重复
    country,         -- 重复
    city,            -- 重复
    product_category, -- 重复
    EXTRACT(YEAR FROM order_date);  -- 重复（表达式也要复制）
```

问题：
1. **冗余**: 非聚合列名写两遍
2. **维护成本**: SELECT 加一列，GROUP BY 也要加，容易遗漏导致报错
3. **表达式重复**: 含计算表达式时更痛苦（复制长表达式，易出错）

### GROUP BY ALL 的解决方案

```sql
-- GROUP BY ALL: 自动推断（DuckDB / Databricks）
SELECT
    region, country, city, product_category,
    EXTRACT(YEAR FROM order_date) AS order_year,
    SUM(amount) AS total_amount,
    COUNT(*) AS order_count
FROM orders
GROUP BY ALL;
-- 引擎自动将 SELECT 中非聚合的列/表达式加入 GROUP BY
```

### ORDER BY ALL

DuckDB 还支持 `ORDER BY ALL`，按 SELECT 列表中所有列排序：

```sql
-- 等效于 ORDER BY 1, 2, 3, ...（按 SELECT 中所有列依次排序）
SELECT region, country, SUM(amount) AS total
FROM orders
GROUP BY ALL
ORDER BY ALL;
```

## 语法详解

### DuckDB

```sql
-- 基本用法
SELECT dept, job_title, AVG(salary) AS avg_sal
FROM employees
GROUP BY ALL;
-- 等效于: GROUP BY dept, job_title

-- 表达式自动推断
SELECT
    EXTRACT(YEAR FROM hire_date) AS year,
    dept,
    COUNT(*) AS cnt
FROM employees
GROUP BY ALL;
-- 等效于: GROUP BY EXTRACT(YEAR FROM hire_date), dept

-- ORDER BY ALL
SELECT dept, COUNT(*) AS cnt, AVG(salary) AS avg_sal
FROM employees
GROUP BY ALL
ORDER BY ALL;
-- 等效于: ORDER BY dept, cnt, avg_sal (即 ORDER BY 1, 2, 3)

-- GROUP BY ALL 与 HAVING 组合
SELECT dept, COUNT(*) AS cnt
FROM employees
GROUP BY ALL
HAVING cnt > 5;

-- 嵌套聚合不受 GROUP BY ALL 影响
SELECT dept, SUM(salary) AS total, SUM(salary) / COUNT(*) AS avg_manual
FROM employees
GROUP BY ALL;
-- SUM 和 COUNT 被识别为聚合，dept 被推断为 GROUP BY 列
```

### Databricks

```sql
-- Databricks Runtime 12.0+ 支持
SELECT region, product, SUM(revenue) AS total_revenue
FROM sales
GROUP BY ALL;

-- 与窗口函数的交互: 窗口函数不算聚合，但也不加入 GROUP BY
-- 以下写法在 GROUP BY ALL 中不合法或需要引擎特殊处理
```

### 等价改写: 不支持的引擎

手动列出所有非聚合列即可——这正是 GROUP BY ALL 要自动化的事：

```sql
-- 手动 GROUP BY（所有引擎都支持）
SELECT dept, job_title, COUNT(*), AVG(salary)
FROM employees
GROUP BY dept, job_title;

-- 如果表达式复杂，可以用位置编号（部分引擎支持）
SELECT EXTRACT(YEAR FROM hire_date), dept, COUNT(*)
FROM employees
GROUP BY 1, 2;
```

## 推断规则详解

### 核心规则

引擎在语义分析阶段扫描 SELECT 列表，将每个表达式分为两类：

| 类型 | 处理 | 示例 |
|------|------|------|
| 包含聚合函数 | 不加入 GROUP BY | `SUM(salary)`, `COUNT(*)`, `AVG(x) + 1` |
| 不包含聚合函数 | 加入 GROUP BY | `dept`, `EXTRACT(YEAR FROM d)`, `a + b` |

### 边界情况

```sql
-- 情况 1: 聚合函数的参数不加入 GROUP BY
SELECT dept, SUM(salary) FROM t GROUP BY ALL;
-- salary 是 SUM 的参数，不加入。dept 加入。

-- 情况 2: 混合表达式——包含聚合的表达式不加入
SELECT dept, SUM(salary) / COUNT(*) AS avg FROM t GROUP BY ALL;
-- SUM(salary) / COUNT(*) 包含聚合，不加入。dept 加入。

-- 情况 3: 窗口函数——不算聚合
SELECT dept, SUM(salary), RANK() OVER (ORDER BY SUM(salary) DESC)
FROM t GROUP BY ALL;
-- RANK() OVER (...) 是窗口函数。dept 加入 GROUP BY。
-- 窗口函数在 GROUP BY 之后计算。

-- 情况 4: 常量——需要加入吗？
SELECT dept, 'literal', 42, SUM(salary) FROM t GROUP BY ALL;
-- 常量理论上可以不加入 GROUP BY，但加入也无害。
-- DuckDB 选择不将常量加入 GROUP BY。
```

## 争议: 便利性 vs 明确性

### 支持方观点

1. **消除冗余**: GROUP BY 的非聚合列与 SELECT 完全重复，违反 DRY 原则
2. **减少错误**: 修改 SELECT 后忘记更新 GROUP BY 是常见错误
3. **提高可读性**: 查询更简洁，尤其是分组列很多时
4. **向 dbt 靠拢**: dbt 等工具鼓励简洁 SQL，GROUP BY ALL 契合这一趋势

### 反对方观点

1. **隐式行为**: 读者不看 SELECT 就不知道分组依据
2. **重构风险**: SELECT 加一列可能意外改变 GROUP BY 语义
3. **标准偏离**: 不在 SQL 标准中
4. **歧义风险**: 带 `*` 时行为不确定——`SELECT *, SUM(x) GROUP BY ALL` 的 `*` 展开结果可能随表结构变化

### 工程判断

GROUP BY ALL 适合 **OLAP/分析场景**（探索性查询、临时分析、dbt 模型），不适合 **OLTP/生产代码**（需要明确性和稳定性）。

## 对引擎开发者的实现建议

1. 语义分析阶段

在 binder/analyzer 阶段遇到 `GROUP BY ALL` 时：

```
步骤 1: 解析 SELECT 列表中所有表达式
步骤 2: 对每个表达式调用 containsAggregateFunction() 判断
步骤 3: 不包含聚合函数的表达式 → 加入 GROUP BY 列表
步骤 4: 用推断出的 GROUP BY 列表替换 ALL
步骤 5: 后续流程与普通 GROUP BY 完全相同
```

2. containsAggregateFunction 的实现

需要递归遍历表达式树：

```
function containsAggregateFunction(expr):
    if expr is AggregateFunctionCall:
        return true
    if expr is WindowFunctionCall:
        return false  // 窗口函数不算聚合
    for child in expr.children:
        if containsAggregateFunction(child):
            return true
    return false
```

3. SELECT * 的处理

当 SELECT 包含 `*` 时，需要先展开 `*` 为具体列，再做推断：

```sql
SELECT *, SUM(salary) FROM employees GROUP BY ALL;
-- 步骤 1: 展开 * → id, name, dept, salary, hire_date
-- 步骤 2: SUM(salary) 包含聚合，不加入
-- 步骤 3: GROUP BY id, name, dept, salary, hire_date
```

注意: `salary` 既出现在 `SELECT *` 中（非聚合），又出现在 `SUM(salary)` 中（作为聚合参数）。正确行为是将 `salary` 加入 GROUP BY。

4. 错误处理

```sql
-- 全是聚合，没有分组列——合法，相当于无 GROUP BY 的全局聚合
SELECT SUM(salary), COUNT(*) FROM employees GROUP BY ALL;
-- GROUP BY ALL 推断为空列表 → 等效于无 GROUP BY

-- 没有聚合函数——合法吗？
SELECT dept, name FROM employees GROUP BY ALL;
-- 推断为 GROUP BY dept, name → 等效于 SELECT DISTINCT dept, name
-- DuckDB 允许这种用法
```

5. ORDER BY ALL 的实现

ORDER BY ALL 更简单——将 SELECT 列表中所有列按序号加入 ORDER BY：

```
SELECT a, b, c FROM t ORDER BY ALL
→ SELECT a, b, c FROM t ORDER BY 1, 2, 3
```

默认排序方向为 ASC。DuckDB 支持 `ORDER BY ALL DESC`。

## 参考资料

- DuckDB: [GROUP BY ALL](https://duckdb.org/docs/sql/query_syntax/groupby#group-by-all)
- DuckDB: [ORDER BY ALL](https://duckdb.org/docs/sql/query_syntax/orderby#order-by-all)
- Databricks: [GROUP BY ALL](https://docs.databricks.com/en/sql/language-manual/sql-ref-syntax-qry-select-groupby.html)
- DuckDB 博客: [SQL 语法的 Friendly Improvements](https://duckdb.org/2022/05/04/friendlier-sql.html)
