# 查询重写规则 (Query Rewrite Rules)

一条 SQL 在到达 cost-based 优化器之前，往往已经被悄悄改写了几十次——视图被展开、子查询被拉平、常量被折叠、外连接被消除。查询重写（query rewrite）是优化器流水线里最被低估的第一步：它不挑选执行路径，而是把"用户写的 SQL"换成"优化器更喜欢的等价 SQL"。绝大多数 join reordering、index selection 之类的耀眼优化，其实都依赖前置的重写把查询整理成一个干净、可分析的形态。本文系统对比 45+ 个数据库的查询重写能力，从最普通的 constant folding 到 PostgreSQL 独有的 `CREATE RULE`，从 Calcite 的 RelRule DSL 到 CockroachDB 的 optgen，从 Oracle materialized view rewrite 到 Spark Catalyst 的 Scala pattern matching。

## 没有 SQL 标准

ISO/IEC 9075 SQL 标准只规定了语义等价（"两个查询返回相同结果"），却从不定义优化器内部如何把一个表达式改写成另一个等价表达式。查询重写完全是**实现细节**：每个数据库都自己决定有哪些规则、按什么顺序应用、是否暴露给用户。这与 `TABLESAMPLE`、`MERGE`、`WINDOW` 等有正式标准的特性截然不同。

唯一对用户可见的"重写 API"是 PostgreSQL 的 `CREATE RULE`——它源自 Postgres 早期的 query rewrite system（Stonebraker 在 1980s 设计），保留至今主要是因为 `CREATE VIEW` 在内部就是一条 `ON SELECT DO INSTEAD` 规则。MySQL 后来加了一个 query rewrite plugin，允许 DBA 注册基于模式匹配的改写，但它和 PostgreSQL 的 `CREATE RULE` 设计哲学完全不同：MySQL 是"在 parse 阶段做字符串/AST 替换"，PostgreSQL 是"在 query tree 阶段插入或替换 range table entry"。

绝大多数数据库选择**不暴露**重写规则给用户，理由是规则之间会相互依赖、顺序敏感、容易引入正确性 bug。Apache Calcite 通过内部 `RelRule` API 让嵌入它的系统（Flink、Drill、Hive 3.x、Beam、Phoenix）可以注册自定义规则；CockroachDB 的 optgen 是一种内部 DSL，编译期生成 Go 代码；Spark Catalyst 直接用 Scala 的 case class pattern matching 写规则。它们都不对用户可见。

正因为缺标准，"我的查询有没有被重写""规则是否触发"几乎是每个引擎都需要单独学一套调试方式：Oracle 的 10053 trace、PostgreSQL 的 `EXPLAIN (VERBOSE)`、SQL Server 的 `SET STATISTICS XML ON`、Spark 的 `df.queryExecution.optimizedPlan`、Calcite 的 `RelOptListener`。

## 核心重写规则支持矩阵

下表覆盖 45+ 数据库对 14 种最常见的查询重写规则的支持情况。"是"表示规则在当前最新稳定版默认启用；"部分"表示有限制条件（例如只对 ANSI SQL 模式生效）；"--" 表示不支持；"扩展"表示需要插件或非默认配置；"自动"表示无需用户干预。

### 视图与子查询展开

| 引擎 | 视图内联 | 视图谓词下推 | 子查询展开 | EXISTS→Semi | NOT EXISTS→Anti | IN→Semi |
|------|---------|------------|----------|-------------|-----------------|---------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 | 是 |
| MySQL | 是 (8.0+) | 是 (8.0+) | 是 (8.0+) | 是 | 是 | 是 |
| MariaDB | 是 | 是 | 是 | 是 | 是 | 是 |
| SQLite | 是 | 是 | 部分 | 是 | 是 | 是 |
| Oracle | 是 | 是 | 是 | 是 | 是 | 是 |
| SQL Server | 是 | 是 | 是 | 是 | 是 | 是 |
| DB2 | 是 | 是 | 是 | 是 | 是 | 是 |
| Snowflake | 是 | 是 | 是 | 是 | 是 | 是 |
| BigQuery | 是 | 是 | 是 | 是 | 是 | 是 |
| Redshift | 是 | 是 | 是 | 是 | 是 | 是 |
| DuckDB | 是 | 是 | 是 | 是 | 是 | 是 |
| ClickHouse | 是 | 是 | 部分 | 是 | 是 | 是 |
| Trino | 是 | 是 | 是 | 是 | 是 | 是 |
| Presto | 是 | 是 | 是 | 是 | 是 | 是 |
| Spark SQL | 是 | 是 | 是 | 是 | 是 | 是 |
| Hive | 是 | 是 | 是 (3.x) | 是 | 是 | 是 |
| Flink SQL | 是 | 是 | 是 | 是 | 是 | 是 |
| Databricks | 是 | 是 | 是 | 是 | 是 | 是 |
| Teradata | 是 | 是 | 是 | 是 | 是 | 是 |
| Greenplum | 是 | 是 | 是 | 是 | 是 | 是 |
| CockroachDB | 是 | 是 | 是 | 是 | 是 | 是 |
| TiDB | 是 | 是 | 是 | 是 | 是 | 是 |
| OceanBase | 是 | 是 | 是 | 是 | 是 | 是 |
| YugabyteDB | 是 | 是 | 是 | 是 | 是 | 是 |
| SingleStore | 是 | 是 | 是 | 是 | 是 | 是 |
| Vertica | 是 | 是 | 是 | 是 | 是 | 是 |
| Impala | 是 | 是 | 是 | 是 | 是 | 是 |
| StarRocks | 是 | 是 | 是 | 是 | 是 | 是 |
| Doris | 是 | 是 | 是 | 是 | 是 | 是 |
| MonetDB | 是 | 是 | 是 | 是 | 是 | 是 |
| CrateDB | 是 | 部分 | 部分 | 是 | 是 | 是 |
| TimescaleDB | 是 | 是 | 是 | 是 | 是 | 是 |
| QuestDB | 是 | 部分 | 部分 | -- | -- | 是 |
| Exasol | 是 | 是 | 是 | 是 | 是 | 是 |
| SAP HANA | 是 | 是 | 是 | 是 | 是 | 是 |
| Informix | 是 | 是 | 是 | 是 | 是 | 是 |
| Firebird | 是 | 是 | 部分 | 是 | 是 | 是 |
| H2 | 是 | 部分 | 部分 | 部分 | 部分 | 是 |
| HSQLDB | 是 | 部分 | 部分 | 部分 | 部分 | 是 |
| Derby | 是 | 部分 | 部分 | 部分 | 部分 | 部分 |
| Amazon Athena | 是 | 是 | 是 | 是 | 是 | 是 |
| Azure Synapse | 是 | 是 | 是 | 是 | 是 | 是 |
| Google Spanner | 是 | 是 | 是 | 是 | 是 | 是 |
| Materialize | 是 | 是 | 是 | 是 | 是 | 是 |
| RisingWave | 是 | 是 | 是 | 是 | 是 | 是 |
| InfluxDB (SQL) | 是 | 部分 | 部分 | 部分 | 部分 | 是 |
| DatabendDB | 是 | 是 | 是 | 是 | 是 | 是 |
| Yellowbrick | 是 | 是 | 是 | 是 | 是 | 是 |
| Firebolt | 是 | 是 | 是 | 是 | 是 | 是 |

