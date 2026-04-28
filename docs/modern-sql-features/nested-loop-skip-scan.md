# 嵌套循环连接与跳跃扫描 (Nested Loop Join and Skip Scan)

嵌套循环连接（Nested Loop Join, NLJ）是数据库历史上最古老、最简单也最被低估的物理算子。当 build 侧能用索引精确定位、外侧只有少量行时，索引嵌套循环（Index Nested Loop）的延迟与代价都远低于哈希连接。而**跳跃扫描（Skip Scan）**——又名 Loose Index Scan——则把这一思想推向极致：当复合索引 `(a, b)` 上查询只过滤 `b` 时，引擎仍可以跳过 `a` 的不同取值组（DISTINCT VALUES）来"loose"地利用索引，避开全表扫描。这两项优化在不同引擎里以截然不同的成熟度存在，是少数 Oracle 在 2001 年就已具备而 PostgreSQL 直到 2024 年仍在提案阶段的能力。

## 没有 SQL 标准

Nested Loop Join 与 Skip Scan 都是物理算子（physical operator）和访问路径（access path），不属于 SQL 标准。SQL 标准只定义逻辑连接（INNER/LEFT/RIGHT/FULL JOIN），具体使用 Nested Loop、Sort-Merge 还是 Hash Join 由优化器决定；索引访问路径同样由优化器在统计信息与代价模型驱动下选择。本文讨论的所有特性都是**实现细节**，但正是这些实现细节决定了一个引擎能否在带索引的中小连接里跑出毫秒级延迟、能否在前导列高重复时仍利用复合索引——这两项能力对 OLTP 与混合工作负载至关重要。

Nested Loop Join 的基本思想极其朴素：

1. **外侧扫描（outer scan）**：扫描第一张表（驱动表 / driving table），对每一行……
2. **内侧探测（inner probe）**：……在第二张表中查找匹配的行（通常通过索引）

复杂性几乎全部来自工程优化：(a) 怎样让内侧的随机 I/O 顺序化，(b) 怎样通过批量化（batched key access）摊销开销，(c) 怎样通过索引预取（prefetch）隐藏 I/O 延迟。

Skip Scan 的核心思想同样不复杂：在复合索引 `(a, b)` 上，即使 WHERE 不过滤前导列 `a`，只要 `a` 的不同取值（NDV, Number of Distinct Values）不太多，引擎就可以**枚举每个 `a` 的取值，然后对每一段做范围扫描定位 `b`**。当 NDV(a) << N 时，跳跃扫描的代价可能远低于全表扫描或全索引扫描。

## 支持矩阵

### 原生 Nested Loop Join with Index Seek

最朴素的访问路径：外侧扫描 + 内侧索引探测。所有保留 B-Tree 索引的引擎都支持，但流处理 / 列存引擎可能默认禁用或要求显式提示。

| 引擎 | Index Nested Loop | 引入版本 | 备注 |
|------|--------------------|---------|------|
| PostgreSQL | 是 | 早期 | `Nested Loop` + `Index Scan` 计划节点 |
| MySQL | 是 | 早期 | InnoDB 聚簇索引天然友好 |
| MariaDB | 是 | 早期 | 继承 MySQL |
| SQLite | 是 | 早期 | **唯一物理连接算法**（仅 NL） |
| Oracle | 是 | V6 (1988) | `NESTED LOOPS` + `INDEX RANGE SCAN` |
| SQL Server | 是 | 早期 | `Nested Loops` + `Index Seek` |
| DB2 | 是 | V1 早期 | NL + Index Scan |
| Snowflake | 部分 | GA | 内部很少选 NL，micro-partition 列存不适配 |
| BigQuery | 部分 | GA | Dremel 主要用 Hash/Broadcast |
| Redshift | 部分 | GA | NL 仅限小表 |
| DuckDB | 是 | 0.1+ | 列存但保留 NL 算子 |
| ClickHouse | 部分 | 早期 | 列存少用 NL，主要用 hash |
| Trino | 是 | 早期 | 受限于连接器 |
| Presto | 是 | 早期 | -- |
| Spark SQL | 是 | 1.0+ | `BroadcastNestedLoopJoin` |
| Hive | 是 | 早期 | -- |
| Flink SQL | 是 | 1.5+ | 批模式 + 流模式 |
| Databricks | 是 | GA | -- |
| Teradata | 是 | V2R3+ | -- |
| Greenplum | 是 | 继承 PG | -- |
| CockroachDB | 是 | 1.0+ | `lookup join` |
| TiDB | 是 | 1.0+ | `IndexJoin` / `IndexLookup` |
| OceanBase | 是 | 1.x+ | -- |
| YugabyteDB | 是 | 继承 PG | -- |
| SingleStore | 是 | 早期 | -- |
| Vertica | 部分 | 早期 | 列存少用 NL |
| Impala | 是 | 1.0+ | -- |
| StarRocks | 部分 | 早期 | 主要用 hash |
| Doris | 部分 | 早期 | 主要用 hash |
| MonetDB | 是 | 早期 | 列存 |
| CrateDB | 是 | 4.2+ | -- |
| TimescaleDB | 是 | 继承 PG | -- |
| QuestDB | 是 | 6.0+ | 时序优化 |
| Exasol | 是 | 早期 | MPP |
| SAP HANA | 是 | 早期 | -- |
| Informix | 是 | 早期 | -- |
| Firebird | 是 | 早期 | 早期版本仅 NL |
| H2 | 是 | 早期 | -- |
| HSQLDB | 是 | 早期 | **仅 NL**（无 hash） |
| Derby | 是 | 早期 | **仅 NL**（无 hash） |
| Amazon Athena | 是 | 继承 Trino | -- |
| Azure Synapse | 是 | GA | -- |
| Google Spanner | 是 | GA | 分布式 NL |
| Materialize | 是 | GA | dataflow |
| RisingWave | 是 | GA | 流式 |
| InfluxDB (SQL) | 是 | 3.0+ (DataFusion) | -- |
| DatabendDB | 是 | GA | -- |
| Yellowbrick | 是 | GA | -- |
| Firebolt | 是 | GA | -- |

> 统计：49 个引擎几乎全部支持 NL + 索引探测；列存 / MPP 引擎对 NL 的依赖度低（默认 hash），但仍在 OLTP 风格小连接里使用 NL。

### Index Skip Scan / Loose Index Scan

复合索引 `(a, b)` 上仅过滤 `b` 时跳过 `a` 的不同值组进行扫描，避免全索引扫描。

