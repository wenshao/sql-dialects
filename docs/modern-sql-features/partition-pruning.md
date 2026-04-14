# 分区裁剪 (Partition Pruning)

一张 10TB 的事实表被切成 1000 个分区，一次查询只扫 3 个分区还是全扫 1000 个，性能差距是三个数量级——**分区裁剪** (Partition Pruning) 就是把查询 WHERE 条件与分区定义做匹配、在执行前或执行中剔除无关分区的优化技术。它是分区存在的**第一价值**，没有分区裁剪，分区只会让写入变慢、元数据膨胀，而换不回任何查询收益。

本文聚焦**运行时裁剪**：从编译期静态常量裁剪，到绑定变量裁剪，再到基于 Join 另一侧的动态裁剪 (DPP)，以及 Bloom Filter、Min/Max 元数据跳块等与分区裁剪紧密相关的机制。文章所讨论的"分区策略对比"（Range/List/Hash/Composite 等 DDL 定义层面）请参见姊妹文 [partition-strategy-comparison.md](./partition-strategy-comparison.md)。

## 静态裁剪 vs 动态裁剪

| 类型 | 决策时机 | 输入 | 典型例子 |
|------|---------|------|---------|
| 静态裁剪 (Static) | 编译/优化阶段 | 字面常量 WHERE | `WHERE dt = '2026-04-15'` |
| 动态裁剪 (Dynamic, 绑定变量) | 执行首次绑定时 | 绑定参数 `:p1` / `?` | `WHERE dt = ?` |
| 运行时 Join 裁剪 (DPP / Runtime Filter) | 执行时从 Join 另一侧构建 | Hash build side 的值域 | `fact JOIN dim ON fact.dt = dim.dt WHERE dim.is_holiday=true` |
| 递归/相关裁剪 | 逐行执行 | 子查询结果 | `WHERE dt IN (SELECT max(dt) FROM ...)` |

三者的识别方式不同：静态裁剪在 `EXPLAIN` 中表现为"访问的分区列表"；动态裁剪在 `EXPLAIN (ANALYZE)` / `EXPLAIN ANALYZE VERBOSE` 中表现为"Subplans Removed / Dynamic Filters"；DPP 在 Spark/Trino 中表现为一个从 build 端到 probe 端的 runtime filter 连线。

## 无 SQL 标准

ISO/IEC 9075 (SQL:2016、SQL:2023) 均未定义分区裁剪——它完全是**优化器层面的实现特性**，而不是语言语义。SQL 标准里连分区 DDL 本身都只有 `PARTITION BY` 作为窗口函数关键字；物理分区 (`PARTITION BY RANGE`、`PARTITION BY HASH`) 是各厂商的方言扩展，裁剪行为自然也不在标准之列。这带来三个后果：

1. 同一个查询在不同引擎裁剪结果可能完全不同，甚至同一引擎不同版本也不同。
2. 是否裁剪、裁剪到几个分区只能通过 `EXPLAIN` 验证，不能用标准断言。
3. 厂商可以随意加新的裁剪类型（DPP、Bloom、Zone Map），向后兼容只需保证结果正确。

## 支持矩阵（45+ 引擎）

### 静态分区裁剪（常量 WHERE）

| 引擎 | 支持 | 起始版本 | EXPLAIN 体现 |
|------|------|---------|-------------|
| PostgreSQL | 是 | 10 (2017) 声明式；更早约束排除 | `Subplans/Partitions: ...` |
| MySQL | 是 | 5.1 (2008) | `EXPLAIN PARTITIONS` / 5.7+ 默认列 |
| MariaDB | 是 | 5.3 | `EXPLAIN PARTITIONS` |
| SQLite | 否 | -- | 无原生分区 |
| Oracle | 是 | 8i (1999) | `PARTITION RANGE/LIST/HASH` 行 |
| SQL Server | 是 | 2005 | `Partition Count` / `Actual Partition Count` |
| DB2 | 是 | LUW V8 / z/OS | `DP-ELIM` 标记 |
| Snowflake | 是 | GA | Micro-partition 扫描数 |
| BigQuery | 是 | GA | `Slots` + `Bytes billed` |
| Redshift | 是 | GA (Spectrum) | External table partition count |
| DuckDB | 是 | 0.9+ (Hive 分区) | Hive partition pruning 行 |
| ClickHouse | 是 | 早期 | `Selected X/Y parts` |
| Trino | 是 | 早期 | `Input: X partitions` |
| Presto | 是 | 早期 | 同 Trino |
| Spark SQL | 是 | 1.6 | `PartitionFilters: [...]` |
| Hive | 是 | 0.7 | `Partition filter predicate` |
| Flink SQL | 是 | 1.10+ | Partition pushdown |
| Databricks | 是 | GA | 同 Spark + Delta |
| Teradata | 是 | V2R5+ (PPI) | `PARTITION` step |
| Greenplum | 是 | 4+ | `Partition Selector` |
| CockroachDB | 部分 | 有限（索引分区） | -- |
| TiDB | 是 | 4.0+ | `partition:p0,p1` |
| OceanBase | 是 | 1.0+ | `PARTITION [p0,p1]` |
| YugabyteDB | 是 | 继承 PG 11+ | `Subplans Removed` |
| SingleStore | 是 | GA (shard key) | `Partitions: X/Y` |
| Vertica | 是 | GA | ROS container pruning |
| Impala | 是 | 1.0+ | `partitions=X/Y` |
| StarRocks | 是 | GA | `partitions=X/Y` |
| Doris | 是 | GA | `partitions=X/Y` |
| MonetDB | 部分 | MERGE TABLE 级 | -- |
| CrateDB | 是 | GA | Partition routing |
| TimescaleDB | 是 | 继承 PG + chunk exclusion | `Chunks excluded` |
| QuestDB | 是 | GA (time partition) | Partition scan count |
| Exasol | 否 | -- | 自动哈希分布，无用户分区 |
| SAP HANA | 是 | GA | `Partition pruning info` |
| Informix | 是 | 早期 (fragment elimination) | `Fragments scanned` |
| Firebird | 否 | -- | 无分区 |
| H2 | 否 | -- | 无分区 |
| HSQLDB | 否 | -- | 无分区 |
| Derby | 否 | -- | 无分区 |
| Amazon Athena | 是 | GA (继承 Trino/Hive) | `Input: X partitions` |
| Azure Synapse | 是 | GA | 分区消除 |
| Google Spanner | 是 | GA (interleaved + shard) | -- |
| Materialize | 部分 | -- | 视图级增量 |
| RisingWave | 部分 | -- | 流处理模型 |
| InfluxDB (SQL/IOx) | 是 | IOx | Time-chunk pruning |
| DatabendDB | 是 | GA | Block pruning |
| Yellowbrick | 是 | GA | Shard pruning |
| Firebolt | 是 | GA | Index pruning |

> 约 40 个引擎支持静态分区裁剪；不支持的基本都是单机嵌入式数据库（SQLite、H2、HSQLDB、Derby、Firebird）或采用"自动分布而非显式分区"模型的系统（Exasol）。

### 动态分区裁剪（绑定变量 / 运行时值）

| 引擎 | 支持 | 起始版本 | 备注 |
|------|------|---------|------|
| PostgreSQL | 是 | 11 (2018) | `Subplans Removed` / `(never executed)` |
| MySQL | 部分 | 5.7+ | 绑定参数在 PREPARE 时展开，裁剪发生在优化重解析 |
| MariaDB | 部分 | 同 MySQL | -- |
| Oracle | 是 | 9i (2001) | `KEY` / `KEY(INLIST)` 起始/结束分区 |
| SQL Server | 是 | 2008+ | `Seek Predicate: PtnIds` |
| DB2 | 是 | V9+ | -- |
| Snowflake | 是 | GA | Bind 值进入 pruner |
| BigQuery | 是 | GA | 参数化查询支持分区过滤 |
| Redshift | 是 | GA | -- |
| DuckDB | 是 | 0.9+ | -- |
| ClickHouse | 是 | 早期 | `WHERE dt = {param:Date}` |
| Trino | 是 | 早期 | Prepared statement |
| Spark SQL | 是 | 3.0+ | Driver side 值展开 |
| Hive | 否 | -- | 仅支持常量字面量，绑定变量通常无法裁剪 |
| Flink SQL | 是 | 1.12+ | Dynamic partition pruning (FLIP-248) |
| Databricks | 是 | GA | -- |
| Teradata | 是 | V2R6.2+ | Dynamic Partition Elimination |
| Greenplum | 是 | 4.3+ | Dynamic partition selection |
| TiDB | 是 | 6.0+ | Dynamic pruning mode |
| OceanBase | 是 | 2.0+ | -- |
| YugabyteDB | 是 | 继承 PG | -- |
| SingleStore | 是 | GA | -- |
| Vertica | 是 | GA | -- |
| Impala | 是 | 2.0+ | -- |
| StarRocks | 是 | GA | -- |
| Doris | 是 | GA | -- |
| TimescaleDB | 是 | 继承 PG + chunk_append | -- |
| QuestDB | 部分 | -- | -- |
| SAP HANA | 是 | GA | -- |
| Informix | 是 | 早期 | -- |
| Athena / Synapse / Firebolt | 是 | GA | -- |

