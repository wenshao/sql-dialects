# 并行查询执行 (Parallel Query Execution)

单核 CPU 时代已经结束十多年，但很多数据库的查询执行器仍然像 1990 年代那样按行迭代——并行查询是把数据库从单线程瓶颈中解放出来的关键能力，也是 OLTP 与 OLAP 融合时代最不能忽视的工程话题。

> 注：本文聚焦**单节点内部并行 (intra-node parallelism)**，即同一台机器上多核/多线程对单个查询的协同执行。跨节点的分布式 JOIN 策略请参考 [`distributed-join-strategies.md`](./distributed-join-strategies.md)。

## 为什么并行查询如此重要

一台普通服务器今天有 64 ~ 192 个物理核心，1 TB 内存，NVMe SSD 每秒可读取 7 GB+。如果一个 SELECT 只能用 1 个 CPU、占用 1 条 I/O 队列，那么硬件资源中超过 99% 的算力被浪费。混合负载场景下这个问题尤其突出：

- **OLTP 主导的数据库** (MySQL, PostgreSQL 早期版本) 默认按"每连接一线程"模型设计，单查询用单核足以应对几十毫秒的事务，但当业务方在同一个库上跑分析型 SQL 时就会出现"一条 SELECT 跑 3 小时占满一个核心，但其他 63 个核空闲"的尴尬。
- **HTAP 数据库** (TiDB, OceanBase, SingleStore, SAP HANA) 必须同时满足毫秒级点查和秒级聚合，没有 intra-query 并行就无法让分析查询在合理时间内返回。
- **数据仓库** (Snowflake, BigQuery, Redshift, ClickHouse) 几乎所有查询都是大规模扫描+聚合+JOIN，并行执行不是优化项而是生命线。

## 三种执行模型：Volcano vs Vectorized vs Morsel-Driven

要理解各引擎并行能力的差异，必须先理解三代查询执行模型。

### 1. Volcano / Iterator Model（火山模型）

由 Goetz Graefe 在 1994 年提出，每个算子实现 `next()` 接口，逐行从下层算子拉取元组：

```
Aggregate.next() → Join.next() → Scan.next() → 一行
```

并行化通常通过 **Exchange 算子** 实现 (Volcano 论文同样提出)：

- `Gather` (PostgreSQL) / `Gather Streams` (SQL Server) 收集多个 worker 的输出
- 每个 worker 独立运行一份子计划
- worker 间通过 shuffle / hash 重分布数据

**典型代表**：PostgreSQL 9.6+、SQL Server、Oracle、Greenplum、传统 MPP

**优点**：模型清晰，复用单机迭代器逻辑，并行化只是在下方插入 `Gather`。
**缺点**：每行一次虚函数调用，CPU cache 与分支预测效率差；并行度在计划时固定，运行期负载不均时部分 worker 提前结束 (straggler 问题)。

### 2. Vectorized Execution（向量化执行）

由 MonetDB/X100 (后来的 VectorWise) 在 2005 年提出，将 `next()` 的"一行"改为"一批 (batch)"——通常 1024 ~ 65536 行。算子接口变为：

```
Aggregate.next_batch() → Join.next_batch() → Scan.next_batch() → 一个 ColumnBatch
```

**典型代表**：ClickHouse、DuckDB (向量化+morsel)、StarRocks、Doris、Snowflake、Vertica、CockroachDB Vec Engine、Databend、Velox (Meta)、Photon (Databricks)

**优点**：摊薄函数调用开销 (1024 行只调用一次 `next_batch`)，对列存友好，能利用 SIMD (AVX2/AVX-512) 一条指令处理 16/32 个值。
**缺点**：仍需要 Exchange 算子做并行调度；批的大小必须仔细调优 (太大爆 L2，太小白白调用)。

### 3. Morsel-Driven Execution（小粒度任务驱动）

由 Thomas Neumann 等人在 HyPer 数据库于 2014 年 SIGMOD 论文中提出："Morsel-Driven Parallelism: A NUMA-Aware Query Evaluation Framework for the Many-Core Age"。核心思想：

- 把表切成大小固定的 **morsel** (典型 100K 行)
- 一个全局任务队列，所有空闲线程从队列中拿 morsel
- pipeline breakers (hash table build, sort) 后再开下一个 pipeline
- 调度器 NUMA 感知，尽量让线程访问本地内存的 morsel

**典型代表**：HyPer、Umbra、DuckDB、CedarDB、SingleStore (部分)、最近的 Velox 也借鉴了类似思想

**优点**：天然解决 straggler——快线程多拿 morsel，不需要在计划时确定并行度；对 NUMA 友好；可以在运行期动态收缩或扩张并行度。
**缺点**：实现复杂，需要重写整个执行器；与传统 Volcano 算子不兼容。

### 三模型并行特征对比

| 维度 | Volcano | Vectorized | Morsel-Driven |
|------|---------|------------|---------------|
| 数据粒度 | 1 行 | 1024 ~ 65536 行 | 100K 行 (morsel) |
| 并行调度 | 计划时静态 (Exchange) | 计划时静态 + 动态批 | 运行期动态任务窃取 |
| Straggler 处理 | 差 | 中 | 好 |
| NUMA 感知 | 无 | 通常无 | 原生支持 |
| SIMD 利用 | 几乎不能 | 是 | 是 |
| Cache 友好性 | 差 | 好 | 好 |
| 实现复杂度 | 低 | 中 | 高 |
| 代表系统 | PostgreSQL, SQL Server, Oracle | ClickHouse, Snowflake, Vertica | HyPer, DuckDB, Umbra |

