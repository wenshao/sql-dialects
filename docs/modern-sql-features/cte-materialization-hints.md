# CTE 物化提示 (CTE Materialization Hints)

一个 WITH 子句只有两种可能：要么被执行成"视图栅栏 (view fence)"——计算一次、存入临时关系、多处引用；要么被优化器**内联展开 (inline expansion)**——当作一段宏，在每个引用点替换回原查询树，交给代价估算重新决策。这两条路的性能差距在实际生产里常常达到 **10x–1000x**，而控制这条开关的不是 SQL 标准、不是索引、也不是 JOIN 顺序，而是**引擎默认策略 + 极少数方言提供的显式 hint**。本文横向对比 45+ 引擎在 CTE 物化这件小事上的巨大分歧。

相关文章：[CTE 与递归查询：各 SQL 方言全对比](./cte-recursive-query.md)（覆盖 CTE 通用语法、递归、循环检测）。本文聚焦**物化策略**这一维度，不再重复 CTE 基础语法。

## 为什么 CTE 物化是最大的性能变量

```sql
-- 典型"双面 CTE"：一次定义、多次引用
WITH recent_orders AS (
    SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '7 days'
)
SELECT COUNT(*) FROM recent_orders WHERE status = 'paid'
UNION ALL
SELECT COUNT(*) FROM recent_orders WHERE status = 'refunded';
```

- **物化路径**：`recent_orders` 计算一次（一次全表扫 + 时间过滤），结果写入临时关系（内存或磁盘），两次 UNION 分支各扫一遍该临时关系。I/O = 1 次底表扫 + 2 次小表扫。
- **内联路径**：`recent_orders` 被当作宏替换进两个分支，变成两次独立的 `SELECT ... FROM orders WHERE created_at > ... AND status = ?`。两次都能命中 `(status, created_at)` 复合索引。I/O = 2 次索引范围扫，且完全无需写临时关系。

到底哪种更快？**取决于**：

1. `recent_orders` 的结果集大小（KB 级 vs GB 级）
2. 是否有相关索引可被下推
3. 引用次数（1 次、2 次、N 次）
4. 子查询里是否有 `LIMIT`、聚合、窗口函数等"语义壁垒"
5. CTE 里是否包含易变函数 (volatile functions)、DML 或副作用

SQL 标准**从未**规定 CTE 必须物化，但历史实现（尤其 PostgreSQL ≤ 11、Oracle 早期、Teradata）都**隐式地**把它当成了物化点——这导致一条性能经验之谈广为流传："把 CTE 改写成子查询就会快"。直到 PostgreSQL 12（2019）引入 `MATERIALIZED / NOT MATERIALIZED` 显式 hint、Oracle 引入 `MATERIALIZE / INLINE` hint 之后，这场争论才被正式交到 SQL 使用者手里。

## 支持矩阵（综合）

### 1. 默认策略：内联 vs 物化

| 引擎 | 默认策略 | 切换条件 | 版本节点 |
|------|---------|---------|---------|
| PostgreSQL | ≤ 11：始终物化；≥ 12：单引用且无副作用时内联，多引用或 RECURSIVE 物化 | 引用次数 + 易变性 | 12+ (2019) |
| MySQL | 始终内联（等同派生表） | -- | 8.0+ (2018) |
| MariaDB | 始终内联 | -- | 10.2+ (2017) |
| SQLite | 3.35 前始终物化；3.35+ 可选，默认单引用内联 | 引用次数 | 3.35+ (2021) |
| Oracle | 单引用内联、多引用物化（启发式） | 引用次数 + hint 覆盖 | 9i+ |
| SQL Server | 始终内联（CTE 为语法糖） | -- | 2005+ |
| DB2 (LUW) | 始终内联 | -- | 所有 |
| DB2 (z/OS) | 可物化（内部临时表） | 优化器决策 | 11+ |
| Snowflake | 始终内联 | -- | GA |
| BigQuery | 始终内联 | -- | GA |
| Redshift | 可选：单引用内联，多引用物化 | WITH [NOT] MATERIALIZED (2023) | 部分 |
| DuckDB | 默认内联 | `MATERIALIZED` 关键字 | 0.8+ |
| ClickHouse | 始终内联（CTE 为宏） | `WITH ... AS (SELECT ...)` 语义为文本替换 | 早期 |
| Trino | 始终内联 | -- | 所有 |
| Presto | 始终内联 | -- | 所有 |
| Spark SQL | 始终内联（Catalyst 优化器展开） | -- | 2.0+ |
| Hive | 始终内联 | -- | 0.13+ |
| Flink SQL | 始终内联 | -- | 1.12+ |
| Databricks | 始终内联 | -- | GA |
| Teradata | 可物化（spool 文件） | 复杂度阈值 | 14+ |
| Greenplum | 继承 PG：≤ 6.x 物化，7+ 同 PG12 | 引用 + 副作用 | 7+ |
| CockroachDB | 默认内联 | `MATERIALIZED` 关键字 | 20.2+ (2020) |
| TiDB | 始终内联 | -- | 5.0+ |
| OceanBase | 始终内联 | -- | GA |
| YugabyteDB | 继承 PG12 语义 | 引用 + 副作用 | 2.6+ |
| SingleStore | 始终内联 | -- | GA |
| Vertica | 物化（内部临时关系） | 优化器决策 | 9.0+ |
| Impala | 始终内联 | -- | 2.1+ |
| StarRocks | 始终内联 | -- | 2.5+ |
| Doris | 始终内联 | -- | 1.2+ |
| MonetDB | 始终内联 | -- | 所有 |
| CrateDB | 始终内联 | -- | 4.1+ |
| TimescaleDB | 继承 PG12 语义 | 引用 + 副作用 | 继承 PG |
| QuestDB | 始终内联 | -- | GA |
| Exasol | 物化（内部 temp） | 优化器决策 | 所有 |
| SAP HANA | 内联为主，复杂时物化 | 优化器 | 2.0+ |
| Informix | 始终内联 | -- | 11+ |
| Firebird | 始终内联 | -- | 2.1+ |
| H2 | 始终内联 | -- | 所有 |
| HSQLDB | 始终内联 | -- | 2.0+ |
| Derby | 始终内联 | -- | 所有 |
| Amazon Athena | 继承 Trino：内联 | -- | GA |
| Azure Synapse | 继承 SQL Server：内联 | -- | GA |
| Google Spanner | 始终内联 | -- | GA |
| Materialize | 增量物化视图语义；CTE 内联 | -- | GA |
| RisingWave | CTE 内联（流式场景） | -- | GA |
| InfluxDB (SQL) | 始终内联 | -- | GA |
| DatabendDB | 始终内联 | -- | GA |
| Yellowbrick | 继承 PG：单引用内联 | -- | GA |
| Firebolt | 始终内联 | -- | GA |