| 引擎 | Skip Scan / Loose Index Scan | 引入版本 | 备注 |
|------|------------------------------|---------|------|
| Oracle | 是（Index Skip Scan） | 9i (2001) | 经典实现，前导列低 NDV |
| MySQL | 部分（Loose Index Scan） | 5.0 (2005) | **仅限 GROUP BY MIN/MAX** |
| MariaDB | 部分（Loose Index Scan） | 继承 MySQL | 同上 |
| PostgreSQL | -- | 17 不支持 | **18 提案中（Peter Geoghegan）** |
| SQL Server | -- | -- | **不支持**，需 OR-rewrite |
| DB2 | 是（Jump Scan） | 10.5+ | LUW 称 "Jump Scan" |
| SQLite | -- | -- | -- |
| Snowflake | -- | -- | micro-partition 模型不适用 |
| BigQuery | -- | -- | 列存 Dremel |
| Redshift | -- | -- | 列存 |
| DuckDB | 部分 | 自适应 | min-max 索引部分等价 |
| ClickHouse | 部分 | 早期 | sparse primary index 类似但不同 |
| Trino | -- | -- | -- |
| Presto | -- | -- | -- |
| Spark SQL | -- | -- | -- |
| Hive | -- | -- | -- |
| Flink SQL | -- | -- | -- |
| Databricks | -- | -- | Photon 不支持 |
| Teradata | -- | -- | NUSI/USI 但无 skip scan |
| Greenplum | -- | -- | 继承 PG，无 |
| CockroachDB | -- | -- | -- |
| TiDB | -- | -- | -- |
| OceanBase | 部分 | 4.x+ | 类似 Oracle skip scan |
| YugabyteDB | -- | -- | 继承 PG |
| SingleStore | -- | -- | -- |
| Vertica | -- | -- | -- |
| Impala | -- | -- | -- |
| StarRocks | -- | -- | -- |
| Doris | -- | -- | -- |
| MonetDB | -- | -- | -- |
| CrateDB | -- | -- | -- |
| TimescaleDB | -- | -- | 继承 PG |
| QuestDB | -- | -- | -- |
| Exasol | -- | -- | -- |
| SAP HANA | -- | -- | 列式不需要 |
| Informix | -- | -- | -- |
| Firebird | -- | -- | -- |
| H2 | -- | -- | -- |
| HSQLDB | -- | -- | -- |
| Derby | -- | -- | -- |
| Amazon Athena | -- | -- | -- |
| Azure Synapse | -- | -- | -- |
| Google Spanner | -- | -- | -- |
| Materialize | -- | -- | -- |
| RisingWave | -- | -- | -- |
| InfluxDB (SQL) | -- | -- | -- |
| DatabendDB | -- | -- | -- |
| Yellowbrick | -- | -- | -- |
| Firebolt | -- | -- | -- |

> 统计：49 个引擎中仅 Oracle、DB2、OceanBase 完整支持 Index Skip Scan；MySQL/MariaDB 仅在 GROUP BY MIN/MAX 这一受限场景；ClickHouse 的 sparse primary index 和 DuckDB 的 min-max 索引在思想上接近但语义不同；绝大多数引擎根本不实现。这是 OLAP 工程师常忽视的 OLTP 优化能力。

### Broadcast Join Hint（NL 跨节点应用）

分布式系统里小表广播的 hint 控制——本质是 NL/Hash Join 的分发策略选择。

| 引擎 | Broadcast Hint | 语法示例 |
|------|----------------|---------|
| Oracle | -- | 优化器自动 |
| SQL Server | -- | 优化器自动 |
| MySQL | -- | 单机 |
| PostgreSQL | -- | 单机 |
| Snowflake | 自动 | 优化器决定 |
| BigQuery | -- | 自动 |
| Redshift | DS_DIST_ALL_NONE / DS_BCAST_INNER | EXPLAIN 体现 |
| DuckDB | -- | 单机 |
| ClickHouse | GLOBAL JOIN | 显式广播 |
| Trino | `join_distribution_type=BROADCAST` | session property |
| Presto | 同 Trino | -- |
| Spark SQL | `/*+ BROADCAST(t) */` | hint |
| Hive | `/*+ MAPJOIN(t) */` | hint |
| Flink SQL | `/*+ BROADCAST */` | hint |
| Databricks | `/*+ BROADCAST(t) */` | hint |
| TiDB | `/*+ BCJ(t) */` | TiFlash |
| OceanBase | `/*+ USE_NL(t1 t2) PQ_DISTRIBUTE */` | -- |
| StarRocks | `[broadcast]` | hint |
| Doris | `[broadcast]` | hint |
| Impala | `/* +BROADCAST */` | hint |
| Greenplum | `gp_segments_for_planner` | -- |
| CockroachDB | -- | 自动 |
| YugabyteDB | -- | 自动 |
| Vertica | `/*+ DISTRIB(L,B) */` | -- |
| SAP HANA | `WITH HINT(NO_HASH_JOIN, USE_NL_JOIN)` | -- |
| Teradata | -- | 自动 |
| Exasol | -- | 自动 |

### Index Prefetch（异步索引预取）

NL 内侧查找时大批量异步发出 I/O，隐藏磁盘延迟。

| 引擎 | Index Prefetch / Async I/O | 引入版本 | 备注 |
|------|----------------------------|---------|------|
| Oracle | 是 | 8i+ | 表预取（table prefetching） + 缓冲区 |
| SQL Server | 是（WithUnorderedPrefetch） | 2005+ | NL 内侧预取 |
| DB2 | 是（List Prefetch） | LUW 早期 | RID 排序后批量 I/O |
| MySQL | 部分 | 8.0.32+ | 引入 `mrr` (Multi-Range Read) |
| MariaDB | 是 | 5.3+ | MRR + ICP |
| PostgreSQL | -- | 17 不支持 | **18 计划增加** |
| Snowflake | 是 | GA | 内置 |
| BigQuery | 是 | GA | -- |
| Redshift | 是 | GA | -- |
| DuckDB | 是 | 0.10+ | 自动预取扫描 |
| ClickHouse | 是 | 早期 | 异步读 |
| Trino | 是 | 早期 | 连接器层 |
| Presto | 是 | -- | -- |
| Spark SQL | -- | -- | -- |
| Teradata | 是 | 早期 | -- |
| Greenplum | -- | -- | 继承 PG |

### Batched Key Access (BKA)

外侧批量积累 key，排序后向内侧索引发出顺序探测——MySQL 5.6 的标志性 NL 优化。

| 引擎 | BKA / 等价能力 | 引入版本 | 备注 |
|------|----------------|---------|------|
| MySQL | 是（BKA） | 5.6 (2013) | `optimizer_switch` 控制 |
| MariaDB | 是（BKA + BKAH） | 5.3 (2012) | **比 MySQL 早 1 年** |
| Oracle | 是（Vector Index Access） | 11g+ | -- |
| SQL Server | 是（List Prefetch） | 2005+ | NL 内侧 |
| DB2 | 是（List Prefetch） | LUW 早期 | -- |
| PostgreSQL | -- | -- | 类似能力由 sort + index scan 替代 |
| 其他 | -- | -- | 多数靠 hash 取代 |

> BKA / List Prefetch / Vector Index Access 是同一思想的不同名字：把外侧 key 缓存→排序→批量索引探测，把随机 I/O 变成顺序 I/O。

## 各引擎详解

### Oracle：Index Skip Scan 的开创者（9i, 2001）

Oracle 9i Release 1（2001）首次引入 **Index Skip Scan**，这是数据库历史上第一个商用的跳跃扫描实现。设计动机非常具体：

> 某复合索引 `(GENDER, EMPLOYEE_ID)`，前导列 `GENDER` 只有 'M' / 'F' 两个不同值（NDV=2）。查询 `WHERE EMPLOYEE_ID = 12345` 没有过滤 `GENDER`，但仍可利用此索引：分别为 `GENDER='M'` 和 `GENDER='F'` 各做一次范围扫描。

```sql
-- Oracle Index Skip Scan 的经典示例
CREATE INDEX idx_emp ON employees (gender, employee_id);

-- 查询不过滤 gender，仍能使用此索引
SELECT * FROM employees WHERE employee_id = 12345;

-- 执行计划:
-- |   0 | SELECT STATEMENT             |             |
-- |   1 |  TABLE ACCESS BY INDEX ROWID | EMPLOYEES   |
-- |*  2 |   INDEX SKIP SCAN            | IDX_EMP     |
--
-- Predicate Information:
--    2 - access("EMPLOYEE_ID"=12345)
--        filter("EMPLOYEE_ID"=12345)
```