## 支持矩阵（45+ 引擎）

### 并行扫描与并行索引扫描

| 引擎 | 并行 Seq Scan | 并行 Index Scan | 并行 Bitmap Scan | 引入版本 |
|------|---------------|----------------|-----------------|---------|
| PostgreSQL | 是 | 是 | 是 | 9.6 / 10 |
| MySQL (InnoDB) | 主键扫描 | -- | -- | 8.0.14 |
| MariaDB | -- | -- | -- | 不支持 |
| SQLite | -- | -- | -- | 不支持 |
| Oracle | 是 | 是 | 是 | 7.1 (1994, 并行 Query Option) |
| SQL Server | 是 | 是 | -- | 2000+ |
| DB2 | 是 | 是 | 是 | DB2 EEE 早期 |
| Snowflake | 是 (自动) | 不适用 | -- | GA |
| BigQuery | 是 (slot 调度) | -- | -- | GA |
| Redshift | 是 (slice 并行) | -- | -- | GA |
| DuckDB | 是 (morsel) | 是 | 是 | 0.3+ |
| ClickHouse | 是 (max_threads) | 是 (跳数索引) | -- | 早期 |
| Trino | 是 (split 并行) | -- | -- | GA |
| Presto | 是 (split 并行) | -- | -- | GA |
| Spark SQL | 是 (partition 并行) | 不适用 | -- | 早期 |
| Hive (Tez/MR) | 是 | -- | -- | 早期 |
| Flink SQL | 是 (subtask 并行) | -- | -- | GA |
| Databricks (Photon) | 是 | -- | -- | GA |
| Teradata | 是 (AMP 并行) | 是 | -- | V2 早期 |
| Greenplum | 是 | 是 | 是 | 6.0+ (intra-segment) |
| CockroachDB | 是 | 是 | -- | 19.x+ |
| TiDB | 是 (TiFlash MPP) | 是 | -- | 4.0+ |
| OceanBase | 是 (PX 框架) | 是 | -- | 2.x+ |
| YugabyteDB | 是 | 是 | -- | 继承 PG |
| SingleStore | 是 | 是 | -- | 早期 |
| Vertica | 是 (ROS 并行) | -- | -- | 早期 |
| Impala | 是 | -- | -- | 早期 |
| StarRocks | 是 (pipeline) | 是 | -- | 2.0+ |
| Doris | 是 (pipeline) | 是 | -- | 1.2+ |
| MonetDB | 是 (BAT 并行) | -- | -- | 早期 |
| CrateDB | 是 (shard 并行) | -- | -- | GA |
| TimescaleDB | 是 (chunk 并行) | 是 | 是 | 继承 PG |
| QuestDB | 是 (page frame) | -- | -- | 7.x+ |
| Exasol | 是 | -- | -- | 早期 |
| SAP HANA | 是 | 是 | -- | 早期 |
| Informix | 是 (PDQ) | 是 | -- | 早期 |
| Firebird | -- | -- | -- | 不支持 (4.0 起部分 utility 并行) |
| H2 | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | 不支持 |
| Amazon Athena | 是 (继承 Trino) | -- | -- | GA |
| Azure Synapse | 是 (DW units) | -- | -- | GA |
| Google Spanner | 是 (split 并行) | -- | -- | GA |
| Materialize | 是 (timely dataflow) | -- | -- | GA |
| RisingWave | 是 (actor 并行) | -- | -- | GA |
| InfluxDB IOx | 是 (DataFusion) | -- | -- | GA |
| Databend | 是 (pipeline) | -- | -- | GA |
| Yellowbrick | 是 | 是 | -- | GA |
| Firebolt | 是 | -- | -- | GA |

> 统计：约 41 个引擎支持某种形式的并行扫描；4 个完全不支持 (SQLite, Firebird, H2, HSQLDB, Derby)。MariaDB 与 MySQL 在 intra-query 并行上严重落后。

### 并行聚合 / 并行 JOIN / 并行排序

| 引擎 | 并行 Aggregate | 并行 Hash Join | 并行 Merge Join | 并行 NL Join | 并行 Sort |
|------|---------------|---------------|----------------|-------------|-----------|
| PostgreSQL | 部分+最终 | 11+ | -- | 是 | 13+ (Incremental Sort) |
| MySQL | -- | -- | -- | -- | -- |
| Oracle | 是 | 是 | 是 | 是 | 是 |
| SQL Server | 是 | 是 | 是 | 是 | 是 |
| DB2 | 是 | 是 | 是 | 是 | 是 |
| Snowflake | 是 | 是 | -- | 是 | 是 |
| BigQuery | 是 | 是 | -- | -- | 是 |
| Redshift | 是 | 是 | 是 | -- | 是 |
| DuckDB | 是 | 是 | -- | 是 | 是 |
| ClickHouse | 是 | 是 | -- | -- | 是 |
| Trino / Presto | 是 | 是 | -- | -- | 是 |
| Spark SQL | 是 | 是 | 是 | 是 | 是 |
| Greenplum | 是 | 是 | 是 | 是 | 是 |
| CockroachDB | 是 | 是 | -- | -- | 是 |
| TiDB | 是 (MPP) | 是 | -- | -- | 是 |
| OceanBase | 是 (PX) | 是 | 是 | 是 | 是 |
| SingleStore | 是 | 是 | -- | -- | 是 |
| Vertica | 是 | 是 | 是 | -- | 是 |
| StarRocks / Doris | 是 (pipeline) | 是 | -- | -- | 是 |
| SAP HANA | 是 | 是 | -- | -- | 是 |
| Teradata | 是 | 是 | 是 | 是 | 是 |
| Impala | 是 | 是 | -- | -- | 是 |
| MonetDB | 是 | 是 | -- | -- | 是 |
| Databricks (Photon) | 是 | 是 | -- | -- | 是 |

