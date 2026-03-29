# CTE 与递归查询：各 SQL 方言全对比

Common Table Expression (CTE) 是 SQL:1999 引入的核心特性，递归 CTE 更是图遍历、层级查询的基础能力。然而 45+ 种 SQL 引擎在 WITH 语法、RECURSIVE 关键字要求、循环检测、物化策略等方面存在显著差异。本文面向引擎开发者，做全面横向对比。

---

## 1. 基本 CTE 支持矩阵

WITH 子句允许在 SELECT 前定义命名的临时结果集，提升可读性并允许复用。

### 语法

```sql
-- SQL 标准: WITH 子句
WITH dept_stats AS (
    SELECT dept_id, AVG(salary) AS avg_salary
    FROM employees
    GROUP BY dept_id
)
SELECT e.name, e.salary, d.avg_salary
FROM employees e
JOIN dept_stats d ON e.dept_id = d.dept_id;
```

### 支持矩阵

| 引擎 | 基本 CTE | 递归 CTE | RECURSIVE 关键字 | 版本 | 备注 |
|------|---------|---------|-----------------|------|------|
| PostgreSQL | ✅ | ✅ | 必须 | 8.4+ (2009) | SQL 标准实现 |
| MySQL | ✅ | ✅ | 必须 | 8.0+ (2018) | 8.0 前不支持 |
| MariaDB | ✅ | ✅ | 必须 | 10.2+ (2017) | - |
| Oracle | ✅ | ✅ | 不需要 | 11gR2+ (2009) | 也有 CONNECT BY |
| SQL Server | ✅ | ✅ | 不需要 | 2005+ | 隐式递归 |
| SQLite | ✅ | ✅ | 必须 | 3.8.3+ (2014) | - |
| BigQuery | ✅ | ✅ | 必须 | GA | 有深度限制 |
| Snowflake | ✅ | ✅ | 必须 | GA | - |
| ClickHouse | ✅ | ⚠️ | 必须 | 20.6+ (CTE) / 21.8+ (递归) | 递归为实验性功能 (allow_experimental_analyzer) |
| Hive | ✅ | ❌ | N/A | 0.13+ | 不支持递归 |
| Spark SQL | ✅ | ❌ | N/A | 2.0+ | 不支持递归 CTE |
| Flink SQL | ✅ | ❌ | N/A | 1.12+ | 流式场景不适合递归 |
| MaxCompute | ✅ | ❌ | N/A | GA | 不支持递归 |
| Hologres | ✅ | ❌ | N/A | GA | 不支持递归 |
| StarRocks | ✅ | ❌ | N/A | 2.5+ | 不支持递归 |
| Doris | ✅ | ❌ | N/A | 1.2+ | 不支持递归 |
| TiDB | ✅ | ✅ | 必须 | 6.1+ (2022) | - |
| OceanBase | ✅ | ✅ | 必须 (MySQL 模式) | 3.x+ | Oracle 模式不需要 |
| CockroachDB | ✅ | ✅ | 必须 | 2.0+ | 兼容 PostgreSQL |
| Spanner | ✅ | ❌ | N/A | GA | 不支持递归 |
| DuckDB | ✅ | ✅ | 必须 | 0.2.0+ | 完整支持 |
| Trino | ✅ | ✅ | 必须 | 340+ | 有深度限制 |
| Presto | ✅ | ✅ | 必须 | 0.246+ | - |
| Databricks | ✅ | ⚠️ | N/A | Runtime 7+ | 无标准递归 CTE；有 CONNECT BY 扩展 |
| Redshift | ✅ | ❌ | N/A | GA | 不支持递归 |
| Teradata | ✅ | ✅ | 必须 | 14.0+ | - |
| Db2 | ✅ | ✅ | 不需要 | 9.7+ | 隐式递归 |
| H2 | ✅ | ✅ | 必须 | 1.4+ | - |
| Greenplum | ✅ | ✅ | 必须 | 6.0+ | 基于 PostgreSQL |
| Vertica | ✅ | ❌ | N/A | GA | 不支持递归 |
| SAP HANA | ✅ | ✅ | 不需要 | 1.0+ | 隐式递归 |
| Informix | ✅ | ✅ | 必须 | 12.10+ | - |
| SingleStore | ✅ | ❌ | N/A | GA | 不支持递归 |
| YugabyteDB | ✅ | ✅ | 必须 | 2.6+ | 兼容 PostgreSQL |
| PolarDB | ✅ | ✅ | 必须 | GA | 兼容 MySQL/PostgreSQL |
| TimescaleDB | ✅ | ✅ | 必须 | GA | PostgreSQL 扩展 |
| QuestDB | ✅ | ❌ | N/A | GA | 不支持递归 |
| Firebolt | ✅ | ❌ | N/A | GA | 不支持递归 |
| Impala | ✅ | ❌ | N/A | 2.1+ | 不支持递归 |
| Kylin | ✅ | ❌ | N/A | GA | 不支持递归 |
| AnalyticDB | ✅ | ❌ | N/A | GA | 不支持递归 |

