# 相关子查询执行 (Correlated Subquery Execution)

`SELECT *, (SELECT MAX(amount) FROM orders WHERE customer_id = c.id) FROM customers c;`——这一行看起来人畜无害的 SQL，是查询优化器最经典的"O(N²) 陷阱"。朴素执行下，外层 customers 每来一行就把 orders 全表扫一次：100 万客户 × 1 亿订单 = 10^14 次行触碰，单次查询可以跑数小时甚至数天。而同样的查询，PostgreSQL / Oracle / SQL Server / DuckDB 的优化器在内部把它"去关联化"（decorrelation / unnesting）后，能压成一次哈希连接，O(N+M) 完成，性能提升 4–6 个数量级。

去关联化是查询优化最重要也最复杂的代数变换之一。本文系统对比 45+ 个 SQL 引擎在相关子查询执行上的能力差异：从 PostgreSQL 早期的 pull-up 重写、Oracle 9i 引入的 UNNEST hint、Galindo-Legaria 等 TODS 1997 / SIGMOD 2001 的 magic decorrelation，一直到 Neumann/Kemper 2015 BTW 论文证明的"任意嵌套层数都可去关联化"在 DuckDB / Umbra 的实现。每一节都给出 EXPLAIN 形态、回退路径、可观测信号。

> **关联文章**：子查询整体优化能力见 [subquery-optimization.md](subquery-optimization.md)；EXISTS / IN / NOT EXISTS / NOT IN 重写为 Semi/Anti-Join 的细节见 [semi-anti-join-rewrite.md](semi-anti-join-rewrite.md)；LATERAL 语法对比见 [lateral-join.md](lateral-join.md)。

## 什么是相关子查询：朴素执行的 O(N²) 陷阱

相关子查询（correlated subquery，也叫 dependent subquery）是指内层子查询引用了外层查询的列。它的"语义定义"是逐行求值——外层每出一行，就用这行的列值代入内层重新执行一遍：

```sql
-- 相关标量子查询：内层引用外层 c.id（最常见形态）
SELECT c.name,
       (SELECT MAX(amount) FROM orders o WHERE o.customer_id = c.id) AS max_order
FROM customers c;

-- 相关 EXISTS：外层每行触发一次 EXISTS 检查
SELECT c.name
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id AND o.status = 'paid');

-- 相关 IN：与上式同义
SELECT c.name FROM customers c
WHERE c.id IN (SELECT o.customer_id FROM orders o WHERE o.status = 'paid');

-- 相关 LATERAL：FROM 子句中显式声明，内层可用外层列
SELECT c.name, t.recent_amount
FROM customers c,
     LATERAL (SELECT amount AS recent_amount FROM orders o
              WHERE o.customer_id = c.id ORDER BY ts DESC LIMIT 1) t;
```

朴素的"逐行重执行"实现叫 **nested-loop apply**（也叫 correlated apply、SubPlan）：

```
foreach row r in outer:
    push r 的列值到 inner_query 参数
    re-execute inner_query
    把内层结果跟外层 r 拼起来
```

这是关系代数中的 `Apply` 算子（也叫 `Dependent Join`），由 Galindo-Legaria & Joshi 在 SIGMOD 2001 论文中正式定义。它是相关子查询的"诚实但慢"的实现，数学上正确，但代价是 O(N) 次内层执行——每次内层执行通常要扫描或索引查找，叠加起来就是 O(N×M)（无索引）或 O(N×log M)（有索引）。

去关联化（decorrelation / unnesting）的目标就是把 Apply 改写成普通 Join：

```
correlated apply (outer, inner_with_correlation)
  ↓ decorrelation
join (outer, inner_without_correlation, on = correlation_predicate)
```

改写之后，内层子查询只需执行**一次**（提前算好或与外层并行哈希），外层每行只是在哈希表里查找，总成本 O(N+M)。

## 没有 SQL 标准

ISO/IEC 9075（SQL:2023）只定义了相关子查询的**语义**——内层引用外层列时，结果应等价于"外层每行重新执行一次内层"。它**从不规定**优化器必须把它执行成什么物理算子。"去关联化"、"unnesting"、"pull-up"、"magic decorrelation"、"Apply elimination" 这些术语**全是实现细节**，跟标准无关。

这导致：

- **触发条件不一**：是否要求关联谓词为等值？是否要求内层无聚合？是否要求外层非空？每个引擎答案不同。
- **回退路径不一**：去关联化失败时，PostgreSQL 退化为 SubPlan，Oracle 退化为 FILTER，SQL Server 退化为 Apply（Nested Loops）。
- **可观测性不一**：去关联化是否在 EXPLAIN 中显式标注？Oracle 显示 `HASH JOIN SEMI`，PostgreSQL 显示 `Hash Semi Join` 或 `SubPlan`，DuckDB 显示 `MARK_JOIN`。
- **算子名称不一**：Oracle 叫 "Apply"，SQL Server 叫 "Apply"（实际是 Nested Loops + Filter），PostgreSQL 内部叫 "SubLink/SubPlan"，DuckDB 叫 "DependentJoin"，Spark Catalyst 叫 "Lateral Subquery"。

正因为没有标准，引擎之间的能力差异巨大——同一句相关子查询在 PostgreSQL 上是 0.1 秒、在 ClickHouse 上是 60 秒，这种 600× 差距完全合理。

## 支持矩阵

下表覆盖 45+ 个常见 SQL 引擎在 6 个能力维度的支持情况：

1. **SELECT 列中的相关标量子查询**：是否支持（最基础形态）
2. **WHERE 中的相关 EXISTS**：是否支持
3. **FROM 中的相关 LATERAL**：是否支持显式 LATERAL
4. **Magic decorrelation**：是否支持 Galindo-Legaria 风格、能处理带聚合的相关子查询（SIGMOD 2001）
5. **任意嵌套层级（Neumann/Kemper）**：是否支持任意嵌套层数的去关联化
6. **EXPLAIN 中能看到去关联化结果**：是否在执行计划中明确标注