### 并行控制参数（Knobs & Hints）

| 引擎 | 并行度参数 | Hint 语法 | 自动决定 | 默认并行度 |
|------|-----------|-----------|---------|-----------|
| PostgreSQL | `max_parallel_workers_per_gather` | -- (无 hint) | 基于代价 | 2 |
| MySQL | `innodb_parallel_read_threads` | -- | 仅主键扫描 | 4 |
| Oracle | `parallel_degree_policy` | `/*+ PARALLEL(t, 8) */` `/*+ PQ_DISTRIBUTE */` | AUTO/MANUAL | 表/索引 DEGREE |
| SQL Server | `MAXDOP` (实例/数据库/查询) | `OPTION (MAXDOP 8)` | 是 | 0 (=auto) |
| DB2 | `dft_degree`, `INTRA_PARALLEL` | `OPTION (DEGREE 8)` | 是 | 1 (需开启 INTRA_PARALLEL) |
| Snowflake | warehouse size | -- | 自动 | XS=1 节点 ... 6XL=512 节点 |
| BigQuery | slot 数量 | -- | 自动 | 按 reservation |
| Redshift | concurrency scaling | -- | 自动 | slice 数 |
| DuckDB | `threads` / `PRAGMA threads` | -- | 自动 (morsel) | 物理核数 |
| ClickHouse | `max_threads` | `SETTINGS max_threads=N` | 是 | 物理核数 |
| Trino / Presto | `task.concurrency`, `node-scheduler.max-splits-per-node` | -- | 自动 | 16 |
| Spark SQL | `spark.sql.shuffle.partitions`, `spark.default.parallelism` | -- | 自动 | 200 |
| Greenplum | `gp_resource_group_cpu_limit` | -- | 自动 | segment 数 |
| TiDB | `tidb_distsql_scan_concurrency`, `tidb_executor_concurrency` | `/*+ READ_FROM_STORAGE(TIFLASH[t]) */` | 是 | 15 |
| OceanBase | `parallel_servers_target` | `/*+ PARALLEL(8) */` | 是 | 1 |
| CockroachDB | `distsql` | -- | 自动 | -- |
| SingleStore | -- | -- | 自动 | partition 数 |
| Vertica | `MaxConcurrencyScaling` | -- | 自动 | -- |
| Impala | `mt_dop` | `SET MT_DOP=8` | -- | 0 |
| StarRocks | `pipeline_dop` | -- | 自动 | 物理核数 |
| Doris | `parallel_fragment_exec_instance_num` | -- | 自动 | 1 |
| SAP HANA | `max_concurrency` | -- | 是 | -- |

### 高级并行能力

| 引擎 | Parallel Append | Parallel CTE | Parallel CREATE INDEX | Parallel VACUUM/ANALYZE | Parallel DML | Morsel-Driven |
|------|----------------|--------------|----------------------|------------------------|--------------|---------------|
| PostgreSQL | 11+ | -- | 11+ | 13+ (VACUUM), 16+ (ANALYZE) | -- (只有 SELECT) | -- |
| Oracle | 是 | 是 | 是 | 是 | 9i+ | -- |
| SQL Server | 是 | 是 | 是 | 是 | 是 | -- |
| DB2 | 是 | 是 | 是 | 是 | 是 | -- |
| DuckDB | 是 | 是 | 是 | 不需要 | 是 | 是 |
| ClickHouse | 是 | -- | 是 | 是 | 是 (mutation) | -- |
| Snowflake | 是 | 是 | 不需要 | 不需要 | 是 | -- |
| Greenplum | 是 | 是 | 是 | 是 | 是 | -- |
| HyPer / Umbra | 是 | 是 | 是 | 不需要 | 是 | 是 |
| SingleStore | 是 | -- | 是 | -- | 是 | 部分 |

## 各引擎详解

### PostgreSQL：从 9.6 到 16 的并行查询演进

PostgreSQL 是开源数据库中 intra-query 并行做得最系统的，但起步比 Oracle/SQL Server 晚了近 20 年。

**版本演进**：

- **9.6 (2016)**：首次引入并行查询。支持 Parallel Sequential Scan、Parallel Aggregate (Partial + Final)、Parallel Nested Loop Join。设计核心是 `Gather` 节点：leader 进程 fork 出多个 worker 进程，每个 worker 跑相同的子计划，结果通过共享内存 (Dynamic Shared Memory, DSM) 汇总到 leader。
- **10 (2017)**：Parallel Index Scan、Parallel Index-Only Scan、Parallel Bitmap Heap Scan、Parallel Merge Join 的部分支持、`gather_merge` (有序汇总避免顶层重排序)。
- **11 (2018)**：**Parallel Hash Join** (重大特性) — 共享 hash table 在 DSM 中构建；Parallel CREATE INDEX (B-tree)；Parallel Append (UNION ALL / 分区表多分区并行扫描)。
- **12 (2019)**：Partition pruning 与 Parallel Append 协同；Parallel Insert into partitioned table 部分场景。
- **13 (2020)**：Parallel VACUUM (索引并行清理)；Incremental Sort 支持并行。
- **14 (2021)**：Parallel sequential scan 的 chunk 大小自适应；Parallel Foreign Scan (postgres_fdw)。
- **15 (2022)**：Parallel SELECT INTO；改进 Parallel Hash Join 的内存使用。
- **16 (2023)**：Parallel FULL/RIGHT Hash Join；Parallel ANALYZE on partitioned tables；Parallel string aggregate (`string_agg`, `array_agg`)。