> Hive 是本文唯一明确"仅支持静态裁剪"的主流引擎——它在编译时把分区目录列表固化进查询计划，绑定变量或非字面量函数（如 `WHERE dt = current_date()`）都会退化成全扫。这也是为什么 Hive 长期被 Spark/Trino 蚕食。

### Join 推入式动态裁剪（DPP / Runtime Filter）

| 引擎 | 支持 | 起始版本 | 名称 |
|------|------|---------|------|
| PostgreSQL | 否 | -- | 只做自身 WHERE 裁剪，不做 Join 推入 |
| Oracle | 是 | 11g | Bloom filter join pruning |
| SQL Server | 是 | 2016 | Bitmap filter / Adaptive Join |
| DB2 | 是 | LUW 10+ | -- |
| Snowflake | 是 | GA | Dynamic pruning via join |
| BigQuery | 是 | GA | Runtime filter |
| Redshift | 是 | GA | Bloom filter |
| ClickHouse | 部分 | 23.x+ | Set / join runtime filter（有限） |
| Trino | 是 | 330+ (2020) | Dynamic Filter |
| Presto | 是 | 0.230+ | Dynamic Filter |
| Spark SQL | 是 | 3.0 (2020) | DPP (Dynamic Partition Pruning) |
| Hive | 是 | Hive 2.x (Tez/LLAP) | Dynamic Partition Pruning |
| Flink SQL | 是 | 1.16+ | Runtime filter / DPP |
| Databricks | 是 | 6.x+ | DPP + DFP (Dynamic File Pruning) |
| Teradata | 是 | -- | -- |
| Greenplum | 是 | 5+ | Partition selector from hash join |
| TiDB | 是 | 6.0+ | Runtime filter (TiFlash) |
| Impala | 是 | 2.5+ | Runtime filter (Bloom/Min-Max) |
| StarRocks | 是 | GA | Global runtime filter |
| Doris | 是 | GA | Runtime filter |
| Vertica | 是 | GA | SIP (Sideways Information Passing) |
| SingleStore | 是 | 7.x+ | Bloom filter |
| DuckDB | 是 | 0.8+ | Bloom / zonemap pushdown |
| SAP HANA | 是 | GA | -- |
| Athena / Firebolt / Yellowbrick | 是 | GA | -- |
| MySQL / MariaDB / SQLite / Hive 1.x / Firebird / H2 / HSQLDB / Derby | 否 | -- | -- |

> Join 推入裁剪是分布式 OLAP 的分水岭：没有它，"星型模型 + 分区事实表 + 维度过滤"这个最常见的 BI 模式会退化成全表扫描。Spark 3.0 的 DPP 是其里程碑之一（见后文深入）。

### 按分区类型的裁剪能力

| 引擎 | Range 裁剪 | List 裁剪 | Hash 裁剪 | 多级子分区裁剪 |
|------|-----------|-----------|-----------|---------------|
| PostgreSQL | 是 | 是 | 是 (11+) | 是 (声明式嵌套) |
| MySQL | 是 | 是 | 是 | 是 (SUBPARTITION BY) |
| MariaDB | 是 | 是 | 是 | 是 |
| Oracle | 是 | 是 | 是 | 是 (Composite 全组合) |
| SQL Server | 是 | -- (无原生 List) | -- | 通过多列分区函数模拟 |
| DB2 | 是 | -- | -- | 是 |
| MySQL/Oracle 的 HASH 等值裁剪 | 等值 | 等值 + IN | 仅等值 / IN | -- |
| Snowflake | 自动 | 自动 | 自动 | 自动 (micro-partition metadata) |
| BigQuery | 是 (time/int range) | -- | -- | + 聚簇（非真正分区） |
| Redshift | 是 (Spectrum) | 是 | -- | -- |
| DuckDB | 是 (Hive 目录) | 是 | -- | 是 |
| ClickHouse | 是 | 是 | -- (不是分区概念) | + 跳数索引 |
| Trino / Presto | 是 | 是 | 是 (bucket) | 是 |
| Spark SQL | 是 | 是 | 是 (bucket) | 是 |
| Hive | 是 | 是 | 是 (bucket, 静态) | 是 |
| Flink SQL | 是 | 是 | 是 | 是 |
| Databricks | 是 | 是 | 是 | + Liquid Clustering |
| Teradata | 是 (PPI) | 是 | -- (自动 hash) | 是 (MLPPI) |
| Greenplum | 是 | 是 | 是 | 是 |
| TiDB | 是 | 是 | 是 (Hash/Key) | 部分 |
| OceanBase | 是 | 是 | 是 | 是 (二级分区) |
| YugabyteDB | 是 | 是 | 是 | 是 |
| SingleStore | 是 (shard key) | -- | 是 | -- |
| Vertica | 是 | 是 | -- (projection segmentation) | -- |
| Impala | 是 | 是 | 是 (Kudu) | 是 |
| StarRocks | 是 | 是 | 是 (bucket) | 是 |
| Doris | 是 | 是 | 是 (bucket) | 是 |
| CrateDB | 是 | -- | -- | -- |
| TimescaleDB | 是 (time chunks) | -- | 是 (space dimension) | 是 (time + space) |
| QuestDB | 是 (time only) | -- | -- | -- |
| SAP HANA | 是 | 是 | 是 | 是 |
| Informix | 是 | 是 | 是 | 是 |
| Athena | 是 | 是 | 是 (bucket) | 是 |
| Azure Synapse | 是 | -- | 是 (分布列) | -- |
| Spanner | 是 | -- | -- | Interleaved tables |
| Materialize | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- |
| InfluxDB IOx | 是 (time) | -- | -- | -- |
| DatabendDB | 是 | 是 | -- | -- |
| Yellowbrick | 是 | 是 | 是 | -- |
| Firebolt | 是 | -- | -- | -- |

### EXPLAIN 是否展示被裁剪分区

| 引擎 | EXPLAIN 显示保留分区 | EXPLAIN 显示被裁剪数 | 运行时裁剪统计 |
|------|-------------------|---------------------|---------------|
| PostgreSQL | 是（计划节点下子表） | 是 (`Subplans Removed: N`) | 是 (`(never executed)`) |
| MySQL | 是 (`partitions` 列) | 否（仅差集可推） | 否 |
| Oracle | 是 (`PSTART`/`PSTOP`) | 隐式 | `v$sql_plan_monitor` |
| SQL Server | 是 (`Partition Count`) | 隐式 | `Actual Partition Count` |
| ClickHouse | 是 (`Selected X/Y parts`) | 是 | 是 (详细的 parts、granules) |
| Snowflake | 是 (`partitionsScanned/partitionsTotal`) | 是 | QUERY_HISTORY 视图 |
| BigQuery | 是 (`Bytes processed`) | 隐式 (通过 bytes) | dry-run 支持 |
| Trino / Presto | 是 (`Input: X rows, Y partitions`) | 是 | 是 (Dynamic Filter 段) |
| Spark SQL | 是 (`PartitionFilters`) | 是 (`numPartitions`) | Spark UI SQL tab 显示 DPP |
| Hive | 是 (`Partition filter predicate`) | -- | -- |
| TiDB | 是 (`partition:p0,p1`) | 是 | Runtime stats |
| StarRocks / Doris | 是 (`partitions=X/Y`) | 是 | Profile |
| Impala | 是 (`partitions=X/Y files=...`) | 是 | Profile (runtime filters) |
| Vertica | 是 | 是 | QUERY_EVENTS |
| Greenplum | 是 (`Partition Selector`) | 是 | GPCC |
| Teradata | 是 | 是 | -- |
| DuckDB | 是 | 是 | PROFILE |