**关键发现**: OLAP / 大数据引擎（Hive、Spark SQL、StarRocks、Doris、MaxCompute、Redshift、Vertica 等）普遍不支持递归 CTE。ClickHouse 从 21.8 起提供实验性递归 CTE 支持。这不是疏忽，而是设计选择——递归查询本质上是迭代计算，与大规模并行处理（MPP）架构的批量扫描模式不兼容。

---

## 2. WITH RECURSIVE 与隐式递归

SQL 标准（SQL:1999）要求使用 `WITH RECURSIVE` 关键字来声明递归 CTE。但部分引擎选择了隐式递归——只要 CTE 体内引用了自身，就自动按递归模式执行。

### 两种流派

```sql
-- 流派一: 显式 RECURSIVE（SQL 标准）
-- PostgreSQL, MySQL, SQLite, BigQuery, Snowflake, TiDB, DuckDB, H2 等
WITH RECURSIVE ancestors AS (
    SELECT id, parent_id, name FROM nodes WHERE id = 100
    UNION ALL
    SELECT n.id, n.parent_id, n.name
    FROM nodes n JOIN ancestors a ON n.id = a.parent_id
)
SELECT * FROM ancestors;

-- 流派二: 隐式递归（无需 RECURSIVE 关键字）
-- Oracle, SQL Server, Db2, SAP HANA
WITH ancestors AS (
    SELECT id, parent_id, name FROM nodes WHERE id = 100
    UNION ALL
    SELECT n.id, n.parent_id, n.name
    FROM nodes n JOIN ancestors a ON n.id = a.parent_id
)
SELECT * FROM ancestors;
```

### 设计动机分析

| 方案 | 优点 | 缺点 |
|------|------|------|
| 显式 RECURSIVE | 意图明确；解析器可快速判断是否需要迭代执行计划；SQL 标准 | 用户需要记住额外关键字 |
| 隐式递归 | 语法更简洁；减少用户认知负担 | 解析器需要分析 CTE 体是否存在自引用；可能误判 |

**对引擎开发者**: 推荐实现显式 `WITH RECURSIVE`（SQL 标准路线），同时可选地接受隐式递归作为兼容扩展。OceanBase 的双模策略（MySQL 模式需要 RECURSIVE、Oracle 模式不需要）是一个好的参考。

---

## 3. 多 CTE 与 CTE 间引用

### 多 CTE 定义

```sql
-- 在同一个 WITH 中定义多个 CTE
WITH
    active_users AS (
        SELECT user_id, name FROM users WHERE status = 'active'
    ),
    user_orders AS (
        SELECT user_id, COUNT(*) AS order_count
        FROM orders
        GROUP BY user_id
    )
SELECT a.name, COALESCE(o.order_count, 0)
FROM active_users a
LEFT JOIN user_orders o ON a.user_id = o.user_id;
```

所有支持 CTE 的引擎都支持多 CTE 定义。

### CTE 引用其他 CTE

```sql
-- CTE 可以引用在它之前定义的其他 CTE
WITH
    base AS (
        SELECT dept_id, AVG(salary) AS avg_sal FROM employees GROUP BY dept_id
    ),
    enriched AS (
        SELECT b.dept_id, b.avg_sal, d.name
        FROM base b JOIN departments d ON b.dept_id = d.dept_id  -- 引用 base
    )
SELECT * FROM enriched;
```

所有支持 CTE 的引擎都允许后定义的 CTE 引用先定义的 CTE（前向引用），但不允许前定义的 CTE 引用后定义的 CTE（反向引用）。

### 递归与非递归混合

```sql
-- 一个 WITH RECURSIVE 块中可以混合递归和非递归 CTE
-- RECURSIVE 关键字作用于整个 WITH 块
WITH RECURSIVE
    config AS (                               -- 非递归
        SELECT max_depth FROM settings WHERE key = 'tree_depth'
    ),
    tree AS (                                 -- 递归
        SELECT id, name, parent_id, 1 AS depth
        FROM nodes WHERE parent_id IS NULL
        UNION ALL
        SELECT n.id, n.name, n.parent_id, t.depth + 1
        FROM nodes n
        JOIN tree t ON n.parent_id = t.id
        JOIN config c ON t.depth < c.max_depth  -- 引用非递归 CTE
    )
SELECT * FROM tree;
```