**关键 GUC 参数**：

```sql
-- 实例级并行 worker 总池子
SHOW max_worker_processes;             -- 默认 8
SHOW max_parallel_workers;             -- 默认 8 (并行查询专用，不能超过上一个)

-- 单个 Gather 节点最多 worker 数
SHOW max_parallel_workers_per_gather;  -- 默认 2
SET max_parallel_workers_per_gather = 8;

-- 维护操作的并行度
SHOW max_parallel_maintenance_workers; -- 默认 2，影响 CREATE INDEX/VACUUM

-- 触发并行扫描的最小表大小
SHOW min_parallel_table_scan_size;     -- 默认 8MB
SHOW min_parallel_index_scan_size;     -- 默认 512KB

-- 并行启动/单元代价 (优化器代价模型)
SHOW parallel_setup_cost;              -- 默认 1000
SHOW parallel_tuple_cost;              -- 默认 0.1

-- 强制并行 (调试/测试用)
SET force_parallel_mode = on;          -- PG 16 起改名 debug_parallel_query
```

**示例：观察并行计划**

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, COUNT(*), SUM(amount)
FROM orders
WHERE order_date >= '2024-01-01'
GROUP BY customer_id;

-- 典型计划：
-- Finalize HashAggregate
--   ->  Gather
--         Workers Planned: 4
--         Workers Launched: 4
--         ->  Partial HashAggregate
--               ->  Parallel Seq Scan on orders
--                     Filter: (order_date >= '2024-01-01'::date)
```

**PostgreSQL 并行的著名局限**：

1. **基于进程**：每个 worker 是独立 OS 进程，启动开销 ~5 ms (相比线程的 ~50 μs)。短查询不适合并行。
2. **没有 Hint**：完全依赖优化器。要强制并行必须改 GUC，无法在 SQL 级别精细控制 (与 Oracle/SQL Server 不同)。
3. **不支持并行 DML**：UPDATE/DELETE/INSERT 不能并行执行 (PG 16 仍然如此，社区在讨论中)。Parallel Insert 仅在 CTAS 等少数场景。
4. **Subquery 受限**：含相关子查询、CTE、SRF 的查询往往退化为单进程。
5. **Worker 数固定**：计划时决定，运行期不能调整 (无 morsel 风格的弹性)。

### Oracle：最早的商业并行实现

Oracle 在 7.1 (1994) 就引入了 Parallel Query Option，是商业数据库中最早系统化支持 intra-query 并行的产品。其模型对后来所有 MPP 数据库都有深远影响。

**核心概念**：

- **PX (Parallel Execution) Server**：worker 进程池，由 `parallel_servers_target` 控制总数。
- **Query Coordinator (QC)**：原查询会话本身充当协调者。
- **Producer / Consumer 模型**：每个并行子计划由 producer 组生产数据、consumer 组消费，类似两层 worker 的 pipeline。
- **Table Queue (TQ)**：producer 与 consumer 之间的数据交换通道，支持多种重分布方式 (Hash/Range/Broadcast/Round-Robin)。

**PARALLEL Hint**：

```sql
-- 显式指定并行度 8
SELECT /*+ PARALLEL(orders, 8) */ * FROM orders WHERE ...;

-- 系统选择最优并行度 (Automatic DOP, 11gR2+)
SELECT /*+ PARALLEL(AUTO) */ * FROM orders WHERE ...;

-- 控制 producer/consumer 间数据分布方式
SELECT /*+ PQ_DISTRIBUTE(o HASH HASH) */ ...
FROM   orders o JOIN customers c ON o.cust_id = c.id;
-- 可选: HASH HASH, BROADCAST NONE, NONE BROADCAST, PARTITION NONE,
--      NONE PARTITION, RANGE NONE, NONE RANGE

-- 表级默认 DOP
ALTER TABLE orders PARALLEL 16;

-- 全局策略 (11gR2 引入 Auto DOP)
ALTER SYSTEM SET parallel_degree_policy = AUTO;
-- 可选: MANUAL, LIMITED, AUTO, ADAPTIVE
```

**Parallel DML** (9i+)：

```sql
-- 必须先在 session 级开启
ALTER SESSION ENABLE PARALLEL DML;

-- 然后才能并行 INSERT/UPDATE/DELETE/MERGE
INSERT /*+ APPEND PARALLEL(8) */ INTO sales_archive
SELECT * FROM sales WHERE sale_date < '2020-01-01';
```

Oracle 的并行 DML 是行业标杆——PostgreSQL 至今没有，SQL Server 也只在 2014+ 的 columnstore 上有限支持。

### SQL Server：MAXDOP 的世界

SQL Server 自 2000 版起支持并行查询，其控制粒度是工业级的——`MAXDOP` 可以在实例、数据库、Resource Governor 工作负载组、单条语句四个级别独立配置。

```sql
-- 实例级
EXEC sp_configure 'max degree of parallelism', 8;
RECONFIGURE;

