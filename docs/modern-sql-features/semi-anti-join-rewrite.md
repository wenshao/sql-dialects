# 半连接与反连接重写 (Semi-Join and Anti-Join Rewriting)

`EXISTS`、`IN`、`NOT EXISTS`、`NOT IN`——这四个看似平常的子查询谓词，是 SQL 优化器最频繁触发的重写场景。在朴素的"嵌套循环 + 内层独立执行"实现下，它们会让一个 1 亿行外表对一个 1000 万行内表跑出 10^15 次行比较；而一旦优化器把它们改写为半连接（Semi-Join）或反连接（Anti-Join），同样的查询能用一次哈希连接 + 早停（short-circuit）跑完，性能差距常常是 4 个数量级。

可惜这场重写在标准之外：ISO/IEC 9075 SQL 标准只定义了 `EXISTS` / `IN` / `NOT EXISTS` / `NOT IN` 的**语义**（什么时候为真），从不规定优化器必须把它们重写成什么物理算子。"重写为 Semi-Join / Anti-Join" 完全是实现选择。本文系统对比 45+ 个 SQL 引擎在这一重写上的能力差异，从 Oracle "unnest" 提示到 PostgreSQL 的 pull-up，从 Galindo-Legaria 的 magic decorrelation 到 SQL Server 的 anti-semi-apply，把这条重写流水线讲透。

> **关联文章**: 子查询整体优化见 [subquery-optimization.md](subquery-optimization.md)；查询重写规则全览见 [query-rewrite-rules.md](query-rewrite-rules.md)；Semi/Anti-Join 物理实现细节见 [hash-join-algorithms.md](hash-join-algorithms.md)。

## EXISTS / IN / NOT EXISTS / NOT IN：何时该重写

四个谓词在 SQL 文本中读起来差不多，但在优化器内部走的是完全不同的代码路径。理解它们的语义差异是讨论重写的前提：

```sql
-- EXISTS: 内层至少返回一行 → TRUE，否则 FALSE。NULL 不传播。
SELECT * FROM dept d WHERE EXISTS (
    SELECT 1 FROM emp e WHERE e.dept_id = d.dept_id
);

-- IN: 外层值等于内层任一值 → TRUE。内层若有 NULL，且无匹配，结果是 UNKNOWN（而非 FALSE）。
SELECT * FROM dept WHERE dept_id IN (SELECT dept_id FROM emp);

-- NOT EXISTS: 内层返回 0 行 → TRUE。NULL 不传播。
SELECT * FROM dept d WHERE NOT EXISTS (
    SELECT 1 FROM emp e WHERE e.dept_id = d.dept_id
);

-- NOT IN: 外层值不等于内层每一行。一旦内层有 NULL，整体陷入 3VL 陷阱（见后文）。
SELECT * FROM dept WHERE dept_id NOT IN (SELECT dept_id FROM emp);
```

把它们映射到物理算子，思路非常直接：

| 子查询形式 | 重写目标 | 算子语义 |
|-----------|--------|---------|
| `EXISTS (...)` | Semi-Join | 外表每行只要内表至少一个匹配就保留，匹配上即停 |
| `IN (subquery)` | Semi-Join | 同上，但需要先对子查询去重；处理 NULL 时与 EXISTS 略有不同 |
| `NOT EXISTS (...)` | Anti-Join | 外表每行只要内表无任何匹配就保留 |
| `NOT IN (subquery)` | Anti-Join with NULL guard | 同上，但内层任意 NULL 会导致整体返回空集 |

**为什么必须重写？** 朴素地按 SQL 语义执行子查询有两个致命问题：

1. **关联子查询的 N×M 复杂度**：`WHERE EXISTS (SELECT 1 FROM emp WHERE emp.dept_id = dept.dept_id)` 的字面执行是"对 dept 的每一行，扫一次 emp"。N 行 dept × M 行 emp = N×M 次比较。
2. **早停优化的丢失**：朴素实现需要内层完整跑完才能返回最终结果，无法利用 "Semi-Join 在第一个匹配后即可停止" 的特性。

而 Semi-Join / Anti-Join 算子有专用的执行路径：

- **哈希实现**：先用内层建立哈希表，外层逐行探测；探测命中（Semi）或未命中（Anti）即可立即决定是否输出。
- **排序合并实现**：双侧排序后线性扫描，遇到匹配/不匹配立即输出或丢弃。
- **嵌套循环实现**：仅在内层小或有索引时使用，但仍可早停。

总成本从 O(N×M) 降到 O(N+M)（哈希）或 O(N log N + M log M)（排序合并）。

**何时不该重写？** 罕见，但存在：

- **极小内层 + 极小外层**：嵌套循环可能更快，重写为哈希连接的代价反而更高。
- **内层有副作用**：标准 SQL 不允许，但部分方言允许 `SELECT FUNCTION_WITH_SIDE_EFFECT()` 在子查询中。
- **NOT IN + 不能保证非 NULL 的列**：3VL 语义下 Anti-Join 的等价改写需要额外的 NULL guard，开销不一定小（详见后文）。

## 没有 SQL 标准

ISO/IEC 9075 标准（最新版 SQL:2023）从未规定优化器必须把 `EXISTS` 改写为 Semi-Join，也从未定义 Semi-Join 或 Anti-Join 这两个名字本身。它只规定：

- `EXISTS` / `IN` / `NOT EXISTS` / `NOT IN` 的逻辑语义（包括 3VL 行为）
- 子查询去关联化是允许的（"等价改写"），但并非必需

"Semi-Join" 这个名字最早出自 1980 年代分布式数据库的论文（如 SDD-1），用来描述减少跨节点数据传输的优化技术：A SemiJoin B 等价于 A 投影到与 B 的连接键，传回 A 节点过滤。后来 Galindo-Legaria 在 1992 年 SIGMOD 论文中把它正式引入查询优化器作为通用代数算子。

在 ANSI SQL / ISO SQL 标准里，"Semi-Join" 至今**不是关键字**：没有任何方言支持 `SELECT ... FROM A SEMI JOIN B ...` 这种语法（注：Spark SQL 和 DuckDB 支持 `LEFT SEMI JOIN` 和 `LEFT ANTI JOIN` 作为方言扩展，本身不在标准内）。它纯粹是优化器内部代数算子，用户只能通过 `EXISTS` / `IN` 这种"高层 SQL"间接表达。

正因为没有标准，每个引擎对 Semi/Anti-Join 重写的支持范围、触发条件、是否可关闭都不一样：

- 触发条件：是否要求内层无聚合？是否要求关联谓词为等值？是否要求外层不空？
- 关闭方式：Oracle `NO_UNNEST` / SQL Server `OPTION (NO_UNNEST)` / PostgreSQL 无开关
- 算子名称：Oracle "HASH SJ"、SQL Server "Right Semi Join"、PostgreSQL "Hash Semi Join"、DuckDB "HASH_JOIN (Mark)"
- 失败回退：Oracle 回退为 FILTER 子查询、PostgreSQL 回退为 SubPlan、SQL Server 回退为 Apply

下文会逐一展开。

## 支持矩阵

下表覆盖 45+ 个常见 SQL 引擎在 6 个能力维度上的支持：

1. **EXISTS → Semi-Join**：是否能将 `EXISTS (...)` 重写为 Semi-Join 算子
2. **IN → Semi-Join**：是否能将 `IN (subquery)` 重写为 Semi-Join 算子
3. **NOT EXISTS → Anti-Join**：是否能将 `NOT EXISTS (...)` 重写为 Anti-Join 算子
4. **NOT IN → Anti-Join with NULL trap**：是否能在保证 3VL 正确性的前提下重写 `NOT IN (subquery)`
5. **Magic decorrelation**：是否支持 Galindo-Legaria 1992 风格的去关联化（针对带聚合的关联子查询）
6. **Flattening correlated subquery**：是否能拉平多层嵌套的关联子查询