### LIMIT / Top-N 分区裁剪

当查询是 `ORDER BY partition_key DESC LIMIT N` 的形式，优化器理论上可以只扫最大的若干个分区。

| 引擎 | 支持 Top-N 分区停扫 | 备注 |
|------|-------------------|------|
| PostgreSQL | 是 (Append 节点按序返回 + LIMIT 提前终止) | 11+ 的 `Append -> Sort` 可按 partition 排序直出 |
| Oracle | 是 | `PARTITION RANGE ITERATOR`，按范围顺序扫描直到满足 LIMIT |
| SQL Server | 是 | Partition aligned index seek + Top |
| ClickHouse | 是 (`optimize_read_in_order`) | 按分区键 + 主键有序读 |
| TimescaleDB | 是 (`ChunkAppend` ordered) | 最常用于时序最新 N 行场景 |
| QuestDB | 是 | 时序表的核心优化 |
| InfluxDB IOx | 是 | 同上 |
| Trino / Presto | 部分 | 不保证跨分区顺序，除非按分区键排序且启用 ordered 执行 |
| Spark SQL | 部分 | 需要 `spark.sql.optimizer.topKOptimization` + 有序源 |
| Hive | 否 | 无 |
| MySQL | 否 | 不按分区顺序合并 |
| TiDB | 是 | 6.2+ 的 Partition-aware Top-N |
| Snowflake | 是 | LIMIT pushdown 到 micro-partition 扫描器 |

> Top-N 分区裁剪对"最新 100 条日志"、"最近一小时 DAU" 这类查询影响巨大，可从秒级降到毫秒级。

## 详细引擎解析

### PostgreSQL：从 constraint_exclusion 到声明式 + 运行时

PostgreSQL 的分区裁剪可以分成三个历史阶段：

1. **继承表 + constraint_exclusion** (8.1 – 9.6)：用户通过 `INHERITS` + `CHECK` 约束 + 触发器手工构建"分区表"，优化器在 `constraint_exclusion = on | partition` 时，把 WHERE 与每个子表的 CHECK 做一致性证明，不满足则跳过。此法**只在规划期生效、只处理常量**，且 CHECK 证明逻辑有限（只能处理 `=`、`<`、`<=`、`BETWEEN` 等简单谓词）。

2. **声明式分区** (10, 2017)：引入 `PARTITION BY RANGE / LIST / HASH` 语法和 `pg_inherits` 元数据，优化器直接从分区元数据生成裁剪，不再依赖 CHECK 证明。10 只做静态裁剪。

3. **运行时分区裁剪** (11, 2018)：提交 `499be013de` 引入 `Append` / `MergeAppend` 的运行时裁剪，三种场景：
   - **执行初始 (ExecInitNode)**：绑定参数、`$1` / `PREPARE`
   - **执行期 (each rescan)**：嵌套循环的相关参数、子查询结果
   - **Parallel Append**：每个 worker 独立裁剪

```sql
-- PG 11+ 的典型 EXPLAIN
EXPLAIN (ANALYZE)
SELECT * FROM orders WHERE created_at = $1;

-- Append  (actual rows=...)
--   Subplans Removed: 364    <-- 运行时被裁掉 364 个分区
--   ->  Seq Scan on orders_2026_04_15  (actual rows=...)
```

PG 的不足：不做 join 推入 DPP，一直到 17（2024）仍然是 "planner knows static, executor knows bind vars"，跨表动态裁剪只能靠开发者写子查询/CTE 手工触发。

### Oracle：分区裁剪的教科书

Oracle 8i (1999) 首发分区裁剪，9i (2001) 引入绑定变量动态裁剪，11g (2007) 引入 Bloom filter join pruning，19c 引入 hybrid partition。经过 25 年迭代，其 EXPLAIN 中 `PSTART` / `PSTOP` 两列是所有引擎最清晰的裁剪指示：

| PSTART | PSTOP | 含义 |
|--------|-------|------|
| `1` | `1` | 精确单分区 |
| `3` | `7` | 范围 3..7 |
| `KEY` | `KEY` | 运行时决定 |
| `KEY(INLIST)` | `KEY(INLIST)` | IN 列表运行时迭代 |
| `1` | `1048575` | 无法裁剪，全扫 |

典型计划节点包括 `PARTITION RANGE SINGLE`、`PARTITION RANGE ITERATOR`、`PARTITION RANGE ALL`、`PARTITION RANGE INLIST`、`PARTITION LIST`、`PARTITION HASH` 和 **`PARTITION JOIN FILTER`**（11g 的 Bloom filter pruning）。后者在星型事实表 + 维度表场景下极其高效：

```sql
-- Oracle 11g+ Bloom filter partition pruning
SELECT /*+ USE_HASH(f d) */ *
FROM   sales_by_day f          -- RANGE(sale_date) 1095 个分区
JOIN   dim_date d  ON f.sale_date = d.sale_date
WHERE  d.is_holiday = 'Y';

-- 执行计划会看到:
-- PART JOIN FILTER CREATE :BF0000     <- 从 d 侧构建 Bloom filter
-- PARTITION RANGE JOIN-FILTER         <- 用 BF 裁剪 f 侧分区
--   PSTART KEY(JOIN FILTER) PSTOP KEY(JOIN FILTER)
```

### SQL Server：分区消除与 2005 起的稳定实现

SQL Server 2005 引入"水平分区表"及分区函数 (`CREATE PARTITION FUNCTION`)。分区裁剪在查询优化器中称为 **Partition Elimination**，通过 `$PARTITION.pf(value)` 函数映射列值到 partition id，优化器把 WHERE 谓词下推成 partition id 范围，`Index Seek` 的 `Seek Predicate` 会包含 `PtnIds1001`、`PtnIds1001–1005` 这样的字段。

动态裁剪在 2008+ 稳定支持，2016+ 引入 **batch mode + bitmap filter**，在列存表 (columnstore) 上自动启用，类似 Bloom filter 的维度-事实裁剪。

### MySQL：5.1 首发的 EXPLAIN PARTITIONS

MySQL 5.1 (2008) 引入原生分区，同时引入 `EXPLAIN PARTITIONS`（5.7 起合并进标准 `EXPLAIN` 的 `partitions` 列）。MySQL 分区裁剪特点：

- **支持**：RANGE、LIST、HASH、KEY 以及 RANGE COLUMNS / LIST COLUMNS；等值、IN、BETWEEN、`<`/`>`、AND/OR 组合
- **不支持**：跨 Join 推入、函数内列（除了官方允许的 `YEAR()`、`TO_DAYS()` 等少数分区函数）、用户自定义函数
- **限制**：优化器在 `PREPARE` 时对参数化查询做"参数展开后再优化"，动态裁剪效果依赖 `prepared_stmt_count` 和 `optimizer_switch`

MySQL 的分区一直被视为"锦上添花"：InnoDB 的聚簇索引已经把绝大多数 OLTP 场景的范围查询处理得很好，分区主要用于归档和大表 DDL 分治。

### ClickHouse：分区 + 主键 + 跳数索引三位一体

ClickHouse 的"分区"与其说是数据路由，不如说是**数据合并单元**：`PARTITION BY toYYYYMM(event_date)` 只影响 parts 的物理分组和 TTL/drop partition 操作，真正的查询性能来自**主键 (ORDER BY) 跳块** + **跳数索引 (data skipping index)**。但三者在 WHERE 裁剪时是协同工作的：

```sql
CREATE TABLE events (
    event_date Date,
    user_id UInt64,
    event_type LowCardinality(String),
    INDEX idx_type event_type TYPE set(100) GRANULARITY 4
) ENGINE = MergeTree
PARTITION BY toYYYYMM(event_date)
ORDER BY (user_id, event_date);

SELECT count() FROM events
WHERE event_date = '2026-04-15' AND event_type = 'click';
-- 1. partition pruning: 只选 202604 这一个 month-part
-- 2. primary key mark range: 在 202604 内按主键二分到 user_id * event_date 的 granule
-- 3. skipping index: 跳过没有 'click' 的 granule
-- EXPLAIN 显示: Selected 1/12 parts, 4096/1048576 granules
```

### Snowflake：micropartition 的全自动裁剪