-- 数据库级 (2016+)
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 4;

-- 单个查询
SELECT customer_id, SUM(total)
FROM   orders
GROUP  BY customer_id
OPTION (MAXDOP 16);

-- 触发并行的开销阈值
EXEC sp_configure 'cost threshold for parallelism', 50;
```

SQL Server 的并行计划在执行计划中以 **Parallelism (Distribute Streams / Repartition Streams / Gather Streams)** 算子可视化展示，粒度极细，便于 DBA 调优。SQL Server 还是少数支持**并行 INSERT/UPDATE/DELETE** 的传统行存数据库。

**MAXDOP=0 vs MAXDOP=1 的常见误区**：

- `MAXDOP = 0` (默认)：让优化器决定，对 ≤8 核机器使用全部核，> 8 核时上限取 8 (SQL Server 2016 之后部分版本调整)
- `MAXDOP = 1`：强制串行执行，常用于 OLTP 服务器避免并行带来的 lock escalation 和 CXPACKET 等待

### MySQL：并行查询的迟到者

MySQL 是主流数据库中并行查询能力**最弱**的之一。直到 8.0.14 (2019) 才在 InnoDB 中引入有限的并行扫描，且**仅**用于聚簇索引 (主键) 扫描，触发场景极窄：

```sql
SET GLOBAL innodb_parallel_read_threads = 8;

-- 仅对全表 COUNT(*) 等覆盖主键扫描的场景生效
SELECT COUNT(*) FROM large_table;
-- 或 CHECK TABLE ... 等 utility 操作
```

**MySQL 不支持的并行场景** (8.4 LTS 仍然如此)：

- 任何 SELECT (除 `COUNT(*)`)
- 任何 JOIN
- 任何 GROUP BY / ORDER BY
- 任何索引扫描
- 任何 UPDATE/DELETE
- CREATE INDEX (有有限的 multi-thread sort，参数 `innodb_ddl_threads`)

如果业务需要 MySQL 上的并行分析，常见方案：HeatWave (Oracle MySQL Cloud 的列存加速器)、ProxySQL + 多副本路由、或换用 MariaDB ColumnStore / TiDB。

### MariaDB：复制并行而非查询并行

MariaDB 的 "parallel replication" (10.0+) 经常被混淆为并行查询，实际上是**复制 SQL Thread 的并行重放**——主库上多个事务的 binlog 在备库可以由多个 SQL Thread 并行 apply，提高 replica 的 catch-up 速度。

MariaDB 本身的查询执行器与 MySQL 同源，**没有 intra-query 并行**。需要并行分析能力时使用 MariaDB ColumnStore (基于 InfiniDB)，那是一个完全独立的 MPP 列存引擎。

### DuckDB：morsel-driven 的开源旗手

DuckDB 从 0.3 版起就采用 morsel-driven 执行模型，是除 HyPer/Umbra 之外最完整的开源 morsel 实现。

```sql
-- 并行度控制
PRAGMA threads = 8;
SET threads TO 16;

-- 查看当前线程数
SELECT current_setting('threads');
```

DuckDB 的 morsel 大小默认 122880 行 (`STANDARD_VECTOR_SIZE * 60`，2048*60)。每个线程从全局任务队列拿 morsel 处理，pipeline breaker (hash build, sort) 后启动新 pipeline。这种模型让 DuckDB 在单机场景下经常击败 ClickHouse 和 Spark。

DuckDB 的并行特点：

- **零配置**：默认即用满所有物理核
- **NUMA 感知**：在多 socket 机器上线程绑核，减少跨 socket 内存访问
- **运行期负载均衡**：morsel-driven 自然解决 straggler
- **没有 Exchange 算子**：与 Volcano 模型截然不同，所有线程访问共享数据结构

### ClickHouse：max_threads 与向量化

ClickHouse 的并行模型是**partition + part 级别并行 × 向量化 batch**：

```sql
-- 单个查询的最大线程数
SET max_threads = 32;

-- 服务器级默认值 (config.xml)
<max_threads>auto</max_threads>  -- 通常等于物理核数

-- 在查询中临时设置
SELECT count() FROM trips
SETTINGS max_threads = 64;
```

每个 part (MergeTree 的物理数据单元) 的扫描分配给一个线程，线程内部以 8192 行的 batch 通过向量化算子流动。Aggregate 算子按 hash 分桶，最后两阶段合并。ClickHouse 的 SIMD 利用极其激进——`uniqHLL12`、聚合 hash 函数、字符串过滤都有 AVX-512 实现。

### Snowflake：仓库即并行度

Snowflake 把并行度抽象为 **Warehouse Size**：

| Size | 节点数 | 信用消耗/小时 |
|------|-------|--------------|
| X-Small | 1 | 1 |
| Small | 2 | 2 |
| Medium | 4 | 4 |
| Large | 8 | 8 |
| X-Large | 16 | 16 |
| 2X-Large | 32 | 32 |
| 3X-Large | 64 | 64 |
| 4X-Large | 128 | 128 |
| 5X-Large | 256 | 256 |
| 6X-Large | 512 | 512 |

每个节点是 8 核 16 GB 的 EC2 实例，节点内向量化执行，节点间 MPP shuffle。用户无需调任何并行度参数，Resize warehouse 即扩缩容。这种"用钱换并行度"的模式让 Snowflake 在企业市场快速崛起。

### BigQuery：Slot 模型

BigQuery 的并行单位是 **slot**——一个 slot 大致对应一个 vCPU 的算力，一个查询会被分解为 stages，每 stage 内有多个 worker 并行处理 shard。用户的 reservation 决定可用 slot 总数 (按需 / 月度承诺 / Edition)。

BigQuery 的 Dremel 引擎 (2010 论文) 是 stages-of-stages 的 tree of execution：每个 stage 输出 shuffled 到下一 stage 的 workers。ROOT stage 输出最终结果。EXPLAIN 中可以看到每个 stage 的 slot ms、shuffle bytes、并行度。

### Spark SQL：Task = Partition

Spark SQL 的并行单位是 **task**，一个 task 处理一个 partition：

```scala
// 调整 shuffle 后的分区数
spark.conf.set("spark.sql.shuffle.partitions", "400")