| 引擎 | EXISTS→Semi | IN→Semi | NOT EXISTS→Anti | NOT IN→Anti (NULL 安全) | Magic decorrelation | 嵌套关联拉平 |
|------|------------|---------|-----------------|----------------------|---------------------|--------------|
| **PostgreSQL** | 是 | 是 | 是 | 是（生成 NULL guard） | 是 | 部分（multi-level 有限制） |
| **MySQL 8.0** | 是 | 是 | 是 (8.0.17+) | 部分（部分版本回退到 FILTER） | 部分 | 部分 |
| **MySQL 5.7** | 是 (5.6+) | 是 (5.6+) | -- | -- | -- | -- |
| **MariaDB** | 是 | 是 | 是 | 是 | 部分 | 部分 |
| **SQLite** | 是 (3.35+) | 是 | 是 (3.35+) | 部分 | -- | -- |
| **Oracle** | 是 | 是 | 是 | 是（NULL-aware Anti-Join）| 是（unnest 支持聚合） | 是 |
| **SQL Server** | 是 | 是 | 是 | 是（Anti-Semi-Apply） | 是 | 是 |
| **DB2** | 是 | 是 | 是 | 是 | 是 | 是 |
| **Snowflake** | 是 | 是 | 是 | 是 | 是 | 是 |
| **BigQuery** | 是 | 是 | 是 | 是 | 是 | 是 |
| **Redshift** | 是 | 是 | 是 | 是 | 部分 | 部分 |
| **DuckDB** | 是 | 是 | 是 | 是（Mark Join 处理 NULL） | 是（基于论文的通用 unnest） | 是 |
| **ClickHouse** | 是 (21.x+) | 是 | 是 | 部分（受限） | -- | -- |
| **Trino** | 是 | 是 | 是 | 是 | 是 | 是 |
| **Presto** | 是 | 是 | 是 | 是 | 是 | 部分 |
| **Spark SQL** | 是 | 是 | 是 | 是 | 是 (3.x) | 是 |
| **Hive 3.x** | 是 | 是 | 是 | 部分（依赖 Calcite） | 部分 | -- |
| **Flink SQL** | 是 | 是 | 是 | 部分 | -- | -- |
| **Databricks** | 是 | 是 | 是 | 是 | 是 | 是 |
| **Teradata** | 是 | 是 | 是 | 是 | 是 | 是 |
| **Greenplum** | 是 | 是 | 是 | 是 | 部分 | 部分 |
| **CockroachDB** | 是 | 是 | 是 | 是 | 是 | 部分 |
| **TiDB** | 是 | 是 | 是 | 是 | 部分 | 部分 |
| **OceanBase** | 是 | 是 | 是 | 是 | 是 | 是 |
| **YugabyteDB** | 是 | 是 | 是 | 是 | 是 | 部分 |
| **SingleStore** | 是 | 是 | 是 | 是 | 部分 | 部分 |
| **Vertica** | 是 | 是 | 是 | 是 | 是 | 部分 |
| **Impala** | 是 | 是 | 是 | 是 | 部分 | -- |
| **StarRocks** | 是 | 是 | 是 | 是 | 部分 | 部分 |
| **Doris** | 是 | 是 | 是 | 是 | 部分 | 部分 |
| **MonetDB** | 是 | 是 | 是 | 是 | 部分 | 部分 |
| **TimescaleDB** | 是 | 是 | 是 | 是 | 是 | 部分 |
| **CrateDB** | 部分 | 是 | 部分 | -- | -- | -- |
| **QuestDB** | -- | 是 | -- | -- | -- | -- |
| **Exasol** | 是 | 是 | 是 | 是 | 是 | 部分 |
| **SAP HANA** | 是 | 是 | 是 | 是 | 是 | 是 |
| **Informix** | 是 | 是 | 是 | 是 | 部分 | 部分 |
| **Firebird** | 是 | 是 | 是 | 部分 | -- | -- |
| **H2** | 部分 | 是 | 部分 | -- | -- | -- |
| **HSQLDB** | 是 | 是 | 是 | 部分 | -- | -- |
| **Derby** | 是 | 是 | 是 | 部分 | -- | -- |
| **DamengDB** | 是 | 是 | 是 | 是 | 是 | 是 |
| **KingbaseES** | 是 | 是 | 是 | 是 | 是 | 部分 |
| **openGauss** | 是 | 是 | 是 | 是 | 是 | 部分 |
| **GaussDB** | 是 | 是 | 是 | 是 | 是 | 是 |
| **MaxCompute** | 是 | 是 | 是 | 是 | 部分 | 部分 |
| **Athena** | 是 | 是 | 是 | 是 | 是 | 是 |
| **Azure Synapse** | 是 | 是 | 是 | 是 | 部分 | 部分 |
| **Calcite (框架)** | 是 | 是 | 是 | 是 | 是 | 是 |
| **ByConity** | 是 | 是 | 是 | 部分 | -- | -- |
| **Materialize** | 是 | 是 | 是 | 是 | 是 | 是 |
| **RisingWave** | 是 | 是 | 是 | 部分 | -- | -- |

> **统计**：约 45 个引擎能将 `EXISTS` / `IN` 重写为 Semi-Join；约 40 个引擎能将 `NOT EXISTS` 重写为 Anti-Join；约 30 个引擎能正确处理 `NOT IN` 的 NULL 陷阱（其余在内层包含 NULL 时回退到嵌套循环或返回不正确结果）；约 25 个引擎实现了 Galindo-Legaria 风格的 magic decorrelation（针对带聚合的关联子查询）。

> **图例说明**：
> - **是**：默认启用，用户无需任何配置即可触发
> - **部分**：受版本、配置或语法形式限制（例如只支持等值关联、不支持嵌套）
> - **--**：默认未实现，子查询执行为传统 FILTER / 嵌套循环

### 各方言的算子命名

实际触发后，EXPLAIN 输出中你会看到不同的算子名称。这对调试至关重要：

| 引擎 | Semi-Join 算子名 | Anti-Join 算子名 | 备注 |
|------|----------------|-----------------|------|
| **PostgreSQL** | `Hash Semi Join` / `Nested Loop Semi Join` / `Merge Semi Join` | `Hash Anti Join` / `Nested Loop Anti Join` / `Merge Anti Join` | EXPLAIN 输出明确 |
| **MySQL 8.0** | `Semijoin` (FirstMatch / LooseScan / Materialization) | `Antijoin` | 5 种 Semi-Join 策略 |
| **Oracle** | `HASH JOIN SEMI` / `NESTED LOOPS SEMI` / `MERGE JOIN SEMI` | `HASH JOIN ANTI` / `NESTED LOOPS ANTI` / `HASH JOIN ANTI NA` | "NA" = NULL Aware |
| **SQL Server** | `Hash Match (Right Semi Join)` / `Nested Loops (Left Semi Join)` | `Hash Match (Right Anti Semi Join)` / `Nested Loops (Left Anti Semi Join)` | "Apply" 是物理算子 |
| **DB2** | `HSJOIN (S)` / `MSJOIN (S)` / `NLJOIN (S)` | `HSJOIN (A)` / `MSJOIN (A)` / `NLJOIN (A)` | 内部代码 |
| **DuckDB** | `HASH_JOIN (LEFT_SEMI / RIGHT_SEMI / MARK)` | `HASH_JOIN (LEFT_ANTI / RIGHT_ANTI)` | Mark Join 是核心 |
| **Spark SQL** | `BroadcastHashJoin (LeftSemi)` / `SortMergeJoin (LeftSemi)` | `BroadcastHashJoin (LeftAnti)` / `SortMergeJoin (LeftAnti)` | Catalyst 优化器 |
| **Trino** | `SemiJoin` (Distributed / Local) | `SemiJoin (Anti)` 或 `LookupOuterJoin` | 多种执行模式 |
| **ClickHouse** | `JoinExpression (LEFT SEMI)` | `JoinExpression (LEFT ANTI)` | 21.x 后支持 |
| **TiDB** | `HashJoin (semi)` / `IndexJoin (semi)` | `HashJoin (anti)` / `IndexJoin (anti)` | 类 PostgreSQL EXPLAIN |
| **CockroachDB** | `lookup join (semi)` / `merge join (semi)` | `lookup join (anti)` / `merge join (anti)` | - |

### 各方言的关闭/控制开关

引擎开发者和 DBA 调试时常需要关闭重写以观察基准行为：

| 引擎 | 关闭 Semi-Join 重写 | 关闭 Anti-Join 重写 | 备注 |
|------|--------------------|---------------------|------|
| **Oracle** | `/*+ NO_UNNEST */` 提示 | `/*+ NO_UNNEST */` 提示 | 还有 `NO_QUERY_TRANSFORMATION` |
| **SQL Server** | `OPTION (LOOP JOIN)` 强制 NL | `OPTION (NO_PERFORMANCE_SPOOL)` | 也可禁用 `QueryRules` |
| **PostgreSQL** | `set enable_hashjoin = off` | 同左 | `enable_hashjoin` 同时控制 anti/semi join |
| **MySQL** | `SET optimizer_switch = 'semijoin=off'` | `SET optimizer_switch = 'antijoin=off'` | 8.0.17+ |
| **DuckDB** | 暂无开关 | 暂无开关 | 内部强制使用 Mark Join |
| **Spark SQL** | 配置 `spark.sql.optimizer.excludedRules` | 同左 | 排除 `RewritePredicateSubquery` |
| **Trino** | 配置 `optimizer.rewrite-filtering-semi-join-to-inner-join=false` | 类似配置 | - |
| **TiDB** | `SET tidb_opt_insubq_to_join_and_agg=0` | 类似 | - |
| **OceanBase** | `/*+ NO_UNNEST */` | 同左 | 类 Oracle 提示 |