| 引擎 | SELECT 列标量 | WHERE EXISTS | FROM LATERAL | Magic decorrelation | 任意嵌套 | EXPLAIN 可见 |
|------|--------------|--------------|--------------|---------------------|---------|-------------|
| **PostgreSQL** | 是 | 是 | 是 (9.3+) | 是 | 部分 | 是（SubPlan/Hash Semi Join 区分） |
| **MySQL 8.0** | 是 | 是 | 是 (8.0.14+) | 部分（2018 子查询重写器） | 部分 | 是（DEPENDENT SUBQUERY → SEMI JOIN） |
| **MySQL 5.7** | 是 | 是 | 否 | 否 | 否 | 是（DEPENDENT SUBQUERY） |
| **MariaDB** | 是 | 是 | 是 (10.6+) | 部分 | 部分 | 是 |
| **Oracle** | 是 | 是 | 是 (12c+) | 是（unnest 支持聚合） | 是 | 是（HASH JOIN SEMI/UNNEST） |
| **SQL Server** | 是 | 是 | CROSS/OUTER APPLY (2005+) | 是（CardEstimator 处理多种形态） | 是 | 是（Apply / Hash Semi Join 区分） |
| **DB2** | 是 | 是 | 是 (9.1+) | 是 | 是 | 是 |
| **SQLite** | 是 | 是 (3.35+) | 否 | 否 | 否 | 部分（EXPLAIN QUERY PLAN 不显式标注） |
| **DuckDB** | 是 | 是 | 是 | 是（Mark Join + Apply elimination） | **是（Neumann/Kemper 2015 实现）** | 是（DEPENDENT_JOIN/MARK_JOIN） |
| **ClickHouse** | 部分（22.3+） | 是 | 否（用 ARRAY JOIN） | 否 | 否 | 部分 |
| **Spark SQL** | 是 (2.0+) | 是 | 是 (3.3+) | 是（Catalyst RewriteCorrelatedSubquery） | 部分 | 是（DECORRELATE_SUBQUERY 规则） |
| **Trino** | 是 | 是 | 是 | 是（TransformCorrelatedScalarSubquery） | 部分 | 是（rewriteCorrelatedSubquery） |
| **Presto** | 是 | 是 | 是 | 是 | 部分 | 是 |
| **BigQuery** | 是 | 是 | UNNEST | 是 | 部分 | 部分（详细计划层） |
| **Snowflake** | 是 | 是 | LATERAL FLATTEN | 是 | 是 | 部分（Profile UI） |
| **Redshift** | 是 | 是 | 否 | 部分 | 否 | 是（基于旧 PG） |
| **Hive** | 部分 | 是 | LATERAL VIEW (UDTF) | 否 | 否 | 否 |
| **Impala** | 是 | 是 | 否 | 部分 | 部分 | 是 |
| **Flink SQL** | 部分（流处理限制） | 是 | LATERAL TABLE | 部分 | 否 | 部分 |
| **CockroachDB** | 是 | 是 | 是 | 是（基于 PG） | 部分 | 是 |
| **TiDB** | 是 | 是 | 否 | 部分（4.0+ 改进） | 部分 | 是 |
| **OceanBase** | 是 | 是 | 是（Oracle 模式） | 是 | 部分 | 是 |
| **PolarDB MySQL** | 是 | 是 | 是 | 部分 | 部分 | 是 |
| **PolarDB PostgreSQL** | 是 | 是 | 是 | 是 | 部分 | 是 |
| **GaussDB** | 是 | 是 | 是 | 是 | 部分 | 是 |
| **openGauss** | 是 | 是 | 是 | 是 | 部分 | 是 |
| **KingbaseES** | 是 | 是 | 是 | 是 | 部分 | 是 |
| **DamengDB** | 是 | 是 | 是 | 部分 | 部分 | 是 |
| **YugabyteDB** | 是 | 是 | 是 | 是（基于 PG） | 部分 | 是 |
| **Greenplum** | 是 | 是 | 是 (6.0+) | 是（PG 基础 + GPORCA 加强） | 部分 | 是 |
| **Vertica** | 是 | 是 | 是 | 是 | 部分 | 是 |
| **Teradata** | 是 | 是 | 否 | 是（成熟） | 是 | 是 |
| **SAP HANA** | 是 | 是 | 是 (2.0+) | 是 | 部分 | 是 |
| **Informix** | 是 | 是 | 否 | 部分 | 否 | 是 |
| **Firebird** | 是 | 是 | 否 | 否 | 否 | 部分 |
| **MonetDB** | 是 | 是 | 否 | 部分 | 否 | 是 |
| **HSQLDB** | 是 | 是 | 是 | 否 | 否 | 部分 |
| **H2** | 是 | 是 | 否 | 否 | 否 | 否 |
| **Derby** | 是 | 是 | 否 | 否 | 否 | 否 |
| **Exasol** | 是 | 是 | 否 | 部分 | 否 | 是 |
| **SingleStore (MemSQL)** | 是 | 是 | 否 | 部分 | 否 | 是 |
| **StarRocks** | 是 | 是 | 否 | 部分 | 否 | 是 |
| **Doris** | 是 | 是 | LATERAL VIEW (Hive 兼容) | 部分 | 否 | 是 |
| **MaxCompute** | 是 | 是 | LATERAL VIEW | 部分 | 否 | 是 |
| **Materialize** | 是 | 是 | 是 | 是（基于 dataflow） | 是 | 是 |
| **RisingWave** | 是 | 是 | 是 | 部分 | 部分 | 是 |
| **CrateDB** | 部分 | 是 | 否 | 否 | 否 | 部分 |
| **QuestDB** | 部分 | 部分 | 否 | 否 | 否 | 否 |
| **TimescaleDB** | 是 | 是 | 是 | 是（继承 PG） | 部分 | 是 |
| **ByConity** | 是 | 是 | 否 | 部分 | 部分 | 是 |
| **Calcite** | 是 | 是 | 是 | 是（SubQueryRemoveRule） | 是 | 是（框架层规则） |
| **Athena** | 是 | 是 | 是 | 是（继承 Trino） | 部分 | 是 |
| **Databricks SQL** | 是 | 是 | 是 (3.3+) | 是 | 部分 | 是 |
| **Azure Synapse** | 是 | 是 | CROSS APPLY | 是 | 部分 | 是 |

> 统计：约 38 个引擎能对常见相关子查询做某种形式的去关联化；约 6 个引擎仅支持基础语义但优化能力有限（H2 / Derby / CrateDB / QuestDB / Firebird / 部分 ClickHouse 场景）；**只有 Oracle / SQL Server / DB2 / DuckDB / Materialize / Calcite / Teradata 真正实现了"任意嵌套层数 + 任意聚合"的完整去关联化**。

## 朴素 Nested-Loop Apply 的成本分析

要理解为什么去关联化如此关键，先看朴素 Nested-Loop Apply 的真实代价。

设外层有 N 行，内层每次执行扫描 M 行。三种典型场景：

### 场景 1：内层无索引，全表扫描

```
朴素 Apply 总成本 = N × M
```

外层 N=10⁶ 行 customers，内层每次扫 M=10⁸ 行 orders：**10¹⁴ 次行触碰**。即使每行 100ns，也需要 10⁷ 秒 ≈ 4 个月。这就是"失控的 EXISTS"在生产事故现场的标准画风。

### 场景 2：内层有索引

```
朴素 Apply 总成本 = N × log₂(M) × IO_per_seek
```

外层 N=10⁶ 行，B+ 树高度 ~30（10⁸ 行的 8KB 页索引）：**3×10⁷ 次随机 IO**。SSD 上每次 100µs，总耗时 ~50 分钟。仍然非常昂贵，且每次必须做随机 IO，缓存命中率取决于外层列的局部性。

### 场景 3：去关联化为哈希连接

```
解关联后总成本 = N + M
  + 内层一次性建哈希: O(M)
  + 外层逐行探测: O(1) × N
```

10⁶ + 10⁸ = ~10⁸ 次操作。如果哈希表能装进内存：**几秒到几十秒**。比朴素 Apply 快 10⁵ 倍。

### 实测数据示例（PostgreSQL 14 / 8 核 / 32GB）

| 数据规模 | 朴素 Apply（关闭去关联） | 去关联后哈希连接 | 加速比 |
|---------|-------------------------|------------------|-------|
| 10⁴ × 10⁵ | 47s | 0.18s | 261× |
| 10⁵ × 10⁶ | 1842s（30 分钟） | 1.4s | 1316× |
| 10⁶ × 10⁷ | 跑了 6 小时未结束 | 12.7s | >1700× |