// 自适应执行 (AQE, 3.0+)
spark.conf.set("spark.sql.adaptive.enabled", "true")
spark.conf.set("spark.sql.adaptive.coalescePartitions.enabled", "true")
```

AQE (Adaptive Query Execution) 是 Spark 3.0 的杀手特性——运行期根据上一 stage 的实际输出大小动态调整下一 stage 的并行度，自动合并小分区、自动切分倾斜 partition、动态切换 join 策略。

### TiDB / OceanBase / SingleStore：HTAP 的并行设计

**TiDB** 通过 TiKV (行存 OLTP) + TiFlash (列存 OLAP) 双引擎实现 HTAP。OLAP 查询路由到 TiFlash 的 MPP 引擎执行，节点间 shuffle，节点内向量化。

```sql
-- 强制走 TiFlash MPP
SELECT /*+ READ_FROM_STORAGE(TIFLASH[orders]) */
       region, SUM(amount)
FROM orders GROUP BY region;
```

**OceanBase** 的 PX (Parallel Execution) 框架几乎是 Oracle PX 的开源克隆，支持 PARALLEL hint、PQ_DISTRIBUTE、DOP 自适应：

```sql
SELECT /*+ PARALLEL(8) */ * FROM big_table;
```

**SingleStore** (前 MemSQL) 是 row + columnstore 混合引擎，每个 partition 一个 worker，单查询并行度 = partition 数。新版引入了部分 morsel-driven 思想。

## 不支持并行查询的引擎

下列引擎在 2024 年仍然没有 intra-query 并行能力，只能依赖单核执行：

| 引擎 | 原因 / 替代方案 |
|------|----------------|
| SQLite | 设计目标是嵌入式单进程；可用 `sqlite-parallel` 外部工具按 WHERE 范围切分 |
| Firebird | 4.0 仅 backup/sweep 等 utility 并行；查询仍单线程 |
| H2 | 嵌入式，无并行执行计划 |
| HSQLDB | 嵌入式，无并行执行计划 |
| Derby | 嵌入式，无并行执行计划 |
| MySQL (除 COUNT) | 8.0.14 仅主键扫描，其他场景全部单核 |
| MariaDB | 同上 |

对于 OLTP 工作负载，单核执行往往是合理选择 (避免并行启动开销和 lock 冲突)。但当业务在嵌入式数据库上跑分析查询 (例如 SQLite 上 GB 级表的 GROUP BY)，迁移到 DuckDB 通常能获得数十倍加速。

## Morsel-Driven vs Volcano vs Vectorized 深度对比

### 例子：1 亿行表的 GROUP BY

```sql
SELECT customer_id, COUNT(*), SUM(amount)
FROM orders          -- 1 亿行，10 GB
GROUP BY customer_id; -- 100 万 distinct customer
```

**Volcano (PostgreSQL 16, 8 worker)**：

```
Finalize HashAggregate                         <- leader 进程
  └─ Gather (Workers Planned: 8)               <- exchange
       └─ Partial HashAggregate                <- 每 worker 一份
            └─ Parallel Seq Scan on orders     <- 每 worker 拿一段 block range
```

执行特征：每个 worker 拿固定的 block range (运行前切分)，扫到尾后退出。如果某 worker 的 block range 包含很多被 buffer 缓存的页，跑得很快；其他 worker 还在读盘，leader 必须等所有 worker 完成 Partial Aggregate 才能进入 Final 阶段。这就是经典的 **straggler**。

**Vectorized (ClickHouse, max_threads=8)**：

```
执行流：
  8 个线程，每个绑定 1~N 个 part
  线程内：part → 8192 行 batch → SIMD GROUP BY hash → local hash table
  pipeline breaker：所有 local hash table → 全局两阶段 merge
```

执行特征：batch 让 CPU cache 命中率极高，SIMD 加速 hash 计算。但部之间的工作分配在调度时确定，仍然有 straggler。

**Morsel-Driven (DuckDB, threads=8)**：

```
执行流：
  全局任务队列：[morsel_0, morsel_1, ..., morsel_812]   (1 亿 / 122880 ≈ 813 个 morsel)
  8 个线程从队列竞争 morsel
  每线程内：morsel → 1024 行 vector → GROUP BY hash → thread-local hash table
  pipeline breaker：thread-local hash tables → 全局 hash table 合并