> 注：视图内联（view inlining/merging）指优化器把 `FROM v` 替换为 `v` 的定义体，使外部谓词可以下推到底层基表。所有现代成熟数据库默认启用，但实际效果取决于视图是否"可合并"（mergeable）：含 `DISTINCT`、`GROUP BY`、`LIMIT`、窗口函数的视图通常无法直接合并，会退化成"先物化再过滤"。

### 表达式与连接简化

| 引擎 | 常量折叠 | 常量传播 | 谓词简化 | Join 消除 | OUTER→INNER | COUNT(*)/COUNT(1) |
|------|---------|---------|---------|----------|-------------|------------------|
| PostgreSQL | 是 | 是 | 是 | 是 (9.0+) | 是 | 是 |
| MySQL | 是 | 是 | 是 | 部分 | 是 | 是 |
| MariaDB | 是 | 是 | 是 | 部分 | 是 | 是 |
| SQLite | 是 | 是 | 是 | 是 | 是 | 是 |
| Oracle | 是 | 是 | 是 | 是 | 是 | 是 |
| SQL Server | 是 | 是 | 是 | 是 | 是 | 是 |
| DB2 | 是 | 是 | 是 | 是 | 是 | 是 |
| Snowflake | 是 | 是 | 是 | 是 | 是 | 是 |
| BigQuery | 是 | 是 | 是 | 是 | 是 | 是 |
| Redshift | 是 | 是 | 是 | 是 | 是 | 是 |
| DuckDB | 是 | 是 | 是 | 是 | 是 | 是 |
| ClickHouse | 是 | 是 | 是 | 部分 | 是 | 是 |
| Trino | 是 | 是 | 是 | 是 | 是 | 是 |
| Presto | 是 | 是 | 是 | 是 | 是 | 是 |
| Spark SQL | 是 | 是 | 是 | 是 | 是 | 是 |
| Hive | 是 | 是 | 是 | 是 | 是 | 是 |
| Flink SQL | 是 | 是 | 是 | 是 | 是 | 是 |
| Databricks | 是 | 是 | 是 | 是 | 是 | 是 |
| Teradata | 是 | 是 | 是 | 是 | 是 | 是 |
| Greenplum | 是 | 是 | 是 | 是 | 是 | 是 |
| CockroachDB | 是 | 是 | 是 | 是 | 是 | 是 |
| TiDB | 是 | 是 | 是 | 是 | 是 | 是 |
| OceanBase | 是 | 是 | 是 | 是 | 是 | 是 |
| YugabyteDB | 是 | 是 | 是 | 是 | 是 | 是 |
| SingleStore | 是 | 是 | 是 | 是 | 是 | 是 |
| Vertica | 是 | 是 | 是 | 是 | 是 | 是 |
| Impala | 是 | 是 | 是 | 是 | 是 | 是 |
| StarRocks | 是 | 是 | 是 | 是 | 是 | 是 |
| Doris | 是 | 是 | 是 | 是 | 是 | 是 |
| MonetDB | 是 | 是 | 是 | 部分 | 是 | 是 |
| CrateDB | 是 | 是 | 部分 | 部分 | 是 | 是 |
| TimescaleDB | 是 | 是 | 是 | 是 | 是 | 是 |
| QuestDB | 是 | 部分 | 部分 | -- | 部分 | 是 |
| Exasol | 是 | 是 | 是 | 是 | 是 | 是 |
| SAP HANA | 是 | 是 | 是 | 是 | 是 | 是 |
| Informix | 是 | 是 | 是 | 是 | 是 | 是 |
| Firebird | 是 | 部分 | 是 | -- | 是 | 是 |
| H2 | 是 | 部分 | 是 | -- | 是 | 是 |
| HSQLDB | 是 | 部分 | 是 | -- | 是 | 是 |
| Derby | 是 | 部分 | 部分 | -- | 是 | 是 |
| Amazon Athena | 是 | 是 | 是 | 是 | 是 | 是 |
| Azure Synapse | 是 | 是 | 是 | 是 | 是 | 是 |
| Google Spanner | 是 | 是 | 是 | 是 | 是 | 是 |
| Materialize | 是 | 是 | 是 | 是 | 是 | 是 |
| RisingWave | 是 | 是 | 是 | 是 | 是 | 是 |
| InfluxDB (SQL) | 是 | 部分 | 部分 | -- | 部分 | 是 |
| DatabendDB | 是 | 是 | 是 | 是 | 是 | 是 |
| Yellowbrick | 是 | 是 | 是 | 是 | 是 | 是 |
| Firebolt | 是 | 是 | 是 | 是 | 是 | 是 |

> Join 消除（join elimination）的典型场景：`SELECT a.* FROM a LEFT JOIN b ON a.id = b.aid`，如果 `b.aid` 是唯一键且 SELECT/WHERE 没有引用 `b` 的列，则整个 JOIN 可以被丢弃。PostgreSQL 9.0 加入此规则；早期版本完全没有。MySQL 直到 8.0 仍然只能消除 `INNER JOIN` 子树而非 `LEFT JOIN`，故标记"部分"。