> 统计：45+ 引擎中，**大多数采用始终内联**，**仅 PostgreSQL 12+、Oracle、CockroachDB 20.2+、DuckDB、SQLite 3.35+、Redshift（部分区域）** 提供显式 `MATERIALIZED` 切换。Oracle 通过 hint 语法、其余通过关键字。

### 2. MATERIALIZED / NOT MATERIALIZED 显式 hint

| 引擎 | 语法 | 作用域 | 引入版本 |
|------|------|--------|---------|
| PostgreSQL | `WITH cte AS [NOT] MATERIALIZED (...)` | 单个 CTE | 12 (2019) |
| Oracle | `/*+ MATERIALIZE */` / `/*+ INLINE */`（在 CTE 子查询内） | 单个 CTE | 9i |
| CockroachDB | `WITH cte AS [NOT] MATERIALIZED (...)` | 单个 CTE | 20.2 (2020) |
| DuckDB | `WITH cte AS MATERIALIZED (...)` | 单个 CTE | 0.8 (2023) |
| SQLite | `WITH cte AS [NOT] MATERIALIZED (...)` | 单个 CTE | 3.35 (2021) |
| Redshift | `WITH cte AS [NOT] MATERIALIZED (...)` | 单个 CTE | 2023 起部分支持 |
| YugabyteDB | `WITH cte AS [NOT] MATERIALIZED (...)` | 单个 CTE | 继承 PG12 |
| Greenplum 7 | `WITH cte AS [NOT] MATERIALIZED (...)` | 单个 CTE | 7.0 |
| TimescaleDB | `WITH cte AS [NOT] MATERIALIZED (...)` | 单个 CTE | 继承 PG |
| 其他引擎 | -- | -- | 不支持 |

### 3. 优化器栅栏 (Optimization Fence) 行为

"栅栏"指：优化器**不会**将外层查询的谓词、投影、聚合下推进 CTE 内部。这既是物化的副作用，也是 PG ≤ 11 被诟病的核心原因。

| 引擎 | 默认是否栅栏 | 显式栅栏语法 | 备注 |
|------|------------|------------|------|
| PostgreSQL ≤ 11 | 是（总是栅栏） | -- | 历史行为，改写为子查询可绕开 |
| PostgreSQL ≥ 12 | 单引用否、多引用是 | `MATERIALIZED` | 可显式恢复栅栏 |
| Oracle | 取决于物化决策 | `/*+ MATERIALIZE */` | 物化即栅栏 |
| SQL Server | 否（内联无栅栏） | -- | 谓词全部下推 |
| MySQL | 否 | -- | derived_merge 会合并 CTE |
| MariaDB | 否（10.2.1+ derived_merge） | -- | 可用 `NO_MERGE` hint 强制栅栏 |
| Snowflake | 否 | -- | Catalyst 式全局展开 |
| BigQuery | 否 | -- | 全局重写 |
| ClickHouse | 否 | -- | CTE 为文本宏，完全展开 |
| Trino/Presto | 否 | -- | 规则引擎展开 |
| Spark SQL | 否 | -- | Catalyst 展开后再下推 |
| CockroachDB | 否（除非 MATERIALIZED） | `MATERIALIZED` | -- |
| DuckDB | 否（除非 MATERIALIZED） | `MATERIALIZED` | -- |
| SQLite ≥ 3.35 | 否（除非 MATERIALIZED） | `MATERIALIZED` | -- |

### 4. 多引用自动物化

当同一 CTE 被引用 ≥ 2 次时，引擎是否自动切换为物化？

| 引擎 | 多引用自动物化 | 决策算子 | 备注 |
|------|-------------|---------|------|
| PostgreSQL ≥ 12 | 是（引用次数 ≥ 2） | 规则：`cte_scan_cost * refcount > materialize_cost` | 可用 `NOT MATERIALIZED` 覆盖 |
| Oracle | 是（启发式） | 引用次数 + 子查询复杂度 | 默认 2 次以上物化 |
| CockroachDB | 否（默认总是内联） | -- | 需显式 `MATERIALIZED` |
| DuckDB | 否 | -- | 需显式 `MATERIALIZED` |
| SQLite ≥ 3.35 | 是（存在多引用） | 保守启发式 | 可被 `NOT MATERIALIZED` 覆盖 |
| Redshift | 是（部分版本） | 代价模型 | 2023+ 起支持显式 |
| SQL Server | 否 | -- | 永远内联 |
| MySQL 8.0 | 否 | -- | 永远内联（可能重复计算） |
| Snowflake | 否 | -- | 永远内联，依赖缓存 |
| BigQuery | 否 | -- | 永远内联 |
| Trino | 否 | -- | 永远内联 |
| Spark SQL | 否 | -- | 永远内联，Catalyst 会子查询消除 |
| Teradata | 是 | spool 决策 | 复杂度达阈值即物化 |
| DB2 z/OS | 是 | 代价模型 | -- |
| Vertica | 是 | 代价模型 | 默认物化 |
| Exasol | 是 | 代价模型 | -- |