```

执行特征：813 个 morsel 远多于 8 个线程，自然实现负载均衡——快线程多拿。某线程因 NUMA 远端访问慢一点也无所谓，下次少拿一个 morsel 就行。pipeline breaker 后的 thread-local hash table 合并阶段也可以再 morsel 化 (把全局 hash table 按 hash 范围切片)。

### 三模型量化对比（典型 8 核机器, 1 亿行 GROUP BY）

| 指标 | Volcano (PG) | Vectorized (CH) | Morsel (DuckDB) |
|------|--------------|-----------------|-----------------|
| 总耗时 | 18 s | 4.2 s | 3.1 s |
| 每行 CPU 周期 | ~250 | ~45 | ~30 |
| L1 D-cache miss | 高 | 中 | 低 |
| Worker 启动开销 | ~40 ms (fork) | ~1 ms (线程池) | ~0.1 ms (任务窃取) |
| Straggler 影响 | 高 (~30% 末尾尾巴) | 中 | 低 |
| NUMA 友好 | 否 | 部分 | 是 |

(以上数字基于 H2O.ai db-benchmark 与社区基准的典型相对量级，实际值依硬件而异)

### 为什么不是所有引擎都用 morsel-driven？

morsel-driven 的工程难度比向量化高得多：

1. **必须重写整个执行器**：现存的 Volcano `next()` 接口与 morsel 调度不兼容，所有算子都要改。
2. **共享数据结构的并发**：hash table、sort buffer 都要做 lock-free 或 partitioned 实现，调试极难。
3. **NUMA 感知调度**：需要查询 OS 拓扑、绑核、内存分配策略。
4. **EXPLAIN 不直观**：用户看不到清晰的 Exchange 边界，调试更难。

因此 PostgreSQL、Oracle、SQL Server 等"老牌"数据库都选择保留 Volcano + Exchange，而 DuckDB、HyPer、Umbra 这些 from-scratch 项目可以放手用 morsel。

## 内核实现关键点

### 1. Worker 模型：进程 vs 线程

| 模型 | 代表 | 优点 | 缺点 |
|------|------|------|------|
| 多进程 | PostgreSQL, Oracle | 隔离性好，crash 不影响 leader | fork 开销 ~5ms，共享内存复杂 |
| 多线程 | SQL Server, MySQL InnoDB, DuckDB, ClickHouse | 启动快 ~50μs，共享地址空间 | 线程崩溃可能影响整个 process |
| 协程/任务 | Trino, Presto | 调度开销最低 | 需要 cooperative scheduling |

PostgreSQL 选择多进程是为了 crash safety——但代价是并行启动慢，短查询并行收益为负。

### 2. 共享 vs 分区数据结构

**Hash Table 在并行 Hash Join 中的两种选择**：

```
A. Partitioned Hash Table (经典 MPP, Greenplum/Oracle/SQL Server)
   - Build 阶段：按 hash 把行 shuffle 到 N 个 worker，每 worker 建 1/N hash table
   - Probe 阶段：probe 行同样 shuffle，到对应 worker 查找
   - 优点：每 worker 的 hash table 独立，无锁
   - 缺点：shuffle 网络/内存成本高；倾斜场景部分 worker 的 hash table 爆内存

B. Shared Hash Table (PostgreSQL 11+, DuckDB, HyPer)
   - Build 阶段：所有 worker 并发往同一个 hash table 插入 (lock-free 或 latch)
   - Probe 阶段：所有 worker 并发查同一个 hash table
   - 优点：无 shuffle 开销；负载自动均衡
   - 缺点：lock-free hash table 实现复杂；插入热点
```

PostgreSQL 11 的 Parallel Hash Join 用了 DSM (Dynamic Shared Memory) + 分桶共享 hash table，build 阶段每个桶有自己的 latch，是工程上的精彩平衡。

### 3. Exchange 算子的数据交换

```
RANGE_DISTRIBUTE: 按值范围分发 (用于 SORT-MERGE JOIN)
HASH_DISTRIBUTE:  按 hash 分发 (用于 HASH JOIN)
BROADCAST:        广播到所有 consumer (小表 JOIN 大表的小表侧)
ROUND_ROBIN:      平均轮询 (用于负载均衡)
GATHER:           N → 1 汇总到 leader
GATHER_MERGE:     N → 1 保持有序汇总
```

Oracle 的 PQ_DISTRIBUTE hint 直接暴露了这些选项给用户。PostgreSQL 没有 hint，但 EXPLAIN 中能看到 `Hash Repartition` 等节点。

### 4. 自适应并行度（AQE / Adaptive DOP）

运行期调整并行度的几种思路：

- **Spark AQE (3.0+)**：每个 stage 完成后根据实际数据量决定下一 stage 的 partition 数。
- **Oracle Adaptive Plans (12c+)**：运行期可以从 Nested Loop 切到 Hash Join，从串行切到并行。
- **SQL Server Adaptive Joins (2017+)**：编译两套计划，运行期根据实际行数选择。
- **DuckDB Morsel-Driven**：本质上就是运行期自适应——更多空闲线程意味着更多 morsel 被并行处理。

### 5. 倾斜处理 (Skew Handling)

并行查询最大的敌人是数据倾斜——一个 key 占了 80% 的行，那个 worker 永远做不完。

```
解决方案：
  1. Skew detection: 运行期统计 key 频率，识别热 key
  2. Salting: 给热 key 加随机后缀 → 拆成多个子 key 并行 → 最后合并
  3. Two-stage aggregate: partial aggregate 减少 shuffle 数据量
  4. Adaptive join: 倾斜 key 单独走 broadcast，非倾斜 key 走 hash