## 各引擎重写细节

下面分引擎深入展开重写算法、限制和典型 EXPLAIN 形态。

### PostgreSQL：早期就有的子查询 pull-up

PostgreSQL 的子查询展开（subquery pull-up）从 8.x 时代就支持 `EXISTS` 和 `NOT EXISTS` 的去关联化，经过 9.x、10.x 的持续优化，目前已经是最成熟的开源实现之一。

```sql
-- 原始查询
EXPLAIN (COSTS OFF)
SELECT * FROM dept d
WHERE EXISTS (SELECT 1 FROM emp e WHERE e.dept_id = d.dept_id);

-- 输出
Hash Semi Join
   Hash Cond: (d.dept_id = e.dept_id)
   ->  Seq Scan on dept d
   ->  Hash
         ->  Seq Scan on emp e
```

PostgreSQL 在 `subquery_planner()` 阶段调用 `convert_EXISTS_sublink_to_join()` 函数完成该转换。核心代码路径（`src/backend/optimizer/plan/subselect.c`）：

```
convert_EXISTS_sublink_to_join():
  1. 检查内层子查询是否是 SELECT 子句（其他类型不可拉平）
  2. 检查 WHERE 子句中的关联条件是否可以提升到外层 JOIN ON
  3. 创建一个 RangeTblEntry 包装内层
  4. 在外层 jointree 中插入 JoinExpr，jointype = JOIN_SEMI
  5. 移除原 SubLink 节点
```

`NOT EXISTS` 走的是 `convert_ANY_sublink_to_join()` 的 anti 分支，结果是 `JOIN_ANTI`。

PostgreSQL 还能处理 `IN (subquery)` 和 `NOT IN (subquery)`：

```sql
-- IN 子查询
SELECT * FROM dept WHERE dept_id IN (SELECT dept_id FROM emp);

-- 重写为
SELECT d.* FROM dept d SEMI JOIN emp e ON d.dept_id = e.dept_id;
-- 注意：内层不需要 DISTINCT，因为 SEMI JOIN 自然只输出外层每行一次
```

```sql
-- NOT IN 子查询（仅当列声明为 NOT NULL 或被优化器证明非 NULL 时）
SELECT * FROM dept WHERE dept_id NOT IN (SELECT dept_id FROM emp);

-- 当 emp.dept_id 为 NOT NULL 时，重写为
SELECT d.* FROM dept d ANTI JOIN emp e ON d.dept_id = e.dept_id;

-- 当 emp.dept_id 可空时，PostgreSQL 不能简单重写为 ANTI JOIN
-- 而是回退到 SubPlan + 显式 NULL 检查（性能差很多）
```

PostgreSQL 14 起引入更激进的 NULL-aware Anti-Join，用 `Hash Anti Join` 配合一个 NOT NULL filter，避免回退到 SubPlan。

**关键参数**：

- `enable_hashjoin = off`：会同时禁用 hash semi/anti join，迫使优化器走 nested loop 或 merge 形式
- `enable_mergejoin = off`：禁用 merge semi/anti join
- `from_collapse_limit = 8`：控制能拉平多少层子查询；设太低会导致深层关联子查询无法去关联化
- `join_collapse_limit = 8`：类似上面，但控制显式 JOIN 的合并

**EXPLAIN 中的 SubPlan**：

```
->  Seq Scan on dept d
      Filter: (NOT (SubPlan 1))
      SubPlan 1
        ->  Seq Scan on emp e
              Filter: (e.dept_id = d.dept_id)
```

看到 `SubPlan` 就意味着重写**没有发生**——这是性能问题的强烈信号。常见原因：内层有聚合且非简单形式、关联条件包含函数、外层是非 SELECT 语句的某种特殊位置。

### Oracle："unnest" 提示与 NULL-aware Anti-Join

Oracle 是历史最长、最成熟的子查询重写实现之一。它把这个过程称为 "subquery unnesting"，可以通过 `/*+ UNNEST */` 和 `/*+ NO_UNNEST */` 提示精确控制。

```sql
-- 显式提示重写（即使代价模型本不愿意）
SELECT /*+ UNNEST */ *
FROM dept d
WHERE EXISTS (SELECT 1 FROM emp e WHERE e.dept_id = d.dept_id);

-- 显式禁止重写（用于对比测试）
SELECT /*+ NO_UNNEST */ *
FROM dept d
WHERE EXISTS (SELECT 1 FROM emp e WHERE e.dept_id = d.dept_id);
```

EXPLAIN 输出的算子名为 `HASH JOIN SEMI` / `MERGE JOIN SEMI` / `NESTED LOOPS SEMI`：

```
| Id | Operation             | Name | Rows | Bytes | Cost |
|  0 | SELECT STATEMENT      |      |      |       |      |
|  1 |  HASH JOIN SEMI       |      |  100 |  3000 |   12 |
|  2 |   TABLE ACCESS FULL   | DEPT |  100 |  2000 |    3 |
|  3 |   TABLE ACCESS FULL   | EMP  | 1000 | 12000 |    8 |
```

**Oracle NOT IN NULL anomaly handling**：

Oracle 对 `NOT IN` 的 NULL 处理是所有引擎里最讲究的。它定义了三种 Anti-Join 变体：

1. **HASH JOIN ANTI**：当列声明为 NOT NULL 时使用，性能最好
2. **HASH JOIN ANTI NA**（NA = Null Aware）：当列可空时使用，需要在内层先检测是否存在 NULL；若存在则整体返回空（符合 3VL 语义）
3. **HASH JOIN ANTI SNA**（SNA = Single Null Aware）：当只有一列需要 NULL 检查时的优化

```sql
-- 列声明为 NOT NULL
ALTER TABLE emp MODIFY (dept_id NOT NULL);

EXPLAIN PLAN FOR
SELECT * FROM dept d
WHERE d.dept_id NOT IN (SELECT e.dept_id FROM emp e);
-- 算子: HASH JOIN ANTI（不需要 NULL 检查）

-- 列可空
ALTER TABLE emp MODIFY (dept_id NULL);

EXPLAIN PLAN FOR
SELECT * FROM dept d
WHERE d.dept_id NOT IN (SELECT e.dept_id FROM emp e);
-- 算子: HASH JOIN ANTI NA（先扫描内层是否有 NULL）
```

Oracle 12c 起还引入了 `ANTI_NA` 的延迟检测：在执行哈希探测时一边构建一边检测 NULL，避免单独的预扫描。

**Oracle 的 magic decorrelation**：

Oracle 是首个完整实现 Galindo-Legaria 算法的商业数据库。它能处理带聚合的关联子查询，比如：

```sql
-- 带聚合的关联子查询
SELECT *
FROM emp e
WHERE e.salary > (SELECT AVG(e2.salary) FROM emp e2 WHERE e2.dept_id = e.dept_id);

-- Oracle unnest 后改写为：
SELECT e.*
FROM emp e,
     (SELECT dept_id, AVG(salary) AS avg_sal FROM emp GROUP BY dept_id) g
WHERE e.dept_id = g.dept_id AND e.salary > g.avg_sal;
```

这是 magic 重写的核心：识别出关联谓词 `e2.dept_id = e.dept_id` 实际上是 `dept_id` 的等值关联，因此可以把内层改写为按 `dept_id` 分组的聚合，外层与之 JOIN。这一步把 N×M 的代价降到 N+M。

### SQL Server：查询优化器的 anti-semi-apply

SQL Server 的查询优化器（QO）通过 "Apply" 物理算子统一处理子查询。Apply 是一个表值函数式的算子：对外层每行，把外层列绑定到内层后执行内层。

但 SQL Server 不会停在 Apply：它的 `Optimizer.Transformations` 库里有一系列 "Apply Decorrelation Rules"，会把 `Left Semi Apply` / `Left Anti Semi Apply` 重写为更高效的 Hash Match 或 Merge Join：

```sql
-- 原始查询
SELECT * FROM dept d
WHERE EXISTS (SELECT 1 FROM emp e WHERE e.dept_id = d.dept_id);

-- 朴素执行计划（如果不重写）：
-- Filter
--    Left Semi Apply
--       Clustered Index Scan (dept)
--       Index Seek (emp WHERE dept_id = @d.dept_id)

-- 重写后：
-- Hash Match (Right Semi Join, HASH:([d.dept_id])=([e.dept_id]))
--    Clustered Index Scan (dept)
--    Clustered Index Scan (emp)
```