**何时触发 Skip Scan**：

1. 前导列的不同值个数（NDV）远小于总行数——经验阈值是 NDV < 几百或几千
2. 过滤列在索引中（除了前导列）
3. 没有更优的访问路径（如更窄索引或全表扫描）
4. 优化器代价模型确认 skip scan 比全表扫描或全索引扫描更优

**代价计算的近似公式**：

```
Skip Scan 代价 ≈ NDV(leading_col) × (B-tree 探测代价 + 范围扫描代价)
全表扫描代价 ≈ N × 单行扫描代价
全索引扫描代价 ≈ 索引叶子页数 × 单页扫描代价
```

当 `NDV(leading_col) × 范围扫描代价 << N × 单行扫描代价` 时，skip scan 获胜。

```sql
-- Oracle 提示语法
SELECT /*+ INDEX_SS(employees idx_emp) */ *
FROM employees WHERE employee_id = 12345;

-- 禁用 skip scan
SELECT /*+ NO_INDEX_SS(employees idx_emp) */ *
FROM employees WHERE employee_id = 12345;

-- 查看 skip scan 是否被使用
SELECT operation, options, object_name
FROM v$sql_plan
WHERE sql_id = ':sql_id' AND options = 'SKIP SCAN';
```

Oracle 11g 进一步引入了 **Index Skip Scan with IN-list 扩展**：当前导列出现在 IN (...) 而非等值时，仍可触发 skip scan，每个 IN 值一次范围扫描。Oracle 12c 之后，skip scan 与 Adaptive Plans 互动，运行时根据真实行数决定是否切换到全表扫描。

### SQL Server：没有 Skip Scan，靠 OR 改写

SQL Server（截至 2022 / 2025 GA）**不支持** Index Skip Scan。微软的 query optimizer 团队的立场是：可通过查询改写显式枚举前导列值实现等价语义，且代价模型可控。

```sql
-- 索引: idx_emp (Gender, EmployeeID)
-- 查询无法利用索引（前导列未过滤）:
SELECT * FROM Employees WHERE EmployeeID = 12345;
-- 计划: Clustered Index Scan (全表)

-- 改写 1: OR 枚举前导列（Gender NDV=2）
SELECT * FROM Employees
WHERE EmployeeID = 12345
  AND (Gender = 'M' OR Gender = 'F');
-- 计划: Index Seek + Key Lookup（命中索引）

-- 改写 2: UNION ALL（更直接）
SELECT * FROM Employees WHERE Gender = 'M' AND EmployeeID = 12345
UNION ALL
SELECT * FROM Employees WHERE Gender = 'F' AND EmployeeID = 12345;
-- 计划: 两个 Index Seek 串联

-- 改写 3: IN-list
SELECT * FROM Employees
WHERE EmployeeID = 12345
  AND Gender IN ('M', 'F');
-- 计划: Index Seek（范围探测）
```

实际上多数 SQL Server DBA 会建议添加正确顺序的索引（`(EmployeeID, Gender)`）而不是依赖改写。SQL Server 的并行性、Batch Mode 列存等其他优化弥补了 skip scan 的缺失，但在 OLTP 场景仍然是真实的功能差距。

### MySQL：Loose Index Scan（仅限 GROUP BY MIN/MAX）

MySQL 5.0（2005）引入 **Loose Index Scan**，但**严格限制于 GROUP BY 配合 MIN()/MAX() 聚合**。这与 Oracle 的通用 Index Skip Scan 是两个不同的概念，常被混淆。

```sql
-- 表 t (a INT, b INT, c INT, INDEX idx (a, b))
-- 标准 Loose Index Scan 触发条件:
--   1. SELECT 中只有索引列
--   2. GROUP BY 是索引前缀
--   3. 聚合函数仅 MIN/MAX

-- 触发 Loose Scan 的查询:
SELECT a, MIN(b), MAX(b)
FROM t
GROUP BY a;
-- EXPLAIN 显示 "Using index for group-by"

-- 不带 MIN/MAX 也能触发（仅取每组第一行）:
SELECT DISTINCT a FROM t;
-- 等价于 SELECT a FROM t GROUP BY a，内部走 loose scan

-- WHERE 条件有限支持:
SELECT a, MIN(b)
FROM t
WHERE a > 10
GROUP BY a;
-- 仍能触发，但 WHERE 必须是索引前缀的 range

-- 不能触发的场景:
SELECT a, MIN(b) FROM t WHERE c = 5 GROUP BY a;  -- 非索引列 c 过滤
SELECT a, COUNT(*) FROM t GROUP BY a;             -- 非 MIN/MAX 聚合
SELECT a, b, MIN(c) FROM t GROUP BY a, b;          -- c 不在索引中
```

MySQL 8.0 在原有基础上扩展了 **Skip-Scan Range Access Method**（不要与 Oracle Index Skip Scan 混淆，这是另一个名字相同的特性，5.7.32 引入，8.0 增强）：在 EXPLAIN 中显示 `Using index for skip scan`。

```sql
-- MySQL 8.0+ Skip-Scan Range Access
-- 索引: idx (a, b), a 的 NDV 较小
SELECT a, b FROM t WHERE b BETWEEN 10 AND 20;
-- EXPLAIN: type=range, Extra: "Using index for skip scan"
```

但这个特性比 Oracle 的版本受限：必须只访问索引列（不能回表读其他列），且 a 的 NDV 必须很小。`optimizer_switch` 中的 `skip_scan=on/off` 控制启用。

### MySQL Batched Key Access（BKA, 5.6, 2013）

MySQL 5.6（2013-02）引入 **Batched Key Access**，是对 NL Join 的关键改进：

```sql
-- 经典 NL: 外侧 1 行 → 内侧 1 次随机 I/O
-- BKA: 外侧 N 行积累到 join_buffer → 排序 key → 内侧批量顺序 I/O

EXPLAIN
SELECT /*+ BKA(o, c) */ *
FROM orders o JOIN customers c ON o.cust_id = c.id;

-- Extra 列出现 "Using join buffer (Batched Key Access)"
-- 实际执行步骤:
--   1. 扫描 orders, 把 cust_id 积累到 join_buffer (大小由 join_buffer_size 控制)
--   2. 对 buffer 中的 cust_id 排序
--   3. 用 MRR (Multi-Range Read) 接口向 customers 索引发出批量探测
--   4. 内部 buffer 收集结果, 顺序 I/O 而非随机
```

**优化器开关**：

```sql
SET optimizer_switch = 'mrr=on,mrr_cost_based=on,batched_key_access=on';

-- 三个相关开关:
--   mrr: Multi-Range Read 接口（BKA 的底层）
--   mrr_cost_based: 仅在估算划算时用 MRR
--   batched_key_access: 启用 BKA 算法
```

**适用场景**：

1. 内侧表的索引按 PK 或聚簇键组织，且 join key 与该索引相关
2. 外侧表行数较多但内侧匹配率不高
3. 系统是磁盘瓶颈而非 CPU 瓶颈（顺序 I/O 收益最大）

**与 Hash Join 的对比**：MySQL 8.0.18 引入了真正的 hash join 后，多数等值连接场景下 hash join 已成默认。BKA 仍在以下场景胜出：

- 内侧索引已存在，且匹配率极低（hash 还要 build）
- 内存紧张（hash 要建表，BKA 流式）
- 外侧已排序（不需 buffer 排序的额外开销）