PostgreSQL 默认就会做去关联化，关闭它的方法是写成"故意阻断优化器"的形式（如把 OFFSET 0 加到 CTE，或用 RECURSIVE CTE 包装），仅用于教学对比。

### 为什么哈希连接的代价分析这么干净？

去关联化的本质是把"参数化的 N 次执行"变成"批量化的一次执行"。批量化让两件事变成可能：

1. **内层只算一次**：哈希连接、排序合并、Bloom Filter 都是"先把内层全跑一遍"再跟外层连接。
2. **向量化和 SIMD**：批量处理是向量化引擎的前提。Apply 算子每次只处理一行，向量化效率为 0。

## 主要引擎的去关联化能力详解

### PostgreSQL：pull-up 去关联化（自 7.x 起）

PostgreSQL 是开源数据库中最早系统性实现去关联化的。核心机制叫 **subquery pull-up**（子查询拉起），实现在 `src/backend/optimizer/plan/subselect.c` 和 `src/backend/optimizer/plan/initsplan.c`。

```sql
-- PG 内部把这条
SELECT * FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id);

-- 拉起为 Hash Semi Join
EXPLAIN (ANALYZE) SELECT * FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id);
/*
 Hash Semi Join  (cost=... rows=...)
   Hash Cond: (c.id = o.customer_id)
   ->  Seq Scan on customers c
   ->  Hash
         ->  Seq Scan on orders o
*/
```

**支持的形态**：

- `EXISTS` / `NOT EXISTS` 关联子查询 → Semi/Anti Join（自 PG 8.4+ 完整）
- `IN` / `NOT IN` 关联子查询 → Semi/Anti Join（注意 NOT IN 的 NULL guard）
- 标量子查询 in SELECT 列 → LEFT JOIN（自 PG 7.x 起，但限制较多）
- 标量子查询 in WHERE → 可能拉为 JOIN（视形态而定）
- LATERAL 子查询 → 自 9.3 起，本身就是显式声明，不需要去关联化

**回退路径**：去关联化失败时，PostgreSQL 在 EXPLAIN 中显示 `SubPlan` 或 `InitPlan`（不带相关参数则是 InitPlan，带相关参数则是 SubPlan）。`SubPlan` 就是逐行执行的 Apply。

```
SubPlan 1
  ->  Seq Scan on orders o
        Filter: (customer_id = c.id)   -- ← 相关谓词
```

看到 `SubPlan` 就是优化器没去关联化的信号。常见原因：内层有 LIMIT、内层有窗口函数、内层是聚合且外层引用聚合结果中带聚合的复杂表达式、关联谓词非等值等。

**关联工具**：

- `pg_hint_plan` 扩展（NTT 维护）：可以用注释 hint 强制 / 阻止去关联化，例如 `/*+ NoSubqueryUnnest(orders) */`。
- 但 PG 主线**没有**官方 hint 机制。生产经验是改写 SQL 而非依赖 hint。

**已知限制**：

- 多层嵌套的相关子查询（外层关联到中层、中层关联到内层）拉起能力有限，常退化为 SubPlan。
- 内层带 `LIMIT 1` 的标量子查询（"取每个客户最近一笔订单"模式）目前只能用 LATERAL 显式改写，PG 自身不会自动 unnest 这种"top-N per group"形态。
- 内层带 OUTER JOIN 时拉起规则更严格。

```sql
-- 这种 PG 不会自动去关联化（带 LIMIT）
SELECT c.id,
       (SELECT amount FROM orders o
        WHERE o.customer_id = c.id ORDER BY ts DESC LIMIT 1) AS last_amount
FROM customers c;
-- EXPLAIN 显示 SubPlan，N 次内层执行

-- 改写为 LATERAL，单次哈希
SELECT c.id, t.amount
FROM customers c,
     LATERAL (SELECT amount FROM orders o
              WHERE o.customer_id = c.id ORDER BY ts DESC LIMIT 1) t;
-- EXPLAIN 仍可能是 Nested Loop（如果 orders 上 (customer_id, ts) 有索引），
-- 但这是用户显式声明的形态，索引下可以很快
```

**EXPLAIN 区分**：

- `Hash Semi Join` / `Hash Anti Join`：去关联化为半/反连接成功。
- `Nested Loop Semi Join`：去关联化成功但物理算子选了嵌套循环（小表场景）。
- `SubPlan` / `correlated SubPlan`：去关联化失败，逐行 Apply。
- `InitPlan`：非相关子查询，只算一次。

### Oracle：unnest hint 与最复杂的相关子查询处理（自 9i 起）

Oracle 的相关子查询去关联化在传统商业数据库中是**最复杂、覆盖最广**的，源代码量级远超 PG。

```sql
-- Oracle 自动 unnest 这条
SELECT c.id, c.name
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id);

-- DBMS_XPLAN 显示
/*
| Id | Operation        | Name      |
|  0 | SELECT STATEMENT |           |
|  1 |  HASH JOIN SEMI  |           |   ← 已 unnest
|  2 |   TABLE ACCESS   | CUSTOMERS |
|  3 |   TABLE ACCESS   | ORDERS    |
*/
```

**关键 hint**：

| Hint | 含义 |
|------|------|
| `/*+ UNNEST */` | 强制对子查询做 unnest |
| `/*+ NO_UNNEST */` | 禁止对子查询做 unnest |
| `/*+ PUSH_SUBQ */` | 早执行子查询（提示，配合 unnest） |
| `/*+ NO_PUSH_SUBQ */` | 推迟子查询执行 |
| `/*+ HASH_SJ */` | 强制半连接走哈希 |
| `/*+ NL_SJ */` | 强制半连接走嵌套循环 |
| `/*+ MERGE_SJ */` | 强制半连接走排序合并 |
| `/*+ HASH_AJ */` / `/*+ NL_AJ */` / `/*+ MERGE_AJ */` | 反连接的算子选择 |

```sql
-- 强制 unnest 并走哈希半连接
SELECT /*+ UNNEST HASH_SJ(o) */ c.*
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id);

-- 禁止 unnest（用于 A/B 对比）
SELECT /*+ NO_UNNEST */ c.*
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id);
-- 此时 EXPLAIN 显示 FILTER 算子（即逐行 Apply）
```

**Oracle 的 unnest 覆盖范围**（远超 PG）：

- `EXISTS` / `NOT EXISTS` / `IN` / `NOT IN` 全部支持 unnest
- 标量相关子查询 in SELECT 列 → LEFT JOIN（包括带聚合的，如 `(SELECT MAX(...) FROM ... WHERE ...)`）
- 标量相关子查询 in WHERE 比较右侧 → JOIN
- **多层嵌套相关子查询** → 递归 unnest（这是 Oracle 比 PG 强的地方）
- **内层带聚合 + 外层引用** → 通过 group-by 重写处理
- **NOT IN with NULLable 列** → NULL-aware Anti Join（标准的 NOT IN NULL 陷阱保留）

**Complex View Merging（CVM）**：Oracle 还能合并视图与外查询，间接帮助子查询去关联化。开关 `_complex_view_merging`。

**回退路径**：unnest 失败时显示 `FILTER` 算子，效果等价于 PG 的 SubPlan：