**注意**: 在 PostgreSQL、MySQL 等引擎中，`WITH RECURSIVE` 中的 RECURSIVE 是语法标记，并非要求每个 CTE 都必须递归。只要有一个 CTE 需要递归，整个 WITH 块就需要 RECURSIVE 关键字。

---

## 4. 递归 CTE 终止语义

递归 CTE 的终止有两种基本机制：

### 4.1 空结果终止（所有引擎）

```
迭代执行:
  WorkTable := 锚成员结果
  Result := WorkTable
  WHILE WorkTable 不为空:
      NewRows := 用 WorkTable 执行递归成员
      Result := Result ∪ NewRows
      WorkTable := NewRows
  RETURN Result
```

当某次迭代的递归成员不产生新行时，递归终止。这是所有引擎共有的核心语义。

### 4.2 UNION vs UNION ALL

```sql
-- UNION ALL: 保留所有行（可能包含重复）
-- 大多数引擎的默认选择，性能更好
WITH RECURSIVE r AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM r WHERE n < 10
)
SELECT * FROM r;  -- 结果: 1, 2, 3, ..., 10

-- UNION: 自动去重
-- 可作为简单的循环检测手段（重复行不再加入工作表）
WITH RECURSIVE r AS (
    SELECT id FROM graph WHERE id = 1
    UNION                                      -- 去重！
    SELECT g.target_id FROM graph g JOIN r ON g.source_id = r.id
)
SELECT * FROM r;
```

| 引擎 | UNION ALL | UNION (去重) | 备注 |
|------|----------|-------------|------|
| PostgreSQL | ✅ | ✅ | - |
| Oracle | ✅ | ✅ | - |
| SQL Server | ✅ | ✅ | - |
| MySQL | ✅ | ✅ (8.0.19+) | 8.0.19 前仅 UNION ALL |
| SQLite | ✅ | ✅ | - |
| MariaDB | ✅ | ✅ | 10.3+ 支持 UNION |
| BigQuery | ✅ | ✅ | - |
| Snowflake | ✅ | ✅ | - |
| DuckDB | ✅ | ✅ | - |
| TiDB | ✅ | ❌ | 仅 UNION ALL |
| CockroachDB | ✅ | ✅ | - |
| Trino | ✅ | ✅ | - |
| Db2 | ✅ | ✅ | - |
| Spark SQL | - | - | 不支持递归 CTE |

TiDB 仅支持 `UNION ALL` 是重要的兼容性差异（MySQL 从 8.0.19 起已支持 UNION DISTINCT）。这意味着在 TiDB 上遍历图结构时，必须手动维护访问路径来防止无限循环。

---

## 5. 最大递归深度限制

递归 CTE 最危险的问题是无限循环。各引擎通过不同的默认限制和配置方式来防护。

### 对比矩阵

| 引擎 | 默认限制 | 配置方式 | 作用域 |
|------|---------|---------|--------|
| PostgreSQL | 无限制 | 无内置参数（需手动 WHERE 控制） | - |
| MySQL | 1000 | `SET cte_max_recursion_depth = N` | 会话/全局 |
| MariaDB | 1000 | `SET max_recursive_iterations = N` | 会话/全局 |
| Oracle | 无限制 | 无内置参数 | - |
| SQL Server | 100 | `OPTION (MAXRECURSION N)` | 查询级 |
| SQLite | 1000 | 编译时 `SQLITE_MAX_TRIGGER_DEPTH`；无运行时 PRAGMA | 编译时 |
| BigQuery | 500 | 不可调整 | 固定 |
| Snowflake | 无限制 | 无内置参数 | - |
| DuckDB | 无限制 | 无内置参数 | - |
| TiDB | 1000 | `SET cte_max_recursion_depth = N` | 会话/全局 |
| CockroachDB | 无限制 | 无内置参数 | - |
| Trino | 10 | `max_recursion_depth` 配置 | 会话级 |
| Db2 | 无限制 | 无内置参数 | - |
| SAP HANA | 无限制 | 无内置参数（推荐 WHERE 限制） | - |

### 配置示例

```sql
-- MySQL / TiDB: 会话级调整
SET cte_max_recursion_depth = 10000;

-- SQL Server: 查询级 hint
WITH org AS (...)
SELECT * FROM org
OPTION (MAXRECURSION 500);           -- 仅影响此查询

-- SQL Server: 取消限制（危险）
OPTION (MAXRECURSION 0);             -- 0 = 无限制

-- MariaDB: 会话级调整
SET max_recursive_iterations = 5000;

-- Trino: 会话级
SET SESSION max_recursion_depth = 100;
```