### 用户可定义规则与物化视图重写

| 引擎 | 用户定义规则 | 自动 MV 重写 | API/语法 |
|------|------------|------------|---------|
| PostgreSQL | 是 | -- | `CREATE RULE`（内置 view 用），无原生 MV rewrite |
| MySQL | 插件 | -- | query rewrite plugin (5.7+) |
| MariaDB | 插件 | -- | 继承 MySQL 插件 |
| SQLite | -- | -- | -- |
| Oracle | -- | 是 | `query_rewrite_enabled=TRUE` |
| SQL Server | -- | 是 (Indexed View) | NOEXPAND/EXPAND VIEWS hint |
| DB2 | -- | 是 (MQT) | `CURRENT REFRESH AGE` |
| Snowflake | -- | 是 | 自动透明 |
| BigQuery | -- | 是 | 自动透明 |
| Redshift | -- | 是 | `mv_enable_aqmv_for_session` |
| DuckDB | -- | -- | 暂无 MV |
| ClickHouse | -- | -- | MV 是触发器式，无 rewrite |
| Trino | -- | 是 | connector dependent |
| Presto | -- | 是 | connector dependent |
| Spark SQL | -- | 部分 | Iceberg/Hudi MV with hint |
| Hive | -- | 是 (3.x) | Calcite-based |
| Flink SQL | -- | -- | 查询本身是流，MV 概念不同 |
| Databricks | -- | 是 | Photon + Delta Live Tables |
| Teradata | -- | 是 | Join Index rewrite |
| Greenplum | -- | -- | 继承 PG，无 MV rewrite |
| CockroachDB | -- | -- | optgen 仅内部 |
| TiDB | -- | -- | TiFlash MPP，无 rewrite |
| OceanBase | -- | 是 (4.x) | Oracle 兼容 MV |
| YugabyteDB | -- | -- | 继承 PG |
| SingleStore | -- | -- | -- |
| Vertica | -- | 是 | Live Aggregate Projection |
| Impala | -- | -- | -- |
| StarRocks | -- | 是 | 同步/异步 MV rewrite |
| Doris | -- | 是 | sync/async MV rewrite |
| MonetDB | -- | -- | -- |
| CrateDB | -- | -- | -- |
| TimescaleDB | -- | 部分 | continuous aggregate |
| QuestDB | -- | -- | -- |
| Exasol | -- | -- | -- |
| SAP HANA | -- | 是 | calculation view |
| Informix | -- | 是 | -- |
| Firebird | -- | -- | -- |
| H2 | -- | -- | -- |
| HSQLDB | -- | -- | -- |
| Derby | -- | -- | -- |
| Amazon Athena | -- | 是 | 继承 Trino + Glue MV |
| Azure Synapse | -- | 是 | materialized view auto |
| Google Spanner | -- | -- | -- |
| Materialize | -- | 是 | 一切都是 MV，自动维护 |
| RisingWave | -- | 是 | 流式 MV |
| InfluxDB (SQL) | -- | -- | -- |
| DatabendDB | -- | -- | -- |
| Yellowbrick | -- | 是 | postgres 兼容 + 自有 MV |
| Firebolt | -- | 是 | aggregating index |

> 统计：约 23 个引擎支持自动物化视图重写；只有 PostgreSQL 暴露原生 `CREATE RULE` API，MySQL/MariaDB 通过 plugin 提供有限的用户定义重写能力。其他 40+ 数据库的重写规则全部封闭在优化器内部。

## 关键重写规则详解

### 1. 视图内联（View Inlining / View Merging）

最经典的重写：把视图引用替换成它的定义体，使外层谓词可以下推到基表。

```sql
CREATE VIEW vip_orders AS
    SELECT o.*
    FROM orders o
    WHERE o.customer_tier = 'GOLD';

-- 用户写：
SELECT order_id, total
FROM vip_orders
WHERE order_date >= '2026-01-01';

-- 优化器重写为：
SELECT order_id, total
FROM orders
WHERE customer_tier = 'GOLD'
  AND order_date >= '2026-01-01';
```

**不可合并的情况**：

- 视图含 `DISTINCT` / `GROUP BY` / `HAVING`（聚合改变行数语义）
- 视图含 `LIMIT` / `OFFSET`（截断顺序敏感）
- 视图含窗口函数（PARTITION 边界依赖输入集合）
- 视图含 `UNION`（PostgreSQL 通常仍可"分支"重写）
- 用户用 `WITH MATERIALIZED` 显式要求物化（PostgreSQL 12+）

### 2. 谓词下推到视图（Predicate Pushdown Through Views）

视图内联本身就是谓词下推的前提；但即使视图不可完全内联，优化器仍可能把"安全"的谓词推进去：

```sql
-- 视图含聚合，无法整体内联
CREATE VIEW dept_summary AS
    SELECT dept_id, COUNT(*) AS n, SUM(salary) AS total
    FROM employees
    GROUP BY dept_id;

SELECT * FROM dept_summary WHERE dept_id = 10;

-- 优化器仍可下推 dept_id = 10，因为它出现在 GROUP BY 中：
SELECT dept_id, COUNT(*), SUM(salary)
FROM employees
WHERE dept_id = 10           -- 推进去
GROUP BY dept_id;
```

PostgreSQL、Oracle、SQL Server、Calcite 系都支持这种"分组键过滤下推"。

### 3. 常量折叠（Constant Folding）

最便宜的重写：在编译期就算出常量表达式：

```sql
SELECT * FROM orders WHERE total > 100 + 50 * 2;
-- 重写为
SELECT * FROM orders WHERE total > 200;
```

适用范围包括算术、字符串拼接、`CAST`、纯函数（`UPPER('abc')` → `'ABC'`）。注意 `NOW()`、`RANDOM()` 等不稳定函数**不能**折叠。

### 4. 常量传播（Constant Propagation）

更进一步：从等值谓词推断变量值，扩散到其他位置：

```sql
SELECT * FROM orders o, customers c
WHERE o.customer_id = c.id
  AND c.id = 42;

-- 重写为
SELECT * FROM orders o, customers c
WHERE o.customer_id = 42         -- 新增
  AND c.id = 42;
```

