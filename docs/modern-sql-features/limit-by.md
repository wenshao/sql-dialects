# LIMIT BY / Top-N per Group 语法

每组取前 N 行——SQL 中最高频的分析需求之一，各引擎从专用语法到通用方案的不同选择。

## 支持矩阵

| 引擎 | 专用语法 | 语法形式 | 版本 | 通用替代 |
|------|---------|---------|------|---------|
| ClickHouse | LIMIT BY | `LIMIT N BY col` | 早期 | ROW_NUMBER (21.1+) |
| PostgreSQL | DISTINCT ON | `DISTINCT ON (col) ... ORDER BY` | 8.0+ | ROW_NUMBER |
| Snowflake | QUALIFY | `QUALIFY ROW_NUMBER() ... <= N` | GA | 子查询 |
| BigQuery | QUALIFY | 同上 | GA | 子查询 |
| DuckDB | QUALIFY | 同上 | 0.3.0+ | 子查询 |
| Databricks | QUALIFY | 同上 | Runtime 11.0+ | 子查询 |
| Teradata | QUALIFY | 同上 | 早期 | 子查询 |
| MySQL | 无 | - | - | ROW_NUMBER + 子查询 |
| SQL Server | 无 | - | - | ROW_NUMBER / CROSS APPLY |
| Oracle | 无 | - | - | ROW_NUMBER + 子查询 |

## 各引擎的专用语法

### ClickHouse LIMIT BY（独有语法）

ClickHouse 的 `LIMIT BY` 是最直观的 Top-N per Group 语法，在普通 LIMIT 之前按分组截断：

```sql
-- 每个 department 取薪资最高的 3 人
SELECT dept_id, emp_name, salary
FROM employees
ORDER BY salary DESC
LIMIT 3 BY dept_id;

-- LIMIT BY 可以与普通 LIMIT 组合
-- 先每组取 3 行，再全局取前 100 行
SELECT dept_id, emp_name, salary
FROM employees
ORDER BY salary DESC
LIMIT 3 BY dept_id
LIMIT 100;

-- LIMIT BY 支持多列分组
SELECT region, category, product_name, revenue
FROM sales
ORDER BY revenue DESC
LIMIT 5 BY region, category;

-- LIMIT BY 还支持 OFFSET
-- 每组跳过前 2 行，取接下来的 3 行
SELECT dept_id, emp_name, salary
FROM employees
ORDER BY salary DESC
LIMIT 2, 3 BY dept_id;    -- OFFSET 2, LIMIT 3
```

语法位置在 SQL 执行顺序中：

```
FROM → WHERE → GROUP BY → HAVING → ORDER BY → LIMIT BY → LIMIT → SELECT
```

### PostgreSQL DISTINCT ON

PostgreSQL 独有的 `DISTINCT ON` 可以高效实现每组取第一行：

```sql
-- 每个 department 薪资最高的 1 人
SELECT DISTINCT ON (dept_id)
    dept_id, emp_name, salary
FROM employees
ORDER BY dept_id, salary DESC;

-- 注意: ORDER BY 必须以 DISTINCT ON 的列开头
-- 错误: ORDER BY salary DESC（缺少 dept_id）
-- 正确: ORDER BY dept_id, salary DESC

-- 每个用户最近的一条日志
SELECT DISTINCT ON (user_id)
    user_id, log_time, message
FROM logs
ORDER BY user_id, log_time DESC;
```

`DISTINCT ON` 的局限：

1. **只能取每组第一行**（不能 Top-N，N > 1）
2. **ORDER BY 必须以分组列开头**，限制了排序灵活性
3. **非 SQL 标准**，只有 PostgreSQL 和 CockroachDB 等兼容引擎支持

### QUALIFY 方案（Snowflake / BigQuery / DuckDB 等）

```sql
-- 每个 department 薪资最高的 3 人
SELECT dept_id, emp_name, salary
FROM employees
QUALIFY ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) <= 3;

-- 每个 category 销量 Top 5
SELECT category, product_name, sales_amount
FROM products
QUALIFY RANK() OVER (PARTITION BY category ORDER BY sales_amount DESC) <= 5;
-- 使用 RANK 时，并列排名可能返回超过 5 行

-- 每组取唯一值（去重保留最新）
SELECT *
FROM events
QUALIFY ROW_NUMBER() OVER (PARTITION BY user_id, event_type ORDER BY ts DESC) = 1;
```

## 标准通用方案

### ROW_NUMBER + 子查询（所有引擎通用）

```sql
-- 每个 department 薪资最高的 3 人
SELECT dept_id, emp_name, salary
FROM (
    SELECT dept_id, emp_name, salary,
        ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) AS rn
    FROM employees
) ranked
WHERE rn <= 3;

-- 用 CTE 提高可读性
WITH ranked AS (
    SELECT dept_id, emp_name, salary,
        ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) AS rn
    FROM employees
)
SELECT dept_id, emp_name, salary
FROM ranked
WHERE rn <= 3;
```

### LATERAL JOIN / CROSS APPLY（有索引时最高效）

```sql
-- PostgreSQL: LATERAL（有合适索引时避免全表扫描）
SELECT d.dept_id, e.emp_name, e.salary
FROM departments d
JOIN LATERAL (
    SELECT emp_name, salary FROM employees
    WHERE dept_id = d.dept_id ORDER BY salary DESC LIMIT 3
) e ON true;

-- SQL Server: CROSS APPLY（语义等同）
SELECT d.dept_id, e.emp_name, e.salary
FROM departments d
CROSS APPLY (
    SELECT TOP 3 emp_name, salary FROM employees
    WHERE dept_id = d.dept_id ORDER BY salary DESC
) e;
```