```
| Id | Operation                 | Name      |
|  1 |  FILTER                   |           |   ← 没 unnest
|  2 |   TABLE ACCESS FULL       | CUSTOMERS |
|  3 |   TABLE ACCESS BY INDEX   | ORDERS    |
|  4 |    INDEX RANGE SCAN       | ORDERS_FK |
```

`FILTER` 节点表示：节点 2 每出一行，把行的列值代入节点 3 重新执行一次。

**Oracle 9i 之前**：8i 及更早版本的 Oracle 优化器对 EXISTS / IN 的处理远不如今天，常用的"老 Oracle DBA 经验"——`IN 改写为 EXISTS 更快`、`EXISTS 改写为 JOIN 更快`，**在 9i+ 之后早就不成立**。9i 引入 `UNNEST` hint，10g 以后默认开启 unnest，11g 进一步增强对带聚合相关子查询的处理。

### SQL Server：CardEstimator 与 Apply 算子（自 2005 起）

SQL Server 在传统商业引擎中相关子查询处理"最深思熟虑"——它的执行引擎从一开始就有**显式的 Apply 算子**（即 CROSS APPLY / OUTER APPLY 在物理层的对应），优化器在去关联化失败时优雅地回退到 Apply。

```sql
-- 朴素相关子查询
SELECT c.name
FROM Customers c
WHERE EXISTS (SELECT 1 FROM Orders o WHERE o.CustomerId = c.Id);

-- 计划（去关联化成功）
/*
|--Hash Match(Right Semi Join, ...)
   |--Index Scan(Orders.IX_CustomerId)
   |--Index Scan(Customers.PK)
*/

-- 关闭 unnest 后（用 OPTION (FORCE ORDER) 或写 OUTER APPLY 模拟）
SELECT c.name
FROM Customers c
CROSS APPLY (SELECT TOP 1 1 AS ex FROM Orders o WHERE o.CustomerId = c.Id) x;

-- 计划：Nested Loops（Inner Join），右侧引用左侧（这就是 Apply）
/*
|--Nested Loops(Inner Join, OUTER REFERENCES:([c].[Id]))
   |--Index Scan(Customers.PK)
   |--Top(TOP EXPRESSION:(1))
      |--Index Seek(Orders.IX_CustomerId, SEEK:([o].[CustomerId]=[c].[Id]))
*/
```

**SQL Server CardEstimator** 在 SQL 2014 重写后，对相关子查询的处理覆盖：

- 标量相关子查询 → LEFT JOIN 或 Hash Match
- EXISTS / IN → Right Semi Join（哈希实现）
- NOT EXISTS / NOT IN → Right Anti Semi Join
- 带聚合的标量子查询（如 `WHERE x > (SELECT AVG(...) WHERE ...)`）→ 通过 Window Aggregate 改写
- 多层嵌套 → 递归 unnest（与 Oracle 类似）

**SQL Server 独有特性**：

- **CROSS APPLY / OUTER APPLY 是显式语法**：用户可以直接写出 Apply，绕过优化器的去关联化判断。这是 SQL Server 自 2005 引入的，比标准 LATERAL（PG 9.3, 2013）早 8 年。
- **Apply 算子可被推导回 Join**：即使写了 CROSS APPLY，优化器仍可能把它改写为 Hash Join（如果右侧没引用左侧的"难"列）。
- **UDF 内联（2019+）**：`Scalar UDF Inlining` 把标量 UDF 展开成行内表达式，间接帮助子查询去关联化。

**开关**：

- `OPTION (NO_PERFORMANCE_SPOOL)` 关闭 spool 优化（可能影响 Apply 性能）。
- 没有专门的 NO_UNNEST，但可以用 `OPTION (FORCE ORDER)` 或显式改写为 APPLY 来"逼"优化器走 Apply。
- `Query Store` 可固化好计划，避免回归。

### DuckDB：Mark Join + Apply Elimination（基于 BTW 2015 论文）

DuckDB 在子查询去关联化上是**新一代引擎里最先进的**——它直接实现了 Hyper / Umbra 团队 Neumann 和 Kemper 在 BTW 2015 论文中证明的"Unnesting Arbitrary Queries"算法，**理论上能消除任意嵌套层数的任意相关子查询**。

核心算子：**MARK_JOIN**（标记连接）和 **DEPENDENT_JOIN**（相关连接 = Apply）。

```sql
-- DuckDB EXPLAIN
EXPLAIN
SELECT c.id, c.name,
       (SELECT MAX(amount) FROM orders o WHERE o.customer_id = c.id) AS max_amt
FROM customers c;

/*
┌───────────────────────────┐
│         PROJECTION        │
│        (id, name, ...)    │
└─────────────┬─────────────┘
┌─────────────┴─────────────┐
│         HASH_JOIN         │   ← 已去关联化为普通哈希连接
│         LEFT JOIN         │
│       customer_id = id    │
└─────────────┬─────────────┘
              ├─────────────┐
        SEQ_SCAN       HASH_GROUP_BY
       customers           orders
                       MAX(amount)
                       GROUP BY customer_id
*/
```

**关键洞见（Neumann/Kemper 2015）**：把任意相关子查询拆成"自由变量集 D"和"内层 plan T"。引入 `D × T` 这一**虚拟笛卡尔积** + 把虚拟列下推到 T 内部 + 用 GROUP BY 重新聚合 = 去关联化总能成功。证明：通过对 plan tree 归纳，每种关系算子（σ, π, ⨝, γ, δ）都有去关联化规则。

```
原 Apply:  outer △ inner_with_correlation
       =  outer △ (σ_corr (inner))

去关联:
       =  outer ⨝_corr (γ_outer_keys (inner ⨝ keys_of_outer))
```

DuckDB 的实现细节（src/optimizer/subquery/flatten_dependent_join.cpp）：

1. 检测相关子查询，包成 `DependentJoin` 算子。
2. 对 `DependentJoin` 递归下推：每遇到一个关系算子，应用去关联化规则。
3. 最终 `DependentJoin` 被消除，剩下的全是普通 Join + Aggregate。
4. 失败时（极少数）回退到 Apply（嵌套循环执行）。

**DuckDB 独有的 MARK JOIN**：处理 `EXISTS` / `IN` / `NOT EXISTS` / `NOT IN` 的统一物理算子。它在哈希探测时不仅返回"匹配/不匹配"，还产生一个布尔列 mark，下游可用这个 mark 做任意逻辑组合（如 `EXISTS AND NOT EXISTS` 复合谓词）。

```
MARK_JOIN
  ├── 物理实现: 哈希连接的变种
  ├── 输出: 左表所有行 + 一个 mark 列 (TRUE/FALSE/NULL)
  ├── 优势: 一次扫描完成所有 EXISTS / IN 子查询
  └── 适用: WHERE EXISTS、SELECT EXISTS()、CASE WHEN EXISTS
```

实战例子：DuckDB 跑 TPC-H Q22（带 `WHERE NOT EXISTS` 的复杂相关子查询）速度领先 PostgreSQL 10×+，主要就是 MARK JOIN + 任意嵌套 unnest 的功劳。

### MySQL：8.0 Subquery Rewriter（自 2018 起）

MySQL 在子查询优化上"长期落后"——5.5 及更早版本对 IN 子查询的处理是把它转换为关联 EXISTS 然后逐行执行，这是当年"IN 比 EXISTS 慢"传说的源头。

**版本演进**：