新增的 `o.customer_id = 42` 可以让 `orders` 表用上 `customer_id` 索引。Oracle 称之为 transitive predicate generation；PostgreSQL 在 `equivalence class` 机制中实现；Calcite 有 `ReduceExpressionsRule` + `JoinPushTransitivePredicatesRule`。

### 5. 子查询展开 / 拉平（Subquery Unnesting / Flattening）

最高 ROI 的重写之一：把相关子查询变成 JOIN：

```sql
-- 用户写
SELECT *
FROM orders o
WHERE EXISTS (
    SELECT 1 FROM customers c
    WHERE c.id = o.customer_id
      AND c.tier = 'GOLD'
);

-- 重写为
SELECT o.*
FROM orders o
SEMI JOIN customers c
       ON c.id = o.customer_id
      AND c.tier = 'GOLD';
```

子查询执行需要逐外行 N 次嵌套循环；JOIN 形态可以走 hash join、merge join、bloom filter，性能差距常常上千倍。MySQL 在 5.6 之前的"DEPENDENT SUBQUERY"性能灾难的根源就是缺少子查询展开；5.7 才补齐 IN-to-semi-join。

### 6. EXISTS → SEMI JOIN

```sql
-- 用户写
SELECT * FROM orders WHERE EXISTS (
    SELECT 1 FROM payments WHERE payments.order_id = orders.id);

-- 内部 plan
HashSemiJoin
    Hash Cond: (orders.id = payments.order_id)
    -> Seq Scan on orders
    -> Hash
        -> Seq Scan on payments
```

### 7. NOT EXISTS → ANTI JOIN

```sql
-- 用户写
SELECT * FROM customers WHERE NOT EXISTS (
    SELECT 1 FROM orders WHERE orders.customer_id = customers.id);

-- 内部 plan
HashAntiJoin
    Hash Cond: (customers.id = orders.customer_id)
```

注意 NULL 语义：`NOT IN (subquery)` 和 `NOT EXISTS` 在子查询返回 NULL 时**结果不同**。优化器只有在能证明子查询列 NOT NULL 时，才会把 `NOT IN` 改写成 anti join；否则只能保留 nested loop 风格的 anti semi join。

### 8. IN → SEMI JOIN

```sql
SELECT * FROM orders WHERE customer_id IN (
    SELECT id FROM customers WHERE region = 'APAC');

-- 重写为
SELECT o.*
FROM orders o
SEMI JOIN customers c
       ON o.customer_id = c.id
      AND c.region = 'APAC';
```

`IN (常量列表)` 形式不需要 semi join，会被直接展开为 `OR` 链或哈希查找表。

### 9. 未使用 OUTER JOIN 消除（Join Elimination）

```sql
CREATE TABLE orders (id INT PRIMARY KEY, customer_id INT, total NUMERIC);
CREATE TABLE customers (id INT PRIMARY KEY, name TEXT);

-- 用户写
SELECT o.id, o.total
FROM orders o
LEFT JOIN customers c ON c.id = o.customer_id;

-- 优化器消除 customers 这一边
SELECT o.id, o.total FROM orders o;
```

成立条件：

1. JOIN 类型是 LEFT/RIGHT OUTER（INNER 不行——可能减少行数）
2. 被消除一侧的连接键有 UNIQUE 约束（保证每个外行最多匹配一行）
3. SELECT、WHERE、GROUP BY、ORDER BY 都没有引用被消除一侧的列

PostgreSQL 9.0、SQL Server 早期、Oracle 10g、Calcite 都有这个规则。MySQL 8.0 仍然不能完美消除 LEFT JOIN——只能在 ORM 框架自动生成的 `LEFT JOIN ... 1=1` 模式下识别出"无用 JOIN"的简单子集。

### 10. OUTER → INNER JOIN（NULL 拒绝谓词）

如果 WHERE 谓词会拒绝 NULL，那 LEFT JOIN 实际上等价于 INNER JOIN：

```sql
-- 用户写
SELECT *
FROM orders o
LEFT JOIN customers c ON c.id = o.customer_id
WHERE c.region = 'APAC';            -- 拒绝 c 侧的 NULL 行

-- 重写为
SELECT *
FROM orders o
INNER JOIN customers c ON c.id = o.customer_id
WHERE c.region = 'APAC';
```

INNER JOIN 比 LEFT JOIN 多了 join order 自由度，优化器可以选择以 customers 为驱动表。这条规则几乎所有现代优化器都有。

### 11. 谓词简化（Predicate Simplification）

包括重言式消除、矛盾检测、范围合并：

```sql
WHERE x = x                  -- 重写为 x IS NOT NULL（注意 NULL 语义）
WHERE 1 = 1 AND x > 10       -- 重写为 x > 10
WHERE x > 10 AND x > 20      -- 重写为 x > 20
WHERE x = 5 AND x = 10       -- 重写为 FALSE，整个查询不执行
WHERE x BETWEEN 1 AND 10
   OR x BETWEEN 5 AND 15     -- 重写为 x BETWEEN 1 AND 15
```

### 12. COUNT(\*) 与 COUNT(1) 的等价

虽然两者在 SQL 标准中语义相同（计数不为 NULL 的行——`COUNT(*)` 计数所有行，`COUNT(1)` 计数所有 `1` 字面量，结果相同），所有现代优化器都把 `COUNT(1)`、`COUNT(2)`、`COUNT('x')` 等价规约为 `COUNT(*)`。这意味着在性能上选哪种写法**完全没有差别**——这是被无数博客文章错误地反复争论的问题。

不过 `COUNT(col)` 不同——它只计数 `col` 不为 NULL 的行。

### 13. 用户定义重写规则

PostgreSQL 是唯一暴露原生 API 的：

```sql
-- 屏蔽对敏感表的 DELETE
CREATE RULE no_delete_audit AS
    ON DELETE TO audit_log
    DO INSTEAD NOTHING;

-- 把 INSERT 重定向到分区表
CREATE RULE insert_2026 AS
    ON INSERT TO measurements
    WHERE NEW.ts >= '2026-01-01' AND NEW.ts < '2027-01-01'
    DO INSTEAD INSERT INTO measurements_2026 VALUES (NEW.*);
```