Snowflake 没有用户定义的分区 DDL——它把表切成 50–500MB 的不可变列存文件，称为 **micropartition**。每个 micropartition 自动维护列级 min/max/distinct-count/null-count 统计，优化器在 compile 期把 WHERE 谓词与所有候选 micropartition 的 min/max 做相交，只读保留下来的。这是一种"事实上的 list/range 分区裁剪"，且对所有列同时生效（而不是只对分区键）。

```sql
-- 可以在 EXPLAIN 和 QUERY_HISTORY 中看到:
-- partitionsScanned: 47
-- partitionsTotal:   23891
```

用户可以用 `CLUSTER BY (col1, col2)` 指定聚簇键，让数据按该键重排，提高 min/max 的有效性，但这不是"分区"——它只是提高自动裁剪的命中率。

### BigQuery：require_partition_filter 强制守门

BigQuery 的表可以按 `_PARTITIONTIME`、`DATE/TIMESTAMP` 列或整数列分区。真正让 BQ 出名的是一个建表选项：

```sql
CREATE TABLE `proj.ds.events`
PARTITION BY DATE(event_ts)
OPTIONS (
    require_partition_filter = TRUE   -- 缺少 WHERE event_ts 过滤则拒绝执行
);
```

当表设置了 `require_partition_filter = TRUE`，任何不包含分区列过滤的查询会在编译期直接报错：

```
Cannot query over table 'proj.ds.events' without a filter over column(s) 'event_ts'
that can be used for partition elimination
```

这不是运行时保护，而是**计费保护**——BQ 按扫描字节收费，一次忘写 `WHERE event_ts` 就可能烧掉几百美元。官方推荐所有 TB 级以上事实表开启此选项。BQ 的分区裁剪本身相当朴素（只做静态 + 参数化），但因强制过滤 + 每分区独立 metadata 的组合，实际效果常优于没开此选项的 Snowflake / Redshift。

### Spark SQL：Dynamic Partition Pruning (DPP, 3.0)

Spark SQL 在 3.0 (2020) 前只做静态分区裁剪——`WHERE dt='2026-04-15'` 有效，但 `fact JOIN dim WHERE dim.flag=true` 没用。3.0 的 SPARK-11150 落地 DPP，详见后文专节。

### Trino：运行时动态过滤

Trino 330 (2020) 正式把 **Dynamic Filter** 纳入默认执行路径。其模型与 Spark DPP 类似但更通用：

1. Join 的 build 端（小表）先执行完成，收集到 join key 的所有值（或 Bloom filter / min-max range）。
2. 这些值作为 runtime filter 通过 coordinator 推送给 probe 端的 TableScan。
3. probe 端在读取文件时，对分区列用这个 filter 做分区裁剪、对非分区列做 ORC/Parquet stripe/row-group 跳过。

```
Dynamic filters:
    df_123 -> [min: 2026-04-01, max: 2026-04-15, values ~ 14]
```

Trino 的 dynamic filter 不仅裁剪分区，还裁剪文件、stripe、甚至 row group，是 Iceberg / Delta 查询性能的核心。

### TiDB：分区裁剪 + TiFlash 协同

TiDB 4.0 正式支持 Range / List / Hash 分区（早期版本的 Range 分区处于实验状态），6.0 引入 **Dynamic Pruning Mode**，把"为每个分区生成独立 TableReader"改成"生成一个带 `partition:` 标签的 TableReader"，优化器下发时在每个 TiKV region 上只读需要的分区 region。TiFlash (列存副本) 继承此行为，并额外做 min/max 跳块。

```sql
EXPLAIN SELECT * FROM orders PARTITION(p202604) WHERE uid = 123;
-- 或者自动裁剪:
EXPLAIN SELECT * FROM orders WHERE created_at >= '2026-04-01' AND uid = 123;
-- TableReader  partition:p202604
--   └─ Selection uid = 123
--       └─ TableFullScan table:orders
```

### MySQL：EXPLAIN PARTITIONS 的边界案例

MySQL 的分区裁剪虽然 2008 就有，但功能边界一直被低估。以下是常被踩坑的几个事实：

1. **分区表达式必须是整数**（或 DATE/DATETIME 经由 `TO_DAYS`、`TO_SECONDS`、`YEAR`、`UNIX_TIMESTAMP` 这几个白名单函数转成的整数）。字符串列的 `LIST` 分区要靠 `LIST COLUMNS` 语法，`RANGE COLUMNS` 也同理。非 COLUMNS 版本不支持字符串。
2. **裁剪不透明跨 TZ**：`WHERE ts = '2026-04-15 00:00:00'` 如果会话时区与分区函数假设的时区不一致，优化器只会做"表达式对比"，很容易退化到全扫。
3. **NULL 进第一个分区**：RANGE 分区下 NULL 视为"最小值"，落在首个分区；LIST 分区需显式 `NULL` 出现在某个列表里。裁剪时 `WHERE c IS NULL` 会尝试裁到首个分区而不是全扫。
4. **分区表不能带全局 UNIQUE 索引**（除非 UK 包含全部分区列）：这个限制使得大表的 OLTP 方案必须在"全局唯一性"和"分区裁剪"之间二选一。
5. **`EXPLAIN` 的 `partitions` 列显示的是"可能访问"的分区列表**，真正访问数需要 `EXPLAIN ANALYZE` (8.0+) 或 performance_schema。
6. **PREPARE + 绑定参数**：5.7 之前参数化查询几乎不裁剪；8.0 起优化器对简单绑定参数可以裁剪，但涉及 IN 列表的仍然退化。

```sql
-- MySQL 8.0
CREATE TABLE orders (
    id BIGINT NOT NULL,
    created DATE NOT NULL,
    user_id BIGINT NOT NULL,
    PRIMARY KEY (id, created)
)
PARTITION BY RANGE (TO_DAYS(created)) (
    PARTITION p202603 VALUES LESS THAN (TO_DAYS('2026-04-01')),
    PARTITION p202604 VALUES LESS THAN (TO_DAYS('2026-05-01')),
    PARTITION p202605 VALUES LESS THAN (TO_DAYS('2026-06-01')),
    PARTITION pmax    VALUES LESS THAN MAXVALUE
);

EXPLAIN SELECT * FROM orders
WHERE created BETWEEN '2026-04-10' AND '2026-04-20';
-- partitions: p202604           <- OK

EXPLAIN SELECT * FROM orders
WHERE DATE_FORMAT(created, '%Y-%m') = '2026-04';
-- partitions: p202603,p202604,p202605,pmax   <- 全扫, 函数非白名单
```

### SQL Server：分区对齐索引与 2016 批处理位图

SQL Server 的分区架构分两层：**分区函数** (`CREATE PARTITION FUNCTION`) 定义边界值，**分区方案** (`CREATE PARTITION SCHEME`) 把分区映射到文件组。表和索引通过 `ON scheme(col)` 附着到分区方案上。关键概念：

- **对齐索引 (Aligned Index)**：索引与表使用同一个分区函数，此时每个分区在物理上是一个独立的 B-tree，`Partition Elimination` 直接在 seek 时跳过无关 B-tree。
- **非对齐索引**：索引跨所有分区，失去分区裁剪收益，但支持全局约束。
- **`$PARTITION` 函数**：`SELECT *, $PARTITION.pf_sales(sale_date) FROM sales` 可以看每行归属的 partition id，也常用于手写裁剪提示。
- **Partition-Aligned Index Views**：索引视图若按分区列分区，SWITCH PARTITION 操作才能 O(1)。

SQL Server 2016 引入列存表 (`CLUSTERED COLUMNSTORE INDEX`) + **Batch Mode Bitmap Filter**。在星型 join 场景下，Batch mode 会自动在 build 侧（维度表）构建一个 bitmap，broadcast 给 probe 侧（事实表）。这个 bitmap 会作用于：

1. Rowgroup elimination（列存 rowgroup 级裁剪，基于 min/max）
2. Partition elimination（如果事实表分区键与 join key 一致）
3. Batch mode hash probe 早退

```sql
-- EXPLAIN 里会看到:
-- Bitmap(HASH:([d].[date_key]), DEFINE:([Bitmap1001]))
-- Clustered Index Scan ... WHERE PartitionID in Seek(...)
--   PROBE([Bitmap1001]) ...
```

这相当于 SQL Server 对 Oracle `PARTITION JOIN FILTER` 的等价实现，只是仅在列存 + Batch mode 下自动启用。

### Hive：静态裁剪陷阱与 Tez DPP 的补救