```

Spark AQE 的 `skewJoin.enabled` 自动做后两者。Snowflake 内部有自动 salting，BigQuery 用户需要手动改写。

## 关键发现

1. **MySQL 是主流 RDBMS 中并行能力最弱的**。8.0.14 引入的 `innodb_parallel_read_threads` 仅对主键扫描的 `COUNT(*)` 等少数场景生效，UPDATE/DELETE/JOIN/GROUP BY/ORDER BY 全部单核。这在 OLTP 业务跑分析查询时造成严重瓶颈，是迁移到 PostgreSQL/TiDB/DuckDB 的核心驱动力之一。

2. **PostgreSQL 的并行查询用了 7 年才"成熟"**。9.6 (2016) 起步到 16 (2023) 才补齐 Parallel Full Outer Hash Join。但仍然不支持并行 DML，且基于多进程模型导致短查询启动开销高。社区在讨论将来引入线程模型 ("threaded postgres") 来根本性改善这一点。

3. **Oracle 的 Parallel Query 是工程范本**。1994 年的 7.1 起就有完整的 PX 框架、PQ_DISTRIBUTE hint、parallel DML、自动 DOP，至今几乎所有 MPP 数据库 (Greenplum、OceanBase、SingleStore) 的并行架构都是这个模型的变体。

4. **Morsel-Driven 是新引擎的事实标准**。DuckDB、HyPer、Umbra、CedarDB 都基于 morsel 模型，因为它能在单机多核场景下榨干硬件、自然解决 straggler、NUMA 感知。但代价是必须 from scratch 重写执行器——这是 PostgreSQL/Oracle 无法采用的根本原因。

5. **向量化与 morsel-driven 是正交的**。ClickHouse 是"向量化但非 morsel-driven" (worker 间任务静态分配)，DuckDB 是"向量化 + morsel-driven"。两者都用 1024 ~ 8192 行的 batch 摊薄函数调用开销，但调度模型不同。

6. **云数仓把并行度抽象成钱**。Snowflake 用 warehouse size、BigQuery 用 slot、Redshift 用 concurrency scaling——用户不再调 max_threads，而是调消费预算。这极大降低了运维门槛，也是云数仓商业成功的关键。

7. **5 个嵌入式数据库完全没有并行能力**。SQLite、Firebird、H2、HSQLDB、Derby 至今没有 intra-query 并行。当数据规模超过 1 GB、查询复杂度超过简单 SELECT 时，迁移到 DuckDB (同样嵌入式，但完全并行+向量化+morsel) 几乎总是正确的选择。

8. **Hint vs 自动**。Oracle、SQL Server、TiDB、OceanBase 提供 PARALLEL hint 让用户精细控制；PostgreSQL、Snowflake、BigQuery、DuckDB 完全依赖优化器/系统。Hint 派的优势是对单个慢查询能精准调优，自动派的优势是普通用户零门槛。新一代云数仓全部走自动路线。

9. **并行 DML 是分水岭**。Oracle 9i (2001) 起支持，SQL Server 长期支持，DB2 支持。PostgreSQL 至今 (16) 不支持，MySQL 不支持，DuckDB / ClickHouse / Snowflake 通过特殊方式支持 (CTAS, INSERT-SELECT)。这是衡量数据库"是否真正并行"的硬指标。

10. **AQE/自适应执行成为新竞争点**。Spark 3.0 的 AQE、Oracle 12c 的 Adaptive Plans、SQL Server 2017 的 Adaptive Joins、Photon 的 runtime adaptation——运行期根据实际数据动态调整并行度和算子选择，是下一代查询执行器的标配。PostgreSQL 在这一点上明显落后。

## 参考资料

- Volcano: Goetz Graefe, "Volcano—An Extensible and Parallel Query Evaluation System", IEEE TKDE 1994
- Morsel-Driven: Leis et al., "Morsel-Driven Parallelism: A NUMA-Aware Query Evaluation Framework for the Many-Core Age", SIGMOD 2014
- Vectorization: Boncz et al., "MonetDB/X100: Hyper-Pipelining Query Execution", CIDR 2005
- PostgreSQL: [Parallel Query](https://www.postgresql.org/docs/current/parallel-query.html)
- PostgreSQL 11 Parallel Hash Join: [commit b0b39f72](https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=b0b39f72)
- Oracle: [Using Parallel Execution](https://docs.oracle.com/en/database/oracle/oracle-database/19/vldbg/parallel-exec-intro.html)
- SQL Server: [Configure max degree of parallelism](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/configure-the-max-degree-of-parallelism-server-configuration-option)
- MySQL 8.0: [innodb_parallel_read_threads](https://dev.mysql.com/doc/refman/8.0/en/innodb-parameters.html#sysvar_innodb_parallel_read_threads)
- DuckDB: [Pragmas — threads](https://duckdb.org/docs/sql/pragmas)
- ClickHouse: [Settings — max_threads](https://clickhouse.com/docs/en/operations/settings/settings#max_threads)
- Snowflake: [Warehouse Size](https://docs.snowflake.com/en/user-guide/warehouses-overview)
- BigQuery: [Slots](https://cloud.google.com/bigquery/docs/slots)
- Spark AQE: [Adaptive Query Execution](https://spark.apache.org/docs/latest/sql-performance-tuning.html#adaptive-query-execution)
- TiDB: [TiFlash MPP Mode](https://docs.pingcap.com/tidb/stable/use-tiflash)
- HyPer: [HyPer Project](https://hyper-db.de/)
- Umbra: [Umbra Database](https://umbra-db.com/)