MariaDB 的同名特性 **早于 MySQL 1 年**（5.3, 2012），且增强为 **BKAH**（BKA Hash），把 join_buffer 内的 key 用哈希索引而非排序。

### PostgreSQL：17 不支持，18 提案中（Peter Geoghegan）

截至 PostgreSQL 17（2024-09 发布），PostgreSQL **没有原生的 Index Skip Scan**。这是 PostgreSQL 长期被拿来与 Oracle 对比的功能差距之一。

社区的主要应对方案是 **Loose Index Scan 改写技巧**（即 "recursive CTE"模拟）：

```sql
-- 原查询 (低效, 全索引扫描):
SELECT DISTINCT customer_id FROM orders;

-- Loose Index Scan 模拟（PostgreSQL Wiki 推荐）:
WITH RECURSIVE t AS (
    -- 第一行: 取最小 customer_id
    SELECT MIN(customer_id) AS customer_id FROM orders
    UNION ALL
    -- 递归: 取下一个 > 当前的最小 customer_id
    SELECT (SELECT MIN(customer_id)
            FROM orders
            WHERE customer_id > t.customer_id)
    FROM t
    WHERE t.customer_id IS NOT NULL
)
SELECT customer_id FROM t WHERE customer_id IS NOT NULL;

-- 利用 (customer_id) 索引, 每次只读一个叶子节点 + 一次跳跃
-- 100 万行 1000 个不同值: 全索引扫描 ~3秒, 模拟 skip scan ~10毫秒
```

**Peter Geoghegan 的 PostgreSQL 18 提案**（2024-2025）：

PostgreSQL 18 开发周期里，B-Tree 维护者 Peter Geoghegan 提交了多版 patch 实现真正的 Skip Scan，关键设计：

1. **B-Tree 内部跳跃**：扩展 `_bt_first` / `_bt_next` 等核心 API，使其能在前导列范围间跳转
2. **NDV 阈值估算**：利用 PG 的 pg_statistic（特别是 `n_distinct`）决定是否值得 skip scan
3. **与现有 Bitmap Index Scan 协作**：当 skip scan 收益不明显时回退
4. **不引入新计划节点**：复用 `Index Scan` 节点，在执行时动态切换扫描策略

提案目标：覆盖 Oracle Index Skip Scan 的所有典型场景，且代价模型保守（避免回归），预计在 PG 18（2025 年 9 月发布）合入。

```sql
-- PG 18 提案预期效果（截至 2026-04 仍在 review）:
CREATE INDEX idx_emp ON employees (gender, employee_id);

EXPLAIN ANALYZE
SELECT * FROM employees WHERE employee_id = 12345;
-- 预期计划:
--  Index Scan using idx_emp on employees
--    Index Cond: (employee_id = 12345)
--    Skip Scan: (gender)  -- 新增
--    Distinct Prefix Values: 2  -- 新增
```

### PostgreSQL 的 BRIN 作为另类替代

PostgreSQL 9.5（2016-01）引入 **BRIN（Block Range Index）**，是另一个填补 skip scan 角色的索引类型：

```sql
-- BRIN 索引: 按数据块范围存储 min/max 摘要, 极小（KB 级 vs B-Tree 的 GB 级）
CREATE INDEX idx_orders_date_brin ON orders USING BRIN (order_date)
WITH (pages_per_range = 128);

-- 查询时: 先扫 BRIN 摘要确定哪些块可能含目标值, 再回表
SELECT * FROM orders WHERE order_date > '2025-01-01';

-- BRIN 的优势:
--   - 索引极小（百万行表的 BRIN 仅几 KB）
--   - 适合自然有序的列（如插入顺序与时间相关）
--   - 类似 ClickHouse sparse index、DuckDB 的 zone map

-- BRIN 的局限:
--   - 不能精确定位单行（只是块级摘要）
--   - 数据无序时近乎无效
```

BRIN 与 Skip Scan 解决的是相关但不同的问题：BRIN 用于"大范围裁剪"，Skip Scan 用于"避开前导列全扫描"。两者不互斥。

### CockroachDB：无 Skip Scan，依赖正确索引

CockroachDB（截至 24.x）不支持 Index Skip Scan。Cockroach Labs 的工程立场是：

1. 分布式索引的 skip scan 实现复杂度高
2. 用户应通过 `CREATE INDEX` 创建专门的索引（CRDB 索引创建很快）
3. 如有迫切需求可通过 **lookup join** 显式枚举

```sql
-- CockroachDB 的 lookup join (NL with index)
EXPLAIN
SELECT * FROM orders o
INNER LOOKUP JOIN customers c ON o.cust_id = c.id;

-- distribution: local
-- vectorized: true
--   • lookup join
--   │ table: customers@customers_pkey
--   │ equality: (cust_id) = (id)
--   • scan
--     table: orders@orders_pkey
```

CRDB 的 lookup join 是分布式 NL with index 的命名，本质上把 batched key access 和分布式查询路由结合。

### TiDB：无 Skip Scan，依赖 IndexJoin

TiDB（截至 8.x）也不支持 Index Skip Scan。TiDB 的对应能力是：

```sql
-- IndexJoin: 类似 Oracle NL with index
EXPLAIN
SELECT /*+ INL_JOIN(o, c) */ *
FROM orders o JOIN customers c ON o.cust_id = c.id;

-- IndexJoin
--   ├─ TableScan: orders
--   └─ IndexLookUp: customers (with cust_id batch)
--      ├─ IndexRangeScan: idx_customers
--      └─ TableRowIDScan: customers
```

TiDB 提供了三种 NL 变体的 hint：

- `/*+ INL_JOIN() */`：经典 Index NL Join
- `/*+ INL_HASH_JOIN() */`：内侧用哈希加速
- `/*+ INL_MERGE_JOIN() */`：内侧已排序时用归并

但都不能等价于 Skip Scan——后者是单表的访问路径优化，与 Join 无关。

### DuckDB：自适应执行 + min-max 索引

DuckDB（截至 1.x）没有传统意义的 Index Skip Scan，但其向量化执行 + 自适应优化在某些场景给出近似效果：

```sql
-- DuckDB 的 zone map (自动维护的 min-max)
-- 每个 row group 存储所有列的 min/max
CREATE TABLE orders AS SELECT * FROM ...;

-- 查询时自动跳过不可能匹配的 row group
SELECT * FROM orders WHERE customer_id = 12345;
-- 扫描时用 row group min/max 裁剪, 效果类似 BRIN
```

DuckDB 没有 B-Tree 索引（早期不支持，现在的 ART 索引主要用于约束），所以不存在传统意义的 skip scan。其向量化引擎的代价模型决定了在多数场景下 hash join 优于 NL，索引访问路径较少使用。

### DB2：Jump Scan（10.5+）

IBM DB2 LUW 10.5（2013）引入 **Jump Scan**，本质就是 Oracle 风格的 Index Skip Scan，但使用了不同的命名以避免商标问题：

```sql
-- DB2 索引: idx_emp (gender, employee_id)
-- 查询不过滤 gender:
SELECT * FROM employees WHERE employee_id = 12345;

-- EXPLAIN PLAN 输出 "JUMPSCAN" 操作符
--   或在 db2exfmt 输出中:
--   Access Method: JUMPSCAN
--   Index: SCHEMA.IDX_EMP
--   Predicates:
--     Sargable: EMPLOYEE_ID = 12345
```