Hive 的分区是**目录级物理分区**：`/warehouse/fact/dt=2026-04-15/region=us/part-0000.orc`。好处是文件系统 ls 即可枚举分区；坏处是 metastore 的分区元数据膨胀（几十万分区的表 ls 都会超时）。

Hive 1.x/MR 引擎只有静态裁剪：

```sql
SELECT * FROM fact WHERE dt = '2026-04-15';             -- OK
SELECT * FROM fact WHERE dt = DATE_SUB(CURRENT_DATE, 1); -- 1.x: 全扫！
SELECT * FROM fact f JOIN dim d ON f.dt=d.dt WHERE d.flag=1; -- 1.x: 全扫！
```

Hive 2.x 起，在 Tez / LLAP 执行引擎下支持 **Hive Dynamic Partition Pruning**（通过 `hive.tez.dynamic.partition.pruning = true`），机制与 Spark DPP 类似：map join 的 build 端把 join key 的 distinct 值通过 event 广播给 probe 端的 mapper，动态选择要读的分区目录。但配置复杂、内存占用大，且 MR 引擎下仍不支持。这是"迟到的修补"而非设计上的起点。

Hive 的另一个痛点：**函数表达式不会被推入分区**。`WHERE year(dt) = 2026` 永远全扫，必须改写成 `WHERE dt >= '2026-01-01' AND dt < '2027-01-01'`。好在 Calcite + HiveCBO 在 3.x 对部分常见函数做了展开，但覆盖仍然不全。

### TimescaleDB：chunk exclusion 与 continuous aggregate

TimescaleDB 把超表（hypertable）切成以时间为主维度、可选空间为第二维度的 chunk。chunk 本质是 PG 11 的声明式分区子表，但 Timescale 自带一个定制的 `ChunkAppend` 计划节点，支持：

- **编译期 chunk exclusion**：与 PG 的声明式分区裁剪一致。
- **运行时 chunk exclusion**：PG 11 运行时裁剪的超集，额外支持按 chunk 的 min/max 统计（不只是分区边界）做裁剪。
- **有序 ChunkAppend**：按时间倒序读 chunk，配合 `LIMIT N` 可以提前终止。对"最近 1000 条观测"这类查询性能秒杀原生 PG。
- **连续聚合 (continuous aggregate)**：预计算的物化视图，查询时根据时间范围自动决定"聚合表 + 实时追尾原始 chunk"的组合，本质是多级分区裁剪。

### ClickHouse projection 与 skipping index 的组合裁剪

ClickHouse 在 21.6 (2021) 引入 **projection**——表级的"另一套 ORDER BY + 列裁剪 + 预聚合"，查询时优化器自动选最便宜的 projection。projection 与原表共享分区定义，但可以有完全不同的 ORDER BY，也就拥有不同的 mark range 裁剪能力。一个典型用法：

```sql
ALTER TABLE events ADD PROJECTION p_by_type (
    SELECT * ORDER BY (event_type, event_date, user_id)
);
ALTER TABLE events MATERIALIZE PROJECTION p_by_type;

-- 原表 ORDER BY (user_id, event_date)：按 user 查询高效
-- projection  ORDER BY (event_type, event_date, user_id)：按类型查询高效
```

查询 `WHERE event_type='click' AND event_date = '2026-04-15'` 时优化器会走 projection，先做分区裁剪，再在 projection 的主键上做 mark range 二分，最后可能还叠加跳数索引。这是"多物理副本 + 自动选择"的分区裁剪范式。

### StarRocks / Doris：分区 + 分桶 + Global Runtime Filter

StarRocks 和 Doris 的共同架构：表先按 `PARTITION BY` (通常是时间) 切成分区，每个分区再按 `DISTRIBUTED BY HASH(col) BUCKETS N` 切成桶。查询时的裁剪顺序：

1. **分区裁剪**：WHERE 谓词匹配分区列 → 选出保留分区集合
2. **分桶裁剪**：WHERE 等值谓词匹配分桶列 → 从每个保留分区中只选一个桶
3. **前缀索引裁剪**：在选中的 tablet 内用前缀索引二分
4. **Bitmap / BloomFilter / ZoneMap**：在 segment 内做行级裁剪
5. **Global Runtime Filter**：从 join build 侧构建 BF / MinMax / IN filter，广播给 probe 侧用于再次分区/分桶/行级裁剪

StarRocks 2.3+ 的 Global Runtime Filter 可以同时做 Bloom、MinMax 和 IN 三种形态，小表 build 时自动选择最便宜的。Doris 2.0 的实现大同小异。

### Impala runtime filter 的双模式

Impala 从 2.5 (2016) 起支持 runtime filter，分两种：

- **Bloom Filter**：大 build 端（几十万到几百万行）使用，假阳性可接受。
- **Min-Max Filter**：小 build 端使用，配合 Parquet/Kudu 的 min-max stats 对 row group 做精准跳过。

两者可以同时启用，`runtime_filter_mode` 控制 local/global 传递范围。Impala 的一个独特优化是 **filter 等待时长自适应**：probe 侧的 scan 不是立即开始，而是等待一个 `runtime_filter_wait_time_ms`（默认 1 秒），期望在此期间 build 完成并下发 filter；若超时则降级为无 filter 扫描。这种"有限等待 + 优雅降级"模式被后续很多引擎借鉴。

### DuckDB 的 Hive 分区与 zonemap 协同

DuckDB 没有传统意义上的"分区表 DDL"，但它对 `read_parquet('s3://bucket/events/*/*.parquet', hive_partitioning=true)` 这种目录结构的 Hive 分区路径提供一等支持：

1. 扫描目录构建分区文件列表（可被 `glob` 缓存）。
2. 按 WHERE 谓词对目录名编码的分区列做裁剪。
3. 读取选中文件时，用 Parquet footer 的 min/max 再做 row group 级裁剪。
4. Join 时通过 hash build 端构建 Bloom / MinMax filter 推给 probe 扫描。

对于嵌入式 OLAP 场景，DuckDB + Hive 分区目录 + Parquet 的组合已经成为"轻量版 Trino"的事实标准。

## 常见反模式与修复

分区裁剪失效的原因绝大多数不在引擎，而在查询写法。下面是跨引擎最常见的反模式：

| 反模式 | 症状 | 修复 |
|-------|------|------|
| `WHERE DATE(ts) = '2026-04-15'` | 函数包住分区列，裁剪失效 | 改为 `WHERE ts >= '2026-04-15' AND ts < '2026-04-16'` |
| `WHERE ts = '2026-04-15'::timestamptz` 类型不匹配 | 隐式转换导致优化器放弃裁剪 | 保持类型一致，或在常量侧转换 |
| `WHERE ts BETWEEN (SELECT MIN(...)) AND (SELECT MAX(...))` | 相关子查询在某些引擎不触发裁剪 | 两步：先算出边界，再在主查询里用字面值 |
| `WHERE partition_col IN (SELECT col FROM other)` | 无 DPP 引擎下退化全扫 | 预先 `SELECT DISTINCT` 物化成数组，或改用 JOIN + DPP |
| `OR` 跨分区列与非分区列 | OR 打破谓词下推 | 拆成 UNION ALL 分别裁剪 |
| `CAST(dt AS VARCHAR) LIKE '2026%'` | 类型转换 + LIKE，几乎总是全扫 | 用范围谓词 |
| 绑定参数类型与列类型不一致 (`?::text`) | 引擎放弃运行时裁剪 | JDBC 连接串加 `stringtype=unspecified` 或显式 cast |
| 在 `LEFT JOIN` 的 ON 里过滤分区列 | BigQuery `require_partition_filter` 不认、且逻辑上对空值侧无效 | 把过滤移到 WHERE（等价于 INNER），或使用 EXISTS |
| `UNION ALL` 两个分区表，WHERE 在外层 | 老优化器不下推到各分支 | 把 WHERE 下推到每个 UNION 分支 |
| `GROUP BY dt ... HAVING dt='2026-04-15'` | HAVING 不参与分区裁剪 | 把谓词移到 WHERE |
| 视图里用 `row_number() OVER (PARTITION BY ...)` 再外层过滤 | 窗口函数把分区列变成中间结果 | 预过滤或改写成侧查询 |
| Spark 在 DPP 前用 CTE 复用 dim | CTE 被 inline 两次，DPP 只命中一次 | `spark.sql.optimizer.excludedRules` 调整或物化 dim |