**设计建议**: SQL Server 的查询级 `MAXRECURSION` hint 是最灵活的设计——不影响其他查询，且错误信息清楚提示当前限制值和调整方法。MySQL 的会话级参数次之。PostgreSQL / Oracle 完全无限制的做法在生产环境中有风险。

---

## 6. CYCLE 子句：循环检测（SQL:1999）

### 支持矩阵

| 引擎 | CYCLE 子句 | SEARCH 子句 | 版本 | 备注 |
|------|-----------|------------|------|------|
| PostgreSQL | ✅ | ✅ | 14+ (2021) | SQL 标准实现 |
| Oracle | ✅ | ✅ | 11gR2+ | 较早支持 |
| DuckDB | ✅ | ✅ | 0.8.0+ | - |
| Db2 | ✅ | ✅ | 9.7+ | - |
| MySQL | ❌ | ❌ | - | 需手动实现 |
| SQL Server | ❌ | ❌ | - | 需手动实现 |
| SQLite | ❌ | ❌ | - | 需手动实现 |
| MariaDB | ❌ | ❌ | - | 需手动实现 |
| BigQuery | ❌ | ❌ | - | 需手动实现 |
| Snowflake | ❌ | ❌ | - | 需手动实现 |
| TiDB | ❌ | ❌ | - | 需手动实现 |
| CockroachDB | ❌ | ❌ | - | 需手动实现 |
| Trino | ❌ | ❌ | - | 需手动实现 |

### 标准语法

```sql
-- CYCLE 子句: 自动检测并标记循环路径
WITH RECURSIVE graph_walk AS (
    SELECT id, parent_id, name
    FROM nodes WHERE id = 1

    UNION ALL

    SELECT n.id, n.parent_id, n.name
    FROM nodes n
    JOIN graph_walk g ON n.parent_id = g.id
)
CYCLE id SET is_cycle USING path        -- PostgreSQL 14+, Oracle, Db2
SELECT * FROM graph_walk;

-- CYCLE 子句语义:
-- CYCLE id           → 用 id 列值判断是否出现重复
-- SET is_cycle       → 生成布尔列标记循环
-- USING path         → 生成路径列记录访问历史
-- 检测到循环的行仍出现在结果中（is_cycle = true），但不再继续递归
```

### 手动循环检测（兼容方案）

```sql
-- PostgreSQL / DuckDB（使用数组）
WITH RECURSIVE graph_walk AS (
    SELECT id, parent_id, ARRAY[id] AS visited, false AS is_cycle
    FROM nodes WHERE id = 1

    UNION ALL

    SELECT n.id, n.parent_id,
           g.visited || n.id,
           n.id = ANY(g.visited)
    FROM nodes n
    JOIN graph_walk g ON n.parent_id = g.id
    WHERE NOT g.is_cycle
)
SELECT * FROM graph_walk WHERE NOT is_cycle;

-- MySQL / TiDB（使用字符串拼接）
WITH RECURSIVE graph_walk AS (
    SELECT id, parent_id, CAST(id AS CHAR(500)) AS path
    FROM nodes WHERE id = 1

    UNION ALL

    SELECT n.id, n.parent_id, CONCAT(g.path, ',', n.id)
    FROM nodes n
    JOIN graph_walk g ON n.parent_id = g.id
    WHERE FIND_IN_SET(n.id, g.path) = 0
)
SELECT * FROM graph_walk;

-- SQL Server（使用字符串路径）
WITH graph_walk AS (
    SELECT id, parent_id,
           CAST('/' + CAST(id AS VARCHAR) + '/' AS VARCHAR(MAX)) AS path
    FROM nodes WHERE id = 1

    UNION ALL

    SELECT n.id, n.parent_id,
           CAST(g.path + CAST(n.id AS VARCHAR) + '/' AS VARCHAR(MAX))
    FROM nodes n
    JOIN graph_walk g ON n.parent_id = g.id
    WHERE g.path NOT LIKE '%/' + CAST(n.id AS VARCHAR) + '/%'
)
SELECT * FROM graph_walk;
```

---

## 7. CTE 物化策略：MATERIALIZED / NOT MATERIALIZED

CTE 是否物化（将结果存入临时表）对性能影响巨大。

### 支持矩阵