但 PostgreSQL 官方文档明确建议：**新代码不要用 RULE，请用 trigger 或 partitioning**。RULE 唯一仍然必要的用途是 `CREATE VIEW`（内部生成 `ON SELECT DO INSTEAD`）和某些 INSTEAD OF 视图更新。

MySQL query rewrite plugin 的写法：

```sql
INSTALL PLUGIN rewriter SONAME 'rewriter.so';
INSERT INTO query_rewrite.rewrite_rules (pattern, replacement)
VALUES ('SELECT * FROM users WHERE id = ?',
        'SELECT id, name FROM users WHERE id = ?');
CALL query_rewrite.flush_rewrite_rules();
```

它工作在 parse 后的 AST 上，靠 `?` 占位符做模式匹配，能力远不及优化器内部规则。

### 14. 物化视图自动重写

```sql
-- Oracle 例子
CREATE MATERIALIZED VIEW mv_dept_sum
    BUILD IMMEDIATE
    REFRESH FAST
    ENABLE QUERY REWRITE
AS
    SELECT dept_id, SUM(salary) AS total
    FROM employees
    GROUP BY dept_id;

-- 用户的查询
SELECT dept_id, SUM(salary) FROM employees GROUP BY dept_id;

-- 优化器重写为
SELECT dept_id, total AS "SUM(salary)" FROM mv_dept_sum;
```

需要 `query_rewrite_enabled = TRUE`（Oracle 默认开启），且物化视图被标记为 `ENABLE QUERY REWRITE`，且 `query_rewrite_integrity` 允许 stale 数据时还可以利用未同步的 MV。Snowflake、BigQuery、Databricks、Redshift、Synapse、StarRocks、Doris、SAP HANA、DB2 都有类似机制（详见 `materialized-view-patterns.md`）。

## 各引擎重写机制详解

### PostgreSQL：rewrite system + planner rewrites

PostgreSQL 的查询处理分为四个阶段：parser → **rewriter** → planner → executor。"rewriter" 是一个独立的子系统，专门处理 `CREATE RULE` 和视图展开；planner 内部还有一套"二次重写"，包括 subquery pullup、outer join simplification、qual pushdown 等。

```sql
-- 查看重写后的查询树
EXPLAIN (VERBOSE, COSTS OFF, FORMAT JSON)
SELECT *
FROM (SELECT * FROM orders WHERE total > 100) sub
WHERE sub.customer_id = 42;

-- 你会看到 sub 已经被消除，只剩一个 Seq Scan 带两个谓词
```

PostgreSQL planner 重写要点：

- **Subquery pull-up**：`FROM (SELECT ...) sub` 会被消除，子查询的 from list、quals 直接挂到外层。条件是子查询不含 `LIMIT`、`DISTINCT`、`GROUP BY`、`HAVING`、窗口函数等。
- **Equivalence classes**：PG 为每个等值连接维护一个等价类（例如 `a.x = b.x = c.x`），常量传播、谓词派生都基于此机制。
- **Outer join simplification**：见 `joinrels.c::reduce_outer_joins`。
- **Join elimination**：9.0 引入，需要外键 + 唯一约束。
- **CREATE RULE**：见 `rewriteHandler.c`，把 ON SELECT 规则展开成嵌套 SELECT。

PostgreSQL 没有原生物化视图自动重写——`CREATE MATERIALIZED VIEW` 只是个手动 refresh 的快照表，需要用户在 SQL 里显式查询它。社区有 `pg_ivm` 扩展实现增量维护，但仍无 query rewrite。

### Oracle：物化视图重写之王 + 10053 trace

Oracle 有业内最成熟的 materialized view query rewrite，支持 query containment、aggregate roll-up、join back、partial text match 等多种匹配方式：

```sql
ALTER SESSION SET query_rewrite_enabled = TRUE;
ALTER SESSION SET query_rewrite_integrity = STALE_TOLERATED;

-- 即使用户的查询和 MV 不完全相同，也可能被重写
-- 例如 MV 按 dept_id, year 分组，查询按 dept_id 分组 → roll-up
```

Oracle 还有：

- **Star transformation**：把 star schema 查询重写成 bitmap join 形式
- **Subquery unnesting**：通过 `_unnest_subquery` 隐藏参数控制
- **Predicate move-around (PMA)**：跨子查询块复制谓词
- **JPPD (Join Predicate Push-Down)**：把 join 谓词推到分组子查询内部
- **OR-expansion**：把 `WHERE x=1 OR y=2` 重写为两个子查询的 UNION ALL

调试方式：

```sql
ALTER SESSION SET EVENTS '10053 trace name context forever, level 1';
EXPLAIN PLAN FOR SELECT ...;
-- trace 文件包含每条 transformation 是否被应用的详细日志
```

### SQL Server：Memo + transformation rules

SQL Server 的查询优化器（"QO"）基于 Cascades 框架，所有重写都表达成 Memo 中的 transformation rule。常见规则包括 `JoinAssociate`、`JoinCommute`、`JNtoLASJN`（join → left anti semi join）、`SELonJN`（谓词推到 JOIN 下方）等。

调试方式：

```sql
-- 显示 transformation 的统计
DBCC TRACEON (3604, 8675);
SELECT ...;
DBCC TRACEOFF (3604, 8675);

-- 或者 XML showplan
SET STATISTICS XML ON;
```

可以通过 `OPTION (USE HINT(...))` 启用/禁用部分规则，例如 `OPTION (USE HINT('DISABLE_OPTIMIZED_NESTED_LOOP'))`。

### MySQL：迟到的子查询重写者

MySQL 5.6 之前的 `WHERE id IN (SELECT ...)` 是出了名的灾难——优化器无法 unnest，只能逐外行重新执行子查询。5.6 引入 semi-join transformation（首次支持 `IN→SEMI`），5.7 进一步加入 derived table merge 和 subquery materialization，8.0 才接近 PostgreSQL/Oracle 的水平。

8.0 的重写能力：

- IN→semi join、EXISTS→semi join
- 派生表合并（derived table merging）
- 条件下推到派生表
- 外连接简化
- 索引条件下推（ICP）
- 哈希连接（8.0.18+）

但仍然没有：完整的 join elimination（不能消除带 LEFT JOIN 的无用表）、相关子查询的复杂 unnest（嵌套层数过深时退化）。