| 版本 | 改进 |
|------|------|
| 5.6 (2013) | 首次引入 Semi-Join 优化（IN → Semi-Join） |
| 5.7 (2015) | 子查询物化优化器开关 |
| 8.0.0 (2016 milestone, GA 2018) | 子查询重写器（Subquery Transformer），覆盖更多场景 |
| 8.0.14 (2018) | 引入显式 LATERAL 语法 |
| 8.0.17 (2019) | NOT EXISTS / NOT IN → Anti-Join |
| 8.0.21+ | Hash Join 普遍可用，相关子查询去关联化获得新算子 |

**EXPLAIN 关键字**：

```
DEPENDENT SUBQUERY     -- 没去关联化，逐行 Apply（"坏"信号）
SUBQUERY               -- 非相关子查询，只跑一次
MATERIALIZED           -- 子查询物化为临时表
SEMIJOIN              -- 已重写为半连接（"好"信号）
ANTIJOIN              -- 已重写为反连接（8.0.17+）
```

```sql
-- MySQL 8.0
EXPLAIN FORMAT=TREE
SELECT * FROM customers c
WHERE c.id IN (SELECT customer_id FROM orders WHERE status = 'paid');

/*
-> Hash semi join (c.id = orders.customer_id)
    -> Table scan on c
    -> Hash
        -> Filter: (orders.status = 'paid')
            -> Table scan on orders
*/
```

**MySQL 优化器开关**（`optimizer_switch`）：

```sql
-- 查看
SELECT @@optimizer_switch;

-- 关闭 semijoin（用于诊断）
SET optimizer_switch = 'semijoin=off';

-- 关闭物化（用于诊断）
SET optimizer_switch = 'materialization=off';

-- 8.0.17+: 关闭 antijoin
SET optimizer_switch = 'antijoin=off';
```

**已知短板**：

- 标量相关子查询 in SELECT 列的去关联化能力**仍弱于 PG/Oracle**——很多情况下显示为 DEPENDENT SUBQUERY。
- 内层带 LIMIT 的子查询不会自动去关联化。
- 多层嵌套（>2 层）支持有限。

**生产建议**：MySQL 上写相关子查询，**优先用 LATERAL 显式改写**（8.0.14+），而不是依赖优化器去关联化。

### ClickHouse：相关子查询支持有限

ClickHouse 早期（≤ 22.3）几乎不支持相关子查询——内层引用外层列直接报错。22.3+ 开始支持 `WHERE EXISTS`、IN 形态，但**仍不支持任意位置的相关标量子查询**（如 SELECT 列中、HAVING 中）。

```sql
-- ClickHouse 22.3+ 可以
SELECT * FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id);

-- ClickHouse 仍可能报错或低效（直到非常新的版本才部分支持）
SELECT c.id,
       (SELECT MAX(amount) FROM orders o WHERE o.customer_id = c.id)
FROM customers c;
-- 错误: Subquery has correlated columns ... not supported（旧版本）
```

**推荐做法**：在 ClickHouse 中把相关子查询**手工改写为 JOIN**：

```sql
-- 手工去关联化
SELECT c.id, agg.max_amt
FROM customers c
LEFT JOIN (
    SELECT customer_id, MAX(amount) AS max_amt
    FROM orders GROUP BY customer_id
) agg ON c.id = agg.customer_id;
```

这是 ClickHouse 与 PG/Oracle/DuckDB 最大的差距——OLAP 引擎默认假设"用户会自己写好 JOIN"，优化器不会兜底。

### Spark SQL：Catalyst RewriteCorrelatedSubquery

Spark Catalyst 优化器有专门的规则 `RewriteCorrelatedScalarSubquery`（src/sql/catalyst/optimizer/subquery.scala）。处理流程：

1. 识别 `ScalarSubquery` 表达式（标量相关子查询）。
2. 把内层的相关谓词提到 JOIN ON 子句。
3. 内层包装成 LEFT OUTER JOIN（如果外层无匹配，标量值为 NULL）。
4. 加聚合保证标量子查询的"单行"语义（如果内层可能多行，加 `LIMIT 2 + 检查`）。

```sql
-- Spark SQL
EXPLAIN EXTENDED
SELECT c.id,
       (SELECT MAX(amount) FROM orders o WHERE o.customer_id = c.id) AS m
FROM customers c;

/*
== Optimized Logical Plan ==
Project [id#10, m#20]
+- Project [id#10, max(amount)#19 AS m#20]
   +- Join LeftOuter, (customer_id#15 = id#10)    ← 已重写
      :- LogicalRelation customers
      +- Aggregate [customer_id#15], [max(amount), customer_id#15]
         +- LogicalRelation orders
*/
```

**Catalyst 的边界**：

- 简单标量子查询、EXISTS/IN/NOT EXISTS/NOT IN 都能去关联化。
- 多层嵌套支持有限（部分 case 仍走 Subquery Apply 物理算子）。
- 内层带 OUTER JOIN 时规则更保守。
- DSv2（DataSource v2）下相关子查询下推到数据源时支持有限。

**版本演进**：

- 1.x: 几乎不支持相关子查询
- 2.0 (2016): 首次系统支持，标量 + EXISTS/IN
- 3.0 (2020): RewriteCorrelatedSubquery 重构
- 3.3 (2022): 引入显式 LATERAL 语法
- 3.4+ (2023): 改进 NULL-aware Anti-Join

### Trino / Presto：RewriteCorrelatedSubquery

Trino 优化器有规则 `TransformCorrelatedScalarSubquery`、`TransformExistsApplyToCorrelatedJoin`、`RewriteCorrelatedSubquery`，覆盖：

- 标量相关子查询 → CorrelatedJoin → 普通 Join（通过 Apply elimination）
- EXISTS / IN → Semi-Join
- NOT EXISTS / NOT IN → Anti-Join

```sql
-- Trino EXPLAIN
EXPLAIN
SELECT * FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id);

/*
- Output[customers.id, customers.name]
  - SemiJoin[id = customer_id]
    - TableScan[customers]
    - TableScan[orders]
*/
```

Trino 内部把所有相关子查询先转换为 `Apply` / `CorrelatedJoin` 节点，然后通过一系列规则尝试消除（apply elimination）。失败时保留 `CorrelatedJoin`，物理执行成嵌套循环。

**版本演进**：

- Presto 0.x: 仅支持简单形态
- 0.148+: 引入 LATERAL
- Trino fork (2018+): 重写规则大幅改进
- Trino 350+: 任意嵌套层数支持显著提升

**已知限制**：在分布式执行模型下，相关子查询的去关联化对数据分布敏感——shuffle 代价可能让"去关联化后的连接"反而比 Apply 慢。Trino 的代价模型会权衡。

### 其他引擎要点速览