| 引擎 | 默认行为 | MATERIALIZED hint | NOT MATERIALIZED hint | 版本 |
|------|---------|-------------------|----------------------|------|
| PostgreSQL | 12 前总物化；12+ 优化器选择 | ✅ | ✅ | 12+ (2019) |
| MySQL | 优化器选择 | ❌ | ❌ | - |
| Oracle | 优化器选择 | `/*+ MATERIALIZE */` | `/*+ INLINE */` | 11g+ |
| SQL Server | 不物化（内联展开） | ❌ | ❌ | - |
| SQLite | 优化器选择 | ✅ | ✅ | 3.35+ |
| BigQuery | 优化器选择 | ❌ | ❌ | - |
| Snowflake | 优化器选择 | ❌ | ❌ | - |
| DuckDB | 优化器选择 | ✅ | ✅ | 0.8+ |
| MariaDB | 优化器选择 | ❌ | ❌ | - |
| CockroachDB | 总物化 | ✅ | ✅ | 21.2+ |
| Trino | 不物化（内联展开） | ❌ | ❌ | - |
| Spark SQL | 不物化（内联展开） | ❌ | ❌ | - |
| Db2 | 优化器选择 | ❌ | ❌ | - |

### 语法

```sql
-- PostgreSQL 12+ / SQLite 3.35+
WITH expensive_calc AS MATERIALIZED (
    SELECT ... FROM large_table WHERE complex_condition
)
SELECT * FROM expensive_calc a
JOIN expensive_calc b ON a.id = b.ref_id;
-- MATERIALIZED: 强制物化，CTE 结果计算一次存入临时表
-- 适用于 CTE 被多次引用且计算开销大的场景

WITH simple_filter AS NOT MATERIALIZED (
    SELECT * FROM users WHERE active = true
)
SELECT * FROM simple_filter WHERE dept_id = 5;
-- NOT MATERIALIZED: 强制内联（等价于子查询展开）
-- 适用于外层有高选择性过滤条件可下推的场景

-- Oracle: 使用 hint 注释
WITH expensive_calc AS (
    SELECT /*+ MATERIALIZE */ ... FROM large_table
)
SELECT * FROM expensive_calc;

WITH simple_filter AS (
    SELECT /*+ INLINE */ * FROM users WHERE active = true
)
SELECT * FROM simple_filter WHERE dept_id = 5;
```

### 设计动机

物化与内联的核心权衡：

```
物化 (MATERIALIZED):
  + CTE 被多次引用时只计算一次
  + 可以在临时结果上建立索引（部分引擎）
  - 阻止谓词下推（外层的 WHERE 条件无法推入 CTE 内部）
  - 占用额外内存/磁盘空间

内联 (NOT MATERIALIZED):
  + 允许优化器做谓词下推、列裁剪等优化
  + 无需额外存储
  - CTE 被多次引用时会重复计算
  - 可能导致子查询重复展开后计划膨胀
```

**PostgreSQL 12 的行为变更**: 在 12 之前，PostgreSQL 总是物化 CTE（被称为"优化屏障"）。12 开始，优化器会根据 CTE 被引用的次数和复杂度自动选择。这一变更提升了许多查询的性能，但也破坏了依赖旧行为的优化技巧（如故意用 CTE 阻止谓词下推）。

---

## 8. CTE 在 DML 中的使用

CTE 不仅可以用于 SELECT，还可以用于 INSERT、UPDATE、DELETE 语句。

### 支持矩阵

| 引擎 | INSERT ... WITH | UPDATE ... WITH | DELETE ... WITH | WITH ... INSERT | WITH ... UPDATE | WITH ... DELETE |
|------|----------------|----------------|----------------|----------------|----------------|----------------|
| PostgreSQL | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| MySQL | ❌ | ❌ | ❌ | ✅ (8.0+) | ✅ (8.0+) | ✅ (8.0+) |
| Oracle | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| SQL Server | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| SQLite | ❌ | ❌ | ❌ | ✅ (3.35+) | ✅ (3.35+) | ✅ (3.35+) |
| DuckDB | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| MariaDB | ❌ | ❌ | ❌ | ✅ (10.2+) | ✅ (10.2+) | ✅ (10.2+) |
| BigQuery | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| Snowflake | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| TiDB | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| CockroachDB | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Trino | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| Db2 | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| Spark SQL | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |

**说明**: "WITH ... INSERT" 表示 `WITH cte AS (...) INSERT INTO t SELECT * FROM cte`，CTE 在前。"INSERT ... WITH" 表示 `INSERT INTO t WITH cte AS (...) SELECT * FROM cte`，CTE 在 INSERT 之后。大多数引擎只支持前者。

### 语法示例

```sql
-- 模式一: WITH 在前（大多数引擎）
WITH inactive AS (
    SELECT user_id FROM users
    WHERE last_login < CURRENT_DATE - INTERVAL '1 year'
)
DELETE FROM user_profiles WHERE user_id IN (SELECT user_id FROM inactive);

-- 模式二: WITH 在 DML 之后（SQL Server, PostgreSQL）
INSERT INTO archive_table
WITH old_data AS (
    SELECT * FROM orders WHERE order_date < '2020-01-01'
)
SELECT * FROM old_data;

-- PostgreSQL 特有: 可写 CTE（Writeable CTE / Data-Modifying CTE）
WITH deleted_rows AS (
    DELETE FROM orders
    WHERE order_date < '2020-01-01'
    RETURNING *                                -- DML 在 CTE 内部
)
INSERT INTO order_archive SELECT * FROM deleted_rows;
-- 这个特性极为强大: 在一条语句中完成"删除 + 归档"
-- 仅 PostgreSQL 和 CockroachDB 支持
```