`NOT EXISTS` 的算子名是 `Hash Match (Right Anti Semi Join)`：

```sql
SELECT * FROM dept d
WHERE NOT EXISTS (SELECT 1 FROM emp e WHERE e.dept_id = d.dept_id);

-- 执行计划：
-- Hash Match (Right Anti Semi Join)
--    Clustered Index Scan (dept)
--    Clustered Index Scan (emp)
```

**SQL Server 的 NOT IN NULL 处理**：

SQL Server 的优化器会自动检测 `NOT IN` 的 NULL 风险。如果内层列声明为 NOT NULL，则可以直接用 Anti Semi Join。否则它会插入一个 NULL guard：

```
-- NOT NULL 列：
SELECT * FROM dept WHERE dept_id NOT IN (SELECT dept_id FROM emp);
-- 直接 Anti Semi Join

-- 可空列：
SELECT * FROM dept WHERE dept_id NOT IN (SELECT dept_id FROM emp);
-- 重写为复杂形式（伪代码）：
-- 1. 检测 emp 是否有 NULL，如有则返回空
-- 2. 否则做 Anti Semi Join
```

SQL Server 的优化器有一个完整的 `OptimizerRules` 类目录，相关规则：

- `DecorrelateApply`：从 Apply 转为可去关联化的形式
- `RemoveSemiJoinApply`：把 Semi Apply 重写为 Semi Join
- `RemoveAntiSemiJoinApply`：把 Anti Semi Apply 重写为 Anti Semi Join
- `MagicDecorrelation`：处理带聚合的关联子查询

可以通过 `SET STATISTICS XML ON` 看到完整的物理算子树和应用过的规则。

### MySQL 8.0：subquery rewriter

MySQL 在 5.6 之前对子查询的支持非常有限：很多关联子查询会强制走 "DEPENDENT SUBQUERY"，即对外层每一行重新执行一次内层。这是 MySQL 早期被诟病子查询性能差的根本原因。

5.6 引入了 Semi-Join 重写，主要针对 `IN` 和 `EXISTS`：

```sql
SELECT * FROM dept WHERE dept_id IN (SELECT dept_id FROM emp);

-- EXPLAIN：
-- 1 SIMPLE  dept    ALL  ...
-- 1 SIMPLE  emp     ref  ...
-- type 列: 'eq_ref' 或 'ref'，并且 Extra 列出现 "Using semi-join"
```

8.0.17 引入 Anti-Join 重写。在此之前，`NOT EXISTS` 和 `NOT IN` 都走 SubPlan（DEPENDENT SUBQUERY），性能很差。8.0.17+：

```sql
SELECT * FROM dept WHERE NOT EXISTS (SELECT 1 FROM emp WHERE emp.dept_id = dept.dept_id);

-- EXPLAIN 8.0.17+:
-- "Using anti-join"
```

MySQL 的 Semi-Join 有 5 种执行策略（在 EXPLAIN FORMAT=TREE 中可见）：

1. **FirstMatch**：找到第一个匹配即跳到下一外层行，类似 LATERAL + LIMIT 1
2. **LooseScan**：要求内层有可用索引，跳跃式扫描
3. **Materialization**：物化内层为去重临时表，再 Inner Join
4. **DuplicateWeedout**：用 ROW_ID 在外层去重
5. **Table Pull-out**：内层只有一个表时直接合并到外层 FROM

```
optimizer_switch 控制开关：
  semijoin=on / off
  firstmatch=on / off
  loosescan=on / off
  materialization=on / off
  duplicateweedout=on / off
  antijoin=on / off  (8.0.17+)
```

**典型问题**：

- `optimizer_switch='semijoin=off'`：所有 Semi-Join 重写关闭，`IN` 退化为 SubPlan，性能可能差 100 倍
- 子查询包含 `LIMIT`：MySQL 8.0 之前不能去关联化（因为 LIMIT 改变语义）
- 子查询使用 `UNION`：不能去关联化

### ClickHouse：限制较多的子查询支持

ClickHouse 的 SQL 子查询支持长期是短板。早期版本（19.x、20.x）对 `IN` 的实现是把内层物化为一个 SET，外层用 SET 探测——这本身已经等价于 Semi-Join，但只支持非关联子查询。

21.x 起，ClickHouse 引入了对关联子查询的有限支持：

```sql
-- ClickHouse 21.x+ 支持
SELECT * FROM dept WHERE dept_id IN (SELECT dept_id FROM emp);
-- EXPLAIN: 内层物化为 Set，外层 IndexFilter

-- ClickHouse 22.x+ 支持简单 EXISTS
SELECT * FROM dept WHERE EXISTS (SELECT 1 FROM emp WHERE emp.dept_id = dept.dept_id);
-- EXPLAIN: JoinExpression (LEFT SEMI)
```

**限制**：

- 嵌套关联子查询通常不支持，会报 "Unsupported subquery type"
- 内层包含聚合的关联子查询（即 magic decorrelation 场景）支持有限
- `NOT IN` 的 NULL 安全处理在某些版本是 bug-prone 的（社区有多个相关 issue）

ClickHouse 团队选择把精力放在实时分析的物化视图、列存压缩等方向，子查询优化优先级较低。这与它的设计哲学一致：鼓励用户提前用 ETL 把复杂查询打平，而非依赖优化器重写。

### Spark Catalyst：SubqueryAlias 重写

Spark SQL 的 Catalyst 优化器把子查询表示为 `SubqueryExpression` 的几种子类：`ScalarSubquery` / `Exists` / `InSubquery` / `LateralSubquery`。重写规则集中在 `RewritePredicateSubquery` 中（`org.apache.spark.sql.catalyst.optimizer.RewritePredicateSubquery`）。

```scala
// Catalyst 规则伪代码
RewritePredicateSubquery: Rule[LogicalPlan] = {
  case Filter(condition, child) =>
    val (withSubquery, withoutSubquery) =
      splitConjunctivePredicates(condition).partition(SubqueryExpression.hasInOrCorrelatedExistsSubquery)

    val newFilter = withSubquery.foldLeft(child) {
      case (p, Exists(sub, conditions, _, _)) =>
        Join(p, sub, LeftSemi, conditions.reduceOption(And), JoinHint.NONE)
      case (p, Not(Exists(sub, conditions, _, _))) =>
        Join(p, sub, LeftAnti, conditions.reduceOption(And), JoinHint.NONE)
      case (p, InSubquery(values, ListQuery(sub, conditions, _, _, _))) =>
        Join(p, sub, LeftSemi, joinCond(values, sub.output, conditions), JoinHint.NONE)
      case (p, Not(InSubquery(values, ListQuery(sub, conditions, _, _, _)))) =>
        // NULL 安全处理：包装为 Filter + LeftAnti
        ...
    }
    // 应用剩余非子查询条件
    if (withoutSubquery.nonEmpty)
      Filter(withoutSubquery.reduce(And), newFilter)
    else newFilter
}
```

执行计划中可见 `LeftSemi` / `LeftAnti` 关键字：

```
== Physical Plan ==
*(2) BroadcastHashJoin [dept_id#0], [dept_id#5], LeftSemi, BuildRight
:- *(2) FileScan parquet dept[dept_id#0]
+- BroadcastExchange HashedRelationBroadcastMode(List(input[0, int, true]))
   +- *(1) FileScan parquet emp[dept_id#5]
```

Spark 还有专门处理带聚合关联子查询的 `RewriteCorrelatedScalarSubquery` 和 `PullupCorrelatedPredicates` 规则。3.x 系列改进了去关联化对 LATERAL 的支持。

**特殊点**：

- Spark 默认会把小内层广播（`BroadcastHashJoin`），大内层走 `SortMergeJoin (LeftSemi)`
- 跨 stage 的 Anti-Join 在数据倾斜时有性能陷阱
- AQE（Adaptive Query Execution）会动态调整 Semi/Anti-Join 的实现策略

### Trino：RewriteCorrelatedSubquery

Trino（前 Presto SQL）的优化器规则在 `io.trino.sql.planner.iterative.rule` 包下，相关的 Semi/Anti-Join 重写规则有：