MySQL 唯一对用户暴露的"重写 API"是 query rewrite plugin：

```sql
INSTALL PLUGIN rewriter SONAME 'rewriter.so';
INSERT INTO query_rewrite.rewrite_rules
    (pattern, replacement, pattern_database)
VALUES
    ('SELECT * FROM t1 WHERE a = ?',
     'SELECT * FROM t1 WHERE a = ? AND b > 0',
     'mydb');
CALL query_rewrite.flush_rewrite_rules();
```

工作机制：parse 后立刻匹配 AST 模板，命中后用替换 AST 重生成 query。常用于不能修改应用代码时强制改写糟糕 SQL。

### CockroachDB：optgen DSL

CockroachDB 的优化器 "opt" 是从零写的，参考 Cascades，但用了一个独有的 DSL "optgen" 描述重写规则，编译期生成 Go 代码。例子：

```text
[InlineProjectInProject, Normalize]
(Project
    $input:(Project $innerInput:* $innerProjections:*)
    $projections:* & ^(HasOuterCols $projections)
    $passthrough:*
)
=>
(Project
    $innerInput
    (InlineProjections $projections $innerProjections)
    $passthrough
)
```

每条规则有标签 `[Name, Normalize|Explore]` 区分逻辑等价改写（Normalize）和物理探索（Explore）。源码在 `pkg/sql/opt/norm/rules/*.opt`。规则覆盖 200+ 条，从 constant folding 到 join elimination 应有尽有。用户**不能**注册自己的规则——optgen 是编译期工具。

### Snowflake / BigQuery：透明 MV rewrite

Snowflake 和 BigQuery 都把物化视图维护和 query rewrite 完全藏在云端：

- Snowflake：自动维护 MV，查询执行前优化器透明匹配；用户只需 `CREATE MATERIALIZED VIEW` 然后照常查基表，命中 MV 时执行计划会显示为对 MV 的扫描。
- BigQuery：相同模式。`bq query --use_query_cache=false --dry_run` 可以看到是否走 MV。

两家都不提供"禁用 MV rewrite"的会话参数（除了删除 MV 本身），也不暴露规则细节。

### Spark SQL：Catalyst + Scala pattern matching

Catalyst 是 Spark SQL 的优化器，全部用 Scala 写。重写规则就是 Scala 的 case class pattern matching，举例 `ConstantFolding`：

```scala
object ConstantFolding extends Rule[LogicalPlan] {
  def apply(plan: LogicalPlan): LogicalPlan = plan transform {
    case e if e.foldable => Literal.create(e.eval(EmptyRow), e.dataType)
  }
}
```

`Optimizer.scala` 中列出全部 batch、规则、迭代次数。注册自定义规则的方式：

```scala
spark.experimental.extraOptimizations = Seq(MyCustomRule)
```

调试：

```scala
df.queryExecution.optimizedPlan      // 看优化后的 logical plan
df.queryExecution.executedPlan        // 看物理 plan
```

### Calcite-based 引擎（Drill / Flink / Hive 3.x / Beam / Phoenix）

Apache Calcite 是事实上的"开源优化器框架"，被嵌入到大量系统中。它提供：

- **HepPlanner**：启发式规则匹配，按用户给定的规则集顺序应用，适合 normalization。
- **VolcanoPlanner**：基于 Cascades 的 cost-based planner，规则触发后产生新的等价表达式存入 MEMO，由 cost model 选择。
- **RelRule API**：用户继承 `RelRule<Config>` 定义新规则，描述 match pattern 和 onMatch 动作。

```java
public class FilterMergeRule extends RelRule<FilterMergeRule.Config> {
    @Override public void onMatch(RelOptRuleCall call) {
        Filter top = call.rel(0);
        Filter bot = call.rel(1);
        RexNode merged = call.builder()
            .and(top.getCondition(), bot.getCondition());
        call.transformTo(call.builder()
            .push(bot.getInput())
            .filter(merged)
            .build());
    }
}
```

Calcite 自带 200+ 条规则（`org.apache.calcite.rel.rules` 包），覆盖 constant folding、join reordering、aggregate 折叠、materialized view substitution 等。Flink、Drill、Trino（部分）、Hive 3.x、Beam SQL、Phoenix、Apache Pinot 都直接复用这套规则集再加几条自己的。

## Apache Calcite 规则系统深入

Calcite 的 RelRule 不只是模式匹配那么简单。一条规则的完整生命周期：

1. **Match phase**：HepPlanner / VolcanoPlanner 在 Memo 中查找匹配 RelNode tree pattern 的子图。Pattern 是一个 RelNode 操作符 + 子操作符的递归描述。
2. **onMatch**：规则被回调，可访问匹配到的 RelNode 实例。生成等价的新 RelNode 树。
3. **Transform**：调用 `RelOptRuleCall.transformTo(newRel)`，把新表达式注册进 Memo。
4. **Cost evaluation**：VolcanoPlanner 比较新旧表达式的代价，保留更优的；HepPlanner 直接接受。

典型 normalization 规则集（执行顺序很重要）：

```
ProjectMergeRule          -- 合并相邻 Project
FilterMergeRule           -- 合并相邻 Filter
ProjectFilterTransposeRule -- 把 Project 推到 Filter 下方
FilterProjectTransposeRule -- 把 Filter 推到 Project 下方
FilterJoinRule            -- 把 Filter 推到 JOIN 内或下方
JoinPushExpressionsRule   -- 从 JOIN 谓词中拆出非连接条件
AggregateProjectMergeRule -- 合并 Aggregate 与下方 Project
AggregateExpandDistinctAggregatesRule  -- 把 COUNT(DISTINCT x) 重写成两层 Aggregate
ReduceExpressionsRule     -- 常量折叠 + 谓词简化
PruneEmptyRules           -- 删除恒为空的子树
```

物化视图重写在 Calcite 中通过 `MaterializedViewSubstitutionVisitor` 实现，基于"unification"算法匹配查询与已知 MV 的 RelNode 形态，支持 column-level remapping、aggregate roll-up、join compensation。这是 Hive 3.x、Drill、部分 Flink 用例的共享基础。

调试 Calcite：

```java
RelOptListener listener = new RelOptListener() {
    public void ruleProductionSucceeded(RelOptListener.RuleProductionEvent e) {
        System.out.println("Applied: " + e.getRuleCall().getRule());
    }
};
planner.addListener(listener);
```