## 分区裁剪与其他裁剪机制的关系

为了帮助理解，下面列出"裁剪技术栈"——分区裁剪只是金字塔的最上层：

| 层级 | 裁剪单位 | 典型大小 | 技术名称 |
|------|---------|---------|---------|
| 1. 分区 / micropartition | 100MB – 100GB | 目录 / 文件组 | Partition Pruning |
| 2. 文件 / part | 10MB – 1GB | 单个 Parquet/ORC/ClickHouse part | File / Part Pruning |
| 3. Row group / stripe | 64KB – 128MB | Parquet row group, ORC stripe | Row Group Filtering |
| 4. Granule / mark range | 8KB – 1MB | ClickHouse granule (8192 行) | Mark Range Skipping |
| 5. Page | 4KB – 16KB | B-tree 叶页、列存 page | Page / Zone Map |
| 6. 行 | 单行 | 谓词求值 | Row Filter / Predicate Pushdown |

现代 OLAP 引擎的关键能力是把**同一个 WHERE 谓词**同时应用到所有六层，这就是"谓词下推"的终极形式。分区裁剪是最便宜的（无需读任何数据就能跳过），但单独存在意义有限——Snowflake、BigQuery、ClickHouse 的成功就在于"分区裁剪只是统一裁剪框架的一个层级"。

## 深入 Spark DPP

Spark 3.0 之前，下面这个最典型的 BI 查询性能灾难：

```sql
SELECT f.region, SUM(f.amount)
FROM   sales f                   -- PARTITIONED BY (sale_date)  3 年 × 365 天 ≈ 1095 分区
JOIN   dim_date d ON f.sale_date = d.sale_date
WHERE  d.is_weekend = true       -- 大约 312 天
GROUP BY f.region;
```

Catalyst 只能识别 `f` 上的常量 WHERE 谓词，对 `d.is_weekend=true` 无能为力，结果就是 `sales` 全扫 1095 个分区。DPP 的核心想法：**如果 join key 同时是 probe 侧的分区键**，那么 build 侧扫完后其 join key 的去重集合就是 probe 侧需要扫的分区集合。

Spark 3.0 的实现（SPARK-11150 / `PartitionPruning.scala`）步骤：

1. 在逻辑优化阶段，识别 `fact JOIN dim ON fact.part_col = dim.col` 这样的结构，且 fact 侧 `part_col` 是分区列。
2. 插入一个 `DynamicPruningSubquery`：`fact.part_col IN (SELECT dim.col FROM dim WHERE dim.filter)`。
3. 物理计划生成时，如果 join 是 broadcast hash join，子查询会**复用** broadcast 的结果（零额外扫描）；否则会额外起一个子查询拿到 distinct values。
4. `FileSourceScanExec` 在运行时把这些值作为 partition filter 应用。

控制参数：

```
spark.sql.optimizer.dynamicPartitionPruning.enabled = true  (3.0 默认开)
spark.sql.optimizer.dynamicPartitionPruning.useStats = true
spark.sql.optimizer.dynamicPartitionPruning.fallbackFilterRatio = 0.5
spark.sql.optimizer.dynamicPartitionPruning.reuseBroadcastOnly = true
```

**reuseBroadcastOnly** 的取舍：设为 true 表示只有能复用 broadcast 的情况下才启用 DPP，避免为一次额外扫描付出代价；设为 false 则可能对大 join 也启用 DPP，代价是多扫一次 dim 但换来 fact 侧大幅裁剪。Databricks Photon 在此基础上扩展成 **Dynamic File Pruning (DFP)**，把裁剪粒度从分区级降到文件级，对 Delta Lake 的 z-order 数据效果显著。

## 深入 BigQuery require_partition_filter

这是 BigQuery 在 2018 年引入的表选项，后被广泛模仿（Snowflake 的 warehouse level 查询守卫、Databricks 的 SQL warehouse cost guardrails、Redshift Spectrum 的 `CREATE EXTERNAL TABLE ... TBLPROPERTIES('spectrum_scan_all_partitions'='false')`）。

```sql
-- 建表时强制
CREATE TABLE `proj.ds.logs` (
    ts TIMESTAMP,
    user_id INT64,
    event STRING
)
PARTITION BY DATE(ts)
CLUSTER BY user_id, event
OPTIONS (
    require_partition_filter = TRUE,
    partition_expiration_days = 365
);

-- 或对已有表:
ALTER TABLE `proj.ds.logs` SET OPTIONS (require_partition_filter = TRUE);
```

**执行规则**：

1. 查询必须在 `WHERE`、`JOIN ON` 或 `FILTER` 中包含一个**可被优化器静态解析为分区列范围**的谓词。
2. `WHERE DATE(ts) = CURRENT_DATE()` 通过（函数可在编译期折叠）。
3. `WHERE DATE(ts) = (SELECT max_date FROM other)` **不通过**——相关子查询不能被静态折叠，即使逻辑上只会命中一个分区。
4. `LEFT JOIN` 的 ON 条件里的分区谓词不算在内（因为右表缺失时仍需扫全表）。
5. 如果有 `_PARTITIONTIME` 伪列，过滤该列同样生效。

常见"绕过"反模式及其代价：

| 写法 | 是否通过检查 | 是否真正裁剪 |
|------|------------|------------|
| `WHERE ts > TIMESTAMP('2026-04-01')` | 是 | 是 |
| `WHERE ts > (SELECT MAX(ts) FROM logs)` | 否 | -- |
| `WHERE DATE(ts) BETWEEN @d1 AND @d2` | 是 | 是 |
| `WHERE ts IS NOT NULL` | 否 | 无意义 |
| `WHERE CAST(ts AS STRING) LIKE '2026%'` | 否（函数不可折叠） | 否 |

对团队的建议：

- 生产 fact 表**默认开启** `require_partition_filter = TRUE`。
- 在 dbt / Dataform / SQLMesh 等工具链中配套开启 **dry-run cost check**，在 CI 阶段拒绝超预算的查询。
- 监控 `INFORMATION_SCHEMA.JOBS_BY_PROJECT` 中的 `total_bytes_billed`，把"未裁剪查询"作为报警项。

## 其他引擎速览

### Redshift：Spectrum 分区 + Zone Map

Redshift 本身不是按"用户分区"模型设计的：内部表用的是 **sort key + zone map**（每个 1MB 块自动维护 min/max），等价于 Snowflake 的 micropartition。真正的分区裁剪发生在 **Redshift Spectrum**（外部表指向 S3 上的 Hive 分区目录），语法：

```sql
CREATE EXTERNAL TABLE spectrum.events (
    user_id BIGINT, event STRING, ts TIMESTAMP
)
PARTITIONED BY (dt DATE)
STORED AS PARQUET
LOCATION 's3://my-bucket/events/';

ALTER TABLE spectrum.events ADD PARTITION (dt='2026-04-15')
LOCATION 's3://my-bucket/events/dt=2026-04-15/';
```

Spectrum 的分区裁剪是静态 + 绑定参数，不做 join DPP。但 Redshift 2022 年起引入 **Redshift Spectrum Bloom Filter**，允许内部表的 join 结果作为 Bloom filter 下推到 Spectrum 扫描器，间接实现了一种跨引擎的 DPP。

### Databricks：DPP + DFP + Liquid Clustering

Databricks 在 Spark DPP 基础上叠了两层：

1. **Dynamic File Pruning (DFP)**：DPP 把裁剪粒度降到分区，DFP 把粒度降到 Delta Lake 的**文件**。Delta 的每个 parquet 文件在 `_delta_log` 中记录了所有列的 min/max（不仅分区列），DFP 在 join 构建侧完成后，把 runtime filter 应用于这些 min/max 跳过整个文件。
2. **Liquid Clustering** (2023)：Delta Lake 3.0 引入的"非分区聚簇"，替代传统分区 + z-order。用户声明 `CLUSTER BY (col1, col2)`，Delta 自动维护数据局部性，裁剪仍然有效但无需用户挑分区键。

配合 **Photon** 执行引擎，DFP 的命中率可以把查询 IO 降到 1% 以下，是"不需要分区也能跑得飞快"的典型案例。

### Teradata PPI / MLPPI：老牌企业级分区

Teradata V2R5 (2004) 引入 **Partitioned Primary Index (PPI)**，是首个把哈希分布 + 分区组合到一个 Primary Index 下的系统：行先按 PI 哈希到 AMP，再在 AMP 内按分区表达式组织。这意味着分区裁剪发生在 AMP **本地**，跨 AMP 的数据重分布不受影响。