DB2 的 Jump Scan 与 Oracle 的 Skip Scan 在算法上几乎相同（按前导列 distinct prefix 跳转），但 DB2 有更激进的代价控制：当前导列 NDV 估算不可靠时倾向于回退到全索引扫描或全表扫描。

### OceanBase：Oracle 兼容的 Skip Scan

OceanBase 4.x 引入 Index Skip Scan，主要为 Oracle 兼容模式服务：

```sql
-- OceanBase 索引: idx_emp (gender, employee_id)
SELECT /*+ INDEX_SS(employees idx_emp) */ *
FROM employees WHERE employee_id = 12345;

-- 计划包含 INDEX SKIP SCAN 节点
```

OceanBase 也是少数原生支持的 OLTP 引擎之一，主要面向阿里巴巴系内部 Oracle 迁移场景。

## Oracle Index Skip Scan 深入

### NDV 阈值的经验法则

Oracle Index Skip Scan 是否被选中，关键看代价模型对前导列 NDV（Number of Distinct Values）的估算：

```
触发 Skip Scan 的经验阈值:
  - NDV(leading_col) ≤ 100        几乎总是触发
  - NDV(leading_col) ≤ 10000      需要后续列高选择性
  - NDV(leading_col) ≤ 100000     代价模型边缘, 看具体行数
  - NDV(leading_col) > 100000     几乎不触发, 改用其他索引或全表扫描
```

实际公式（简化版）：

```
Skip Scan 代价 ≈ NDV × (B-Tree 高度 + 范围扫描叶子页数 + 回表代价)
```

```sql
-- 查看 NDV 统计
SELECT column_name, num_distinct, num_rows, density
FROM dba_tab_columns
WHERE table_name = 'EMPLOYEES';

-- 触发统计收集（确保 skip scan 决策准确）
EXEC DBMS_STATS.GATHER_TABLE_STATS('SCHEMA', 'EMPLOYEES',
     METHOD_OPT => 'FOR ALL INDEXED COLUMNS SIZE AUTO');

-- 查看 skip scan 是否真的生效
SELECT /*+ GATHER_PLAN_STATISTICS */ *
FROM employees WHERE employee_id = 12345;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(format => 'ALLSTATS LAST'));
-- 关注 A-Rows / E-Rows 是否准确
```

### 与位图索引的对比

Oracle 也支持位图索引（Bitmap Index），与 skip scan 在低 NDV 列上有竞争关系：

```sql
-- 选择 1: B-Tree 复合索引 + Skip Scan
CREATE INDEX idx_btree ON employees (gender, employee_id);

-- 选择 2: 位图索引 (低 NDV 专用)
CREATE BITMAP INDEX idx_bmp_gender ON employees (gender);
CREATE INDEX idx_emp_id ON employees (employee_id);
-- 优化器自动 BITMAP AND 两个索引的结果

-- 对比:
-- B-Tree + Skip Scan: 适合 OLTP, 单行精确查询, 写并发友好
-- Bitmap: 适合 DSS/OLAP, AND/OR 多条件组合, 写并发差
```

Oracle 的官方建议是：OLTP 用 B-Tree + Skip Scan；DW/OLAP 用 Bitmap + Star Transformation。

### Skip Scan 的反模式

```sql
-- 反模式 1: 错误的索引顺序
CREATE INDEX bad_idx ON orders (status, customer_id, order_date);
-- status NDV=5, customer_id NDV=百万, order_date NDV=千日
-- 多数查询是 (customer_id) + 范围(order_date), status 没用
-- skip scan 在 status 上跳 5 次 OK, 但实际可能选错索引

-- 修正: 单独建针对常用列的索引
CREATE INDEX good_idx ON orders (customer_id, order_date);

-- 反模式 2: 滥用 skip scan 当作通用补救
-- skip scan 不是免费的: 仍要做 NDV 次 B-Tree 探测
-- 如果 NDV(leading) > 几千, skip scan 比全表扫描慢

-- 反模式 3: 函数索引 + Skip Scan
CREATE INDEX fn_idx ON employees (UPPER(gender), employee_id);
-- 查询必须用 UPPER(gender) 才能命中, skip scan 路径与函数索引交互复杂
```

## MySQL Batched Key Access 深入

### 工作流程详解

```
Batched Key Access (BKA) 的完整流程:

  外侧 orders                  Join Buffer (按 join_buffer_size)
  ┌────────────┐              ┌──────────────────┐
  │ row 1, k=5 │ ──────────▶  │  k=5             │
  │ row 2, k=3 │ ──────────▶  │  k=3             │
  │ row 3, k=8 │ ──────────▶  │  k=8             │
  │ ...        │              │  k=2             │
  │ row N, k=2 │ ──────────▶  │  ...             │
  └────────────┘              └──────────────────┘
                                       │
                                       ▼ (排序 key)
                              ┌──────────────────┐
                              │  k=2, 3, 5, 8, ..│
                              └──────────────────┘
                                       │
                                       ▼ (MRR 接口批量探测)
                              ┌──────────────────┐
                              │  customers 索引   │
                              │  按 key 顺序读取  │
                              │  顺序 I/O         │
                              └──────────────────┘
                                       │
                                       ▼ (返回结果, 还原原始顺序或忽略)
                              ┌──────────────────┐
                              │  匹配的行         │
                              └──────────────────┘
```

### 与 Hash Join 的代价对比

```sql
-- 测试场景: orders 1000万行, customers 100万行, 内侧索引存在
-- 系统: SSD, join_buffer_size = 256MB

-- 传统 Block Nested Loop (BNL):
EXPLAIN SELECT /*+ NO_BKA(o, c) NO_HASH_JOIN(o, c) */ *
FROM orders o JOIN customers c ON o.cust_id = c.id;
-- Extra: "Using join buffer (Block Nested Loop)"
-- 时间: ~120 秒（多次扫 customers）

-- BKA (5.6+):
EXPLAIN SELECT /*+ BKA(o, c) */ *
FROM orders o JOIN customers c ON o.cust_id = c.id;
-- Extra: "Using join buffer (Batched Key Access)"
-- 时间: ~25 秒（顺序 I/O）

-- Hash Join (8.0.18+):
EXPLAIN SELECT /*+ HASH_JOIN(o, c) */ *
FROM orders o JOIN customers c ON o.cust_id = c.id;
-- 时间: ~15 秒（仅当 customers 能放进内存）

-- 经验:
-- customers 完全 in-memory 且热: Hash Join 胜
-- customers 部分冷, 索引存在, 选择性高: BKA 胜
-- customers 巨大且 cold: BKA 也优于 Hash（hash 要 spill）
```

### 与 MRR 的关系

BKA 依赖 MRR（Multi-Range Read）接口，5.6 同时引入：

```sql
-- MRR 单独使用（无 BKA）也有效:
EXPLAIN SELECT * FROM customers WHERE id IN (5, 3, 8, 1, 7);
-- 不开 MRR: 5 次随机 I/O
-- 开 MRR: id 排序后 5 次顺序 I/O

-- BKA = NL Join 中自动触发 MRR
-- 控制开关:
SET optimizer_switch = 'mrr=on,mrr_cost_based=on,batched_key_access=on';
SET join_buffer_size = 256 * 1024 * 1024;  -- 256 MB

-- mrr_cost_based=off 强制启用（仅测试用）:
SET optimizer_switch = 'mrr_cost_based=off';
```

### MariaDB BKAH（带哈希的 BKA）

MariaDB 5.3 早于 MySQL 引入 BKA，并扩展为 **BKAH**（BKA + Hash）：