## Oracle 物化视图 query rewrite 深入

Oracle 的 MV rewrite 是业内功能最丰富的之一。以下是它能识别的主要模式。

**1. Exact text match（最简单）**

```sql
CREATE MATERIALIZED VIEW mv1
ENABLE QUERY REWRITE AS
SELECT dept_id, SUM(salary) FROM employees GROUP BY dept_id;

-- 用户查询完全相同 → 直接命中
SELECT dept_id, SUM(salary) FROM employees GROUP BY dept_id;
```

**2. Aggregate computability**

```sql
-- MV 按 (dept_id, year) 分组
CREATE MATERIALIZED VIEW mv2
ENABLE QUERY REWRITE AS
SELECT dept_id, year, SUM(salary), COUNT(*)
FROM employees
GROUP BY dept_id, year;

-- 用户按 dept_id 查询 → roll-up
SELECT dept_id, SUM(salary)
FROM employees
GROUP BY dept_id;

-- Oracle 重写为
SELECT dept_id, SUM(SUM_salary)
FROM mv2
GROUP BY dept_id;
```

**3. Join back**

```sql
-- MV 没有 employee_name
CREATE MATERIALIZED VIEW mv3
ENABLE QUERY REWRITE AS
SELECT employee_id, SUM(amount) AS total
FROM payroll
GROUP BY employee_id;

-- 用户查询要 employee_name，可以从 employees 表 join 回来
SELECT e.name, SUM(p.amount)
FROM employees e, payroll p
WHERE e.id = p.employee_id
GROUP BY e.name;

-- Oracle 重写为
SELECT e.name, mv3.total
FROM employees e, mv3
WHERE e.id = mv3.employee_id;
```

**4. Partial text match + dimension constraints**

如果声明了 `DIMENSION` 对象（描述层次关系），Oracle 可以做更激进的 roll-up，例如从"按月分组的 MV"重写"按年分组的查询"。

**关键参数**：

- `query_rewrite_enabled = TRUE`（默认）
- `query_rewrite_integrity = ENFORCED|TRUSTED|STALE_TOLERATED`：分别要求 MV 完全一致 / 信任 RELY 约束 / 允许 stale。
- `optimizer_features_enable = '19.1.0'`：影响哪些重写规则被激活。

**调试**：

```sql
-- 验证查询是否能被重写
DBMS_MVIEW.EXPLAIN_REWRITE(
    query => 'SELECT dept_id, SUM(salary) FROM employees GROUP BY dept_id',
    mv    => 'SCOTT.MV2',
    statement_id => 'X'
);
SELECT * FROM REWRITE_TABLE WHERE statement_id = 'X';
```

输出会告诉你 MV 命中、未命中或部分命中的精确原因（aggregate not computable, missing rollup column, etc.）。

## 重写规则的相互作用与顺序敏感性

规则之间的相互依赖是优化器开发最难的部分。两个例子：

**例 1：常量传播 + 谓词下推**

```sql
SELECT *
FROM orders o
JOIN customers c ON c.id = o.customer_id
WHERE c.id = 42;
```

正确顺序：先做常量传播（推出 `o.customer_id = 42`），再做谓词下推（把两个谓词都推到对应表的扫描算子下方）。如果顺序反了，`o.customer_id = 42` 这条新谓词不会出现，索引扫描错失机会。

**例 2：subquery unnesting + outer join simplification**

```sql
SELECT *
FROM orders o
LEFT JOIN (
    SELECT customer_id, SUM(amount) AS total
    FROM payments
    GROUP BY customer_id
) p ON p.customer_id = o.customer_id
WHERE p.total > 100;
```

`p.total > 100` 拒绝 NULL → outer join 可化为 inner join → 派生表可下推谓词 → 子查询展开 → 最终是一个普通 GROUP BY 后跟一个谓词的 JOIN。但只有按"outer→inner→pushdown→unnest"的顺序应用规则才能得到完整结果。

PostgreSQL 的 planner 内部用一个固定顺序处理这些；Calcite 通过 `HepPlanner.matchOrder` 控制；CockroachDB optgen 把规则分成 Normalize 和 Explore 两组并迭代到 fixed point；Spark Catalyst 把规则编入"batches"，每个 batch 设定迭代上限。

## 重写规则与其他优化阶段的关系

| 阶段 | 输入 | 输出 | 典型操作 |
|------|------|------|---------|
| Parser | SQL 文本 | 语法树 | 词法/语法分析 |
| Analyzer | 语法树 | 解析后 logical plan | 名称解析、类型检查 |
| **Rewriter** | logical plan | 简化的 logical plan | 视图展开、子查询展开、常量折叠 |
| Optimizer | logical plan | 物理 plan | join order、index 选择、物理算子 |
| Executor | 物理 plan | rows | 扫描、连接、聚合 |

重写阶段输出的 logical plan 越规范化（normalized），后续的 cost-based 优化器越好工作。这就是为什么大多数数据库会把 normalization 规则和 exploration 规则严格分开——前者必须无条件应用直至 fixed point，后者按 cost 取舍。

详细的优化器演化历史，参见 `optimizer-evolution.md`；
子查询的具体优化策略，参见 `subquery-optimization.md`；
物化视图重写的更多模式，参见 `materialized-view-patterns.md`。

## 调试与可观测性

| 引擎 | 命令 / 工具 | 输出位置 |
|------|------------|---------|
| PostgreSQL | `EXPLAIN (VERBOSE, COSTS OFF)` + `auto_explain` | 客户端 / 日志 |
| Oracle | `EVENTS '10053 trace'` + `DBMS_MVIEW.EXPLAIN_REWRITE` | trace 文件 |
| SQL Server | `SET STATISTICS XML ON` + `DBCC TRACEON(8675)` | XML showplan |
| MySQL | `EXPLAIN FORMAT=TREE` / `EXPLAIN ANALYZE` | 客户端 |
| Spark SQL | `df.queryExecution.optimizedPlan` | Scala/Python REPL |
| Flink | `EXPLAIN PLAN FOR ...` | SQL CLI |
| Trino / Presto | `EXPLAIN (TYPE LOGICAL)` | 客户端 |
| CockroachDB | `EXPLAIN (OPT, VERBOSE)` | 客户端 |
| Snowflake | query profile UI | Web UI |
| BigQuery | "Execution details" tab | Web UI |
| Calcite-based | `RelOptListener` + `Hook.Closeable` | 应用日志 |