V2R6.2 引入 **MLPPI (Multi-Level PPI)**：多达 62527 个分区组合，支持 Range/Case/Mixed。`EXPLAIN` 中的 "Single Partition"、"N Partitions"、"all partitions" 标记非常清晰，V13 后加入动态裁剪（从绑定参数和 join 推入）。Teradata 至今仍是大型银行和电信数据仓库的常见选择，PPI 是其成本模型的核心。

### OceanBase：二级分区与分区交换

OceanBase (阿里/蚂蚁) 支持 Range / List / Hash / Key 四种一级分区，和 Range/Hash 两种二级分区（总共 8 种组合）。裁剪流程：

1. SQL 层的 `resolver` 把 WHERE 转成分区键的 `Range` 表达式。
2. `partition_pruning` 模块用分区元数据与 `Range` 求交，得到保留分区集合。
3. 对含子分区的表，先裁一级再裁二级。
4. 分布式执行时 RS (RootService) 把请求路由到保留分区所在的 Observer，避免 RPC 放大。

OceanBase 的 `PARTITION ACCESS` 在 `EXPLAIN` 中列出具体分区名。它也支持 `ALTER TABLE ... EXCHANGE PARTITION`，用于快速把非分区表的数据换入一个分区，裁剪行为不变。

### CockroachDB：基于索引分区的裁剪

CockroachDB 不支持传统的 `PARTITION BY` DDL 作为物理分区；它用 **Index Partitioning**：在索引定义上声明 `PARTITION BY LIST/RANGE`，Cockroach 把对应 KV 范围的 replica 调度到指定的 "zone"（比如某个地域的节点集）。这是**数据本地性**优化而不是裁剪优化，但 WHERE 谓词匹配分区列时，优化器可以只读对应 replica 的 range，达到类似裁剪的效果。

局限：只对分区列的等值 / 范围谓词生效；没有跨 join 的 DPP；`EXPLAIN` 里需要看 `spans` 字段而非专门的分区段。

### YugabyteDB：继承 PG 11+ 裁剪 + 全局索引

YugabyteDB 的 YSQL 层 fork 自 PG 11.2，完整继承了 PG 的声明式分区 + 运行时裁剪。存储层是 DocDB（基于 RocksDB + Raft），每个分区对应独立的 tablet，裁剪后直接定位到 tablet leader，不需要跨 region 广播。区别于 PG 的一点：YB 支持"全局 UNIQUE 索引跨分区"（PG 不允许），代价是全局索引的写入需要跨 tablet 协调。

### Vertica：Projection 与 ROS Container Pruning

Vertica 的存储单位不是"表"而是 **projection**（类似物化视图），每个 projection 按 `SEGMENTED BY HASH` 分布到节点，节点内按 `ORDER BY` 排序形成 ROS (Read-Optimized Store) container。ROS container 自带 min/max，查询时的裁剪流程：

1. **Node Elimination**：如果 WHERE 匹配 SEGMENTED BY 的键，只查对应节点。
2. **Projection Selection**：优化器选最便宜的 projection。
3. **ROS Container Pruning**：用 min/max 跳过无关 container。
4. **SIP (Sideways Information Passing)**：类似 runtime filter，从 join build 侧推过来。

Vertica 没有"分区表"DDL 的概念，但 `PARTITION BY` 子句可以声明 **分区表达式**，它不影响数据分布（那是 SEGMENTED BY 做的事），只影响 ROS container 的聚簇方式——等价于"强制按此列排序存储"，然后裁剪就变成 min/max 跳块。这是 90 年代"列存 + 自动裁剪"思路的最早商用实现。

### SAP HANA：内存列存的分区裁剪

HANA 2.0+ 支持 RANGE / HASH / ROUNDROBIN 三种分区，以及 RANGE-RANGE、HASH-RANGE 等二级分区组合。因为 HANA 是内存列存，"分区"的物理含义是列存 delta + main 的分组。裁剪在编译期完成，`EXPLAIN PLAN` 的 `PARTITIONED TABLE SCAN` 节点下有 `PART_ID` 列表。HANA 也支持绑定参数动态裁剪和 join-based 裁剪（通过 `PRUNE_WITHIN_JOIN` 提示）。

### Greenplum：Partition Selector 与 ORCA

Greenplum 4+ 重写的 ORCA 优化器引入了一个专门的 **Partition Selector** 计划节点。对于 `fact JOIN dim` 场景，ORCA 会在 dim 扫描下插入一个 PartitionSelector，负责收集分区键的 distinct 值，再传给 fact 侧的 `DynamicSeqScan` / `DynamicIndexScan`。这相当于 Spark DPP 的早期 (2013) 商用实现。但 Greenplum 的分区元数据量一直被诟病（每个 leaf partition 是 PG 继承表子表，加上 ORCA 统计使 catalog 爆炸），这是 Greenplum 7 才改善的问题。

## 跨引擎裁剪能力综合评分

下面给出一个主观评分（1–5 分），综合静态、动态、Join 推入、类型支持、EXPLAIN 清晰度、Top-N 裁剪、文件/行组联动七个维度：

| 引擎 | 静态 | 动态 | Join DPP | 类型 | EXPLAIN | Top-N | 多层裁剪 | 合计 |
|------|-----|-----|---------|------|---------|------|---------|------|
| Oracle | 5 | 5 | 5 | 5 | 5 | 5 | 4 | 34 |
| Snowflake | 5 | 5 | 5 | 5 (自动) | 4 | 5 | 5 | 34 |
| BigQuery | 5 | 5 | 5 | 4 | 4 | 4 | 5 | 32 |
| Databricks (Photon) | 5 | 5 | 5 | 5 | 4 | 4 | 5 | 33 |
| Trino / Presto | 5 | 5 | 5 | 5 | 5 | 3 | 5 | 33 |
| Spark SQL 3.x | 5 | 5 | 5 | 5 | 4 | 3 | 4 | 31 |
| SQL Server | 5 | 5 | 4 | 4 | 5 | 5 | 4 | 32 |
| PostgreSQL 17 | 5 | 5 | 2 | 5 | 5 | 5 | 3 | 30 |
| ClickHouse | 5 | 5 | 3 | 4 | 5 | 5 | 5 | 32 |
| StarRocks / Doris | 5 | 5 | 5 | 5 | 4 | 4 | 5 | 33 |
| Impala | 5 | 5 | 5 | 5 | 4 | 3 | 5 | 32 |
| Teradata | 5 | 5 | 4 | 5 | 5 | 4 | 4 | 32 |
| TiDB 7+ | 5 | 5 | 4 | 5 | 4 | 5 | 4 | 32 |
| OceanBase | 5 | 5 | 3 | 5 | 4 | 4 | 4 | 30 |
| Vertica | 5 | 5 | 4 | 4 | 4 | 4 | 5 | 31 |
| Greenplum | 5 | 5 | 4 | 5 | 4 | 3 | 4 | 30 |
| MySQL 8 | 5 | 3 | 1 | 3 | 4 | 2 | 2 | 20 |
| Hive 3 (Tez) | 5 | 2 | 3 | 4 | 3 | 1 | 3 | 21 |
| CockroachDB | 3 | 3 | 1 | 3 | 3 | 3 | 2 | 18 |
| DuckDB | 5 | 5 | 4 | 4 | 4 | 4 | 5 | 31 |

> 说明：这是**分区裁剪**维度的评分，不代表引擎整体能力。Oracle 和 Snowflake 并列第一反映了"成熟商用 + 长期迭代"的共性；MySQL 和 Hive 低分反映了它们分别作为 OLTP 和老式 batch 引擎的定位。

## 关键发现

1. **分区裁剪是分区的存在理由**。没有裁剪的分区等于惩罚：DDL 更复杂、小文件更多、元数据更大、插入更慢；只有当查询能实际跳过分区时，你才换回收益。换言之，评估一个分区方案，第一件事就是 `EXPLAIN` 看裁剪率。

2. **静态裁剪是基础，动态裁剪是门槛，Join 推入是分水岭**。45+ 引擎中：约 40 个支持静态裁剪；约 30 个支持绑定变量动态裁剪；只有约 20 个支持 Join 推入式 DPP / runtime filter。OLTP 引擎普遍止步于前两者，真正的 OLAP 引擎必须做第三种。

