# LATERAL JOIN / CROSS APPLY / OUTER APPLY

允许子查询引用外部表的列——打破子查询的封闭性，SQL:1999 标准特性。

## 支持矩阵

| 引擎 | 语法 | 版本 | 备注 |
|------|------|------|------|
| SQL Server | `CROSS APPLY` / `OUTER APPLY` | 2005+ | **最早实现** |
| PostgreSQL | `LATERAL` | 9.3+ (2013) | 完整支持 |
| Oracle | `LATERAL` / `CROSS APPLY` / `OUTER APPLY` | 12c+ (2013) | 同时支持两种语法 |
| MySQL | `LATERAL` | 8.0.14+ (2019) | 较晚支持 |
| BigQuery | `CROSS JOIN UNNEST` / `, UNNEST(...)` | GA | 隐式 LATERAL |
| Snowflake | `LATERAL FLATTEN` | GA | 主要配合 FLATTEN 使用 |
| Databricks | `LATERAL VIEW` | 早期 | Hive 兼容语法 |
| DuckDB | `LATERAL` | 0.6.0+ | - |
| MariaDB | `LATERAL` | 10.6+ | - |
| Trino | `CROSS JOIN UNNEST` | 早期 | 隐式 LATERAL |
| SQLite | 不支持 | - | 需改写 |
| ClickHouse | `ARRAY JOIN` | 早期 | 专用语法，非标准 LATERAL |

## SQL 标准

`LATERAL` 在 SQL:1999 (SQL3) 中引入，是标准的一部分。语义定义：

> LATERAL 关键字使得派生表（derived table）可以引用在 FROM 子句中出现在其前面的表的列。

## 设计动机: 打破子查询的封闭性

### 问题: 普通子查询不能引用外部表

```sql
-- 需求: 每个部门薪资最高的 3 个员工
-- 错误尝试: 子查询无法引用外部 d 表
SELECT d.dept_name, t.emp_name, t.salary
FROM departments d
JOIN (
    SELECT emp_name, salary
    FROM employees
    WHERE dept_id = d.dept_id      -- 错误! 子查询中不能引用 d
    ORDER BY salary DESC LIMIT 3
) t ON true;
```

FROM 子句中的普通子查询是"封闭的"——它不能引用同一 FROM 中其他表的列。这是 SQL 的基本规则。

### LATERAL 的解决方案

```sql
-- LATERAL 打破封闭性: 子查询可以引用外部表
SELECT d.dept_name, t.emp_name, t.salary
FROM departments d
JOIN LATERAL (
    SELECT emp_name, salary
    FROM employees
    WHERE dept_id = d.dept_id      -- 合法! LATERAL 允许引用 d
    ORDER BY salary DESC LIMIT 3
) t ON true;
```

LATERAL 关键字告诉引擎："这个子查询会引用前面表的列，请对外部表的每一行都重新执行一次这个子查询。"

### 典型使用场景

1. **Top-N per group**（上例）
2. **表函数调用**（传入其他表的列）
3. **JSON/数组展开**（配合 UNNEST/FLATTEN）
4. **复杂计算复用**（中间结果供后续 JOIN 使用）

## 语法对比

### SQL 标准 / PostgreSQL / MySQL

```sql
-- INNER LATERAL JOIN: 子查询无结果时排除外部行
SELECT d.dept_name, e.emp_name, e.salary
FROM departments d
JOIN LATERAL (
    SELECT emp_name, salary
    FROM employees
    WHERE dept_id = d.dept_id
    ORDER BY salary DESC
    LIMIT 3
) e ON true;

-- LEFT LATERAL JOIN: 子查询无结果时保留外部行（NULL 填充）
SELECT d.dept_name, e.emp_name, e.salary
FROM departments d
LEFT JOIN LATERAL (
    SELECT emp_name, salary
    FROM employees
    WHERE dept_id = d.dept_id
    ORDER BY salary DESC
    LIMIT 3
) e ON true;

-- LATERAL 配合表函数
SELECT t.id, g.value
FROM my_table t
CROSS JOIN LATERAL generate_series(1, t.n) AS g(value);
```

### SQL Server（CROSS APPLY / OUTER APPLY）

```sql
-- CROSS APPLY = JOIN LATERAL（无结果时排除）
SELECT d.dept_name, e.emp_name, e.salary
FROM departments d
CROSS APPLY (
    SELECT TOP 3 emp_name, salary
    FROM employees
    WHERE dept_id = d.dept_id
    ORDER BY salary DESC
) e;

-- OUTER APPLY = LEFT JOIN LATERAL（无结果时保留 NULL）
SELECT d.dept_name, e.emp_name, e.salary
FROM departments d
OUTER APPLY (
    SELECT TOP 3 emp_name, salary
    FROM employees
    WHERE dept_id = d.dept_id
    ORDER BY salary DESC
) e;

-- 配合表值函数
SELECT o.order_id, s.item_name, s.quantity
FROM orders o
CROSS APPLY dbo.GetOrderItems(o.order_id) s;
```

### Oracle（两种语法都支持）

```sql
-- SQL 标准语法
SELECT d.dept_name, e.emp_name, e.salary
FROM departments d
JOIN LATERAL (
    SELECT emp_name, salary FROM employees
    WHERE dept_id = d.dept_id
    ORDER BY salary DESC FETCH FIRST 3 ROWS ONLY
) e ON 1=1;

-- SQL Server 兼容语法
SELECT d.dept_name, e.emp_name, e.salary
FROM departments d
CROSS APPLY (
    SELECT emp_name, salary FROM employees
    WHERE dept_id = d.dept_id
    ORDER BY salary DESC FETCH FIRST 3 ROWS ONLY
) e;
```