```sql
-- MariaDB BKAH: join_buffer 中用哈希索引而非排序
SET join_cache_level = 8;  -- 启用 BKAH
-- join_cache_level 取值:
--   0: 不用 join buffer
--   1: BNL (Block Nested Loop)
--   2: BNL hashed
--   3: BKA flat
--   4: BKA incremental
--   5: BKA flat hashed (BKAH)
--   6: BKA incremental hashed (BKAH 增量版)
--   7-8: 高级变体

EXPLAIN SELECT * FROM orders o JOIN customers c ON o.cust_id = c.id;
-- Extra: "Using join buffer (incremental, BKAH join)"
```

BKAH 的优势：外侧 buffer 排序的 O(N log N) 变成哈希构建的 O(N)，且哈希探测是 O(1)。代价是哈希需要更多内存。

## PostgreSQL 18 Skip Scan 提案深入

### 技术背景

PostgreSQL 长期不实现 Skip Scan 的原因：

1. **B-Tree 实现的设计假设**：PG 的 B-Tree 假设所有谓词都是前缀匹配
2. **代价模型的复杂度**：估算 NDV × range scan 代价需要更多统计
3. **优先级**：社区资源更多投入到并行查询、Hash Join、JIT 等"通用"优化

直到 2024-2025，Peter Geoghegan（PG 主要 B-Tree 维护者）发起多轮 patch：

```
patch 系列: "Skip scan for B-tree indexes"
邮件列表: pgsql-hackers@lists.postgresql.org
关键设计:
  1. 扩展 _bt_first / _bt_next 内部 API
  2. 引入 "skip arrays" 概念: 跳过的列在内部用 IN-list 形式表达
  3. 与 Bitmap Index Scan 互补: skip scan 是单次 ordered 输出, bitmap 是无序
  4. 复用现有 ScanKey 机制: 不引入新数据结构
```

### 预期 API 变化

```c
// PostgreSQL 18 内部 B-Tree API（提案）
struct BTScanOpaque {
    // 现有字段
    BTScanPosData currPos;
    ScanKey       keyData;

    // 新增: skip scan 状态
    bool          skipScanActive;
    int           skipPrefixCols;       // 跳跃的前缀列数
    Datum*        currentSkipValues;    // 当前 skip 段的前缀值
    bool          advanceSkipPrefix;    // 是否需要跳到下一个段
};

// 关键修改: _bt_first 在 skip scan 模式下
// 1. 找到第一个 skip 前缀值（最小）
// 2. 用现有谓词在该前缀下做范围扫描
// 3. 扫描结束后调用 _bt_advance_skip 找下一个前缀
// 4. 重复直到没有更多前缀值
```

### 触发条件估算

```sql
-- PG 18 提案的触发条件（草案）:
-- 1. 索引前导列在查询中未出现等值或范围谓词
-- 2. 查询中至少有一个谓词覆盖索引非前导列
-- 3. 优化器估算: NDV(leading_cols) ≤ ndistinct_skip_threshold (~1000)
-- 4. 代价: NDV × (索引高度 + 单段范围代价) < 全索引扫描代价

-- 与现有计划的关系:
EXPLAIN
SELECT * FROM employees WHERE employee_id = 12345;

-- PG 17:
--  Seq Scan on employees  (cost=0.00..1234.00 rows=1)
--    Filter: (employee_id = 12345)

-- PG 18 (提案):
--  Index Scan using idx_emp on employees  (cost=8.50..16.55 rows=1)
--    Index Cond: (employee_id = 12345)
--    Skip Cond: (gender)              -- 新增
```

### 社区争论

社区对此 patch 的关注点：

1. **代价模型回归**：错误估算 NDV 会让 skip scan 选中差索引
2. **统计依赖**：skip scan 依赖准确的 `n_distinct`，但 ANALYZE 估算 n_distinct 历来精度有限
3. **并发更新**：skip scan 需在 B-Tree 跳跃时处理 split / vacuum
4. **EXPLAIN 兼容性**：是否引入新计划节点

## 各引擎完整对比

### 嵌套循环 + 索引访问的成熟度

| 引擎 | NL with Index | BKA / MRR | Skip Scan | 索引提示 |
|------|---------------|-----------|-----------|---------|
| Oracle | 是 (1988+) | 是 (Vector Index Access) | 是 (9i, 2001) | `INDEX_SS`, `USE_NL` |
| SQL Server | 是 | 是 (List Prefetch) | -- | `OPTION (LOOP JOIN)` |
| DB2 | 是 | 是 (List Prefetch) | 是 (Jump Scan, 10.5) | -- |
| MySQL | 是 | 是 (BKA, 5.6) | 部分 (5.0 GROUP BY, 8.0 range) | `BKA`, `INDEX` |
| MariaDB | 是 | 是 (BKA + BKAH, 5.3) | 部分 | `BKA`, `BKAH` |
| PostgreSQL | 是 | -- (PG18 计划) | -- (PG18 提案) | `pg_hint_plan` 扩展 |
| OceanBase | 是 | 是 | 是 (4.x) | `INDEX_SS` |
| TiDB | 是 (IndexJoin) | 部分 | -- | `INL_JOIN`, `INL_HASH_JOIN` |
| CockroachDB | 是 (lookup join) | -- | -- | -- |

### 引擎选型建议（OLTP 场景）

| 场景 | 推荐 | 原因 |
|------|------|------|
| 必须 Skip Scan + 复合索引复用 | Oracle / DB2 / OceanBase | 唯一原生支持的成熟引擎 |
| MySQL 兼容 + 大量 NL Join | MariaDB BKAH | 比 MySQL BKA 更优 |
| 等待 Skip Scan 的 PG 用户 | PostgreSQL 18+ (2025) | Peter Geoghegan 的 patch |
| 极致 NL with index 优化 | Oracle | 30+ 年优化积累 |
| 高频小查询 OLTP | MySQL/MariaDB + 正确索引顺序 | 避免依赖 skip scan |
| 分布式 OLTP NL | CockroachDB lookup join / TiDB IndexJoin | 显式语义 |

## 实现建议给引擎开发者

### 1. Index Nested Loop 的核心算子

```
IndexNestedLoopJoin {
    outer: TableScan(orders)
    inner: IndexAccess(customers, idx_id)
    join_key: o.cust_id = c.id

    fn execute() -> Iterator<Row>:
        for outer_row in outer:
            key = extract_join_key(outer_row)
            inner_iter = inner.lookup(key)
            for inner_row in inner_iter:
                yield combine(outer_row, inner_row)
}

// 关键优化:
//   1. 内侧索引访问尽量批量化（参见 BKA）
//   2. 外侧扫描可顺序读取
//   3. 内侧探测的 buffer pool 命中率至关重要
//   4. 与 prefetch 配合可隐藏 I/O 延迟
```

### 2. Batched Key Access 的实现要点