3. **PostgreSQL 的漫长历程（2001 继承表 → 2017 声明式 → 2018 运行时）**说明了分区裁剪的工程难度。尤其运行时裁剪需要打穿 planner/executor 边界，不是单点修改能完成的。PG 至今不做 join DPP，是其作为 OLTP 引擎的合理权衡。

4. **Oracle 至今仍是分区裁剪的黄金标准**。`PSTART`/`PSTOP` 的清晰性、`KEY(INLIST)`、`PARTITION JOIN FILTER`、hybrid partition、reference partition，功能完整度 25 年无人超越。代价是复杂度和专有性。

5. **Hive 是教训**：只做静态裁剪、不做动态裁剪、不做 Join 推入，在 BI 动态 dashboard 场景下每次点击都退化成全扫；这是它被 Spark SQL、Trino、Impala 陆续取代的直接原因之一。Hive 2.x Tez/LLAP 才补上 DPP 但为时已晚。

6. **Spark 3.0 DPP 是分水岭**。之前 Spark SQL 在"分区事实表 + 维度过滤"场景下不如 Impala/Trino；DPP 一出，Databricks 借此构建 lakehouse 叙事并扩展出 Dynamic File Pruning、Liquid Clustering 等派生技术。

7. **Snowflake / BigQuery / ClickHouse / DuckDB 代表"无需显式分区"的新范式**。它们的共同点是 micropartition / part / file 层面自动维护 min/max/zone-map，分区裁剪等价于"对所有列的范围裁剪"，用户不再需要挑选分区键，只需挑选**聚簇/排序键**以提高 min/max 分离度。对多数分析工作负载，这个模型在运维心智负担和性能天花板上都胜出。

8. **`require_partition_filter` 是少数"存在即正确"的选项**。对任何按时间分区的大表都应开启；成本可预测性收益远大于"偶尔嫌麻烦"的代价。Snowflake、Databricks SQL、Redshift 都在抄这个设计。

9. **ClickHouse 的三段式裁剪（分区 + 主键 mark range + 跳数索引）**是单机 OLAP 的极致形态。它表明：分区的意义是"合并/TTL 的物理单元"，主键的意义是"块内排序+跳块"，跳数索引的意义是"低基数维度的额外裁剪"。三者互补而非重复。

10. **LIMIT / Top-N 分区裁剪**被低估。对时序 / 日志 / metric 场景，"最新 N 条"占到日常查询的大头，而支持有序 Append + early termination 的引擎（Postgres、Oracle、ClickHouse、TimescaleDB、QuestDB、TiDB 6.2+）能把这类查询从"全分区扫 + 归并排序" 降到"只扫最新 1 个分区的几个 granule"。选型时务必把这种查询纳入 benchmark。

11. **Dynamic Filter / Runtime Filter 已成 OLAP 默认标配**，但"分区裁剪粒度"和"文件/行组裁剪粒度"的界限正在消失。Trino、Databricks、Impala、StarRocks 的最新版本已经把分区裁剪统一到"通用 runtime filter 应用到 TableScan"的框架下，传统意义上的"分区"更像一个实现细节。

12. **选型速查**：严格 OLTP + 静态分区够用 → MySQL/PG/Oracle；大表 + 动态 BI dashboard → Trino/Spark 3+/Impala/StarRocks；无运维心智负担的仓库 → Snowflake/BigQuery/Databricks；时序场景 → ClickHouse/TimescaleDB/QuestDB/InfluxDB IOx；成本可控的云仓 → BigQuery + `require_partition_filter`。

## 可观测性：如何验证裁剪真的发生了

写了分区、跑了查询、响应时间也还行——你不能就假设裁剪生效了。几乎所有引擎都支持"从 EXPLAIN 或运行时统计中读出实际访问的分区数"，以下是 cheat sheet：

| 引擎 | 命令 / 视图 | 关键字段 |
|------|------------|---------|
| PostgreSQL | `EXPLAIN (ANALYZE, VERBOSE)` | `Subplans Removed`, `(never executed)` |
| Oracle | `DBMS_XPLAN.DISPLAY_CURSOR(format => 'ALLSTATS LAST +PARTITION')` | `PSTART`, `PSTOP`, `Pstart`, `Pstop` |
| SQL Server | `SET STATISTICS XML ON` | `PartitionCount`, `ActualPartitionCount` |
| MySQL | `EXPLAIN FORMAT=TREE` / `EXPLAIN ANALYZE` | `partitions` 列 |
| ClickHouse | `system.query_log`, `EXPLAIN indexes = 1` | `read_parts`, `Selected X/Y parts, Y/Z granules` |
| Snowflake | `QUERY_HISTORY` + `OPERATOR_STATS` | `partitionsScanned`, `partitionsTotal` |
| BigQuery | `INFORMATION_SCHEMA.JOBS_BY_PROJECT` | `total_bytes_processed`, dry-run API |
| Trino / Presto | `EXPLAIN ANALYZE` / Web UI | `Input rows`, `Dynamic filters: [...]` |
| Spark SQL | Spark UI SQL Tab / `spark.sql("...").explain("formatted")` | `PartitionFilters`, `numPartitions`, `dynamicPartitionPruning` |
| Hive | `EXPLAIN EXTENDED` | `Partition filter predicate`, `Processing path`  |
| TiDB | `EXPLAIN ANALYZE` | `partition:p0,p1` 标签 |
| Impala | `PROFILE` | `NumPartitions`, `Runtime filters` 段 |
| StarRocks / Doris | `SHOW PROFILE` / fe audit log | `partitions=X/Y`, `ScanBytes` |
| DuckDB | `PRAGMA enable_profiling; ... EXPLAIN ANALYZE` | `Hive partition` 节点 |
| Greenplum | `EXPLAIN ANALYZE` | `Partition Selector`, `dynamicPartitionSelection` |
| Databricks | Spark UI + `DESCRIBE HISTORY delta.` | DPP / DFP 节点 |

把"实际分区数 / 候选分区数"比值作为监控指标，低于某个阈值（例如 10%）就 paging——这是大厂 DBA 团队的标准做法。

## 调优清单

写给 DBA / 平台 / 分析师的分区裁剪调优清单：

1. **确认分区键能被查询覆盖**：80% 的查询应至少包含分区列的等值或范围谓词。覆盖不到 50% 说明分区键选错了，考虑改为聚簇/排序键。
2. **分区粒度 = "热分区总大小 / 单次查询扫描预算"**：时序表按天分区、日查询最近 7 天的模式最常见；如果用户大部分查询是"最近 1 小时"，应按小时而非按天分区。
3. **避免分区过多**：PG 10 及之前规划时间随分区数线性增长；MySQL 8K 分区上限；Hive metastore 几十万分区会卡 ls。一般保持总分区数 ≤ 1 万。
4. **谓词必须"裸露"分区列**：禁止 `WHERE DATE(ts)=...`、`WHERE CAST(...)`、`WHERE func(dt)`。改造旧 SQL 时先全局 grep 分区列名。
5. **类型严格一致**：参数化查询务必让驱动传入正确类型。JDBC 的 Java8 `LocalDate` → `DATE`、`Instant` → `TIMESTAMPTZ`。
6. **启用运行时裁剪相关参数**：
   - PG: `enable_partition_pruning = on` (默认)
   - Spark: `spark.sql.optimizer.dynamicPartitionPruning.enabled = true` (默认)
   - Trino: `enable-dynamic-filtering = true` (默认)
   - Impala: `runtime_filter_mode = GLOBAL`
   - StarRocks: `enable_global_runtime_filter = true`
7. **BigQuery / Snowflake / Databricks 必开成本护栏**：`require_partition_filter`、`query_tag` 做分类计费、workload monitoring 拒绝超预算查询。
8. **在 CI 阶段跑 EXPLAIN diff**：dbt test / SQLMesh audit 可以断言"此查询 EXPLAIN 必须出现 partition pruning 字样"，避免新人上线时无感退化。
9. **监控裁剪率下降作为 SLO**：Snowflake 的 `partitionsScanned/partitionsTotal` 下降可能意味着数据倾斜、聚簇键过期、或查询模式变了，应该 alert。
10. **学会读 EXPLAIN 里的 runtime filter 段**：Trino / Impala / Spark / StarRocks 的 runtime filter 有命中率指标，命中率 < 10% 的 filter 应当手工禁用（通常是 build 端选择性太差）。