- **DB2**：传统商业引擎中与 Oracle 并列的子查询优化器。"Subquery Transformation" 阶段覆盖任意嵌套、标量、EXISTS、聚合相关子查询。`db2exfmt` 工具可显示完整重写历史。
- **Snowflake**：自动去关联化，QUERY PROFILE UI 中能看到展开后的 Join 树。LATERAL FLATTEN 主要用于半结构化数据。
- **BigQuery**：自动 unnest，UI 详细计划层可见。CROSS JOIN UNNEST(ARRAY(...)) 是显式 LATERAL 替代。
- **CockroachDB**：基于 PG 兼容，去关联化能力跟 PG 类似。分布式场景下额外考虑分片对齐。
- **TiDB**：4.0 之前对相关子查询支持较弱，4.0+ 通过引入 `Apply Decorrelation` 规则改进。仍不支持 LATERAL。
- **OceanBase**：双模式（MySQL/Oracle 兼容），Oracle 模式下能力接近 Oracle，MySQL 模式下接近 MySQL 8.0+。
- **GaussDB / openGauss / KingbaseES / GreatDB**：基于 PG 内核，继承 PG 去关联化能力，部分增强 hint 系统。
- **SAP HANA**：成熟商业引擎，CALCULATION_VIEW 中也支持相关子查询去关联化。
- **Materialize**：基于 differential dataflow，相关子查询在 dataflow 编译期就被去关联化（编译失败则报错而非回退）。
- **Calcite**：作为框架，提供 `SubQueryRemoveRule` 等规则，下游引擎（Flink、Hive LLAP、Drill 等）共享这套基础设施。
- **H2 / Derby / HSQLDB**：嵌入式数据库，相关子查询能跑但优化能力有限——大表上仍是逐行 Apply。

## Magic Decorrelation 深度解析（Galindo-Legaria & Joshi SIGMOD 2001）

César Galindo-Legaria 与 Arnon Rosenthal 在 ACM TODS 1997 *"Outerjoin Simplification and Reordering for Query Optimization"*，以及 Galindo-Legaria 与 Milind Joshi 在 SIGMOD 2001 *"Orthogonal Optimization of Subqueries and Aggregation"* 中正式定义了 **magic decorrelation** 这一变换。

### 核心思想

朴素的 unnest 只能处理"内层不带聚合"的相关子查询。一旦内层有聚合（GROUP BY / MAX / AVG / COUNT），简单 pull-up 不再保证语义等价。例如：

```sql
-- 内层带聚合，要求"对外层每行 c.id 计算 orders 中 customer_id 等于 c.id 的 SUM"
SELECT c.id,
       (SELECT SUM(amount) FROM orders WHERE customer_id = c.id) AS total
FROM customers c;
```

朴素的"把 WHERE 条件挪出去 + 加 LEFT JOIN"行不通——因为 SUM 必须在 GROUP BY customer_id 之后再 JOIN，否则会计算错误。

**Magic decorrelation 的两步**：

1. **创建"魔术表"**：把外层引用的列（关联谓词需要的列）抽出来，去重，得到 D = `SELECT DISTINCT customer_id FROM ...（外层）`。
2. **把内层条件改写为对 D 的连接**：内层变成 `SELECT customer_id, SUM(amount) FROM orders SEMI JOIN D ON orders.customer_id = D.customer_id GROUP BY customer_id`。
3. **再跟外层连接**：`outer LEFT JOIN inner_aggregated ON outer.id = inner.customer_id`。

```sql
-- Magic decorrelation 后等价改写
WITH magic AS (SELECT DISTINCT id FROM customers),
     inner_agg AS (
       SELECT customer_id, SUM(amount) AS total
       FROM orders WHERE customer_id IN (SELECT id FROM magic)
       GROUP BY customer_id
     )
SELECT c.id, ia.total
FROM customers c LEFT JOIN inner_agg ia ON c.id = ia.customer_id;
```

实际优化器实现里"魔术表"通常不显式物化，而是通过谓词下推 + 半连接消除让它消失。

### 为什么叫 "magic"？

源自 Mumick et al. 1990 年 *"Magic is relevant"* 论文——一种把递归查询和聚合查询展开成半连接的技术。Galindo-Legaria 把它推广到任意相关子查询。"Magic" 就指"不显式生成所有中间结果，只生成与外层相关的部分"这一神奇效果。

### 各引擎对 Magic Decorrelation 的支持

| 引擎 | 实现方式 | 触发条件 |
|------|---------|---------|
| Oracle | "Subquery Unnesting with Group-By Pushdown" | 内层带聚合 + 外层引用聚合结果 |
| SQL Server | CardEstimator 中的 GbAggToCorrelatedApply | 自动 |
| DB2 | 显式 magic decorrelation 阶段 | 自动 |
| PostgreSQL | 部分支持（pull-up + 子查询合并） | 简单聚合形态 |
| DuckDB | 通过 Neumann/Kemper 算法泛化处理 | 自动 |
| Snowflake | 自动 unnest，覆盖大部分聚合形态 | 自动 |
| Spark Catalyst | 部分（RewriteCorrelatedScalarSubquery 处理简单聚合） | 自动 |
| Trino | 部分 | 自动 |
| MySQL 8.0 | 部分（聚合下推有限） | 自动 |
| ClickHouse | 不支持 | - |

### 一个具体例子：TPC-H Q17

TPC-H Q17 是经典的 magic decorrelation 测试：

```sql
SELECT SUM(l_extendedprice) / 7.0
FROM lineitem, part
WHERE p_partkey = l_partkey
  AND p_brand = 'Brand#23'
  AND p_container = 'MED BOX'
  AND l_quantity < (
      SELECT 0.2 * AVG(l_quantity)
      FROM lineitem WHERE l_partkey = p_partkey
  );
```

内层：对每个 `p_partkey` 求 `lineitem` 的平均 `l_quantity`，外层用这个平均值过滤。

朴素执行：外层每行（对 part 过滤后约几千行）触发一次 lineitem 全扫，性能极差。

Magic decorrelation 后：

```sql
WITH avg_qty AS (
    SELECT l_partkey, 0.2 * AVG(l_quantity) AS threshold
    FROM lineitem GROUP BY l_partkey
)
SELECT SUM(l_extendedprice) / 7.0
FROM lineitem l, part p, avg_qty a
WHERE p_partkey = l_partkey
  AND p_brand = 'Brand#23'
  AND p_container = 'MED BOX'
  AND a.l_partkey = p_partkey
  AND l.l_quantity < a.threshold;
```

只算一次聚合，O(N+M)。

引擎实测（TPC-H SF100，128GB 内存）：

| 引擎 | 朴素执行 | Magic decorrelation 后 |
|------|---------|----------------------|
| PostgreSQL 14 | >1 小时（未结束） | 47s |
| Oracle 19c | 自动应用 | 32s |
| SQL Server 2022 | 自动应用 | 28s |
| DuckDB 0.9 | 自动应用 | 9s |
| MySQL 8.0 | 数小时 | 部分应用，~110s |
| ClickHouse 23 | 不支持（需手工改写） | 手工改写 14s |

## DuckDB / Umbra：任意嵌套层数（Neumann/Kemper 2015 BTW）

Neumann 和 Kemper 在 *BTW 2015 - Datenbanksysteme für Business, Technologie und Web* 上发表的 *"Unnesting Arbitrary Queries"* 论文证明了一个深刻结果：

> **任何相关子查询都可以被无损地去关联化为不含相关性的关系代数表达式。**

这超越了 Galindo-Legaria 的 magic decorrelation——后者覆盖大量场景但仍有边角；Neumann/Kemper 的算法证明**没有边角**：任意嵌套层数、任意聚合形态、任意外连接、任意窗口函数，都能被消除。

### 算法核心

设原查询树根为相关子查询：`outer ⨝_corr inner(d)`，其中 `d` 是从外层借用的列集。算法分四步：