```
BatchedKeyAccess {
    join_buffer: Vec<Row>          // 大小由 join_buffer_size 控制
    sorted_keys: Vec<(Key, RowIdx)> // 排序后的 key 与原始行索引

    fn build_batch() -> bool:
        join_buffer.clear()
        while join_buffer.len() < buffer_capacity:
            row = outer.next()?
            join_buffer.push(row)
        return !join_buffer.is_empty()

    fn execute_batch():
        // 提取 + 排序 keys
        for (i, row) in join_buffer.iter().enumerate():
            sorted_keys.push((extract_key(row), i))
        sorted_keys.sort_by_key()

        // MRR 批量探测
        for (key, _) in sorted_keys:
            inner_index.prefetch(key)
        for (key, idx) in sorted_keys:
            inner_iter = inner_index.lookup(key)
            outer_row = join_buffer[idx]
            for inner_row in inner_iter:
                yield combine(outer_row, inner_row)
}

// 关键优化:
//   1. join_buffer 大小: 与 L2/L3 cache 对齐
//   2. 排序算法: 小批量用 insertion sort, 大批量用 radix sort
//   3. MRR 接口: 内侧存储引擎需暴露 prefetch / lookup_batch
//   4. 内存预算: 外侧行可能很大, 注意 buffer 实际容量
```

### 3. Skip Scan 的实现核心

```
SkipScanIterator {
    btree: BTreeIndex
    leading_cols: Vec<ColumnId>     // 要跳跃的前导列
    predicate: ScanKey              // 后续列的谓词

    current_prefix: Option<Vec<Datum>>  // 当前 skip 段的前缀值

    fn next() -> Option<Row>:
        loop:
            if current_prefix.is_none():
                // 第一次或上一段结束: 跳到下一个 distinct 前缀
                current_prefix = btree.find_next_distinct_prefix(
                    leading_cols, current_prefix
                )?
                // 在该前缀下设置范围扫描
                btree.position_with_prefix(current_prefix, predicate)

            // 在当前段内扫描
            if let Some(row) = btree.next_in_range():
                return Some(row)
            else:
                // 当前段扫描完毕, 跳到下一个
                current_prefix = None
                continue

    fn find_next_distinct_prefix(prefix: Option<Vec<Datum>>) -> Option<Vec<Datum>>:
        // 在 B-Tree 上利用 _bt_first / _bt_next 找到 leading_cols 上的下一个 distinct 值
        // 关键: 不是逐行扫描, 而是利用 B-Tree 索引结构跳跃
        if prefix.is_none():
            return btree.minimum_prefix(leading_cols)
        else:
            return btree.next_prefix_after(leading_cols, prefix)
}

// 关键优化:
//   1. find_next_distinct_prefix 必须 O(log N), 不能 O(N)
//   2. 利用 B-Tree 内部结构: 从 root 开始向右找第一个不等于 prefix 的叶子
//   3. 谓词下推到段内: 范围扫描时尽早过滤
//   4. 与代价模型集成: NDV 估算决定是否选用 skip scan
```

### 4. 代价模型集成

```
fn cost_skip_scan(
    index: &Index,
    leading_cols: &[ColumnId],
    predicate: &ScanKey,
    stats: &TableStatistics,
) -> Cost {
    let ndv = stats.n_distinct_combination(leading_cols);

    if ndv > NDV_THRESHOLD {
        return Cost::INFINITY;  // 不考虑 skip scan
    }

    let segment_cost = cost_index_range_scan(index, predicate);
    let total_cost = ndv * (B_TREE_HEIGHT_COST + segment_cost);

    // 与全索引扫描和全表扫描对比, 取最小
    let full_index_cost = cost_full_index_scan(index, predicate);
    let full_table_cost = cost_seq_scan(table, predicate);

    cmp::min(total_cost, cmp::min(full_index_cost, full_table_cost))
}
```

### 5. Index Prefetch / Async I/O 的实现

```
AsyncIndexScan {
    btree: BTreeIndex
    outstanding_io: Queue<IoRequest>  // 已发起未完成的 I/O
    prefetch_window: usize              // 提前几个 key 发起 I/O

    fn next() -> Option<Row>:
        // 维持滑动窗口: 一直保持 prefetch_window 个未完成 I/O
        while outstanding_io.len() < prefetch_window:
            if let Some(key) = self.lookahead.next():
                outstanding_io.push(btree.async_lookup(key))
            else:
                break

        // 等待最早发起的 I/O 完成
        let row = outstanding_io.pop_front()?.await
        return Some(row)
}

// 关键优化:
//   1. Linux io_uring (5.1+) / Windows OVERLAPPED 接口
//   2. prefetch_window 大小: 与磁盘队列深度对齐 (HDD ~32, SSD ~128)
//   3. 错误处理: I/O 失败时正确回退
//   4. 与 buffer pool 协作: 已在内存的 page 不发 I/O
```

### 6. 与 Vacuum / Concurrent Update 的交互

Skip Scan 实现的隐藏陷阱：

```
问题: skip 跳跃过程中, 其他事务可能在 B-Tree 上 split / merge / delete

解决方案 (PG 风格):
  1. Snapshot Isolation: skip scan 用单一 snapshot, 跳过期间不感知新插入
  2. B-Tree 版本号: 检测到 split 时回退到上一段重新定位
  3. WAL replay: 标准 MVCC 处理删除可见性
  4. _bt_first 的 race condition: 用 LWLock 保护跳跃过程

PG 18 提案中 Peter Geoghegan 特别处理了:
  - 并发 vacuum 删除 leaf page 时 skip scan 如何正确推进
  - INSERT 引发 page split 时跳跃位置的稳定性
```

### 7. 测试要点

```
功能测试:
  - 各种 NDV 大小 (1, 10, 100, 10000)
  - 谓词组合: 等值, range, IN-list, NULL 处理
  - 边界: 空表, 单行, NDV=1（退化为全索引扫描）
  - 升序 / 降序 / NULLS FIRST/LAST

性能测试:
  - 与全表扫描对比: NDV 多大时 skip 更优
  - 与全索引扫描对比: 选择性多低时 skip 更优
  - 与位图索引对比 (如果引擎支持)
  - I/O 次数与 NDV 的关系曲线

并发测试:
  - skip scan 期间并发 INSERT / DELETE / UPDATE
  - VACUUM 与 skip scan 的交互
  - 长事务 + skip scan 的快照一致性
```

## 设计争议

### Skip Scan 是否值得增加优化器复杂度？

PostgreSQL 社区的反对方观点：

1. **可通过添加正确索引解决**：建一个针对常用查询的索引比依赖 skip scan 更可控
2. **NDV 估算困难**：错误的 NDV 估算会导致选错索引，性能反而更差
3. **维护成本**：B-Tree 内部 API 改动大，影响后续优化（如 parallel index scan）

赞成方观点：

1. **OLTP 场景刚需**：单表 1 亿行带复合索引的查询，少一个索引能省 GB 级存储
2. **Oracle 25 年验证有效**：成熟代价模型 + 用户体验好
3. **不增加用户负担**：用户不需要写 hint，优化器自动选择

### Loose Index Scan 与 Skip Scan 的命名混乱

- **MySQL Loose Index Scan**：仅用于 GROUP BY MIN/MAX 的索引优化
- **MySQL Skip Scan Range Access**：8.0 引入的不同特性，类似 Oracle 但受限
- **Oracle Index Skip Scan**：通用前导列跳跃
- **DB2 Jump Scan**：等价于 Oracle Skip Scan

工程上这四个术语指向不同语义，文档查阅需特别注意。建议在跨引擎讨论时使用 "Loose Index Scan"（学术术语）作为统称。

### NL with Index vs Hash Join 的选择

```
传统经验法则:
  - 外侧行数 < 1000: NL with Index 几乎总是赢
  - 外侧行数 > 100万 且无选择性: Hash Join 赢
  - 中间区间: 看具体数据分布

现代修正:
  - SSD 普及后, NL 的随机 I/O 代价下降
  - BKA / List Prefetch / Vector Index Access 进一步优化 NL
  - 列存引擎几乎不用 NL（向量化效率压倒性）
  - OLTP 引擎仍以 NL 为主, OLAP 引擎以 Hash 为主
```