### BigQuery（隐式 LATERAL）

```sql
-- BigQuery 中 UNNEST 配合逗号 JOIN 自动具有 LATERAL 语义
SELECT t.id, elem
FROM my_table t, UNNEST(t.tags) AS elem;

-- 等效显式写法
SELECT t.id, elem
FROM my_table t
CROSS JOIN UNNEST(t.tags) AS elem;

-- 子查询形式需要使用 LATERAL（BigQuery 也支持但少用）
```

### Snowflake

```sql
-- Snowflake 主要在 FLATTEN 中使用 LATERAL
SELECT t.id, f.value
FROM my_table t,
LATERAL FLATTEN(input => t.tags) f;

-- 等效写法
SELECT t.id, f.value
FROM my_table t
JOIN LATERAL FLATTEN(input => t.tags) f;
```

### 等价改写: 不支持 LATERAL 的引擎

```sql
-- Top-N per group 无 LATERAL 改写
-- 方案 1: 窗口函数
SELECT dept_name, emp_name, salary FROM (
    SELECT d.dept_name, e.emp_name, e.salary,
           ROW_NUMBER() OVER (PARTITION BY e.dept_id ORDER BY e.salary DESC) AS rn
    FROM departments d JOIN employees e ON d.dept_id = e.dept_id
) t WHERE rn <= 3;

-- 方案 2: 相关子查询（性能差但通用）
SELECT d.dept_name, e.emp_name, e.salary
FROM departments d
JOIN employees e ON e.dept_id = d.dept_id
WHERE (
    SELECT COUNT(*) FROM employees e2
    WHERE e2.dept_id = e.dept_id AND e2.salary > e.salary
) < 3;
```

## LATERAL vs 相关子查询

| 特性 | LATERAL | 相关子查询 |
|------|---------|-----------|
| 位置 | FROM 子句 | SELECT / WHERE 子句 |
| 返回行数 | 可以返回多行多列 | SELECT: 单值; WHERE: 可多行 |
| 可以 JOIN | 是 | 否 |
| 可以 LIMIT | 是 | 部分引擎支持 |
| 优化器友好 | 更好（明确的 join 语义） | 一般 |

关键区别: LATERAL 子查询在 FROM 中，可以返回多行多列，像一个"参数化的表"。

## 对引擎开发者的实现建议

1. 语法解析

在 FROM 子句的 table_ref 产生式中支持 `LATERAL` 关键字：

```
table_ref:
    table_name
  | '(' subquery ')' [AS alias]
  | LATERAL '(' subquery ')' [AS alias]    -- 新增
  | table_ref [join_type] JOIN table_ref ON condition
  | table_ref CROSS APPLY '(' subquery ')' AS alias   -- 可选: SQL Server 兼容
  | table_ref OUTER APPLY '(' subquery ')' AS alias   -- 可选: SQL Server 兼容
```

2. 作用域管理

LATERAL 的核心实现挑战是**作用域规则**：

- 普通子查询: 只能看到全局作用域和自己的作用域
- LATERAL 子查询: 还能看到 FROM 中出现在自己**左边**的表

```sql
-- a 不能看 b/c，b 可以看 a（但不能看 c），c 可以看 a 和 b
FROM a, LATERAL (... a.col ...) b, LATERAL (... a.col, b.col ...) c
```

实现: 在解析 FROM 子句时，维护一个"已解析表"列表。遇到 LATERAL 标记时，将已解析表列表注入到子查询的作用域。

3. 执行计划: Correlated Nested Loop

LATERAL 在执行计划中自然映射为 correlated nested loop join：

```
NestedLoopJoin (lateral = true)
├── outer: TableScan(departments)
└── inner: Limit(3,
              Sort(salary DESC,
                  Filter(dept_id = outer.dept_id,
                      TableScan(employees))))
```

对外部表的每一行，重新计算内部子查询。

4. 优化器策略

#### 去关联化 (Decorrelation)

简单的 LATERAL 可以被优化器改写为普通 JOIN + 窗口函数，避免 nested loop 的性能代价：

```sql
-- 原始 LATERAL
FROM departments d JOIN LATERAL (
    SELECT * FROM employees WHERE dept_id = d.dept_id ORDER BY salary DESC LIMIT 3
) e ON true

-- 去关联化后
FROM departments d JOIN (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) AS rn
    FROM employees
) e ON d.dept_id = e.dept_id AND e.rn <= 3
```

但并非所有 LATERAL 都能去关联化——包含 LIMIT、聚合、或复杂逻辑的可能无法改写。

#### 批量执行

对于不能去关联化的 LATERAL，可以用批量化（batching）优化：

- 收集外部表的多行参数，批量发送给内部查询
- 减少内部查询的执行次数（用 IN 代替逐行相关查询）

5. CROSS APPLY 兼容

如果引擎想同时支持标准 `LATERAL` 和 SQL Server 的 `CROSS/OUTER APPLY`：

```
CROSS APPLY → JOIN LATERAL ... ON true
OUTER APPLY → LEFT JOIN LATERAL ... ON true
```

在 parser 阶段做语法糖转换即可，共享后续的优化和执行逻辑。

## 参考资料

- SQL:1999 标准: ISO/IEC 9075-2:1999 Section 7.6
- PostgreSQL: [LATERAL Subqueries](https://www.postgresql.org/docs/current/queries-table-expressions.html#QUERIES-LATERAL)
- SQL Server: [APPLY](https://learn.microsoft.com/en-us/sql/t-sql/queries/from-transact-sql#using-apply)
- MySQL: [Lateral Derived Tables](https://dev.mysql.com/doc/refman/8.0/en/lateral-derived-tables.html)