## 设计分析: 专用语法 vs 通用方案

### 各方案对比

| 方案 | 表达力 | 可读性 | 性能控制 | 标准兼容 |
|------|--------|--------|---------|---------|
| `LIMIT BY` | Top-N | 最佳 | 好（引擎可优化） | ClickHouse 独有 |
| `DISTINCT ON` | Top-1 | 好 | 好 | PostgreSQL 独有 |
| `QUALIFY` + ROW_NUMBER | Top-N | 好 | 取决于优化器 | 非标准但流行 |
| ROW_NUMBER + 子查询 | Top-N | 一般 | 取决于优化器 | SQL 标准 |
| LATERAL / CROSS APPLY | Top-N | 好 | 最优（可用索引） | 标准(LATERAL) |

### 设计取舍

**ClickHouse LIMIT BY** 的设计哲学：直接在语言层面提供常见操作的简洁语法。缺点是引入了非标准关键字。

**PostgreSQL DISTINCT ON** 的设计哲学：复用已有关键字 DISTINCT，扩展其语义。缺点是只能 Top-1，且 ORDER BY 约束令人困惑。

**QUALIFY** 的设计哲学：提供通用的窗口函数过滤能力，Top-N per group 只是其用例之一。这是最通用的方案，但需要理解窗口函数。

## 对引擎开发者的实现建议

1. LIMIT BY 的语法实现

如果要实现 ClickHouse 风格的 LIMIT BY：

```
select_statement:
    SELECT select_list
    FROM table_ref
    [WHERE condition]
    [GROUP BY expr_list]
    [HAVING condition]
    [ORDER BY order_list]
    [LIMIT n BY expr_list]     -- 新增
    [LIMIT m [OFFSET k]]
```

2. 执行计划

#### 方案 A: 哈希分组 + 计数器

```
HashLimitBy (limit=3, by=[dept_id])
├── 内部: HashMap<dept_id, count>
├── 对每行: count = map.getOrDefault(row.dept_id, 0)
│   if count < 3: 输出行, map.put(row.dept_id, count+1)
│   else: 跳过
└── 输入: Sort(salary DESC, TableScan(employees))
```

优点: O(1) 查找，内存占用 = 不同分组数 * 计数器大小。
缺点: 依赖输入已排序（否则取的不是 Top-N 而是任意 N 行）。

#### 方案 B: 排序 + 截断

```
1. 按 (dept_id, salary DESC) 排序
2. 扫描时维护当前 dept_id 和计数器
3. dept_id 变化时重置计数器
4. 计数器 >= N 时跳过，< N 时输出
```

优点: 无需额外内存。缺点: 需要按分组列排序。

#### 最优策略选择

如果 ORDER BY 已经包含分组列（或输入已按分组列排序），方案 B 更优。否则方案 A 更优。

3. DISTINCT ON 的优化

`DISTINCT ON (cols) ... ORDER BY cols, ...` 可以被优化为：

```
1. 按 ORDER BY 排序（包含 DISTINCT ON 列作为前缀）
2. 分组边界检测: 当 DISTINCT ON 列值变化时，输出一行
3. 等效于排序后的 group-by + first-value
```

这可以利用索引有序性跳过排序步骤。

4. ROW_NUMBER + WHERE rn <= N 的优化（最重要）

这是最通用的模式，优化器应该识别并优化：

```sql
-- 识别模式:
SELECT ... FROM (
    SELECT ..., ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...) AS rn
    FROM ...
) WHERE rn <= N

-- 优化为 TopNPerGroup 算子:
TopNPerGroup(n=N, partition_by=[...], order_by=[...])
└── TableScan / IndexScan
```

这个优化避免了为每组计算所有行的 ROW_NUMBER——一旦达到 N 行就可以跳过该组剩余的行。

## 实际场景

```sql
-- 场景 1: 每个用户最近 5 条操作日志
-- ClickHouse
SELECT user_id, action, ts FROM logs ORDER BY ts DESC LIMIT 5 BY user_id;
-- 标准 SQL
SELECT user_id, action, ts FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY ts DESC) AS rn
    FROM logs
) t WHERE rn <= 5;

-- 场景 2: 每个品类销量 Top 3 的产品
-- BigQuery / Snowflake
SELECT category, product, sales
FROM products
QUALIFY ROW_NUMBER() OVER (PARTITION BY category ORDER BY sales DESC) <= 3;

-- 场景 3: 去重保留最新（每组 Top 1）
-- PostgreSQL
SELECT DISTINCT ON (user_id) user_id, email, updated_at
FROM user_profiles ORDER BY user_id, updated_at DESC;
```

## 参考资料

- ClickHouse: [LIMIT BY](https://clickhouse.com/docs/en/sql-reference/statements/select/limit-by)
- PostgreSQL: [DISTINCT ON](https://www.postgresql.org/docs/current/sql-select.html#SQL-DISTINCT)
- Snowflake: [QUALIFY](https://docs.snowflake.com/en/sql-reference/constructs/qualify)
- BigQuery: [QUALIFY clause](https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#qualify_clause)