---

## 9. 递归 CTE 的高级特性对比

### 9.1 SEARCH 子句（搜索顺序控制）

```sql
-- SEARCH DEPTH FIRST: 深度优先遍历
WITH RECURSIVE org AS (
    SELECT id, name, manager_id FROM employees WHERE manager_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.manager_id
    FROM employees e JOIN org o ON e.manager_id = o.id
)
SEARCH DEPTH FIRST BY name SET ordercol
SELECT * FROM org ORDER BY ordercol;

-- SEARCH BREADTH FIRST: 广度优先遍历
-- 语法相同，只改 DEPTH 为 BREADTH
SEARCH BREADTH FIRST BY name SET ordercol
```

仅 PostgreSQL 14+、Oracle 11gR2+、DuckDB 0.8+、Db2 9.7+ 支持。

### 9.2 递归成员中的限制

不同引擎对递归成员中允许的操作有不同限制：

| 限制项 | MySQL | PostgreSQL | Oracle | SQL Server | SQLite |
|--------|-------|-----------|--------|-----------|--------|
| 递归成员中使用 GROUP BY | ❌ | ✅ | ❌ | ❌ | ✅ |
| 递归成员中使用子查询 | ❌ | ✅ | ❌ | ❌ | ✅ |
| 递归成员中使用 LIMIT/TOP | ❌ | ❌ | ❌ | ❌ | ✅ |
| 递归成员中使用聚合函数 | ❌ | ❌ | ❌ | ❌ | ✅ |
| 递归成员中使用窗口函数 | ❌ | ❌ | ❌ | ❌ | ❌ |
| 递归引用多次出现 | ❌ | ❌ | ❌ | ❌ | ❌ |
| 递归引用在 LEFT JOIN 右侧 | ❌ | ❌ | ❌ | ❌ | ❌ |

**通用规则**: 递归引用在递归成员中只能出现一次，且只能在 INNER JOIN 的一侧。这些限制源于递归 CTE 的迭代执行模型——每次迭代只处理上一轮的新增行。

---

## 10. 跨引擎兼容性汇总

### 核心能力矩阵

| 引擎 | 基本 CTE | 递归 | 需要 RECURSIVE | UNION 去重 | CYCLE | 物化 hint | DML 中 CTE | 最大深度 |
|------|---------|------|---------------|-----------|-------|----------|-----------|---------|
| PostgreSQL | ✅ | ✅ | 是 | ✅ | ✅ (14+) | ✅ (12+) | ✅ | 无限制 |
| MySQL | ✅ | ✅ | 是 | ✅ (8.0.19+) | ❌ | ❌ | ✅ | 1000 |
| Oracle | ✅ | ✅ | 否 | ✅ | ✅ | hint | ✅ | 无限制 |
| SQL Server | ✅ | ✅ | 否 | ✅ | ❌ | ❌ | ✅ | 100 |
| SQLite | ✅ | ✅ | 是 | ✅ | ❌ | ✅ (3.35+) | ✅ | 1000 |
| BigQuery | ✅ | ✅ | 是 | ✅ | ❌ | ❌ | ✅ | 500 |
| Snowflake | ✅ | ✅ | 是 | ✅ | ❌ | ❌ | ✅ | 无限制 |
| ClickHouse | ✅ | ⚠️ (实验) | 是 | - | - | - | ❌ | - |
| DuckDB | ✅ | ✅ | 是 | ✅ | ✅ | ✅ | ✅ | 无限制 |
| Trino | ✅ | ✅ | 是 | ✅ | ❌ | ❌ | ✅ | 10 |
| Spark SQL | ✅ | ❌ | - | - | - | - | ✅ | - |
| Hive | ✅ | ❌ | - | - | - | - | ✅ | - |
| Flink SQL | ✅ | ❌ | - | - | - | - | ✅ | - |
| StarRocks | ✅ | ❌ | - | - | - | - | ✅ | - |
| Doris | ✅ | ❌ | - | - | - | - | ✅ | - |
| MaxCompute | ✅ | ❌ | - | - | - | - | ✅ | - |
| TiDB | ✅ | ✅ | 是 | ❌ | ❌ | ❌ | ✅ | 1000 |
| OceanBase | ✅ | ✅ | 模式相关 | ✅ | ❌ | ❌ | ✅ | 1000 |
| CockroachDB | ✅ | ✅ | 是 | ✅ | ❌ | ✅ | ✅ | 无限制 |
| Db2 | ✅ | ✅ | 否 | ✅ | ✅ | ❌ | ✅ | 无限制 |
| Redshift | ✅ | ❌ | - | - | - | - | ✅ | - |
| Teradata | ✅ | ✅ | 是 | ✅ | ❌ | ❌ | ✅ | 无限制 |
| Greenplum | ✅ | ✅ | 是 | ✅ | ❌ | ❌ | ✅ | 无限制 |
| Vertica | ✅ | ❌ | - | - | - | - | ✅ | - |
| SAP HANA | ✅ | ✅ | 否 | ✅ | ❌ | ❌ | ✅ | 无限制 |
| YugabyteDB | ✅ | ✅ | 是 | ✅ | ❌ | ❌ | ✅ | 无限制 |
| PolarDB | ✅ | ✅ | 是 | ✅ | ❌ | ❌ | ✅ | 1000 |
| TimescaleDB | ✅ | ✅ | 是 | ✅ | ✅ (14+) | ✅ (12+) | ✅ | 无限制 |
| Impala | ✅ | ❌ | - | - | - | - | ✅ | - |
| SingleStore | ✅ | ❌ | - | - | - | - | ❌ | - |