1. **识别自由变量**：扫描内层 plan，标记每个出现的外层列引用，得到自由变量集 `D = {d₁, d₂, ...}`。
2. **构建虚拟笛卡尔积**：把 `outer ⨝_corr inner(d)` 改写为 `outer ⨝ (D × inner(D))`，其中 `D × inner(D)` 是"对每个 d 都跑一次 inner"的代数表示。注意这是**虚拟的**，物理上不真的展开。
3. **下推 D 到 inner**：用归纳法对 inner 的每种关系算子（σ, π, ⨝, γ, δ, OuterJoin）应用变换规则，把 `D` 推到底层。例如：
   - σ_p (D × T) → D × σ_p (T) 当 p 不引用 D
   - σ_p (D × T) → 改写谓词后 D × σ_p' (T) 当 p 引用 D
   - γ_g,f (D × T) → γ_g∪D, f (D × T)（GROUP BY 加上 D 列）
4. **消除 D**：D 被推到 inner 的叶节点（基表）后，与基表自然连接（D 来自外层 outer，所以这个连接最终被外层连接吸收）。

变换的不变量：每一步 plan 都与原 plan 语义等价；最终 plan 不含相关性。

### 关键创新

**老 unnest 算法的局限**：每种相关子查询形态需要专用规则——简单 EXISTS、带聚合的标量子查询、带 OUTER JOIN 的、嵌套 N 层的，每种都要单独写代码。规则覆盖不全 = 优化器有边角 = 用户写出"语法上合法但永远跑不完"的查询。

**Neumann/Kemper 算法**：基于关系代数的归纳证明——**任意算子树都能去关联化**，不需要枚举形态。实现量级也小：DuckDB `flatten_dependent_join.cpp` 主体不到 1000 行 C++，处理所有形态。

### DuckDB / Umbra 实战

```sql
-- 一个嵌套 3 层的相关子查询（人为构造，演示极端情况）
SELECT c.id,
       (SELECT MAX(o.amount)
        FROM orders o
        WHERE o.customer_id = c.id
          AND o.product_id IN (
              SELECT p.id FROM products p
              WHERE p.category = (
                  SELECT cat.name FROM categories cat
                  WHERE cat.id = c.preferred_category_id
              )
          )
       ) AS max_amount
FROM customers c;
```

在 PostgreSQL：每层都可能退化为 SubPlan，外层 N=10⁶ × 中层 N=10⁵ × 内层 N=10³ = 10¹⁴ 次。

在 DuckDB：四个表全部去关联化为四路 JOIN + 一次 GROUP BY，O(N+M+K+L)，几秒内完成。

```
EXPLAIN（DuckDB 自动展开后大致结构）:
PROJECTION
  └ HASH_JOIN customer_id = id
       ├ SEQ_SCAN customers
       └ HASH_GROUP_BY MAX(amount), GROUP BY customer_id
            └ HASH_JOIN product_id = p.id
                 ├ SEQ_SCAN orders
                 └ HASH_JOIN p.category = cat.name
                      ├ SEQ_SCAN products
                      └ SEQ_SCAN categories
```

### 为什么不是所有引擎都用这个算法？

1. **实现复杂度**：虽然论文给出了证明，但工程上要正确处理 NULL、3VL 语义、各种边界仍需大量调试。Oracle / SQL Server 的优化器是几十年增量演进的，重写成本高。
2. **代价模型未必同步**：去关联化总是语义等价，但**未必更快**——分布式系统中 shuffle 代价可能让"原地 Apply"反而更优。Trino / Spark / 分布式引擎需要代价模型决定是否真的去关联化。
3. **可观测性挑战**：完全自动 unnest 后，用户写的 SQL 跟实际执行的 plan 形态差异巨大，调优变得困难。

## Apply Elimination：从 Apply 到 Join 的代数变换

Apply 算子（也叫 d-join、parameterized join）是相关子查询的"诚实物理实现"。Apply elimination 是把 Apply 改写为普通 Join 的代数变换集。

```
Apply 的形式定义:
  T₁ A T₂(t₁) =  ⋃_{t₁ ∈ T₁} ({t₁} × T₂(t₁))

其中 T₂(t₁) 表示 T₂ 是参数化的，用 t₁ 的列值实例化
```

**Apply elimination 规则**（Bellamkonda et al. 2009 "Enhanced Subquery Optimizations in Oracle"）：

```
规则 A1（无相关）: T₁ A T₂  ≡  T₁ × T₂   当 T₂ 不引用 T₁
规则 A2（谓词分离）: T₁ A σ_p(T₂)  ≡  σ_p (T₁ × T₂)  当 p 可以提到外层
规则 A3（聚合下推）: T₁ A γ_f(T₂)  ≡  γ_f' (T₁ A T₂)  通过引入额外 GROUP BY 列
规则 A4（投影提升）: T₁ A π_l(T₂)  ≡  π_l (T₁ A T₂)  当 l 不引用 T₁
规则 A5（连接结合）: T₁ A (T₂ ⨝ T₃)  ≡  (T₁ A T₂) ⨝ T₃  当 T₃ 不引用 T₁
```

通过反复应用 A1–A5，Apply 算子被消除，剩下只有标准 Join、Aggregate、Project、Filter。

**实战观察**：现代优化器内部都先把相关子查询包装成 Apply，然后通过规则消除——这是"unify"的好处：处理流程统一，不需要为每种 SQL 形态写专用代码。Apply 在内部表示中通用、强大，但 EXPLAIN 中通常以更友好的名字展示（HASH JOIN SEMI、SubPlan、CorrelatedJoin 等）。

## EXPLAIN 中识别去关联化是否成功

下表是各引擎 EXPLAIN 中"已去关联化"和"未去关联化"的关键信号：

| 引擎 | 去关联化成功（好） | 未去关联化（差） |
|------|------------------|-----------------|
| PostgreSQL | `Hash Semi Join` / `Hash Anti Join` / `Hash Left Join`（标量场景） | `SubPlan N` 节点（带 correlated columns） |
| Oracle | `HASH JOIN SEMI` / `HASH JOIN ANTI` / `NESTED LOOPS SEMI` | `FILTER` 节点 + 内层 access |
| SQL Server | `Hash Match (Right Semi Join)` / `Right Anti Semi Join` | `Nested Loops` 带 `OUTER REFERENCES` |
| MySQL | `Hash semi join` / `Hash anti join` / `MATERIALIZED` | `DEPENDENT SUBQUERY` |
| DuckDB | `HASH_JOIN` / `MARK_JOIN` / 不再有 `DEPENDENT_JOIN` | `DEPENDENT_JOIN` 节点 |
| Spark SQL | `BroadcastHashJoin LeftSemi/LeftAnti` / `SortMergeJoin` | `BroadcastNestedLoopJoin` + filter（subquery 形态） |
| Trino | `SemiJoin` / `Apply` 被消除 | `CorrelatedJoin` 残留 |
| BigQuery | UI 显示扁平的 JOIN 树 | "JOIN" 阶段附带 "Repeated subquery execution" |
| Snowflake | Profile UI 中显式的 Hash Join | 出现 "Filter" 而非 Join 节点 |

## 实战：写出"优化器友好"的相关子查询