- `TransformExistsApplyToCorrelatedJoin`：把 EXISTS 子查询转为 CorrelatedJoin
- `TransformCorrelatedJoinToJoin`：把 CorrelatedJoin 进一步重写为 Join（在能去关联化时）
- `TransformCorrelatedScalarSubquery`：处理标量子查询
- `TransformQuantifiedComparisonApplyToCorrelatedJoin`：处理 ANY / ALL
- `RewriteSpatialPartitioningAggregation`：空间相关
- `ImplementBernoulliSampleAsFilter`：采样相关（不属于本主题）

Trino 的去关联化算法在 `DecorrelateInnerUnnestWithGlobalAggregation` 里实现，能处理嵌套关联：

```sql
-- 嵌套关联子查询
SELECT *
FROM r
WHERE EXISTS (
    SELECT 1 FROM s
    WHERE s.r_id = r.id
    AND s.x > (SELECT AVG(t.x) FROM t WHERE t.s_id = s.id)
);

-- Trino 能拉平为多层 Join + GroupBy
```

执行计划中算子名为 `SemiJoin`（不区分 Semi 和 Anti，看 `filter` 字段）：

```
SemiJoin[r_id = s_id]
   TableScan (r)
   TableScan (s)
```

Trino 还有一个 `SimplifyExpressions` 规则，会把 `IS NOT NULL` 推下去帮助优化器更精确地推断 NOT IN 的 NULL 性。

### DB2：成熟的 unnest

IBM DB2 与 Oracle 一样，是最早商业化的 SQL 引擎之一，子查询重写能力非常成熟。算子名前缀 `HSJOIN` (Hash Star Join) 配合 `(S)` / `(A)` 后缀表示 Semi / Anti：

```
RETURN
  HSJOIN (S) Hash Semi Join
    TBSCAN dept
    TBSCAN emp
```

DB2 的 `db2expln` 工具和 `EXPLAIN` 视图能展示重写细节，包括所有应用过的优化规则。`db2_optimizer_messages` 系统表保留了重写决策的记录。

### DuckDB：基于论文的通用 unnest