---

## 11. 对引擎开发者的实现建议

### 11.1 分层实现路线图

对于尚未支持递归 CTE 的引擎（如 StarRocks、Doris、MaxCompute），建议按以下优先级分阶段实现：

```
Phase 1: 基础递归 CTE
  - WITH RECURSIVE ... UNION ALL
  - 默认递归深度限制 (建议 1000)
  - 迭代执行模型 (WorkTable 方案)
  实现难度: ★★☆☆☆

Phase 2: UNION 去重 + 深度配置
  - 递归 CTE 中支持 UNION (自动去重)
  - 用户可配置最大递归深度
  - 超限时的清晰错误提示
  实现难度: ★★☆☆☆

Phase 3: CYCLE / SEARCH 子句
  - CYCLE 子句 (SQL:2011 循环检测)
  - SEARCH DEPTH/BREADTH FIRST 子句
  - 可在 planner 阶段改写为等价的手动路径维护
  实现难度: ★★★☆☆

Phase 4: 物化控制
  - MATERIALIZED / NOT MATERIALIZED hint
  - 优化器自动选择物化策略
  实现难度: ★★★☆☆
```

### 11.2 递归深度保护设计

```
推荐方案:
1. 默认限制: 1000 (与 MySQL 一致，业界共识)
2. 配置粒度:
   - 查询级 (最灵活): OPTION (MAXRECURSION N)
   - 会话级: SET cte_max_recursion_depth = N
   - 全局默认值: 配置文件中设定
3. 错误信息模板:
   "Recursive query exceeded maximum recursion depth of {limit}.
    Current depth: {current}. Hint: SET cte_max_recursion_depth = {suggested}"
4. 特殊值: 0 表示无限制 (需要显式设置，不作为默认值)
```

### 11.3 内存管理策略

```
递归 CTE 的内存消耗来源:
1. WorkTable: 存放当前迭代的行
2. Result: 累积所有迭代的结果
3. CYCLE 路径: 每行维护一个路径数组

建议:
- WorkTable 使用内存缓冲区，超过阈值后溢出到磁盘
- UNION 模式需要额外的去重 Hash 表
- CYCLE 路径数组应限制最大长度
- 监控指标: 迭代次数、WorkTable 大小、累积行数
```

### 11.4 MPP 架构下的递归 CTE

大数据引擎不支持递归 CTE 的根本原因：

```
挑战:
1. 递归是串行迭代，与 MPP 的并行处理模型冲突
2. 每次迭代可能产生数据倾斜（某些节点有大量子节点）
3. WorkTable 需要在所有计算节点间广播或 Shuffle
4. 迭代次数不可预测，难以做资源规划

可行方案:
- 将递归 CTE 限制在 Coordinator 节点执行
- 要求锚成员和递归成员的结果集较小
- 使用 Broadcast 策略分发 WorkTable
- 设置较低的默认深度限制 (如 100)

Trino 的实现参考:
- 默认限制 10 次迭代（非常保守）
- WorkTable 使用 Exchange 算子在节点间分发
- 每次迭代都是一次完整的分布式查询执行
```

### 11.5 RECURSIVE 关键字的取舍