## 设计争议

**1. 用户可见的重写规则是好主意吗？**

PostgreSQL `CREATE RULE` 的历史教训：规则系统过于强大、过于隐蔽，几乎所有非平凡用例都会引入 bug。MySQL plugin 的折中方案——AST 模板匹配——更安全但表达能力有限。共识是：**不要给用户暴露规则 API**，只提供 hint 来开关已有规则。

**2. 重写规则要不要带 cost？**

历史上有两派：
- 纯启发式（PostgreSQL rewriter、Calcite HepPlanner）：规则总是单方向应用，永远改善或保持中性。
- 基于 cost 的探索（Cascades 系：SQL Server、CockroachDB、Calcite VolcanoPlanner）：规则可能产生更差的形态，由 MEMO 与 cost model 取舍。

实务中两者结合：先做无条件 normalization，再做 cost-based exploration。

**3. 子查询展开总是好的吗？**

不一定。展开后的 join 可能让优化器面对更大的 join order 搜索空间，导致编译时间爆炸。Oracle 在 `_optimizer_unnest_subquery=FALSE` 时退化为 nested loop 风格执行；某些 OLTP 场景下这反而更快。

**4. 物化视图重写的 staleness 模型**

强一致性（每次查询都验证 MV 与基表同步）vs 最终一致性（允许 stale 数据，定时刷新）。Oracle 通过 `query_rewrite_integrity` 三档显式选择；BigQuery、Snowflake 选择"自动维护 + 用户不可控"；Materialize 干脆把所有 MV 都做成增量维护到永远不 stale。

## 关键发现

1. **没有 SQL 标准、几乎没有用户 API**。45+ 数据库里只有 PostgreSQL `CREATE RULE`（不推荐使用）和 MySQL query rewrite plugin（能力有限）两个用户可见接口。其余全部封闭在优化器内部。

2. **基础重写规则已是行业标配**。常量折叠、谓词简化、视图内联、IN/EXISTS→semi join、OUTER→INNER 这些规则在所有现代成熟引擎中都默认开启；嵌入式数据库（H2、HSQLDB、Derby、SQLite）和早期版本的 MySQL 是主要差异点。

3. **Join elimination 是分水岭**。能否消除"未使用的 LEFT JOIN"区分了真正成熟的优化器和入门级实现。PostgreSQL 9.0、Oracle 10g、SQL Server 早期都有；MySQL 8.0 仍只能消除部分；H2/HSQLDB/Derby/Firebird 几乎完全没有。

4. **物化视图重写是 OLAP 引擎的核心战场**。Snowflake、BigQuery、Databricks、Redshift、StarRocks、Doris、SAP HANA、Oracle、DB2 都投入了大量工程，这是它们与开源 OLTP 数据库（PostgreSQL、MySQL）的关键差距。

5. **Apache Calcite 占据开源生态半壁江山**。Flink、Drill、Hive 3.x、Beam、Phoenix、Pinot 等都直接复用 Calcite 的 200+ 条规则。学一遍 Calcite 等于学一遍开源 SQL 优化器历史。

6. **Cascades 框架几乎统一了商业实现**。SQL Server、CockroachDB、Calcite VolcanoPlanner、Greenplum ORCA 都以 Cascades 论文为蓝本。统一的 Memo + transformation rule 模型让重写规则的开发模式高度收敛。

7. **子查询展开是高 ROI 优化**。MySQL 5.7 之前的相关子查询性能灾难史是最好的反例：缺一条 unnest 规则，整类查询慢 1000 倍。

8. **优化器 trace 是被低估的调试工具**。Oracle 10053 trace、SQL Server XML showplan、PostgreSQL `auto_explain`、Spark `optimizedPlan` 都能暴露重写过程，但很少有教程系统讲解。

9. **规则的顺序与相互作用是最大的工程难点**。PostgreSQL planner 用固定顺序，Calcite HepPlanner 用 matchOrder，CockroachDB optgen 用 Normalize/Explore 分组，Spark Catalyst 用 batch + iteration limit。每种方案都有局限。

10. **`COUNT(*)` vs `COUNT(1)` 的争论纯属神话**。所有现代优化器都把它们等价规约，性能完全一致。

## 参考资料

- PostgreSQL: [Rule System](https://www.postgresql.org/docs/current/rules.html)
- PostgreSQL: [Planner / Optimizer source](https://github.com/postgres/postgres/tree/master/src/backend/optimizer)
- Oracle: [Query Rewrite for Materialized Views](https://docs.oracle.com/en/database/oracle/oracle-database/19/dwhsg/advanced-query-rewrite-materialized-views.html)
- Oracle: [10053 Optimizer Trace Reference](https://www.oracle.com/technetwork/database/bi-datawarehousing/twp-explain-the-explain-plan-052011-393674.pdf)
- SQL Server: [Query Optimizer Architecture](https://learn.microsoft.com/en-us/sql/relational-databases/query-processing-architecture-guide)
- MySQL: [The Query Rewriter Plugin](https://dev.mysql.com/doc/refman/8.0/en/rewriter-query-rewrite-plugin.html)
- Apache Calcite: [Algebra and Rules](https://calcite.apache.org/docs/algebra.html)
- Apache Calcite: [Materialized Views](https://calcite.apache.org/docs/materialized_views.html)
- CockroachDB: [Optgen Language](https://github.com/cockroachdb/cockroach/blob/master/pkg/sql/opt/optgen/lang/doc.go)
- Spark Catalyst: [Optimizer source](https://github.com/apache/spark/blob/master/sql/catalyst/src/main/scala/org/apache/spark/sql/catalyst/optimizer/Optimizer.scala)
- Goetz Graefe, "The Cascades Framework for Query Optimization" (1995)
- Pirahesh, Hellerstein, Hasan, "Extensible/Rule Based Query Rewrite Optimization in Starburst" (1992)
- Stonebraker, "The Design of POSTGRES" (1986) — origin of the rule system