### Broadcast Join 与 NL 的关系

```sql
-- 分布式 broadcast join 在小表广播后, 各 worker 本地做的可能是:
-- 1. Hash Join (build 广播的小表)
-- 2. NL with Index (如果广播表已索引)

-- Spark / Trino 的 BHJ 通常是 Hash
-- Oracle RAC / DB2 DPF 可能是 NL with Index (跨节点广播)
```

## 关键发现

1. **Index Nested Loop 是 OLTP 的根基算子**：49 个引擎几乎全部支持，但成熟度差距巨大。Oracle 1988 年商用，30 多年的代价模型与执行优化（BKA、prefetch、skip scan）共同构成了 Oracle 在 OLTP 工作负载上的护城河。

2. **Skip Scan 的存在严重不均衡**：49 个引擎里只有 Oracle、DB2、OceanBase 完整支持；MySQL 仅在 GROUP BY MIN/MAX 受限场景；PostgreSQL 17 仍未支持，18 才在提案中。这是开源数据库与商用数据库长期最显眼的功能差距之一。

3. **Oracle Index Skip Scan 自 9i (2001) 商用**，比 PostgreSQL 提案早 24 年。其核心机制——前导列 NDV 阈值 + B-Tree 跳跃——25 年来未变，证明了算法本身的稳定性。

4. **MySQL Loose Index Scan 与 Skip Scan 是两个不同特性**：5.0 (2005) 的 Loose Index Scan 仅限 GROUP BY MIN/MAX；8.0 的 Skip Scan Range Access 才是类 Oracle 跳跃，但受限于"必须仅访问索引列"。两者命名混乱，文档查阅时需特别注意。

5. **MySQL BKA (5.6, 2013) 是 NL with Index 的关键里程碑**：把外侧 key 缓存→排序→批量探测，让随机 I/O 变顺序 I/O。在 SSD 时代收益略减但 OLTP 仍重要。MariaDB 的 BKAH（5.3, 2011）早于 MySQL 2 年且更优。

6. **PostgreSQL 18 Skip Scan 提案是 2024-2025 PG 社区最受关注的优化器特性之一**。Peter Geoghegan 作为 B-Tree 主要维护者，patch 经过多轮 review。如成功合入将填补 PG 与 Oracle 在 OLTP 索引访问路径上的 24 年差距。

7. **PostgreSQL BRIN (9.5, 2016) 不能替代 Skip Scan**：BRIN 是块级摘要索引，适用于"自然有序大范围裁剪"；Skip Scan 是 B-Tree 内部跳跃，适用于"前导列高重复"。两者解决相关但不同的问题。

8. **CockroachDB / TiDB 等分布式 OLTP 引擎不支持 Skip Scan**：它们的设计哲学倾向"用户应建正确索引"，且分布式 skip scan 的代价模型更复杂。CockroachDB 的 lookup join、TiDB 的 IndexJoin 是 NL with Index 的分布式版本，但与 skip scan 是不同维度。

9. **DuckDB / ClickHouse 的列存模型不需要 Skip Scan**：DuckDB 的 zone map / min-max 索引、ClickHouse 的 sparse primary index，在思想上覆盖了 BRIN 的角色。但它们没有 B-Tree 索引，所以传统意义的 skip scan 不适用。

10. **DB2 Jump Scan (10.5, 2013) 是 IBM 对 Oracle Skip Scan 的对应实现**，命名差异主要为商标考量。DB2 LUW 的代价模型在 NDV 估算不可靠时更保守，倾向回退。

11. **Index Prefetch 是 NL with Index 的隐藏关键**：Oracle table prefetching、SQL Server WithUnorderedPrefetch、DB2 List Prefetch 都是同一思想。PostgreSQL 在 17 仍不支持，这与 skip scan 的缺失共同构成 PG OLTP 工作负载的瓶颈点。

12. **HSQLDB / Derby / SQLite 的"仅 NL"模式**：这三个嵌入式引擎不实现 hash join，完全依赖 NL + index——这反而让 NL 在它们中是唯一物理算法。在小数据嵌入式场景下表现良好，但跨百万行连接时性能瓶颈明显。

13. **Broadcast Join 的命名与 NL/Hash 无直接对应**：分布式 broadcast 是 join 分发策略（小表全广播 vs 双侧重分区），与单机 NL/Hash 的物理算法选择是正交维度。Spark BHJ、Trino broadcast、ClickHouse GLOBAL JOIN 在分发后多数仍是 Hash Join。

14. **Skip Scan 与位图索引的功能重叠**：在 Oracle 中位图索引 + STAR_TRANSFORMATION 在 OLAP 场景常胜过 skip scan。但位图索引写并发差，OLTP 场景仍以 B-Tree + Skip Scan 为主。两者并非互斥，而是 OLTP/OLAP 工作负载的不同选择。

15. **OLTP 引擎在 NL with Index 优化上仍在追赶 Oracle**：MySQL 8.0、PostgreSQL 18 都在主动补齐这个 25 年技术差距。这反映了开源数据库优先发展并行查询、Hash Join、JIT 等"明显"优化，而对 NL 优化（看似传统）投入相对滞后的历史轨迹。

## 参考资料

- Oracle: [Index Skip Scans](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/optimizer-statistics-concepts.html)
- Oracle: [Performance Tuning Guide - Skip Scans](https://docs.oracle.com/cd/B19306_01/server.102/b14211/optimops.htm)
- MySQL: [Loose Index Scan](https://dev.mysql.com/doc/refman/8.0/en/group-by-optimization.html#loose-index-scan)
- MySQL: [Skip Scan Range Access Method](https://dev.mysql.com/doc/refman/8.0/en/range-optimization.html#range-access-skip-scan)
- MySQL: [Block Nested Loop and Batched Key Access Joins](https://dev.mysql.com/doc/refman/8.0/en/bnl-bka-optimization.html)
- MySQL: [Multi-Range Read Optimization](https://dev.mysql.com/doc/refman/8.0/en/mrr-optimization.html)
- MariaDB: [Block-Based Join Algorithms](https://mariadb.com/kb/en/block-based-join-algorithms/)
- PostgreSQL: [Loose Index Scan Wiki](https://wiki.postgresql.org/wiki/Loose_indexscan)
- PostgreSQL: [BRIN Indexes](https://www.postgresql.org/docs/current/brin.html)
- PostgreSQL Hackers: "Skip scan for B-tree indexes" (Peter Geoghegan, 2024-2025)
- SQL Server: [Nested Loops Operator](https://learn.microsoft.com/en-us/sql/relational-databases/showplan-logical-and-physical-operators-reference)
- DB2: [Jump Scan in DB2 LUW 10.5](https://www.ibm.com/docs/en/db2/11.5?topic=indexes-jump-scans)
- CockroachDB: [Lookup Joins](https://www.cockroachlabs.com/docs/stable/joins.html#lookup-joins)
- TiDB: [Index Join](https://docs.pingcap.com/tidb/stable/sql-statement-explain)
- Graefe, G. "Volcano - An Extensible and Parallel Query Evaluation System" (1994)
- Selinger, P.G. et al. "Access Path Selection in a Relational Database Management System" (1979)
- Bayer, R. & Unterauer, K. "Prefix B-Trees" (1977)
- Kim, W. "A New Way to Compute the Product and Join of Relations" (1980)