```
推荐: 要求 WITH RECURSIVE 关键字

理由:
1. SQL 标准合规
2. 解析器实现更简单: 看到 RECURSIVE 就准备迭代执行计划
3. 用户意图明确: 误写递归 CTE（如笔误导致自引用）时会报错而非意外递归
4. 与 PostgreSQL / MySQL 生态兼容（用户基数最大）

如果需要兼容 Oracle / SQL Server 用户:
- 同时接受隐式递归（自引用时自动识别）
- 当检测到隐式递归时可发出 NOTICE 提示用户添加 RECURSIVE 关键字
```

### 11.6 CTE 物化决策

```
优化器自动选择物化策略的参考规则:

物化 (存入临时表):
  - CTE 被引用 >= 2 次
  - CTE 包含 volatile 函数 (如 random(), now())
  - CTE 的估算行数较小 (< 10000)
  - 用户显式指定 MATERIALIZED

内联 (展开为子查询):
  - CTE 被引用恰好 1 次
  - 外层查询有高选择性过滤条件可下推
  - CTE 是简单的过滤/投影 (无聚合、无排序)
  - 用户显式指定 NOT MATERIALIZED

递归 CTE:
  - 必须物化 (WorkTable 本身就是物化结构)
  - 不适用 NOT MATERIALIZED
```

---

## 12. 设计动机与跨引擎权衡

### 为什么 CTE 如此重要

CTE 的价值不仅在于语法糖，更在于三个层面的工程意义：

1. **可读性**: 将复杂查询拆解为命名的逻辑步骤，比深层嵌套子查询更易理解和维护
2. **复用性**: 同一个 CTE 可被多次引用，避免复制粘贴子查询
3. **递归能力**: 递归 CTE 是 SQL 中唯一的图/树遍历标准方案（CONNECT BY 是 Oracle 专有）

### 为什么这么多引擎不支持递归

```
根本原因: SQL 的声明式语义 vs 递归的命令式本质

SQL 被设计为声明式语言: "告诉我你要什么，不要告诉我怎么做"
递归 CTE 打破了这个原则: 它实际上是一个循环结构，有明确的执行顺序

对于 MPP 引擎:
- 每个查询被拆分为多个 Stage/Fragment 并行执行
- 递归要求 "执行一轮 → 检查是否有新行 → 再执行一轮"
- 这种串行依赖无法简单地映射到 DAG 执行模型

对于流式引擎 (Flink SQL):
- 流处理的核心假设是数据无限到达
- 递归 CTE 假设数据有限且会终止
- 两者语义不兼容

实际影响:
- 用户在 StarRocks/Doris 中需要层级查询时，通常用应用层循环代替
- 或者预先将树/图结构扁平化存储（如 Closure Table、Materialized Path）
```

### CONNECT BY vs 递归 CTE

```
历史脉络:
1979  Oracle 2       CONNECT BY (最早的层级查询方案)
1999  SQL:1999       WITH RECURSIVE (标准化方案)
2009  Oracle 11gR2   同时支持两者
2018  MySQL 8.0      WITH RECURSIVE (追赶标准)

CONNECT BY 的启示:
- Oracle 在标准化 20 年前就解决了层级查询问题
- CONNECT BY 语法更紧凑，内置 LEVEL/PATH/ISLEAF 伪列
- 但它只能处理单表层级关系，无法做通用递归计算
- SQL:1999 的递归 CTE 更通用，可以处理多表 JOIN、复杂条件

引擎开发者的选择:
- 实现 WITH RECURSIVE (SQL 标准) 而非 CONNECT BY
- 如果需要兼容 Oracle 迁移用户，可额外支持 CONNECT BY → 递归 CTE 的改写
```

---

## 参考资料

- SQL:1999 标准: ISO/IEC 9075-2:1999, Section 7.13 (Recursive Query)
- SQL:1999 标准: CYCLE clause, SEARCH clause (Section 7.13)
- [PostgreSQL: WITH Queries (CTEs)](https://www.postgresql.org/docs/current/queries-with.html)
- [MySQL 8.0: Recursive CTEs](https://dev.mysql.com/doc/refman/8.0/en/with.html#common-table-expressions-recursive)
- [Oracle: Hierarchical Queries](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Hierarchical-Queries.html)
- [SQL Server: WITH common_table_expression](https://learn.microsoft.com/en-us/sql/t-sql/queries/with-common-table-expression-transact-sql)
- [SQLite: WITH clause](https://www.sqlite.org/lang_with.html)
- [BigQuery: Recursive CTEs](https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#recursive_cte)
- [Snowflake: Recursive CTEs](https://docs.snowflake.com/en/sql-reference/constructs/with#recursive-ctes)
- [DuckDB: WITH clause](https://duckdb.org/docs/sql/query_syntax/with.html)
- [Trino: WITH Recursive](https://trino.io/docs/current/sql/select.html#with-recursive-clause)