DuckDB 实现了 [Neumann & Kemper 2015 论文](http://www.btw-2015.de/res/proceedings/Hauptband/Wiss/Neumann-Unnesting_Arbitrary_Querie.pdf) 的 "Unnesting Arbitrary Queries" 算法，是开源数据库中第一个实现这种通用去关联化的。该算法基于 "Mark Join"——一个特殊的 Join 算子，对外层每行额外标记一列布尔值表示 Join 结果。

```sql
SELECT * FROM dept d
WHERE EXISTS (SELECT 1 FROM emp e WHERE e.dept_id = d.dept_id);

-- DuckDB EXPLAIN
-- ┌─────────────┐
-- │   PROJECTION│
-- └──────┬──────┘
-- ┌──────┴──────┐
-- │  HASH_JOIN  │
-- │   (MARK)    │
-- └──┬───────┬──┘
--    │       │
-- (dept)  (emp)
```

Mark Join 的好处是它**统一处理 Semi / Anti / 标量子查询 / 嵌套关联**：

- Semi-Join = Mark Join + Filter (mark = TRUE)
- Anti-Join = Mark Join + Filter (mark = FALSE OR mark IS NULL)
- 标量子查询 = Mark Join + Aggregation
- 嵌套关联 = 多层 Mark Join 嵌套

NULL 处理：Mark Join 的输出列是 TRUE / FALSE / NULL 三态，自然对应 SQL 3VL：

```
Mark Join 输出表（伪代码）：
外层值     |  Mark
---------+--------
1        |  TRUE   -- 至少一个匹配
2        |  FALSE  -- 无匹配且无 NULL
3        |  NULL   -- 无匹配但内层有 NULL
```

`NOT IN` 在 DuckDB 中天然安全：`Mark IS DISTINCT FROM TRUE` 自动处理 NULL 案例。

### MariaDB

MariaDB 的子查询重写继承自 MySQL 早期，但在 10.0 之后由 Igor Babaev 重写了优化器子查询模块，引入了完整的 Semi-Join、Anti-Join、Materialization 策略。在某些场景下重写能力优于同期的 MySQL 5.7。

`optimizer_switch` 设置类似 MySQL：

```
SET optimizer_switch =
  'semijoin=on,materialization=on,firstmatch=on,loosescan=on,'
  'subquery_cache=on,subquery_to_in_subq=on';
```

`subquery_to_in_subq` 是 MariaDB 独有：把某些标量子查询转为 IN 子查询，再交给 Semi-Join 重写。

### TiDB / OceanBase / 国产 MySQL 兼容

国产 SQL 引擎大多基于 PostgreSQL 或 MySQL 协议，其子查询重写能力依赖于继承的优化器代码 + 各自的增强：

- **TiDB**：基于 Calcite 论文实现，自研 SQL 优化器。Semi/Anti-Join 重写完整支持。`tidb_opt_insubq_to_join_and_agg` 控制 `IN` 子查询是否转为 Join + Agg；默认开启。
- **OceanBase**：双模式（MySQL/Oracle 兼容），子查询重写借鉴 Oracle，包括 `/*+ NO_UNNEST */` 提示。OB 4.x 重写了优化器，支持完整 magic decorrelation。
- **DamengDB / KingbaseES / openGauss / GaussDB**：均基于 PostgreSQL 衍生，继承 PostgreSQL 的子查询展开能力，部分国产化数据库还增加了 Oracle 风格的提示语法。

### CockroachDB

CockroachDB 用 `optgen`（一种内部 DSL）生成优化规则代码。Semi/Anti-Join 重写规则在 `pkg/sql/opt/norm/rules/scalar.opt` 和 `pkg/sql/opt/xform/rules/select.opt` 中定义：

```
[InlineCorrelatedSubquery, Normalize]
(Filter $input:* $filters:* & (HasCorrelatedSubquery $filters))
=>
(Apply $input $filters)

[DecorrelateExistsToSemiJoin, Normalize]
(Apply $left:* (Project $right:* (ConstructProjections $right)) ...)
=>
(SemiJoin $left $right ...)
```

EXPLAIN 输出可见 `lookup join (semi)` / `merge join (anti)` 等。CockroachDB 的分布式执行让 Semi-Join 在跨节点数据传输上有专门的优化（类似 SDD-1 论文的 Bloom filter）。

### 其他云数仓与 MPP

- **Snowflake**：从早期版本就有完整的子查询去关联化，包括 magic decorrelation。EXPLAIN 中算子名为 `LeftSemiJoin` / `LeftAntiJoin`。Snowflake 的优化器决策不暴露给用户调整。
- **BigQuery**：Dremel 早期对子查询支持很差，后期重写了 SQL 引擎，目前能完整重写 EXISTS / IN / NOT EXISTS / NOT IN。EXPLAIN 中算子名为 `Semi-Hash-Join` / `Anti-Hash-Join`。
- **Redshift**：基于 ParAccel（PostgreSQL 8.x 衍生），继承了 PostgreSQL 的 pull-up 能力。但因为是列存 MPP，Semi-Join 实现以 broadcast hash 为主。
- **Vertica**：MPP 列存数据库，Semi/Anti-Join 是核心算子，EXPLAIN 中名为 `[Semi]` / `[Anti]`。
- **Databricks / SAP HANA / Teradata**：均有完整支持，且实现质量与 Oracle / DB2 相当。
- **Materialize**：增量物化视图引擎，Semi/Anti-Join 在 dataflow 中有专门的增量算子实现。
- **RisingWave**：流处理 SQL 引擎，对 NOT IN 的 NULL 处理在某些场景仍有限制。

## NOT IN 的 NULL 陷阱：3VL 危害深度剖析

`NOT IN` + 内层包含 NULL 是 SQL 中最危险也最被低估的陷阱，没有之一。它的危险在于**语义在所有方言上都一样不直观**，但优化器是否能正确处理它**在不同方言上差异很大**。

### 3VL 语义

SQL 用三值逻辑（Three-Valued Logic, 3VL），即每个布尔表达式可能取 TRUE / FALSE / UNKNOWN（即 NULL）三种值之一。`WHERE` 子句只保留 TRUE 的行——FALSE 和 UNKNOWN 都被丢弃。

```sql
-- 重要陷阱：
30 NOT IN (10, 20)        -- TRUE
30 NOT IN (10, 20, NULL)  -- UNKNOWN（不是 TRUE！）

-- 等价展开：
30 NOT IN (10, 20, NULL)
  ≡ NOT (30 IN (10, 20, NULL))
  ≡ NOT (30 = 10 OR 30 = 20 OR 30 = NULL)
  ≡ NOT (FALSE OR FALSE OR UNKNOWN)
  ≡ NOT (UNKNOWN)
  ≡ UNKNOWN
```

实际后果：

```sql
-- 假设 emp.dept_id 中有一行是 NULL
SELECT dept_id FROM emp;
-- 10
-- 20
-- 30
-- NULL

-- 期望：返回所有不在 emp 中的部门
SELECT * FROM dept WHERE dept_id NOT IN (SELECT dept_id FROM emp);
-- 实际：空集！
-- 即使 dept 有 dept_id=99 的行，也不会返回，
-- 因为 99 NOT IN (10, 20, 30, NULL) = UNKNOWN
```

这个陷阱在生产代码中极其常见。一个 24/7 跑了几年的 ETL 突然有一天因为上游表多了一行 NULL 就变成空结果——这种 bug 很难调试，因为数据库不会报错。

### 各引擎的处理策略

**正确处理（NULL-aware Anti-Join）**：

| 引擎 | 算子 | 实现 |
|------|------|------|
| Oracle | `HASH JOIN ANTI NA` | 预扫描内层，发现 NULL 即标记，最终匹配时三态判定 |
| SQL Server | `Hash Match (Right Anti Semi Join)` + NULL guard | 优化器插入 EXISTS 检查 NULL |
| PostgreSQL 14+ | `Hash Anti Join` + NULL filter | 重写时插入 NOT NULL 过滤 |
| DuckDB | `HASH_JOIN (MARK)` 三态 | Mark Join 输出 TRUE/FALSE/NULL 三态自然处理 |
| Snowflake | NULL-aware Anti-Join | 内部实现细节不公开 |
| BigQuery | Anti-Hash-Join + NULL guard | 类似 SQL Server |
| DB2 | NLJOIN (A) + NULL filter | 同 SQL Server |
| Spark Catalyst | LeftAnti + NOT NULL filter | 显式重写 |

**回退到嵌套循环（性能差但正确）**：

| 引擎 | 行为 |
|------|------|
| MySQL 8.0.16- | NOT IN 子查询不能去关联化，走 DEPENDENT SUBQUERY |
| SQLite 3.35- | 同上，回退到 SubPlan |
| ClickHouse 早期 | 物化为 Set，扫描时三态判定，但部分版本有 bug |

**有正确性 bug 的方言**（历史上）：

历史上 MySQL 5.x、ClickHouse 早期、Hive 1.x 都有过 NOT IN + NULL 的正确性问题。这是 SQL 标准要求与优化器自动重写之间最棘手的交互——重写时必须保持 3VL 语义不变。

### 安全替代

对于跨数据库迁移或写防御性 SQL，最佳实践是**永远避免 NOT IN 子查询**，改用 NOT EXISTS：

```sql
-- 不推荐
SELECT * FROM dept d
WHERE d.dept_id NOT IN (SELECT e.dept_id FROM emp e);

-- 推荐：NOT EXISTS 永远不踩 NULL 陷阱
SELECT * FROM dept d
WHERE NOT EXISTS (
    SELECT 1 FROM emp e WHERE e.dept_id = d.dept_id
);
```

`NOT EXISTS` 的语义是 "内层返回 0 行"，与 NULL 无关——内层有 NULL 行时，只要关联条件不匹配就视为不返回。所以 `NOT EXISTS` 永远遵循直觉。

另一种方案是在子查询中显式排除 NULL：

```sql
SELECT * FROM dept
WHERE dept_id NOT IN (
    SELECT dept_id FROM emp WHERE dept_id IS NOT NULL
);
```

这样可以让所有引擎都安全地走 Anti-Join，但要求开发者每次都记得加 `IS NOT NULL`，容易遗漏。

### EXISTS 与 NOT IN 的语义差异（NULL 视角）

```sql
-- EXISTS 表：dept_id, has_match
SELECT d.dept_id, EXISTS(SELECT 1 FROM emp e WHERE e.dept_id = d.dept_id) AS m
FROM dept d;
-- 结果只有 TRUE / FALSE，从不是 NULL

-- IN 表：dept_id, is_in
SELECT d.dept_id, d.dept_id IN (SELECT e.dept_id FROM emp e) AS i
FROM dept d;
-- 结果可能是 TRUE / FALSE / NULL（如果内层有 NULL 且不匹配）
```

这一差异是为什么 `EXISTS` 在重写时永远是简单的 Semi-Join，而 `IN` 需要考虑 NULL。引擎实现者应该把这两条路径分开维护，避免共用代码导致 NULL 处理混淆。

## Magic Decorrelation：Galindo-Legaria 1992

最难的子查询去关联化场景是**带聚合的关联子查询**。例：

```sql
-- 找出薪资高于本部门平均薪资的员工
SELECT e.*
FROM emp e
WHERE e.salary > (
    SELECT AVG(e2.salary)
    FROM emp e2
    WHERE e2.dept_id = e.dept_id
);
```

朴素执行：对 emp 每行重新跑一次内层聚合 = N×M。N=10万 时已经无法接受。

朴素的"拉平"行不通，因为聚合改变了基数。如果直接重写为：

```sql
-- 错误的拉平
SELECT e.*
FROM emp e JOIN emp e2 ON e2.dept_id = e.dept_id
WHERE e.salary > AVG(e2.salary);  -- 错误：AVG 在哪里 group？
```

Galindo-Legaria 在 1992 年 SIGMOD 论文 *Outerjoins as Disjunctions* 和后续相关工作中提出了完整的算法（业内俗称 "magic decorrelation"），核心步骤：

1. **识别关联谓词**：找出内层引用外层的等值条件 `e2.dept_id = e.dept_id`
2. **识别为 group key**：把关联列 `e2.dept_id` 提升为内层聚合的 GROUP BY 键
3. **聚合内层**：把内层改写为 `SELECT dept_id, AVG(salary) FROM emp GROUP BY dept_id`
4. **外层 JOIN**：外层与改写后的聚合结果做 JOIN
5. **应用过滤**：在 JOIN 后施加 `e.salary > avg_sal`

最终：

```sql
SELECT e.*
FROM emp e
JOIN (
    SELECT dept_id, AVG(salary) AS avg_sal
    FROM emp
    GROUP BY dept_id
) g ON g.dept_id = e.dept_id
WHERE e.salary > g.avg_sal;
```

代价从 O(N×M) 降到 O(N + M log M)（按 dept_id 排序聚合）或 O(N + M)（哈希聚合）。

### 为什么叫 "magic"？

这一变换在最早的几个数据库（System R、Ingres）里看起来"魔法般"地把关联子查询变没了，故名 magic decorrelation。后来在 SQL Server 文档里这个名字被沿用，Oracle 优化器内部代号也类似。

Galindo-Legaria（当时在 Microsoft）的主要贡献是给出了**通用框架**：

- 不只是 AVG，所有聚合都能这么改写
- 不只是单表内层，多表 JOIN 内层也能
- 多层嵌套时可以递归应用

### 拓展场景

**HAVING 子句中的关联子查询**：

```sql
SELECT dept_id, COUNT(*)
FROM emp
GROUP BY dept_id
HAVING COUNT(*) > (
    SELECT AVG(cnt) FROM (
        SELECT COUNT(*) AS cnt FROM emp GROUP BY dept_id
    ) t
);
```

这种"按部门计数 > 全局平均部门计数"的查询需要两层聚合，magic decorrelation 处理后变为 CTE + 单次扫描。

**多列关联**：

```sql
SELECT *
FROM order_items oi
WHERE oi.price = (
    SELECT MAX(price)
    FROM order_items
    WHERE order_id = oi.order_id AND product_category = oi.product_category
);
```

把 `(order_id, product_category)` 作为 GROUP BY 键，重写为 JOIN。

**带常量条件**：

```sql
SELECT *
FROM emp e
WHERE e.salary > (
    SELECT AVG(salary) FROM emp WHERE dept_id = e.dept_id AND start_date > '2020-01-01'
);
```

`start_date > '2020-01-01'` 是非关联的常量条件，可以直接保留在内层 WHERE：

```sql
SELECT e.*
FROM emp e JOIN (
    SELECT dept_id, AVG(salary) AS avg_sal
    FROM emp WHERE start_date > '2020-01-01'
    GROUP BY dept_id
) g ON g.dept_id = e.dept_id
WHERE e.salary > g.avg_sal;
```

### 引擎支持现状

实现 Galindo-Legaria 风格 magic decorrelation 的引擎：

- **Oracle**：从 8i 起逐步完善，目前最成熟
- **SQL Server**：从 2005 起完整支持，命名为 "Apply Decorrelation Rules"
- **DB2**：从 V8 起支持
- **PostgreSQL**：从 11+ 开始有限支持，但仍有边界场景回退到 SubPlan
- **DuckDB**：基于 Neumann/Kemper 论文，比 Galindo-Legaria 更通用
- **Spark Catalyst**：3.x 起支持，规则名 `RewriteCorrelatedScalarSubquery` + `PullupCorrelatedPredicates`
- **Snowflake / BigQuery**：完整支持
- **Trino / Presto**：3.x 起逐步支持

不支持或仅有限支持的引擎：MySQL 5.x、ClickHouse、Hive 1.x、SQLite。这些引擎遇到带聚合的关联子查询通常会走 DEPENDENT SUBQUERY，性能差几个数量级。

## EXPLAIN 阅读：识别重写是否发生

调试时最重要的能力是从 EXPLAIN 输出判断重写是否触发。下面给出几个引擎的对照样例。

### PostgreSQL

```sql
EXPLAIN (COSTS OFF, VERBOSE)
SELECT * FROM dept d WHERE EXISTS (
    SELECT 1 FROM emp e WHERE e.dept_id = d.dept_id
);
```

**重写成功**：

```
Hash Semi Join
  Output: d.dept_id, d.name
  Hash Cond: (d.dept_id = e.dept_id)
  ->  Seq Scan on public.dept d
        Output: d.dept_id, d.name
  ->  Hash
        ->  Seq Scan on public.emp e
              Output: e.dept_id
```

**重写失败**（看到 SubPlan 即坏）：

```
Seq Scan on public.dept d
  Output: d.dept_id, d.name
  Filter: (SubPlan 1)
  SubPlan 1
    ->  Seq Scan on public.emp e
          Output: e.empno
          Filter: (e.dept_id = d.dept_id)
```

### MySQL

```sql
EXPLAIN FORMAT=TREE
SELECT * FROM dept WHERE dept_id IN (SELECT dept_id FROM emp);
```

**重写成功 (Semi-Join)**：

```
-> Nested loop semijoin
   -> Table scan on dept
   -> Single-row index lookup on emp using ix_dept_id (dept_id=dept.dept_id)
```

或：

```
-> Hash semijoin (FirstMatch, no condition)
   -> Table scan on dept
   -> Hash
      -> Table scan on emp
```

**重写失败**：

```
-> Filter: (dept.dept_id in (select #2))
   -> Table scan on dept
-> Select #2 (subquery in condition; dependent)
   -> Filter: (emp.dept_id = dept.dept_id)
      -> Index lookup on emp using ix_dept_id (dept_id=dept.dept_id)
```

`dependent` 这个词是性能杀手的明确信号。

### Oracle

```sql
EXPLAIN PLAN FOR
SELECT * FROM dept d WHERE EXISTS (
    SELECT 1 FROM emp e WHERE e.dept_id = d.dept_id
);
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());
```

**重写成功**：

```
| Id | Operation                    | Name  |
|  0 | SELECT STATEMENT             |       |
|  1 |  HASH JOIN SEMI              |       |
|  2 |   TABLE ACCESS FULL          | DEPT  |
|  3 |   TABLE ACCESS FULL          | EMP   |
```

**重写失败 (FILTER)**：

```
| Id | Operation                    | Name  |
|  0 | SELECT STATEMENT             |       |
|* 1 |  FILTER                      |       |
|  2 |   TABLE ACCESS FULL          | DEPT  |
|* 3 |   TABLE ACCESS FULL          | EMP   |
```

`FILTER` 算子表示子查询逐行执行——性能问题。

### SQL Server

```sql
SET SHOWPLAN_TEXT ON;
GO
SELECT * FROM dept d WHERE EXISTS (
    SELECT 1 FROM emp e WHERE e.dept_id = d.dept_id
);
```

**重写成功**：

```
|--Hash Match(Right Semi Join, HASH:([d].[dept_id])=([e].[dept_id]))
   |--Clustered Index Scan(OBJECT:([dept].[PK_dept] AS [d]))
   |--Clustered Index Scan(OBJECT:([emp].[PK_emp] AS [e]))
```

**重写失败 (Apply)**：

```
|--Nested Loops(Left Semi Join, OUTER REFERENCES:([d].[dept_id]))
   |--Clustered Index Scan(OBJECT:([dept].[PK_dept] AS [d]))
   |--Index Seek(OBJECT:([emp].[ix_dept_id] AS [e]),
        SEEK:([e].[dept_id]=[d].[dept_id]))
```

注意：SQL Server 的 `Left Semi Join` 在 Nested Loops 中是正常的（嵌套循环 Semi-Join 也是有效的物理算子，不算失败），关键看是否有 "Hash Match" 或类似聚合算子。如果是 Apply + 非常昂贵的 inner-loop 估计成本，那就是问题。

### Spark SQL

```scala
val df = spark.sql("""
    SELECT * FROM dept WHERE EXISTS (
        SELECT 1 FROM emp WHERE emp.dept_id = dept.dept_id
    )
""")
df.queryExecution.optimizedPlan
```

**重写成功**：

```
== Optimized Logical Plan ==
Join LeftSemi, (dept_id = dept_id)
:- Relation [...] dept
+- Project [dept_id]
   +- Relation [...] emp
```

**重写失败**：

```
== Optimized Logical Plan ==
Filter exists#0
:- Exists
:  +- Project [1]
:     +- Filter (dept_id = outer(dept_id))
:        +- Relation [...] emp
+- Relation [...] dept
```

`Exists` 节点未被消除即重写失败。

## 关键发现

经过 45+ 个 SQL 引擎的横向对比，浮现出几个关键模式：

### 1. 重写能力分三档

- **顶级（Oracle、SQL Server、DB2、Snowflake、BigQuery、DuckDB）**：完整 Semi/Anti/Magic decorrelation，支持嵌套关联，NULL-aware Anti-Join，可调控提示
- **中坚（PostgreSQL、Spark Catalyst、Trino、CockroachDB、TiDB、Vertica、Teradata）**：Semi/Anti 完整，magic decorrelation 部分支持，深层嵌套有限
- **基础（MySQL 8.0+、MariaDB、SQLite 3.35+、ClickHouse 21+）**：能处理简单的 Semi/Anti，但 NOT IN NULL、嵌套、聚合关联子查询常需手工改写

### 2. NOT IN 是跨方言的"事实标准陷阱"

所有引擎都遵守 SQL 3VL 标准，但**对优化器是否能在 NULL 不可证明非空的情况下重写为 Anti-Join 的能力**差异极大。Oracle 的 `HASH JOIN ANTI NA` 是教科书级实现；MySQL 的 NOT IN 子查询直到 8.0.17 才能去关联化。生产代码应**永远避免 NOT IN 子查询**，改用 NOT EXISTS。

### 3. EXPLAIN 是唯一可靠的验证手段

`EXISTS` 这个关键字写在 SQL 文本里，并不等于优化器真的把它重写成 Semi-Join。EPLAN 中出现 `SubPlan` / `FILTER` / `dependent subquery` / `Apply` 都是潜在性能问题。建议在 CI 中加入 EXPLAIN 检查关键查询，避免上线后才发现优化失败。

### 4. Magic decorrelation 是性能差距最大的能力

带聚合的关联子查询（"找出高于自己分组平均值的行"）是 OLAP 中最常见的形态。能否做 magic decorrelation 决定了查询从秒级到分钟级的差异。Oracle、SQL Server、DB2、DuckDB、Snowflake 等顶级实现可以把这种查询自动转为 GROUP BY + JOIN；MySQL、ClickHouse 等需要用户手写 CTE 改写。

### 5. 关闭重写的能力比启用更重要

有时 DBA 需要"关闭"重写来对比基准、定位 bug 或处理特殊数据分布。Oracle 的 `/*+ NO_UNNEST */` 提示是黄金标准；SQL Server 的 `OPTION (LOOP JOIN)` 也很灵活；PostgreSQL 没有专用提示，只能用 `enable_hashjoin = off` 等粗粒度开关（且 `enable_hashjoin` 同时控制 Semi 和 Anti Hash Join）。

### 6. 列存与行存的 Semi/Anti-Join 实现差异

行存（PostgreSQL、MySQL、Oracle）通常优先用 Hash Semi/Anti-Join；列存（ClickHouse、Vertica、Snowflake、DuckDB）会更激进地用 SIMD / 向量化探测。MPP 列存（Vertica、Greenplum、Snowflake、Redshift）还会引入 Bloom filter 减少跨节点数据传输——这是 Semi-Join 在分布式语境的天然优势。

### 7. 流处理引擎对 NOT IN / NOT EXISTS 支持弱

Flink SQL、Materialize、RisingWave 等流引擎对 Anti-Join 的增量维护是开放问题——一个新行的到达可能让原本"不存在匹配"变成"存在匹配"，从而需要追溯之前的输出。多数流引擎要求 Anti-Join 的两侧都是 append-only 流，或对状态容量有严格限制。

### 8. 重写规则的"作用顺序"也是性能差距来源

Subquery pull-up、predicate pushdown、constant folding、Semi-Join 重写之间有相互依赖。例如，`WHERE EXISTS (SELECT 1 FROM t WHERE t.id = outer.id AND outer.flag = 'X')` 中 `outer.flag = 'X'` 应当先被推到外层，再做 Semi-Join 重写——否则重写时关联条件中夹杂着外层常量，分析复杂度上升。Calcite、Spark Catalyst、CockroachDB 的 optgen 等都把这些规则的迭代顺序作为设计核心。

### 9. 提示与开关的命名学

引擎间 hint 命名学有趣对照：Oracle 用 `UNNEST` / `NO_UNNEST`；SQL Server 用 `OPTION (NO_PERFORMANCE_SPOOL)` 等；MySQL 用 `optimizer_switch` 设置；DuckDB 没有 hint。"unnest" 这个词其实在 SQL 标准里指 `UNNEST(array)`，与 Oracle 的子查询去关联化是同形异义。看到 Oracle 提示 `/*+ UNNEST */` 时不要联想到数组展开。

### 10. 子查询去关联化的边界开放问题

学术上仍有未解：

- 带 LIMIT 的关联子查询的去关联化（LIMIT 改变了基数语义）
- 带 ORDER BY 的关联子查询（顺序在 SQL 中是非语义的，但在子查询中可能被引用）
- 带递归 CTE 的关联子查询（递归与去关联化的相互作用）
- 多层嵌套且每层都是关联（爆炸性的状态空间）

DuckDB 团队基于 Neumann/Kemper 论文的实现是目前最接近"通用"的开源实现，但仍有边界场景需要特殊处理。商业数据库（Oracle/SQL Server/DB2）经过几十年累积的 patch 处理了大量边界，新兴引擎仍在追赶。

## 对引擎开发者的实现建议

### 1. 把 EXISTS 和 IN 的代码路径分开

`EXISTS` 不会产生 NULL（结果只能是 TRUE / FALSE），重写时不需要 NULL 处理。`IN` 会产生 NULL，重写时必须保持 3VL 语义。把两者的代码路径分开维护，可以避免 EXISTS 被错误地附加无谓的 NULL 检查（性能损失），也避免 IN 被错误地省略 NULL 检查（正确性 bug）。

### 2. NOT IN 优先实现 NULL-aware Anti-Join

不是所有 NOT IN 都能简单重写为 Anti-Join。当内层列可空时，必须实现 NULL-aware 变体（Oracle "ANTI NA"、SQL Server "Anti Semi Apply" + NULL guard、DuckDB "Mark Join")。如果实现成本太高，至少要在优化器中检测到这种场景并发出警告（"NOT IN with nullable column may yield empty result"）。