### 5. 临时表 / 派生表等价替代

在无 `MATERIALIZED` hint 的引擎里，用户常用的"强制物化"替代方案：

| 引擎 | 推荐替代 | 代价 |
|------|---------|------|
| MySQL | `CREATE TEMPORARY TABLE tmp AS SELECT ...` | 多一次 DDL，事务语义改变 |
| SQL Server | `SELECT ... INTO #tmp FROM ...` | 同上；但支持自动统计信息 |
| Snowflake | `CREATE TEMPORARY TABLE tmp AS ...` 或结果缓存 | 结果缓存常常足够 |
| BigQuery | `CREATE TEMP TABLE` 或子查询结果缓存 | 需要手动 DDL |
| Trino | 无直接等价（不支持 TEMP TABLE） | 只能靠 CTE 内联的代价估算 |
| Spark SQL | `df.cache()` / `CACHE TABLE cte` | 需切换到 DataFrame API 或额外语句 |
| ClickHouse | `CREATE TEMPORARY TABLE` 或视图 | 或用 `MATERIALIZED VIEW` 做预计算 |
| DuckDB | 除 `MATERIALIZED` 关键字外，`CREATE TEMP TABLE` | -- |
| Redshift | `CREATE TEMP TABLE` | 兼容性最好 |
| Vertica | `CREATE LOCAL TEMPORARY TABLE` | -- |

## 1. PostgreSQL：从"物化派代表"到"内联派先驱"的转变

### PG 11 及以前：优化器栅栏

1999–2018 的近二十年里，PostgreSQL 是 CTE 物化派的旗帜。每个 WITH 子句都被当作一个独立优化单元：

```sql
-- PostgreSQL 11 及以前
EXPLAIN
WITH big AS (
    SELECT * FROM orders WHERE amount > 100
)
SELECT * FROM big WHERE customer_id = 42;

-- 计划（PG 11）：
-- CTE Scan on big  (cost=...)
--   Filter: (customer_id = 42)
--   CTE big
--     ->  Seq Scan on orders          ← 全表扫！
--         Filter: (amount > 100)
```

`customer_id = 42` **不会**被下推进 CTE，即使 `orders(customer_id)` 上有索引也用不上。这就是著名的"CTE 栅栏"效应。

### PG 12（2019）：条件内联