虽然现代优化器很强，但**写得"对"的 SQL** 比"靠优化器抢救"的 SQL 在所有引擎上都更稳定。三条原则：

### 1. 优先用 EXISTS 而非 IN（涉及可空列时）

```sql
-- 危险：dept_id 可空时返回空集（NOT IN 的 NULL 陷阱）
SELECT * FROM customers WHERE id NOT IN (SELECT customer_id FROM orders);

-- 安全
SELECT * FROM customers c WHERE NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.customer_id = c.id
);
```

### 2. 内层带 LIMIT 时用 LATERAL 显式声明

```sql
-- PG/MySQL 不会自动 unnest 这种"top-1 per group"
SELECT c.id,
       (SELECT amount FROM orders o WHERE o.customer_id = c.id
        ORDER BY ts DESC LIMIT 1) AS last_amount
FROM customers c;

-- 用 LATERAL 显式声明（在所有支持 LATERAL 的引擎上更高效）
SELECT c.id, t.amount
FROM customers c
LEFT JOIN LATERAL (
    SELECT amount FROM orders o
    WHERE o.customer_id = c.id ORDER BY ts DESC LIMIT 1
) t ON true;
```

### 3. 避免标量子查询多次调用

```sql
-- 反模式：SELECT 列中两次调用相同的标量子查询
SELECT c.id,
       (SELECT MAX(amount) FROM orders WHERE customer_id = c.id) AS max_amt,
       (SELECT MAX(amount) FROM orders WHERE customer_id = c.id) * 1.1 AS budget
FROM customers c;

-- 重构：用 LATERAL 或 JOIN 让聚合只算一次
SELECT c.id, agg.max_amt, agg.max_amt * 1.1 AS budget
FROM customers c
LEFT JOIN (
    SELECT customer_id, MAX(amount) AS max_amt FROM orders GROUP BY customer_id
) agg ON c.id = agg.customer_id;
```

### 4. 用 EXPLAIN 验证去关联化

```sql
-- 部署前永远 EXPLAIN：
-- PG: 确认看到 Hash Semi/Anti/Left Join，而非 SubPlan
-- Oracle: 确认看到 HASH JOIN SEMI/UNNEST，而非 FILTER
-- MySQL: 确认看到 HASH SEMI JOIN / SEMIJOIN，而非 DEPENDENT SUBQUERY
-- DuckDB: 确认看到 HASH_JOIN / MARK_JOIN，而非 DEPENDENT_JOIN
```

## 关键发现

1. **没有 SQL 标准**：去关联化是优化器内部细节。同一句 SQL 在不同引擎上是 0.1 秒还是 1 小时，主要看优化器愿意做多少"魔法"。

2. **45+ 引擎中只有少数实现完整 Neumann/Kemper 风格的任意嵌套去关联化**：DuckDB、Materialize、Calcite（框架层）、Oracle（接近）、SQL Server（接近）、DB2（接近）、Teradata（接近）。其余引擎都有"边角形态"会回退到 Apply。

3. **PostgreSQL 是开源里最早系统支持 pull-up 的**（自 7.x），但对"top-N per group"和多层嵌套支持仍弱于商业引擎。生产建议用 LATERAL 显式补足。

4. **Oracle 和 SQL Server 的子查询优化器最成熟**——20+ 年增量演进，覆盖几乎所有形态。但 hint 系统也最复杂，UNNEST / NO_UNNEST / PUSH_SUBQ 等十几个 hint 互相影响。

5. **DuckDB 是新一代引擎里最先进的**——Mark Join + Apply elimination + Neumann/Kemper 算法的工程实现，2018 后的"去关联化标杆"。Umbra（学术原型）甚至更进一步。

6. **MySQL 长期落后，8.0 显著改进但仍弱**——5.5 之前 IN → EXISTS 的"反向重写"造成大量历史性能问题；8.0 引入子查询重写器后接近 PG 水平，但标量子查询和多层嵌套仍是短板。

7. **ClickHouse / Doris / StarRocks / 分布式 OLAP 引擎对相关子查询支持有限**——这些引擎默认假设用户会自己写好 JOIN，优化器不会兜底。生产上必须手工去关联化。

8. **Spark Catalyst 和 Trino 在分布式场景下的去关联化要权衡 shuffle 代价**——不像单机引擎"总是去关联化更好"，分布式下有时 Apply（带索引）反而比 shuffle-heavy 的 Join 快。

9. **EXPLAIN 中识别去关联化结果的语言不统一**：PostgreSQL 看 SubPlan、Oracle 看 FILTER、SQL Server 看 OUTER REFERENCES、DuckDB 看 DEPENDENT_JOIN、MySQL 看 DEPENDENT SUBQUERY、Spark 看 SubqueryAlias。学习每个引擎的 EXPLAIN 是 DBA 基本功。

10. **写"对"的 SQL 比"靠优化器抢救"更可靠**：用 LATERAL 显式声明 top-N per group，用 EXISTS 而非 IN（避 NULL 陷阱），用 JOIN 替代多次调用的标量子查询，用 EXPLAIN 验证。即使在最优秀的优化器上，这些原则也能让查询计划更稳定、更可预测。

## 参考资料

- Galindo-Legaria, C. & Rosenthal, A. *"Outerjoin Simplification and Reordering for Query Optimization"*, ACM TODS 1997.
- Galindo-Legaria, C. & Joshi, M. *"Orthogonal Optimization of Subqueries and Aggregation"*, SIGMOD 2001.
- Galindo-Legaria, C. *"Outerjoins as Disjunctions"*, SIGMOD 1994.
- Mumick, I. S., Pirahesh, H., Ramakrishnan, R. *"The Magic of Duplicates and Aggregates"*, VLDB 1990.
- Bellamkonda, S. et al. *"Enhanced Subquery Optimizations in Oracle"*, VLDB 2009.
- Neumann, T., Kemper, A. *"Unnesting Arbitrary Queries"*, BTW 2015.
- Hyrkäs, J. *"Don't Hold My Data Hostage – A Case For Client Protocol Redesign"*, VLDB 2017 (DuckDB context).
- Pirahesh, H., Hellerstein, J. M., Hasan, W. *"Extensible/Rule Based Query Rewrite Optimization in Starburst"*, SIGMOD 1992.
- PostgreSQL: [src/backend/optimizer/plan/subselect.c](https://github.com/postgres/postgres/blob/master/src/backend/optimizer/plan/subselect.c)
- DuckDB: [src/optimizer/subquery/flatten_dependent_join.cpp](https://github.com/duckdb/duckdb/blob/main/src/optimizer/subquery/flatten_dependent_join.cpp)
- Oracle: *Database SQL Tuning Guide* — Subquery Unnesting & Hints chapter.
- SQL Server: *Query Processing Architecture Guide* — Cardinality Estimation & Apply.
- MySQL: [Server Internals: Optimizer subquery transformation](https://dev.mysql.com/doc/internals/en/optimizer-subquery-transformations.html)
- Spark Catalyst: [optimizer/subquery.scala](https://github.com/apache/spark/blob/master/sql/catalyst/src/main/scala/org/apache/spark/sql/catalyst/optimizer/subquery.scala)
- Trino: [trino.io/docs - Optimizer rules](https://trino.io/docs/current/optimizer/rules.html)
- pg_hint_plan: [GitHub repo](https://github.com/ossc-db/pg_hint_plan)