### 3. EXPLAIN 输出要明确算子类型

很多引擎的 EXPLAIN 输出对 Semi-Join 和 Anti-Join 不区分，只显示 "JoinExpression" 或 "Hash Match"。这给调试带来巨大麻烦。建议：

- 算子名包含 "Semi" / "Anti" 关键字
- 显示触发的优化规则名（如 "RewriteEXISTSToSemiJoin"）
- 显示是否是 NULL-aware 变体

### 4. magic decorrelation 优先实现 AVG / COUNT / SUM / MIN / MAX

带聚合的关联子查询中，`AVG`、`COUNT`、`SUM`、`MIN`、`MAX` 是 90% 以上的实际用例。优先支持这五种聚合的 magic decorrelation，剩余的（`STDDEV`、`STRING_AGG`、自定义聚合）可以延后或留作 SubPlan。

### 5. 重写规则的迭代收敛

子查询重写、谓词下推、连接重排序之间有依赖。建议在优化器迭代框架中明确：

- 第一轮：parse-time 简单替换（视图展开、CTE 内联）
- 第二轮：子查询拉平 + Semi/Anti-Join 重写
- 第三轮：谓词下推（包括跨重写后的连接边界）
- 第四轮：连接重排序 + 物理算子选择
- 必要时回到第二轮（多层嵌套需要多次拉平）