[PostgreSQL 12 release notes](https://www.postgresql.org/docs/12/release-12.html) 引入了有条件的 CTE 内联：

```sql
-- PostgreSQL 12+ 同样的查询
EXPLAIN
WITH big AS (
    SELECT * FROM orders WHERE amount > 100
)
SELECT * FROM big WHERE customer_id = 42;

-- 计划（PG 12+）：
-- Index Scan using orders_customer_id_idx on orders
--   Index Cond: (customer_id = 42)
--   Filter: (amount > 100)
-- （CTE 被完全内联，两个谓词合并）
```

PG 12 的内联决策规则（见 src/backend/optimizer/plan/subselect.c）：

```
当且仅当以下条件全部满足时内联:
  1. CTE 在外层查询中被引用恰好 1 次
  2. CTE 不是 RECURSIVE
  3. CTE 内不包含 volatile function（如 random()、nextval()、now() 视配置）
  4. CTE 不是 DML (INSERT/UPDATE/DELETE in WITH)
  5. 用户未显式指定 MATERIALIZED
```

### 显式 hint 语法

```sql
-- 强制物化（恢复 PG 11 语义）
WITH big AS MATERIALIZED (
    SELECT * FROM orders WHERE amount > 100
)
SELECT * FROM big WHERE customer_id = 42;
-- 即使单引用，也会走 CTE Scan

-- 强制内联（即使多引用）
WITH big AS NOT MATERIALIZED (
    SELECT * FROM orders WHERE amount > 100
)
SELECT * FROM big WHERE customer_id = 42
UNION ALL
SELECT * FROM big WHERE customer_id = 99;
-- 会把 CTE 宏展开两次，各自独立优化
```

### volatile function 的微妙性

```sql
-- 包含 random() → 不会内联（即使单引用），避免改变语义
WITH sampled AS (
    SELECT * FROM orders ORDER BY random() LIMIT 100
)
SELECT AVG(amount) FROM sampled;
-- 依然物化：random() 是 volatile，内联会导致"每行重算"语义变化
```

这是 PG 优化器非常克制的一面：**宁可保守物化，也不能悄悄改变语义**。

## 2. Oracle：MATERIALIZE hint 的鼻祖（9i, 2001）

Oracle 是最早提供显式 CTE 物化控制的主流数据库。语法走的是 hint 注释风格：

```sql
-- 强制物化：/*+ MATERIALIZE */ 放在 CTE 子查询内部
WITH recent_orders AS (
    SELECT /*+ MATERIALIZE */ *
    FROM orders
    WHERE created_at > SYSDATE - 7
)
SELECT COUNT(*) FROM recent_orders WHERE status = 'paid'
UNION ALL
SELECT COUNT(*) FROM recent_orders WHERE status = 'refunded';

-- 强制内联：/*+ INLINE */
WITH recent_orders AS (
    SELECT /*+ INLINE */ *
    FROM orders
    WHERE created_at > SYSDATE - 7
)
SELECT COUNT(*) FROM recent_orders WHERE customer_id = 42;
```

Oracle 的默认启发式：

- 引用 1 次 → 内联
- 引用 ≥ 2 次 → 物化（spool 到临时段）
- 可用 hint 覆盖

物化产生的临时关系叫做 **"subquery factoring result"** 或 **CTE temp segment**，写在 `TEMP` 表空间，生命周期等同当前语句。EXPLAIN PLAN 里可以看到 `LOAD AS SELECT (CURSOR DURATION MEMORY)` 或 `TEMP TABLE TRANSFORMATION` 操作。

## 3. SQL Server：永不物化的激进内联派

SQL Server 的 CTE 被实现为**纯语法糖**，等价于一个内联的派生表（derived table）。SQL Server 永远不会独立物化 CTE——优化器把 CTE 体直接替换进外层查询树，然后再做整体代价估算。

```sql
-- SQL Server：无论引用几次，都内联
WITH big AS (
    SELECT * FROM Orders WHERE Amount > 100
)
SELECT COUNT(*) FROM big WHERE CustomerId = 42
UNION ALL
SELECT COUNT(*) FROM big WHERE CustomerId = 99;

-- 实际执行：两次独立的索引扫描 + UNION ALL
-- 后果：若 CTE 体本身很重，会被重算两次
```

**副作用**：如果 `big` 里有 `ROW_NUMBER() OVER (...)` 之类昂贵计算，会重算 N 次。SQL Server 用户的"物化"习惯手段是 `SELECT ... INTO #tmp` 或临时表变量。

## 4. MySQL 8.0+：CTE 等价视图，总是内联

MySQL 8.0（2018）首次支持 CTE，实现为**内联派生表**。`WITH cte AS (...)` 在优化器内部被改写成 `FROM (... ) cte`，然后走 derived table merge。

```sql
-- MySQL 8.0+
WITH big AS (
    SELECT * FROM orders WHERE amount > 100
)
SELECT COUNT(*) FROM big WHERE customer_id = 42
UNION ALL
SELECT COUNT(*) FROM big WHERE customer_id = 99;

-- 执行计划（EXPLAIN）：
-- 没有独立的 CTE 节点，orders 被扫两次
```

如果想强制物化，只能：

```sql
-- 方案 1：创建临时表
CREATE TEMPORARY TABLE tmp_big AS
SELECT * FROM orders WHERE amount > 100;

SELECT COUNT(*) FROM tmp_big WHERE customer_id = 42;

-- 方案 2：利用优化器 hint（部分版本）
-- MySQL 不提供 MATERIALIZED 关键字，但可通过 derived_merge=off 禁用合并
SET optimizer_switch = 'derived_merge=off';
```

## 5. DB2：平台差异

- **DB2 LUW (Linux/Unix/Windows)**：默认内联，无 hint 语法，靠优化器代价决策。
- **DB2 for z/OS**：较老版本里 CTE 可物化为临时关系；11+ 起支持类 PG 代价决策。

DB2 无 `MATERIALIZED` 关键字，但可用 `WITH ... AS (... WITH UR)` 等方式控制隔离级别，不直接影响物化。

## 6. Snowflake：永远内联，依赖结果缓存

Snowflake CTE 永远被内联。如果想强制物化，有两条路：

```sql
-- 方案 1：临时表
CREATE TEMPORARY TABLE t_big AS
SELECT * FROM orders WHERE amount > 100;

-- 方案 2：依赖 Snowflake 的 warehouse 结果缓存（自动）
-- 24 小时内相同 SQL 会命中 result cache，无需重算
```

Snowflake 的设计哲学是"让用户少操心"：全局内联 + 激进结果缓存 + 分区裁剪，大部分场景下不需要手动物化。

## 7. BigQuery：同样激进内联

BigQuery CTE 严格内联（展开到逻辑查询树），多次引用会导致**多次扫描基表**。BigQuery 的解法是建议用户用 `CREATE TEMP TABLE`：

```sql
-- BigQuery 官方推荐做法
CREATE TEMP TABLE recent_orders AS
SELECT * FROM `project.dataset.orders`
WHERE created_at > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY);

SELECT COUNT(*) FROM recent_orders WHERE status = 'paid';
SELECT COUNT(*) FROM recent_orders WHERE status = 'refunded';
```

这样不仅避免重复扫描，还能节省按扫描量计费的费用——这是 BigQuery 特有的**成本驱动物化**动机。

## 8. ClickHouse：CTE 是纯文本宏（+ 21.8 起的 MATERIALIZE 变体）

ClickHouse 的 CTE 最初完全是**文本替换**——类似 C 的 `#define`：

```sql
-- ClickHouse 早期
WITH 'europe' AS region
SELECT count() FROM events WHERE region_col = region;
-- 就是字符串替换，不做求值
```

后来支持 subquery CTE 但**仍然是展开式**，多引用会导致重复计算。21.8+ 引入了 `WITH MATERIALIZE` 的实验性支持（通过 subquery + 临时表语义），以及基于 `SET` 的 CTE：

```sql
-- ClickHouse 方案 1：临时表
CREATE TEMPORARY TABLE tmp AS SELECT ...;

-- ClickHouse 方案 2：子查询 + 材料化视图
-- ClickHouse 方案 3：set 变量捕获标量结果
WITH (SELECT max(id) FROM events) AS max_id
SELECT count() FROM events WHERE id > max_id / 2;
-- 标量子查询只执行一次（这是 ClickHouse 的隐式物化）
```

## 9. CockroachDB：兼容 PG12 语法（20.2+）

```sql
-- CockroachDB 20.2+
WITH big AS MATERIALIZED (
    SELECT * FROM orders WHERE amount > 100
)
SELECT * FROM big WHERE customer_id = 42;

-- 与 PG12 不同：CockroachDB 默认总是内联（不论引用次数）
-- 只有显式 MATERIALIZED 才物化
```

CockroachDB 的设计选择是：默认全部内联，让分布式优化器自行决策；用户如需栅栏，必须显式 hint。

## 10. DuckDB：显式 MATERIALIZED（0.8+）

DuckDB 从 0.8 起支持 `MATERIALIZED` 关键字，配合其向量化+列存引擎，物化成本极低：

```sql
-- DuckDB
WITH big AS MATERIALIZED (
    SELECT * FROM 'orders.parquet' WHERE amount > 100
)
SELECT COUNT(*) FROM big WHERE status = 'paid'
UNION ALL
SELECT COUNT(*) FROM big WHERE status = 'refunded';

-- DuckDB 会把 CTE 结果缓存到内存临时关系
-- 多次扫描该关系，避免重读 Parquet 文件
```

这对从对象存储（S3/GCS）读取的场景尤其关键——物化一次 = 避免多次网络 I/O。

## 11. SQLite 3.35+：默认单引用内联

```sql
-- SQLite 3.35+
WITH big AS (                    -- 单引用 → 内联
    SELECT * FROM orders WHERE amount > 100
)
SELECT * FROM big WHERE customer_id = 42;

WITH big AS MATERIALIZED (       -- 强制物化
    SELECT * FROM orders WHERE amount > 100
)
SELECT * FROM big WHERE customer_id = 42;

WITH big AS NOT MATERIALIZED (   -- 强制内联（即使多引用）
    SELECT * FROM orders WHERE amount > 100
)
SELECT COUNT(*) FROM big WHERE customer_id = 42
UNION ALL
SELECT COUNT(*) FROM big WHERE customer_id = 99;
```

SQLite 的文档明确说：3.35 前所有 CTE 都被物化（相当于 PG11 行为），3.35 后改为启发式。

## 12. Teradata：复杂 CTE 默认 spool 物化

Teradata 的 PE/AMP 架构天然依赖 **spool 文件**（中间结果暂存区）。CTE 在执行计划里常常被直接物化为 spool：

```sql
-- Teradata
WITH dept_stats AS (
    SELECT dept_id, AVG(salary) AS avg_sal
    FROM employees
    GROUP BY dept_id
)
SELECT e.name, e.salary, d.avg_sal
FROM employees e
JOIN dept_stats d ON e.dept_id = d.dept_id;

-- Teradata Explain 输出大致：
-- 1) Lock on employees
-- 2) Execute GROUP BY step, store in Spool 2 (N rows)
-- 3) Join employees x Spool 2 → Spool 1
-- 4) Return Spool 1
```

Spool 2 即为物化后的 `dept_stats`。对复杂 CTE，Teradata 几乎总是物化；对简单投影/过滤，优化器会内联。Teradata 没有暴露 `MATERIALIZED` 关键字，只能靠优化器启发式。

## 13. 其他引擎一览

```sql
-- MariaDB：默认内联；10.2.1+ derived_merge hint
WITH cte AS (SELECT /*+ NO_MERGE */ * FROM orders WHERE amount > 100)
SELECT * FROM cte;                     -- 强制栅栏行为

-- Greenplum 7：继承 PG12 语义
WITH big AS MATERIALIZED (SELECT * FROM orders WHERE amount > 100)
SELECT * FROM big WHERE customer_id = 42;

-- YugabyteDB：完整 PG12 兼容
WITH big AS NOT MATERIALIZED (SELECT * FROM orders WHERE amount > 100)
SELECT COUNT(*) FROM big WHERE customer_id = 42;

-- Vertica：默认物化到 ROS 容器的 temp 版本
WITH t AS (SELECT * FROM big_fact WHERE year = 2024)
SELECT COUNT(*) FROM t;                -- Vertica 常常自动物化

-- Exasol：默认物化（内部 temp view）
WITH t AS (...) SELECT ... ;

-- SAP HANA：混合策略，复杂 CTE 自动物化
WITH t AS (...) SELECT ... ;

-- Databricks / Spark：始终内联，手动用 CACHE TABLE
CACHE TABLE big AS SELECT * FROM orders WHERE amount > 100;
SELECT COUNT(*) FROM big WHERE customer_id = 42;

-- StarRocks / Doris：始终内联
WITH t AS (...) SELECT ... ;            -- 无物化 hint，必要时手动临时表

-- Redshift：WITH [NOT] MATERIALIZED（新区域支持）
WITH big AS MATERIALIZED (SELECT * FROM orders WHERE amount > 100)
SELECT * FROM big WHERE customer_id = 42;

-- Materialize (流式引擎)：区分 CTE 与 materialized view
-- CTE 本身内联；物化必须通过 CREATE MATERIALIZED VIEW
CREATE MATERIALIZED VIEW recent AS SELECT * FROM orders WHERE created_at > ...;

-- RisingWave（流式）：同 Materialize，CTE 内联，物化视图分开建
CREATE MATERIALIZED VIEW recent_orders AS SELECT ... ;

-- DatabendDB：内联，用 `CREATE TEMPORARY TABLE` 替代
-- Firebolt：内联，无 hint
-- Yellowbrick：继承 PG，支持 MATERIALIZED
-- QuestDB / InfluxDB：时序引擎，CTE 内联，物化需走 materialized view
```

## PostgreSQL 12 CTE 内联决策深度剖析

PG 12 的内联规则看起来简单，但隐藏着不少陷阱。本节深入源码级理解。

### 决策流程

```
pull_up_subqueries(root)                 ← subquery pullup 阶段
  └─ for each RTE_CTE in rangetable:
       is_inlinable = refcount == 1
                    AND !cte->cterecursive
                    AND cte->ctematerialized != CTEMaterializeAlways
                    AND !contain_volatile_functions(cte->ctequery)
                    AND !has_side_effects(cte->ctequery)
       if is_inlinable:
         inline_cte(root, cte)           ← 把 CTE 体直接插入外层
       else:
         build CTE plan separately
```

对应的语法数据结构 `CommonTableExpr`:

```c
typedef enum CTEMaterialize {
    CTEMaterializeDefault,   /* 无显式 hint，启发式决策 */
    CTEMaterializeAlways,    /* WITH cte AS MATERIALIZED (...) */
    CTEMaterializeNever      /* WITH cte AS NOT MATERIALIZED (...) */
} CTEMaterialize;
```

### volatile 的细分

PG 的 `proVolatile` 分三级：IMMUTABLE / STABLE / VOLATILE。只有 VOLATILE 函数会阻止内联：

```sql
-- IMMUTABLE 示例：内联（abs() 不论何时都返回相同值）
WITH t AS (SELECT abs(amount) AS a FROM orders)
SELECT a FROM t;                        -- 内联

-- STABLE 示例：内联（now() 在单个事务内稳定）
WITH t AS (SELECT now() - created_at AS age FROM orders)
SELECT age FROM t;                      -- 内联（STABLE 允许内联）

-- VOLATILE 示例：不内联
WITH t AS (SELECT random() AS r FROM orders)
SELECT r FROM t;                        -- 物化（random 是 VOLATILE）

-- timeofday() 是 VOLATILE，区别于 STABLE 的 now()
WITH t AS (SELECT timeofday() FROM orders)
SELECT * FROM t;                        -- 物化
```

### DML in WITH 的特殊处理

```sql
WITH deleted AS (
    DELETE FROM old_orders WHERE created_at < '2020-01-01'
    RETURNING *
)
SELECT COUNT(*) FROM deleted;
-- 永远物化：DML 有副作用，且必须只执行一次
```

### 多引用 hint 的覆盖

```sql
-- 即使引用 3 次，NOT MATERIALIZED 也会强制内联
WITH big AS NOT MATERIALIZED (
    SELECT * FROM orders WHERE amount > 100
)
SELECT COUNT(*) FROM big WHERE customer_id = 1
UNION ALL
SELECT COUNT(*) FROM big WHERE customer_id = 2
UNION ALL
SELECT COUNT(*) FROM big WHERE customer_id = 3;
-- 三次独立的 orders 扫描（但每次都能命中 customer_id 索引）
```

## 性能案例对比：何时物化取胜、何时败北

### 案例 1：物化取胜（多次引用，CTE 输出很小）

```sql
-- 场景：从 10 亿行事实表按月聚合，多次引用
WITH monthly AS MATERIALIZED (
    SELECT DATE_TRUNC('month', created_at) AS m,
           SUM(amount) AS total
    FROM fact_orders                   -- 10 亿行
    WHERE created_at >= '2020-01-01'
    GROUP BY 1
)                                       -- 输出 ~60 行
SELECT m, total,
       total - LAG(total) OVER (ORDER BY m) AS mom_delta,
       total - LAG(total, 12) OVER (ORDER BY m) AS yoy_delta,
       AVG(total) OVER (ORDER BY m ROWS 2 PRECEDING) AS rolling_3m
FROM monthly;
-- 一次底表扫 + 一次聚合 = ~30s
-- 60 行结果上跑 3 个窗口函数 = ~1ms
-- 若 NOT MATERIALIZED: 3 次底表扫聚合 ≈ 90s
```

**结论**：底表扫描昂贵 + CTE 输出集合小 + 多次引用 → **物化大胜**。

### 案例 2：内联取胜（单引用，且有下推空间）

```sql
-- 场景：过滤条件在外层，基表有对应索引
WITH filtered AS NOT MATERIALIZED (
    SELECT * FROM events
)
SELECT * FROM filtered
WHERE user_id = 'U1234' AND event_time > NOW() - INTERVAL '1 hour';

-- 内联后：
-- Index Scan on events USING (user_id, event_time)
-- → 微秒级返回

-- 若 MATERIALIZED：先扫全表写 10 亿行到 temp，再过滤
-- → 小时级（可能 OOM）
```

**结论**：单引用 + 外层谓词能用索引 → **内联完胜**。PG 12+ 默认就是这个行为。

### 案例 3：物化的隐性陷阱——volatile 幻觉

```sql
-- 开发者原意：只生成一次随机样本，反复用
WITH sample AS (
    SELECT *, random() AS rnd FROM events
)
SELECT * FROM sample WHERE rnd < 0.01 AND region = 'US'
UNION ALL
SELECT * FROM sample WHERE rnd < 0.01 AND region = 'EU';

-- 如果内联：random() 被调用两次，两个分支拿到不同的"样本"
-- PG 12+ 检测到 VOLATILE 会自动物化，语义得以保持
-- MySQL/ClickHouse 始终内联 → 两个分支的 rnd 不一致！
```

**结论**：跨引擎迁移时，**volatile 函数在 CTE 内**是最大的语义陷阱。PG 最安全，ClickHouse/MySQL 最易踩坑。

### 案例 4：大 CTE 内联爆炸（Spark/Presto 常见）

```sql
-- 反面教材：在 Spark 中复用大 CTE
WITH heavy AS (
    SELECT a.*, b.*, c.*
    FROM big_a a
    JOIN big_b b ON a.id = b.a_id    -- shuffle join
    JOIN big_c c ON a.id = c.a_id    -- 再一次 shuffle
)
SELECT SUM(col_x) FROM heavy
UNION ALL
SELECT SUM(col_y) FROM heavy
UNION ALL
SELECT SUM(col_z) FROM heavy;

-- Spark Catalyst 展开：3 次独立 join → 3 倍 shuffle 成本
-- 正确做法：
CACHE TABLE heavy AS SELECT ...;  -- 或者 df.cache()
SELECT SUM(col_x) FROM heavy ...;
```

**结论**：分布式引擎无 `MATERIALIZED` hint 时，必须手动用 `CACHE TABLE` / `CREATE TEMP TABLE` 兜底。

### 案例 5：Oracle 引用次数启发式失效

```sql
-- 当 CTE 被作为标量用，Oracle 仍可能物化
WITH ref_cnt AS (
    SELECT COUNT(*) AS c FROM orders
)
SELECT o.*, (SELECT c FROM ref_cnt) AS total_rows
FROM orders o;
-- Oracle 可能把 ref_cnt spool，然后每行查表
-- 对于小标量 CTE，应该 /*+ INLINE */ 避免 spool 开销
```

### 性能度量方法

```sql
-- PostgreSQL：EXPLAIN (ANALYZE, BUFFERS) 对比
EXPLAIN (ANALYZE, BUFFERS)
WITH t AS MATERIALIZED (...) SELECT ...;
-- 关注: CTE Scan rows、Materialize node、shared read/hit

EXPLAIN (ANALYZE, BUFFERS)
WITH t AS NOT MATERIALIZED (...) SELECT ...;
-- 关注: 是否消失了 CTE 节点、是否下推了谓词

-- Oracle：
EXPLAIN PLAN FOR WITH t AS (SELECT /*+ MATERIALIZE */ ...) SELECT ...;
SELECT * FROM TABLE(dbms_xplan.display);
-- 关注: TEMP TABLE TRANSFORMATION、LOAD AS SELECT 步骤

-- SQL Server：SET STATISTICS IO ON; SET SHOWPLAN_XML ON;
-- 关注：逻辑读次数、是否有 Spool 节点
```

## 对引擎开发者的实现建议

### 1. 决策点：把开关交给用户还是优化器？

```
方案 A（SQL Server 派）：完全内联，不做物化
  优点：行为一致、可预测；代价模型简单
  缺点：重度计算 CTE 会被重算 N 次

方案 B（PG 12 派）：启发式 + 显式 hint
  优点：常规场景自动正确，用户可干预
  缺点：启发式规则复杂，需要处理 volatile/side-effect

方案 C（MPP 派）：纯内联 + 结果缓存
  优点：依赖底层缓存机制，避免物化开销
  缺点：缓存命中率差时性能退化
```

### 2. 启发式规则（PG 12 式实现）

```rust
struct CTEMaterializationDecision {
    fn decide(cte: &CommonTableExpression, refcount: usize) -> bool {
        // 1. 用户显式 hint 优先
        if cte.hint == MaterializeHint::Always { return true; }
        if cte.hint == MaterializeHint::Never  { return false; }

        // 2. 强制物化场景
        if cte.is_recursive { return true; }
        if cte.is_dml { return true; }
        if contain_volatile_functions(&cte.query) { return true; }

        // 3. 引用次数阈值
        if refcount >= 2 { return true; }

        // 4. 默认：单引用内联
        false
    }
}
```

### 3. 物化实现：存储选择

```
内存临时关系：
  优点：零 I/O、极快访问
  缺点：OOM 风险；需要 spill-to-disk 兜底

磁盘临时表：
  优点：支持大结果、事务安全
  缺点：I/O 开销

混合（PG work_mem 式）：
  小于阈值走内存，超出 spill 到磁盘
  需维护两套访问接口
```

### 4. 栅栏行为的处理

物化 = 天然栅栏。内联时如何避免外层谓词下推破坏 volatile 语义：

```
当 CTE 被内联时，必须在内联点保留一个"语义墙"：
  1. volatile function 不能被复制（否则多次求值语义变）
  2. LIMIT / ORDER BY 不能被改变（否则结果集变化）
  3. DISTINCT / UNION 不能被消除

实现：在 planner 里给被内联的 CTE 结果加上 "force_materialize_if_volatile" 标记
```

### 5. 代价估算的陷阱

```
陷阱 1：物化代价 = CTE 执行代价 + 写临时关系代价
  很多引擎忘了算写临时关系的 CPU/I/O

陷阱 2：多引用的内联代价不是 N * single_cost
  因为每次内联后能独立下推不同谓词，实际可能远小于 N * single

陷阱 3：物化后的 CTE scan 代价被低估
  无索引、无统计信息的 temp 关系扫描，cardinality 常常低估
```

### 6. EXPLAIN 输出建议

```
物化路径: 显示独立的 "CTE <name>" 节点 + 后续 "CTE Scan on <name>"
内联路径: CTE 节点消失，改为标注 "(Inlined from CTE <name>)"
        让用户能判断当前走的哪条路径
```

### 7. 测试要点

```
1. 单引用内联 / 多引用物化边界测试
2. volatile/stable/immutable 三类函数的内联决策
3. DML in WITH 必须物化
4. 递归 CTE 必须物化
5. 显式 MATERIALIZED / NOT MATERIALIZED 覆盖启发式
6. volatile 内联时的语义保留（LIMIT + RANDOM 等场景）
7. 多次 EXPLAIN 验证代价估算稳定
```

## 关键发现

1. **SQL 标准从未要求 CTE 必须物化**——这纯粹是早期实现（PG、Oracle、Teradata）的历史惯例。SQL Server、MySQL、Snowflake、BigQuery 从一开始就是"始终内联"派。

2. **PostgreSQL 12（2019）的转身是 CTE 物化语义史上的分水岭**。此前近二十年，"CTE = 栅栏"是 PG 生态的金科玉律，大量查询改写教程都基于此。PG 12 之后，这条经验反而成了陷阱——继续用 `MATERIALIZED` 可能让 PG 11 性能优秀的查询在 12+ 变慢（因为被下推优化过头）。

3. **显式 `MATERIALIZED / NOT MATERIALIZED` 关键字是 PostgreSQL 阵营的专利**：PG、CockroachDB、DuckDB、SQLite、Redshift、YugabyteDB、Greenplum 7、TimescaleDB 共享这套语法。Oracle 走自家 hint 注释风格。其他主流引擎（MySQL、SQL Server、Snowflake、BigQuery、Trino、Spark）**没有任何显式物化控制**。

4. **MPP / 分布式引擎普遍选择"始终内联 + 结果缓存 / 手动 TEMP TABLE"**：Snowflake、BigQuery、Redshift（旧）、Trino、Spark、ClickHouse、StarRocks、Doris。设计动机是分布式优化器希望看到完整查询树做全局优化，而不是被栅栏分段。

5. **Volatile function 是跨引擎迁移最大的隐性语义陷阱**。PG 会自动物化含 volatile 的 CTE 以保持"一次求值"语义；MySQL、ClickHouse、Trino 等始终内联引擎会把 `random()`、`nextval()` 在每次引用点独立求值，导致多引用时结果不一致。迁移 PG → MySQL 的 CTE 代码需要特别审计。

6. **"把 CTE 改写成子查询会变快"这条老经验今天基本失效**，除非你明确用的是 PostgreSQL 11 或更早、Oracle 默认物化场景、Teradata 复杂 CTE。在 MySQL 8+/SQL Server/Snowflake/BigQuery/Trino 上，CTE 和派生表在优化器眼里是完全等价的。

7. **引用次数是物化决策的核心启发式**。单引用几乎总是内联（内联后谓词下推才能充分发挥）；多引用的"值不值得物化"取决于 CTE 体代价 vs 重算代价。PG 12 的规则是保守的"多引用就物化"；Oracle 类似；CockroachDB/DuckDB 反其道而行——**总是内联**，除非用户显式要求。

8. **分布式引擎的"手动物化"套路**：Spark `CACHE TABLE`、BigQuery `CREATE TEMP TABLE`、Snowflake 临时表 / 依赖 result cache、Redshift `CREATE TEMP TABLE`、Trino 无直接等价。这些是显式物化 hint 的功能等价物，但语法割裂，跨引擎脚本复用困难。

9. **流式 / 实时引擎区分了两种物化**：Materialize、RisingWave、Flink SQL 里，CTE 依然是内联语义，真正的物化概念被提升到 `CREATE MATERIALIZED VIEW` 层面——这是与批处理世界最大的语义分歧。

10. **Teradata、Vertica、Exasol、SAP HANA 等传统 MPP** 仍偏向默认物化（spool / temp relation），但**不暴露用户级 hint**——用户只能通过复杂度/引用次数间接影响优化器决策。这在迁移到 PG/Snowflake 时常常带来性能惊喜（或灾难）。

11. **SQLite 3.35（2021）是最后一个主流转向的引擎**，把早期"总是物化"改成了"默认单引用内联 + 可选 hint"，和 PG 12 保持高度一致。这反映了"内联派"在 2019–2023 间成为新共识。

12. **对引擎开发者而言，支持 `MATERIALIZED` 关键字的技术成本不高，但决策模型的正确实现（尤其 volatile 检测、recursive 强制物化、DML in WITH 的处理）才是真正的工程难点**。推荐直接借鉴 PG 12 的 subselect.c 决策流程。

## 参考资料

- PostgreSQL 12 Release Notes: <https://www.postgresql.org/docs/12/release-12.html>
- PostgreSQL CTE Materialization: <https://www.postgresql.org/docs/current/queries-with.html#id-1.5.6.12.7>
- Oracle MATERIALIZE / INLINE hints: <https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Comments.html>
- SQLite 3.35 Release Notes: <https://www.sqlite.org/releaselog/3_35_0.html>
- CockroachDB CTE: <https://www.cockroachlabs.com/docs/stable/common-table-expressions>
- DuckDB MATERIALIZED CTE: <https://duckdb.org/docs/sql/query_syntax/with>
- SQL Server CTE: <https://learn.microsoft.com/en-us/sql/t-sql/queries/with-common-table-expression-transact-sql>
- MySQL CTE: <https://dev.mysql.com/doc/refman/8.0/en/with.html>
- Snowflake CTE: <https://docs.snowflake.com/en/sql-reference/constructs/with>
- BigQuery CTE: <https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#with_clause>
- Redshift WITH Clause: <https://docs.aws.amazon.com/redshift/latest/dg/r_WITH_clause.html>
- ClickHouse WITH: <https://clickhouse.com/docs/en/sql-reference/statements/select/with>
- Spark SQL WITH / CACHE TABLE: <https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-cte.html>
- Teradata Spool 与 CTE: <https://docs.teradata.com/r/Teradata-Database-SQL-Functions-Operators-Expressions-and-Predicates>
- Vertica WITH Clause: <https://docs.vertica.com/latest/en/sql-reference/statements/select/with-clause/>
- SAP HANA CTE: <https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/>
- Informix WITH Clause: <https://www.ibm.com/docs/en/informix-servers/14.10>
- 相关文章：[CTE 与递归查询：各 SQL 方言全对比](./cte-recursive-query.md)