迭代收敛的判定可以用规则签名（哪些规则在本轮触发了），如果一轮没有规则触发即收敛。

### 6. 测试套件必须覆盖 NOT IN + NULL

引擎实现 Semi/Anti-Join 重写的单元测试必须显式包含以下场景：

- `NOT IN` + 内层无 NULL → 返回正确的非匹配集
- `NOT IN` + 内层全 NULL → 返回空集
- `NOT IN` + 内层混合 NULL → 返回空集（关键陷阱）
- `NOT IN` + 内层 LEFT JOIN 产生的 NULL → 同上
- `NOT EXISTS` 在三种场景下都返回直觉结果（与 NULL 无关）

不少历史 bug 是因为测试只覆盖了 "内层有数据" 和 "内层为空"，没有覆盖 "内层有 NULL"。

### 7. 提示语法的设计

如果新引擎要支持提示控制重写：

- 沿用 Oracle 风格的 `/*+ HINT */` 语法（被广泛认知）
- 提示名称用业内常见词汇（UNNEST、NO_UNNEST、SEMIJOIN、NO_SEMIJOIN）
- 提示作用域明确（语句级、子查询级、JOIN 级）
- 文档明确每个提示能"覆盖"代价模型多少

### 8. 与代价模型的协作

Semi/Anti-Join 重写本身只是"逻辑等价变换"，是否真的更快取决于代价模型估计。重写阶段不应只看"能不能重写"，还要考虑：

- 内层基数：太大时 Hash Semi-Join 内存压力大
- 关联条件选择性：低选择性时 Anti-Join 不一定优于 NOT IN 的常规执行
- 索引可用性：如果内层有可用索引，Nested Loops Semi-Join 反而最快

### 9. 分布式场景的 Bloom filter 优化

对于 MPP / 分布式数据库，Semi-Join 在跨节点 shuffle 时的数据传输量是关键。建议实现：

- 内层先做 sketch（HyperLogLog / Bloom filter）
- 把 sketch 广播到外层节点
- 外层用 sketch 预过滤，再 shuffle 到 Join 节点

这是从 SDD-1（1980 年代）到现代 MPP（Vertica、Greenplum、Trino）一脉相承的优化。

### 10. 与 streaming 的兼容

如果引擎要支持流处理（Flink、Materialize、RisingWave），Semi/Anti-Join 的增量维护需要：

- 状态存储：保存内层每个 key 的 ref count
- 撤回处理：当 ref count 减到 0 时输出撤回（retract）
- 状态 TTL：避免状态无限增长

Anti-Join 的增量维护比 Semi-Join 难一些，因为新行的到达可能让"不匹配"变"匹配"，需要回溯之前的输出。Materialize 的 differential dataflow 模型在这方面有最优雅的处理。

## 参考资料

- ISO/IEC 9075:2023 SQL 标准（语义部分）
- Galindo-Legaria, C. & Joshi, M. *Orthogonal Optimization of Subqueries and Aggregation*. SIGMOD 2001.
- Galindo-Legaria, C. *Outerjoins as Disjunctions*. SIGMOD 1994.
- Neumann, T. & Kemper, A. *Unnesting Arbitrary Queries*. BTW 2015.
- Seshadri, P. et al. *Cost-Based Optimization for Magic: Algebra and Implementation*. SIGMOD 1996.
- Oracle: [SQL Tuning Guide - Subquery Unnesting](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/)
- SQL Server: [Subquery Unfolding and Decorrelation](https://learn.microsoft.com/en-us/sql/relational-databases/query-processing-architecture-guide)
- PostgreSQL: [Planner/Optimizer - Subqueries](https://www.postgresql.org/docs/current/planner-optimizer.html)
- PostgreSQL: [enable_hashjoin parameter](https://www.postgresql.org/docs/current/runtime-config-query.html)
- MySQL: [Optimizing Subqueries](https://dev.mysql.com/doc/refman/8.0/en/subquery-optimization.html)
- DuckDB: [Unnesting Subqueries](https://duckdb.org/2023/05/26/correlated-subqueries-in-sql.html)
- Spark: [Catalyst Optimizer](https://databricks.com/glossary/catalyst-optimizer)
- Trino: [Iterative Optimizer Rules](https://github.com/trinodb/trino/tree/master/core/trino-main/src/main/java/io/trino/sql/planner/iterative/rule)
- ClickHouse: [Subquery support evolution](https://clickhouse.com/docs/en/sql-reference/operators/exists)
