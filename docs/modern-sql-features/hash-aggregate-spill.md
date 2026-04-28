# 哈希聚合外存溢出 (Hash Aggregate Spill)

`GROUP BY customer_id` 在 1 亿行表上跑得飞快，直到某天 customer 基数从十万跳到上亿——内存里的哈希表不再装得下，查询要么 OOM 杀进程，要么悄无声息地把 200 GB 临时文件写满 NVMe。哈希聚合外存溢出是 OLAP 引擎最沉默的差异化能力：每家厂商的算法、阈值、可观测性差异极大，运维不读源码就只能凭经验猜。

## 无 SQL 标准

SQL:2023 标准对聚合的执行算法没有任何强制要求，更不会规定内存超出后的行为。`GROUP BY` 只是逻辑算子——引擎可以选 sort-aggregate（先排序再扫描）、hash-aggregate（哈希表分组）、stream-aggregate（已排序数据流）甚至 segment-aggregate。当聚合的 distinct group 数超过 `work_mem` / `tmp_table_size` / `query.max-memory` 时，引擎可以选择：

1. **报错退出**（早期 ClickHouse、默认 Trino）
2. **退化到排序聚合**（MySQL：tmp table 满 → filesort）
3. **递归分区到磁盘**（PostgreSQL 13+、Spark、DuckDB、Snowflake、Oracle）
4. **混合策略**（SQL Server batch mode：先尝试哈希，spill 时切换 sort-based fallback）

各家把这件事做对的时间差超过十年，且很多引擎到今天都没有完整答卷。本文聚焦「哈希聚合算子在内存压力下的溢写行为」，与 [`temp-space-management.md`](./temp-space-management.md) 描述的临时空间配额管理、[`parallel-query-execution.md`](./parallel-query-execution.md) 描述的并行执行模型互为补充。

## 经典递归分区 vs Sort-then-Aggregate fallback

哈希聚合外存溢出有两条主流技术路径，理解它们才能解释为什么 PG / Spark / DuckDB 长得很像，而 MySQL / 老 SQL Server 走的是完全不同的路。

### 路径 A：递归分区（Recursive Partitioning，又名 GRACE-style HashAgg）

源自 1980 年代 Kitsuregawa 等人提出的 GRACE Hash Join 算法，迁移到聚合场景：

```
1. 内存里维护一个目标大小为 work_mem 的哈希表
2. 当哈希表满，按 hash(group_key) 选定 partition_count（如 32），把溢出的元组写到对应分区文件
3. 输入扫描结束后，逐个分区单独读回内存做哈希聚合
4. 如果某个分区仍然超过 work_mem → 递归地再做一次分区（增加 hash bit）
5. 极端情况下递归层数 = log_partition_count(N / work_mem)
```

代表实现：PostgreSQL 13+ HashAgg spill、Spark SQL HashAggregateExec、DuckDB RadixPartitionedHashTable、CockroachDB external aggregator、Snowflake / BigQuery 内部 shuffle aggregation。

优点：**真正的哈希语义**——不需要全局排序，单次 IO 复杂度 O(N)。

代价：递归深度无上界（pathological 情况下 hash 冲突严重时变慢），分区文件数量可能成千上万（小文件问题）。

### 路径 B：Sort-then-Aggregate Fallback

```
1. 内存哈希表满，把当前所有 (group_key, agg_state) 全部刷到磁盘
2. 对所有溢写的中间状态按 group_key 做外部归并排序
3. 顺序扫描排好序的数据流，遇到相同 key 就合并 agg_state
```

代表实现：SQL Server row mode HashAgg（spill 后 fallback 到 sort）、老版本 MySQL（GROUP BY 走 filesort）、部分 Oracle 计划（HASH GROUP BY 失败回退 SORT GROUP BY）。

优点：实现简单（复用排序代码）、无递归层数问题。

代价：必须做全局排序 O(N log N)，且要按全部 group key 排序而非部分。

### 现代趋势

2010 年后新设计的引擎（Spark、DuckDB、Snowflake、ClickHouse、CockroachDB）几乎全部走递归分区路线，因为：

- 列存 / 向量化引擎按 batch 处理，按 hash 分区天然契合
- shuffle 已经是 partition-aware 的（数据按 hash 路由到节点）
- 排序聚合的全局排序成本对超大基数 group 不可接受

而 MySQL 至今未实现真正意义上的哈希聚合溢写——内部仍依赖 `tmp_table_size` + filesort 的旧机制。

## 支持矩阵（综合）

下表覆盖 45+ 引擎的哈希聚合溢写能力。列含义：

- **哈希聚合溢写**：HashAgg 算子在内存不足时是否能继续执行（不是 OOM 报错）
- **递归分区**：是否使用 GRACE-style 递归分区算法
- **归并排序回退**：是否使用 sort-based fallback 算法
- **溢写粒度**：算子级（整个算子的中间状态）vs 分区级（按 hash 分区独立溢写）
- **磁盘哈希表**：是否在磁盘上维护持久化哈希表（vs 仅缓存中间状态）

| 引擎 | 哈希聚合溢写 | 递归分区 | 归并排序回退 | 溢写粒度 | 磁盘哈希表 |
|------|-------------|---------|-------------|---------|-----------|
| PostgreSQL | 13+ (2020) | 是 | -- | 分区 | -- |
| MySQL | -- (退化到 filesort) | -- | 是 | 算子 | -- |
| MariaDB | -- (退化到 filesort) | -- | 是 | 算子 | -- |
| SQLite | 有限 | -- | 是 | 算子 | -- |
| Oracle | 9i+ | 是 | 回退 SORT GROUP BY | 分区 | 临时段 |
| SQL Server | 2008 R2 (row) / 2012 (batch) | batch mode | row mode | 分区 (batch) | tempdb 工作表 |
| DB2 | 是 | 是 | 是 | 分区 | SHEAPTHRES 控制 |
| Snowflake | 是 (auto) | 是 | -- | 分区 | local SSD |
| BigQuery | 是 (shuffle) | 是 | -- | 分区 | 不透明 |
| Redshift | 是 | 是 | -- | 分区 | 节点 SSD |
| DuckDB | 是 | 是 (Radix) | -- | 分区 | -- |
| ClickHouse | `max_bytes_before_external_group_by` | 是 | 外部归并 | 分区 | -- |
| Trino | `spill_enabled` | 是 | -- | 分区 | -- |
| Presto | `experimental.spill-enabled` | 是 | -- | 分区 | -- |
| Spark SQL | 1.6+ (2016) | 是 | -- | 分区 | UnsafeFixedWidthAggregationMap |
| Hive | 是 | 是 (MapReduce shuffle) | -- | 分区 | -- |
| Flink SQL | 是 (批模式) | 是 | -- | 分区 | RocksDB 状态 |
| Databricks | 是 (Photon) | 是 | -- | 分区 | -- |
| Teradata | 是 (spool) | 是 | 内部 | 分区 | spool 段 |
| Greenplum | 是 (workfiles) | 继承 PG | -- | 分区 | -- |
| CockroachDB | 是 (external aggregator) | 是 | -- | 分区 | Pebble engine |
| TiDB | 5.0+ | 是 | -- | 分区 | -- |
| OceanBase | 是 | 是 | 是 | 分区 | -- |
| YugabyteDB | 继承 PG | 继承 PG | -- | 分区 | -- |
| SingleStore | 是 | 是 | -- | 分区 | -- |
| Vertica | 是 | 是 | -- | 分区 | TEMP 存储 |
| Impala | 是 | 是 | -- | 分区 | scratch_dirs |
| StarRocks | 3.0+ spill | 是 | -- | 分区 | -- |
| Doris | 2.1+ | 是 | -- | 分区 | -- |
| MonetDB | 是 (BAT memory-mapped) | 部分 | -- | 算子 | -- |
| CrateDB | 有限 | -- | -- | 算子 | -- |
| TimescaleDB | 继承 PG | 继承 PG | -- | 分区 | -- |
| QuestDB | 有限 | -- | -- | -- | -- |
| Exasol | 是 | 是 | -- | 分区 | 节点临时区 |
| SAP HANA | 是 | 是 | -- | 分区 | tempblob |
| Informix | 是 | 是 | -- | 分区 | DBSPACETEMP |
| Firebird | 有限 | -- | 是 | 算子 | -- |
| H2 | 有限 | -- | 是 | 算子 | -- |
| HSQLDB | -- | -- | -- | -- | -- |
| Derby | -- | -- | -- | -- | -- |
| Amazon Athena | 继承 Trino | 继承 Trino | -- | 分区 | -- |
| Azure Synapse | 是 | 是 | -- | 分区 | tempdb |
| Google Spanner | 部分 | -- | -- | -- | -- |
| Materialize | 部分 (流) | -- | -- | -- | -- |
| RisingWave | 是 (状态后端) | -- | -- | 分区 | RocksDB |
| InfluxDB (SQL/IOx) | 是 | 是 | -- | 分区 | -- |
| DatabendDB | 是 | 是 | -- | 分区 | spill.storage |
| Yellowbrick | 是 | 是 | -- | 分区 | 节点 SSD |
| Firebolt | 是 | 是 | -- | 分区 | 引擎 SSD |

> 关键统计：45+ 引擎中约 38 个支持某种形式的哈希聚合溢写，其中 30+ 走递归分区路线，仅 5-6 个采用 sort-based fallback（多为老引擎）。MySQL 系列至今没有真正的 HashAgg spill，仍然依赖 `tmp_table_size` + filesort 退化路径。

## PostgreSQL：从 OOM 杀手到分区溢写

PostgreSQL 的 HashAgg 溢写是过去十年最被广泛讨论的 OLAP 改进之一。理解它的演进，能直接看到这个问题的难度。

### PG 12 及以前：致命的内存无界增长

PG 13 之前，HashAgg 算子的逻辑是：

1. 优化器估算 group 数量 < 内存能容纳的阈值（基于 `work_mem` 和统计信息），选 HashAgg
2. 执行时如果实际 group 数远超估算，哈希表会**无限增长直到把后端进程内存吃光**
3. 然后 OOM Killer 杀掉 postgres 进程，连带整个 PostgreSQL 实例所有连接断开

```sql
-- PG 12 上的灾难性查询
SET work_mem = '4MB';
EXPLAIN (ANALYZE)
SELECT user_id, COUNT(*)
FROM events
GROUP BY user_id;
-- 如果 user_id 基数 1 亿，且优化器估算成 10 万
-- → 选 HashAgg → 实际跑起来内存吃 30 GB → OOM

-- 临时缓解：禁用 HashAgg，强制走 GroupAggregate
SET enable_hashagg = OFF;
-- 退化到排序 + 流式聚合，慢但不会 OOM
```

很多生产事故都是这样发生的：开发把 `work_mem` 调到 256 MB，认为「就算超出也不过是 256 MB」，但 HashAgg 完全不遵守这个限制。社区里 `enable_hashagg = off` 一度成为运维规避 OOM 的标配。

### PG 13（2020 年 9 月）：递归分区登场

PG 13 由 Jeff Davis（Greenplum 出身的核心开发者）实现 HashAgg spill，整体借鉴 GRACE HashAgg 算法：

```
1. 内存里维护一个目标 work_mem 的哈希表
2. 当哈希表大小 > work_mem，进入 "partition" 模式
3. 计算需要的分区数 = (估算总大小) / (work_mem)，用 hash bit 路由
4. 哈希表里已有的 group → 留在内存，新到的不在内存的 group → 写到对应分区文件
5. 输入扫描完后，依次读每个分区文件，重新做内存内 HashAgg
6. 如果某个分区仍然超出 work_mem，递归地再做一次分区（再加 hash bit）
```

```sql
-- PG 13+
SET work_mem = '4MB';
EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, COUNT(*)
FROM events
GROUP BY user_id;

-- 输出会出现新的字段：
--  HashAggregate  (cost=...)
--    Group Key: user_id
--    Planned Partitions: 32
--    Batches: 33  Memory Usage: 4145kB  Disk Usage: 384256kB
--    ->  Seq Scan on events (...)
```

`Planned Partitions: 32` 表示初始按 32 个分区写盘；`Batches: 33` 表示总共处理了 33 个批次（1 个内存批 + 32 个磁盘批）。

### PG 15（2022 年 10 月）：hash_mem_multiplier 默认升到 2.0

13/14 版本里 `hash_mem_multiplier` 已经存在但默认 1.0，等价于哈希算子用的就是 `work_mem`。问题是哈希算子（HashAgg + HashJoin）实际需要的内存比排序算子多得多。如果把 `work_mem` 调高来满足哈希算子需求，排序算子就会被授予过多内存，浪费且容易 OOM。

PG 15 把 `hash_mem_multiplier` 默认值提升到 2.0，专门照顾哈希算子：

```sql
-- 哈希算子的内存预算 = work_mem × hash_mem_multiplier
-- 排序算子仍然只用 work_mem
SHOW work_mem;                  -- 4MB
SHOW hash_mem_multiplier;       -- 2.0 (PG 15+ 默认)

-- 实际 HashAgg / HashJoin 可用内存 = 4MB × 2.0 = 8MB
-- 排序仍然 4MB

-- 调到更激进：
ALTER SYSTEM SET hash_mem_multiplier = 4.0;
-- HashAgg 可用 16MB，排序仍然 4MB
```

PG 文档建议在哈希溢写频繁的 OLAP 负载上把 `hash_mem_multiplier` 调到 2.0~8.0，专门减少 HashAgg/HashJoin 溢写。

### PG HashAgg spill 的内部数据结构

```
struct HashAggBatch {
    int           setno;        // 哪个 GROUPING SET
    int           used_bits;    // 已用的 hash bit 数（递归层数标记）
    LogicalTapeSet *tapeset;    // 临时文件的逻辑磁带
    int           input_tapenum; // 输入磁带号
    double        input_tuples; // 这一批包含的元组数估算
    Size          input_card;   // group 基数估算
};

主流程伪代码：
function ExecAgg():
    while (slot = ExecScan(child)):
        hash = hashfunc(slot.group_key)
        if (hash table fits in work_mem * hash_mem_multiplier):
            update existing entry or insert new
        else:
            partition = (hash >> used_bits) & (num_partitions - 1)
            write slot to tapeset[partition]
    
    // 输入处理完，处理溢写分区
    for each non-empty partition:
        if partition fits in memory:
            recursively process via in-memory HashAgg
        else:
            recursive_partition(partition, used_bits + log2(num_partitions))
```

`LogicalTapeSet` 是 PG 排序代码复用的设施——一个文件被切成多个逻辑磁带，磁带之间可独立读写。这让 HashAgg spill 不需要为每个分区开一个独立 OS 文件，避免文件描述符爆炸。

### 监控 HashAgg spill

```sql
-- 1. EXPLAIN ANALYZE 直接观察
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT customer_id, SUM(amount) FROM orders GROUP BY customer_id;
-- 注意 HashAggregate 节点下的：
--   Memory Usage: 实际峰值内存
--   Disk Usage: 累积写盘字节数
--   Batches: 总批次数（>1 表示发生溢写）
--   Planned Partitions: 优化器规划的初始分区数

-- 2. log_temp_files 抓所有临时文件
ALTER SYSTEM SET log_temp_files = '10MB';
-- 日志中：LOG: temporary file: path "base/pgsql_tmp/pgsql_tmp1234.0", size 104857600
-- HashAgg 溢写文件名通常以 "ts" 开头（tape set）

-- 3. pg_stat_database 累积统计
SELECT datname, temp_files, temp_bytes
FROM pg_stat_database
WHERE datname = current_database();

-- 4. 强制一次溢写做对照实验
SET work_mem = '64kB';
EXPLAIN (ANALYZE)
SELECT n, COUNT(*) FROM generate_series(1, 1000000) AS n GROUP BY n;
```

## Oracle：HASH GROUP BY 与 9i 起的工作区管理

Oracle 9i（2001）就引入了 HASH GROUP BY 算子，是商业数据库中最早系统化处理哈希聚合溢写的引擎之一。

### 工作区与一次/多次/最优 pass

Oracle 用 **work area** 概念抽象哈希聚合 / 排序 / 哈希连接的内存使用：

```
- Optimal: 整个算子完成在内存中（无溢写）
- One-pass: 部分溢写到磁盘，但每个数据项只读写一次
- Multi-pass: 数据需要多次读写磁盘（递归分区超过一层）
```

```sql
-- AWR 报告中的工作区统计
SELECT operation_type, optimal_executions, onepass_executions, multipasses_executions
FROM v$sql_workarea_histogram
ORDER BY operation_type;
-- HASH-GROUP BY 行的 multipasses_executions > 0 → 严重溢写

-- 查看正在运行的工作区
SELECT sql_id, operation_type, work_area_size / 1024 / 1024 AS mb,
       expected_size / 1024 / 1024 AS expected_mb,
       actual_mem_used / 1024 / 1024 AS actual_mb
FROM v$sql_workarea_active;
```

### PGA 自动管理（11g+）

老版本 Oracle 用 `hash_area_size` 手动设置每个会话的哈希区大小，11g 起推荐用 `PGA_AGGREGATE_TARGET` + `pga_aggregate_limit`：

```sql
-- 自动模式（默认）
ALTER SYSTEM SET workarea_size_policy = AUTO;
ALTER SYSTEM SET pga_aggregate_target = '10G';
ALTER SYSTEM SET pga_aggregate_limit = '20G';  -- 12c+ 硬上限

-- Oracle 自动在所有 work area 之间分配，避免手动调优
-- 单个 work area 上限 ≈ pga_aggregate_target × 5%（serial）
--                    或 pga_aggregate_target × 30%（parallel）
```

### 监控临时段使用

```sql
-- 当前临时段使用（HASH GROUP BY 溢写会出现在这里）
SELECT s.sid, s.username, u.tablespace,
       u.segtype, u.blocks * 8192 / 1024 / 1024 AS mb
FROM v$session s
JOIN v$tempseg_usage u ON s.saddr = u.session_addr
WHERE u.segtype IN ('HASH', 'SORT', 'LOB')
ORDER BY u.blocks DESC;

-- v$sql_plan_monitor 查看实际执行的内存/磁盘使用
SELECT plan_line_id, plan_operation, plan_options,
       max_workarea_mem / 1024 / 1024 AS max_mem_mb,
       workarea_tempseg_size / 1024 / 1024 AS spill_mb
FROM v$sql_plan_monitor
WHERE sql_id = ':sql_id'
  AND plan_operation = 'HASH'
  AND plan_options = 'GROUP BY';
```

## SQL Server：行模式 vs 批模式两条路径

SQL Server 同时维护两套执行引擎：

- **Row Mode**：传统的逐行 Volcano 模型，2008 R2 起 HashAgg 支持磁盘溢写
- **Batch Mode**：列存 + 向量化引擎，2012 引入（伴随 columnstore index），2019 后扩展到磁盘表

两者的 spill 行为完全不同。

### Row Mode HashAgg spill（2008 R2）

```sql
-- 强制行模式
SELECT CustomerID, SUM(TotalDue)
FROM Sales.SalesOrderHeader
GROUP BY CustomerID
OPTION (RECOMPILE, USE HINT('DISALLOW_BATCH_MODE'));
```

行模式的 HashAgg spill 走 **tempdb 工作表** + 类 sort-based 路径：当哈希表满，把当前条目写到 tempdb 的工作表，新数据继续构建哈希表；扫描完后从工作表读回合并。XEvent `hash_warning` 可以抓到。

```sql
-- 监控 spill：扩展事件
CREATE EVENT SESSION HashSpills ON SERVER
ADD EVENT sqlserver.hash_warning;
ALTER EVENT SESSION HashSpills ON SERVER STATE = START;

-- DMV 查看历史溢写
SELECT TOP 10 query_hash, total_spills, total_logical_reads
FROM sys.dm_exec_query_stats
ORDER BY total_spills DESC;
```

### Batch Mode HashAgg spill（2012+）

批模式聚合走的是真正的 GRACE-style 递归分区：

```
1. 哈希表按 batch（默认 900 行）一组建立
2. 内存预算来自 memory grant
3. 超出预算 → 按 hash bit 分区到 tempdb 工作文件
4. 输入完成后递归处理分区
```

```sql
-- 强制批模式（需要 columnstore index 或 SQL Server 2019+ 启用）
SELECT CustomerID, SUM(TotalDue)
FROM Sales.SalesOrderHeader_CCI  -- columnstore index 表
GROUP BY CustomerID;

-- 实际计划中 Hash Match Aggregate 的属性会显示：
--   Storage = ColumnStore
--   ActualExecutionMode = Batch
--   ActualSpills = 0..N (溢写的分区数)
```

`memory grant` 估算不准是 SQL Server HashAgg 溢写的最大原因。`OPTION (MIN_GRANT_PERCENT = 50)` 之类的提示可以强行抢更多内存，但治标不治本。SQL Server 2017 起的 **adaptive memory grant feedback** 会基于历史执行修正下一次的内存估算。

### Memory Grant 与 Resource Governor

```sql
-- 查看内存授权情况
SELECT session_id, request_id,
       requested_memory_kb / 1024 AS requested_mb,
       granted_memory_kb / 1024 AS granted_mb,
       used_memory_kb / 1024 AS used_mb,
       max_used_memory_kb / 1024 AS max_used_mb,
       dop
FROM sys.dm_exec_query_memory_grants;

-- Resource Governor 限制单 query 内存
CREATE RESOURCE POOL OLAP_pool
    WITH (MAX_MEMORY_PERCENT = 50, REQUEST_MAX_MEMORY_GRANT_PERCENT = 25);
```

## MySQL：没有原生哈希聚合溢写

MySQL 系列（MySQL、MariaDB、Percona）至今没有真正意义上的 HashAgg spill。`GROUP BY` 的执行路径有几条：

1. **使用索引覆盖**：如果 `GROUP BY` 列有索引，走流式聚合，无内存压力
2. **临时表内 HashAgg**：构建一个 `tmp_table_size` 限制的内存临时表，按 group key 哈希
3. **临时表满 → 转 on-disk 临时表**：MySQL 5.7 用 InnoDB 临时表，8.0 用 InnoDB temp tablespace
4. **`tmp_table_size` 不够 + 排序需求 → filesort**

```sql
-- 内存临时表阈值
SHOW VARIABLES LIKE 'tmp_table_size';   -- 默认 16 MB
SHOW VARIABLES LIKE 'max_heap_table_size';  -- 同时限制内存表

-- 监控隐式临时表
SHOW STATUS LIKE 'Created_tmp%';
-- Created_tmp_tables           (内存)
-- Created_tmp_disk_tables      (转磁盘的)
-- Created_tmp_disk_tables 持续增长说明 GROUP BY 频繁溢写

-- 强制看是否走临时表
EXPLAIN
SELECT customer_id, COUNT(*) FROM orders GROUP BY customer_id;
-- Extra 列出现 "Using temporary"; "Using filesort" → 走的是临时表 + 排序
```

MySQL 8.0.18 引入了真正意义上的 hash join，但 **hash join 的溢写仅适用于 JOIN 算子**，不会用于 GROUP BY 聚合。MySQL 团队多次在 worklog 里讨论 HashAgg spill，但截至 9.x 仍未实现。这意味着 MySQL 上做超大基数 GROUP BY 几乎只有这些选项：

- 把 `tmp_table_size` 和 `max_heap_table_size` 调到几个 G（占用大量内存）
- 接受 filesort 的全局排序代价（O(N log N)）
- 应用层分批 + 分组 + 聚合（手动近似 GRACE 算法）
- 迁到列存引擎（ClickHouse / DuckDB / StarRocks）做 OLAP

## DB2：SHEAPTHRES 与排序堆共享池

DB2 的哈希聚合溢写归排序堆（sort heap）管理。`SHEAPTHRES_SHR`（共享）和 `SORTHEAP`（单算子）共同决定阈值：

```sql
-- 查看当前配置
SELECT NAME, VALUE FROM SYSIBMADM.DBCFG
WHERE NAME IN ('SORTHEAP', 'SHEAPTHRES_SHR');

-- SORTHEAP: 单个排序/哈希算子的内存上限（4KB pages）
-- SHEAPTHRES_SHR: 数据库级总内存阈值（所有算子共用）

-- 调优
db2 update db cfg using SORTHEAP 32768          -- 128 MB / 算子
db2 update db cfg using SHEAPTHRES_SHR AUTOMATIC

-- 监控
SELECT TOTAL_HASH_JOINS, TOTAL_HASH_LOOPS, HASH_JOIN_OVERFLOWS,
       HASH_JOIN_SMALL_OVERFLOWS, POST_THRESHOLD_HASH_JOINS
FROM SYSIBMADM.SNAPDB;
-- HASH_JOIN_OVERFLOWS: 哈希溢写到磁盘的次数
-- POST_THRESHOLD_HASH_JOINS: 因 SHEAPTHRES_SHR 受限的执行次数
```

DB2 的哈希聚合溢写采用递归分区，数据写到 SYSTEM TEMPORARY tablespace。DB2 还独有 **post-threshold** 的概念：超过阈值后算子仍然能用受限内存运行，但优先级降低。

## Snowflake：自动溢写到本地 SSD

Snowflake 完全屏蔽了哈希聚合溢写的细节。架构上：

```
Compute Warehouse:
  - 每个 virtual warehouse 是一组 EC2 实例
  - 每个实例本地附带 NVMe SSD（local storage）
  - 当算子内存压力时自动溢写到本地 SSD
  - 本地 SSD 满 → 溢写到 S3（remote spilling，性能差很多）
```

```sql
-- 监控本地溢写
SELECT QUERY_ID, BYTES_SPILLED_TO_LOCAL_STORAGE,
       BYTES_SPILLED_TO_REMOTE_STORAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE BYTES_SPILLED_TO_LOCAL_STORAGE > 0
ORDER BY BYTES_SPILLED_TO_LOCAL_STORAGE DESC
LIMIT 100;

-- BYTES_SPILLED_TO_REMOTE_STORAGE > 0 是性能告警信号
-- → 需要扩大 warehouse size（更多本地 SSD），或重写查询减少状态量
```

Snowflake 的优化器会在编译期估算需要的内存，如果显著超过 warehouse 容量，会建议升级 warehouse。运行期一旦发生远程溢写，查询 latency 通常恶化数十倍（S3 延迟 vs NVMe 延迟）。

## ClickHouse：max_bytes_before_external_group_by

ClickHouse 的哈希聚合默认**不溢写**——超出内存就报错 `Memory limit exceeded`。需要显式开启：

```sql
-- 会话级开启
SET max_bytes_before_external_group_by = 20000000000;   -- 20 GB
SET max_memory_usage = 40000000000;                      -- 40 GB

-- 阈值含义：当哈希聚合中间状态超过 20 GB，开始向磁盘溢写
-- 注意：max_bytes_before_external_group_by 通常设为 max_memory_usage 的一半
-- 因为溢写出去的数据回读时仍要占内存
```

ClickHouse 溢写算法（called "two-level" aggregation）：

1. 内存里维护两级哈希表（256 个 bucket）
2. 当总大小超过阈值，把每个 bucket 的状态写到独立的临时文件
3. 输入处理完，把所有 bucket 的状态归并

```sql
-- 监控溢写
SELECT query, type, memory_usage / 1024 / 1024 AS mem_mb,
       ProfileEvents['ExternalAggregationWritePart'] AS spill_parts,
       ProfileEvents['ExternalAggregationCompressedBytes'] / 1024 / 1024 AS spill_mb
FROM system.query_log
WHERE event_date >= today()
  AND ProfileEvents['ExternalAggregationWritePart'] > 0
ORDER BY event_time DESC;

-- 设置溢写目录
-- 在 config.xml 中：
-- <tmp_path>/var/lib/clickhouse/tmp/</tmp_path>
```

ClickHouse 24.x 还引入了 `aggregation_memory_efficient_merge_threads`，控制磁盘聚合的并行合并线程数，减少高基数场景的合并瓶颈。

### 为什么 ClickHouse 默认不溢写？

ClickHouse 团队的设计哲学是 OLAP 应该在内存里完成，溢写到磁盘性能极差。默认报错让用户主动决定：要么扩大内存，要么显式接受溢写代价。

但生产环境中很多团队被这个默认行为坑过——大查询突然 OOM，整个 server 进程退出导致全集群可用性下降。社区 issues 里多次讨论过是否改默认值，但官方坚持现状。

## Spark SQL：HashAggregateExec 与 Tungsten

Spark 1.6（2016 年 1 月）在 Tungsten 执行引擎中实现了真正的 HashAggregateExec spill。在此之前 Spark SQL 用 SortBasedAggregate（先 shuffle sort 再 streaming aggregate），是 sort-based 聚合的代表。

### UnsafeFixedWidthAggregationMap

Spark Tungsten 的核心数据结构是 **UnsafeFixedWidthAggregationMap**——一个堆外哈希表：

```
UnsafeFixedWidthAggregationMap:
  - Key: UnsafeRow（堆外内存的紧凑 row 表示）
  - Value: UnsafeRow with mutable agg state
  - 哈希函数: MurmurHash3
  - 内存上限: spark.shuffle.spill.numElementsForceSpillThreshold
              + memory manager 给的 page

当哈希表满 → fallback 到 ExternalSorter（sort-based）
然后用 SortAggregateExec 完成最终聚合
```

注意 Spark 的 fallback 路径是 **HashAgg → SortAgg**，不是纯 GRACE 递归分区。从 1.6 到 3.x 这个机制基本稳定。

### 控制参数

```scala
// 物理算子级（spark-sql shell 或 SparkConf）
spark.conf.set("spark.sql.execution.useObjectHashAggregateExec", "true")
// ObjectHashAggregateExec：支持 collect_list/collect_set 等非固定宽度状态

spark.conf.set("spark.shuffle.spill.numElementsForceSpillThreshold",
               "1000000")  // 强制 spill 阈值（默认 Long.MaxValue）

spark.conf.set("spark.sql.adaptive.enabled", "true")
// AQE 在 shuffle 后能动态合并小分区，减少哈希聚合的输入倾斜
```

```sql
-- Spark UI 中 SQL → Stage → Task 列查看 "Spill (Memory)" 和 "Spill (Disk)"
-- explain(true) 输出 *(2) HashAggregate(keys=[customer_id#23], 
--                                      functions=[count(1)], 
--                                      output=[customer_id#23, count(1)#34L])
```

### Tungsten 内存管理

```
Spark 内存模型:
  Executor JVM Heap:
    Reserved (300 MB)
    User memory (40%)
    Storage memory (cached RDDs, broadcast)
    Execution memory (HashAgg, HashJoin, Sort)
  
Off-Heap (Tungsten):
    Page allocator (8 KB pages)
    UnsafeFixedWidthAggregationMap 数据
    UnsafeExternalSorter spill 缓冲区

Storage 与 Execution 间动态借用 (unified memory manager)
当 Execution 需要更多内存且 Storage 借了 → 强制驱逐 Storage
当 Storage 需要内存而 Execution 借了 → 不驱逐，等 Execution 释放
```

### Spark Spill Manager 的关键路径

```scala
// 简化的核心逻辑
trait Spillable {
  def acquireMemory(size: Long): Long
  def spill(): Long  // 返回释放的字节数
}

class UnsafeExternalSorter extends Spillable {
  def spill(): Long = {
    if (inMemSorter.numRecords() > 0) {
      val spillFile = createSpillFile()
      writeSortedRecords(spillFile, inMemSorter.getSortedIterator)
      val released = freeMemory()
      released
    } else 0
  }
}

// SortBasedAggregator 的 fallback：
//   1. 当 UnsafeFixedWidthAggregationMap 内存不足
//   2. 把当前哈希表内容当作 partial agg 输出
//   3. 切换到 ExternalSorter，按 group key 排序
//   4. SortAggregateExec 流式合并
```

Spark 3.0 起的 AQE（Adaptive Query Execution）会基于运行时统计动态调整聚合后的 shuffle 分区数，间接缓解了高基数 GROUP BY 的倾斜问题。

## Trino / Presto：实验性 spill_enabled

Trino（前 PrestoSQL）默认完全在内存中执行所有算子。当查询超过 `query.max-memory` 直接报错失败：

```sql
-- 默认行为
SELECT customer_id, COUNT(*) FROM hive.web.events GROUP BY customer_id;
-- 如果哈希表超出 query.max-memory:
-- Query exceeded per-query memory limit of 8GB
```

Trino 的 spill 功能从 0.179 起作为实验性能力存在，长期未升级到生产 ready 状态：

```properties
# config.properties
spill-enabled=true
spiller-spill-path=/mnt/nvme/trino-spill,/mnt/nvme2/trino-spill
spill-compression-enabled=true
spill-encryption-enabled=false
```

```sql
-- 会话级控制
SET SESSION spill_enabled = true;
SET SESSION aggregation_operator_unspill_memory_limit = '4GB';
```

启用后：
- 哈希聚合算子：内存压力时按 hash 分区写到 spill path
- 哈希连接：build side 可以 spill
- 排序：external sort

但 Trino 团队官方文档警告：**spill 在生产环境性能不可预测**，推荐做法仍是扩大集群内存而非依赖 spill。这也是 Trino 在重 OLAP 场景下相比 Spark 的核心 limitation。

## CockroachDB：external aggregator 与 Pebble

CockroachDB 的 DistSQL 执行框架包含 external aggregator 算子，专门处理超出内存的哈希聚合：

```sql
SHOW CLUSTER SETTING sql.distsql.temp_storage.workmem;
-- 64 MiB (默认)

-- 单 worker 的工作内存阈值，超出走 disk-backed 哈希表
```

实现细节：
- 内存阈值通过 `sql.distsql.temp_storage.workmem` 控制
- 溢写目录由 `--temp-dir` 配置（默认 cockroach-data/temp）
- 底层使用 **Pebble**（CockroachDB 自研 LSM 存储引擎）作为磁盘哈希表
- 同一 SQL workload 同时使用 Pebble，hash agg spill 的写入与 SQL 数据写入共用一个 LSM 引擎，便于统一压缩、复用预写日志

```sql
-- 强制观察溢写
SET CLUSTER SETTING sql.distsql.temp_storage.workmem = '1MiB';
EXPLAIN ANALYZE
SELECT user_id, COUNT(*) FROM events GROUP BY user_id;
-- 结果中 "spilled to disk" 字段会显示 spill 字节数
```

## DuckDB：递归分区 + Radix HashTable

DuckDB 的哈希聚合用 RadixPartitionedHashTable，是教科书级别的 GRACE-style 实现：

```
1. 输入数据按 hash 的高位 bit 分到 256 个 partition
2. 每个 partition 独立维护内存哈希表
3. 当总内存超过 memory_limit，按 partition 顺序 flush 到磁盘
4. 单个 partition 太大 → 按下一个 hash bit 进一步分裂
5. 处理完输入后，遍历每个 partition 的磁盘文件，重新做内存聚合
```

```sql
-- 配置临时空间
PRAGMA temp_directory = '/mnt/nvme/duckdb_tmp';
PRAGMA memory_limit = '4GB';
PRAGMA max_temp_directory_size = '100GB';

-- 强制溢写实验
PRAGMA memory_limit = '256MB';
EXPLAIN ANALYZE
SELECT customer_id, SUM(amount) FROM orders GROUP BY customer_id;
-- Output 中 "Spilled to disk" 行显示溢写量

-- 监控临时文件
SELECT * FROM duckdb_temporary_files();
```

DuckDB 0.9（2023）改写了 streaming HashAgg，让分组场景下哈希聚合可以在不完整收到所有输入时就开始 emit。这是为了把 OLAP 操作集成到流式管道。

## Hive / Spark on Hive：MapReduce 时代的范式

Hive 在 MapReduce 引擎上实现 GROUP BY 是真正的「hash + sort + merge」范式：

```
Map 阶段：
  - 每个 mapper 内部维护一个哈希表（hive.map.aggr=true）做 partial aggregation
  - 当哈希表内存压力大，按 hash(group_key) 分区到 reducer
  
Shuffle 阶段：
  - 按 hash(group_key) % num_reducers 路由到 reducer
  - shuffle 数据按 group_key 排序
  
Reduce 阶段：
  - reducer 收到的数据按 group_key 已排序
  - 流式聚合，O(1) 内存
```

```sql
-- 控制 mapper 端的 partial aggregation
SET hive.map.aggr = true;                           -- 默认开启
SET hive.map.aggr.hash.percentmemory = 0.5;          -- 哈希表占 mapper 内存比例
SET hive.map.aggr.hash.min.reduction = 0.5;          -- 如果哈希表压缩比 < 50%，关闭 partial aggregation

-- 倾斜 GROUP BY 处理
SET hive.groupby.skewindata = true;
-- 分两阶段：先按随机 + group_key 部分聚合，再按 group_key 完全聚合
```

Hive 的设计完全依赖 shuffle 的排序保证，本质上是 sort-based aggregation 的分布式版本。Tez/Spark 引擎接管后开始用更现代的 hash-based 聚合，spill 行为也变得更接近 Spark SQL。

## Flink SQL：批模式的 HashAgg vs 流模式

Flink 的批查询执行器（基于 BLINK planner）实现了完整的 HashAgg spill：

```sql
-- 批模式 HashAgg
SET 'execution.runtime-mode' = 'batch';
SET 'table.exec.resource.default-parallelism' = '8';
SET 'taskmanager.memory.managed.size' = '4gb';

-- 哈希表占 managed memory，超出会按分区溢写到 io.tmp.dirs
```

流模式则完全不同——是增量聚合（每个 group 维护持久化状态，使用 RocksDB state backend）：

```
StreamingAggregation:
  - 每个 group_key 在 RocksDB 中持久化 agg_state
  - 新数据到来 → 读取 state → 更新 → 写回
  - 实质上是 disk-resident 哈希表，没有传统意义的 "spill"
```

这种状态后端模式让 Flink 可以处理无界流的聚合，但代价是每次更新都有 disk I/O。

## CockroachDB 之外的 NewSQL：TiDB / OceanBase

### TiDB：5.0 起支持 HashAgg spill

```sql
-- 启用聚合溢写
SET tidb_enable_parallel_agg_spill = ON;
SET tidb_mem_quota_query = 4 << 30;     -- 4 GB 单查询内存上限
SET tidb_tmp_table_max_size = 64 << 20;

-- 5.0 之前 TiDB 的 HashAgg 超出 mem_quota 直接 OOM kill query
-- 5.0+ 实现了类似 PG 的递归分区
-- 7.0+ 优化了并行 spill 的合并性能
```

### OceanBase：HASH GROUP BY 与租户内存

OceanBase 是 Oracle 兼容架构，HashAgg 行为接近 Oracle：

```sql
-- 系统视图 GV$OB_SQL_AUDIT 中 PLAN_OPERATION 包含 HASH GROUP BY
SELECT PLAN_OPERATION, OUTPUT_ROWS, MEMSTORE_READ_ROW_COUNT,
       SSSTORE_READ_ROW_COUNT, EXEC_TIME
FROM GV$OB_SQL_AUDIT
WHERE PLAN_OPERATION = 'HASH GROUP BY';

-- 租户内存超出 → 走 spill 到本地临时表空间
```

## ClickHouse 的 two-level hashtable 与并行聚合

值得单独展开 ClickHouse 的 two-level hashtable，因为这是高并发场景下的精彩设计：

```
普通哈希表的并行问题:
  - 多线程并发插入需要锁或 CAS
  - 锁竞争在大基数 group 下成为瓶颈

Two-level 设计:
  Level 1: 256 个独立 bucket (按 group_key 高 8 bit 分)
  Level 2: 每个 bucket 内是一个普通哈希表
  
  并行聚合：
    - 每个线程负责一部分 bucket
    - 不同 bucket 之间无锁竞争
    - 同一 bucket 内由单线程处理
  
  溢写：
    - 每个 bucket 的状态独立写到磁盘
    - 256 个文件天然适合并行 IO
```

```xml
<!-- config.xml -->
<aggregation_in_order_max_block_bytes>1048576</aggregation_in_order_max_block_bytes>
<group_by_two_level_threshold>100000</group_by_two_level_threshold>
<group_by_two_level_threshold_bytes>50000000</group_by_two_level_threshold_bytes>
```

`group_by_two_level_threshold` 控制何时从 single-level 升级到 two-level——小基数场景下用 single-level 减少开销，大基数场景下用 two-level 提升并行度。

## Vertica / SAP HANA：列存原生设计

列存数据库的哈希聚合天然适合 GRACE 分区：

### Vertica

```sql
-- 资源池控制
ALTER RESOURCE POOL general MEMORYSIZE '8G' MAXMEMORYSIZE '16G';

-- 监控聚合算子的内存使用
SELECT transaction_id, statement_id, path_id,
       memory_consumption_kb / 1024 AS mem_mb
FROM execution_engine_profiles
WHERE operator_name = 'GroupByHash'
ORDER BY mem_mb DESC;
```

Vertica 的 GroupByHash 算子在内存压力下走自研的 disk spill 机制，溢写到 TEMP storage location（通常配置在独立 SSD）。

### SAP HANA

HANA 的列存执行引擎支持 multi-level HashAgg，但设计哲学是「不应溢写」——一旦发生溢写性能急剧下降，是性能告警信号：

```sql
-- 监控溢写
SELECT * FROM M_TEMPORARY_TABLES
WHERE SCHEMA_NAME = '_SYS_STATISTICS'
  AND TABLE_NAME LIKE 'HASH_AGG%';

-- 调整内存上限
ALTER SYSTEM ALTER CONFIGURATION ('global.ini', 'SYSTEM') 
SET ('memorymanager', 'global_allocation_limit') = '...' WITH RECONFIGURE;
```

## StarRocks / Doris：MPP 列存的现代实现

StarRocks 3.0 引入了完整的 spill 框架（`enable_spill = true`），覆盖 HashAgg / HashJoin / Sort：

```sql
-- 会话级开启
SET enable_spill = true;
SET spill_mode = 'auto';                         -- auto / force / no_spill
SET spill_mem_limit_threshold = 0.8;             -- 内存使用率超过 80% 触发溢写
SET query_mem_limit = 8589934592;                -- 8 GB 单查询上限

-- 监控
SELECT * FROM information_schema.tasks
WHERE TASK_TYPE = 'AGG' AND SPILL_BYTES > 0;
```

Doris 2.1（2024）跟进实现 spill，用法相似。两者底层都借鉴了 Spark / DuckDB 的递归分区设计。

## Impala：scratch_dirs 与 mem_limit

Impala 的 HashAgg spill 自 2.0 起完整支持：

```sql
-- 单查询内存限制
SET MEM_LIMIT = '8gb';

-- spill 目录配置（启动参数）
-- --scratch_dirs=/data1/impala-scratch,/data2/impala-scratch

-- 强制查看 spill
SET MEM_LIMIT = '64mb';
SELECT user_id, COUNT(*) FROM events GROUP BY user_id;
-- profile 中 "Hash Aggregation" 节点会显示：
--   SpilledPartitions: N
--   PeakMemoryUsage: ...
```

## 跨引擎对比：触发溢写的内存阈值参数

不同引擎暴露的「内存阈值」参数语义差异极大，下表汇总核心配置：

| 引擎 | 阈值参数 | 默认值 | 单位 | 作用范围 |
|------|---------|--------|------|---------|
| PostgreSQL | `work_mem * hash_mem_multiplier` | 4MB × 2.0 | 字节 | 每算子 / 每后端 |
| MySQL | `tmp_table_size` | 16MB | 字节 | 每查询的临时表 |
| Oracle | PGA 自动管理 | 5% of pga_aggregate_target | 字节 | 每 work area |
| SQL Server | memory grant | 优化器估算 | 字节 | 每查询 |
| DB2 | `SORTHEAP` | 取决于 STMM | 4KB pages | 每算子 |
| Snowflake | warehouse local SSD | 不可配置 | 字节 | 自动 |
| ClickHouse | `max_bytes_before_external_group_by` | 0（不溢写） | 字节 | 每查询 |
| Trino | `query.max-memory` + `spill_enabled` | 8GB / off | 字节 | 每查询 |
| Spark SQL | `spark.shuffle.spill.numElementsForceSpillThreshold` | Long.MaxValue | 元素数 | 每 task |
| DuckDB | `memory_limit` | 80% RAM | 字节 | 整个进程 |
| TiDB | `tidb_mem_quota_query` | 1GB | 字节 | 每查询 |
| StarRocks | `query_mem_limit` + `spill_mem_limit_threshold` | 0 / 0.8 | 字节 / 比例 | 每查询 |
| Impala | `MEM_LIMIT` | 0 (无限) | 字节 | 每查询 |

> 配置陷阱：PostgreSQL 的 `work_mem` 是**每算子**的，单查询多个 HashAgg + max_parallel_workers 可能消耗 N × M × work_mem；ClickHouse 的 `max_bytes_before_external_group_by` 默认 0 意味着「不溢写直接 OOM」，这是 ClickHouse 生产环境最大的运维陷阱。

## 高基数 GROUP BY 的优化策略

无论哪个引擎，超大基数 GROUP BY 都不应该简单依赖 spill。常见优化策略：

### 1. 用近似算法替代精确聚合

```sql
-- 精确 COUNT(DISTINCT user_id) 在 10 亿基数下需要哈希表存全部 user_id
SELECT COUNT(DISTINCT user_id) FROM events;

-- HyperLogLog 把空间从 O(N) 降到 O(log log N)
-- BigQuery / Snowflake / Trino / DuckDB / Spark 都支持
SELECT APPROX_COUNT_DISTINCT(user_id) FROM events;
```

### 2. 降基数

```sql
-- 不必要的高基数列可以降到桶
SELECT bucket_id, COUNT(*) FROM (
  SELECT MOD(HASH(user_id), 1000) AS bucket_id FROM events
) t GROUP BY bucket_id;
-- 1000 个桶足以覆盖大多数分析需求
```

### 3. 增量聚合

```sql
-- 物化视图增量维护，避免每次全量哈希
CREATE MATERIALIZED VIEW events_by_user AS
SELECT user_id, COUNT(*) AS cnt
FROM events
GROUP BY user_id;
-- PostgreSQL / Snowflake / ClickHouse / SingleStore 等支持
```

### 4. 分区裁剪 + 局部聚合

```sql
-- 利用表分区，每分区独立聚合
SELECT user_id, SUM(amount)
FROM orders
WHERE event_date = '2024-01-15'   -- 仅一个分区
GROUP BY user_id;
```

### 5. 调大 hash_mem_multiplier（PG 15+）

```sql
ALTER SYSTEM SET hash_mem_multiplier = 4.0;
-- HashAgg 可用 work_mem × 4，减少溢写概率
```

## 对引擎开发者的实现建议

### 1. 选 GRACE 递归分区还是 sort-based fallback

GRACE 递归分区（推荐）：
- 真正的哈希语义，无需全局排序
- 列存 / 向量化引擎天然契合（partition by hash）
- 平均时间复杂度 O(N)

sort-based fallback（不推荐）：
- 实现简单（复用排序代码）
- 但全局排序的常数因子让 OLAP 性能差很多
- 仅适合 OLTP 引擎或低频场景

### 2. 决定分区数（partition fan-out）

```
理论最优分区数 = ceil(估算总大小 / 内存预算)

实践需要 trade-off:
  - 分区太多 → 每分区文件太小，IO 效率低
  - 分区太少 → 单分区超出内存，需要递归分区

PG 13 实现：
  - 初始 partition_count = max(2^ceil(log2(N/work_mem)), 4)
  - 每次递归 partition 加 4 bit (16 倍分裂)
  - 单算子最多分区数受 max_files_per_process 影响

DuckDB 实现：
  - 总是 256 个分区（一字节哈希）
  - 单分区过大递归到下一层 256 分区
  - 总文件数可能爆炸，需要文件管理优化
```

### 3. 用 LogicalTapeSet 避免文件数爆炸

```
直接每个分区一个 OS 文件:
  - 假设 256 分区 × 32 并发查询 = 8192 个 fd
  - 触及 ulimit -n，需要全局协调

LogicalTapeSet (PG/Spark 都用):
  - 一个 OS 文件被切成多个逻辑磁带
  - 磁带间可独立读写
  - 文件数从 N × M 降到 M
```

### 4. 处理 hash skew

```
极端情况：所有数据都 hash 到一个分区
  - 分区文件无限大
  - 递归再分区也无效（hash collision）

应对：
  1. 使用强哈希（MurmurHash3, xxHash）减少冲突
  2. 检测到分区严重倾斜时，切换到 sort-based fallback
  3. PG 13 的实现：检测到递归深度过深时报错，让用户介入
  4. Spark 的实现：fallback 到 SortAgg
```

### 5. 与并行执行的协同

```
单算子 HashAgg + N 并行 worker:
  - 每个 worker 独立维护哈希表 (partial aggregation)
  - shuffle/gather 时合并

注意:
  - 每个 worker 的哈希表独立计算 work_mem
  - PG: 总内存 = N × work_mem × hash_mem_multiplier
  - 优化器需要在并行度选择时考虑总内存
```

### 6. 可观测性必须是一等公民

```
EXPLAIN ANALYZE 输出至少包含:
  - 内存峰值 (Memory Usage)
  - 磁盘溢写量 (Disk Usage)
  - 溢写分区数 (Batches / SpilledPartitions)
  - 递归层数 (Used Bits)

系统视图至少:
  - 当前正在 spill 的查询
  - 历史 spill 总量统计
  - 临时空间使用情况
```

PG 13 的 EXPLAIN ANALYZE 输出 `Memory Usage: 4145kB  Disk Usage: 12288kB` 是很好的范例；ClickHouse 的 ProfileEvents 也很完善。SQL Server 的 spill 信息散落在 XEvent 和 DMV 中，可观测性偏弱。

### 7. Cost-based optimizer 要考虑 spill 代价

```
优化器选择 HashAgg vs SortAgg 时:
  - 估算 group 基数 cardinality
  - 估算单个 agg state 的字节大小
  - 总内存需求 = cardinality × state_size
  - 如果 > work_mem * hash_mem_multiplier → spill 代价显著
  
PG 12 之前的核心 bug:
  - 没有把 spill 代价计入 HashAgg 的成本估算
  - 优化器以为 HashAgg 总是在内存里，盲目选择
  - 实际跑起来发生 OOM

PG 13 修复:
  - HashAgg 成本 = base_cost + spill_io_cost (如果预计 spill)
  - 让优化器在估算 group 数大时倾向 SortAgg
```

### 8. 测试要点

```
功能测试:
  - 强制小 work_mem 触发 spill，验证结果正确性
  - 边界：单 group / 1 亿 group / 全部 distinct
  - 边界：空表 / NULL group key

性能测试:
  - 控制变量：work_mem 固定，group 基数 1K → 1B
  - 监控 spill 字节数、IO 时间、总执行时间
  - 与 sort-based 实现对比

压力测试:
  - 极端倾斜：99% 数据 hash 到一个分区
  - 验证递归分区不会无限循环
  - 验证文件描述符不会爆炸
```

## 关键发现

1. **HashAgg spill 的成熟时间差超过十年**：商业数据库（Oracle 9i 2001、SQL Server 2008 R2/2012）领先开源十年以上；PostgreSQL 直到 13 版本（2020）才补齐这块短板，期间 OOM 杀进程是 PG 运维最痛的问题之一。

2. **MySQL 至今没有真正的 HashAgg spill**：依赖 `tmp_table_size` + filesort 退化路径，超大基数 GROUP BY 几乎只能走全局排序。MySQL 8.0 的 hash join 仅适用 JOIN，未扩展到聚合。

3. **递归分区是现代主流**：2010 年后新引擎（Spark 1.6 2016、DuckDB、Snowflake、CockroachDB）几乎全部采用 GRACE 递归分区，sort-based fallback 沦为历史路径。SQL Server 的 batch mode 也是递归分区。

4. **ClickHouse 默认不溢写是设计哲学但也是运维陷阱**：`max_bytes_before_external_group_by = 0` 意味着 OLAP 查询超出内存直接 OOM，生产环境必须显式调整。

5. **Trino 的 spill 长期是实验性功能**：官方推荐做法是扩集群内存而非依赖 spill，这与 Spark / Snowflake 把 spill 当 first-class 的设计哲学相反。

6. **PG 的 hash_mem_multiplier 是优雅的折中**：PG 15（2022）默认 2.0，让哈希算子获得比排序算子更多内存预算，避免「为了 HashAgg 调高 work_mem 导致排序也吃过多内存」的问题。

7. **云数仓把 spill 复杂度藏起来**：Snowflake / BigQuery / Redshift 自动溢写到本地 SSD，远程溢写到对象存储，用户无需配置但也无法精细调优。Snowflake 的 `BYTES_SPILLED_TO_REMOTE_STORAGE > 0` 是核心性能告警信号。

8. **Spark 用 sort-based fallback 而非纯 GRACE**：UnsafeFixedWidthAggregationMap 满后切到 ExternalSorter + SortAggregateExec，是 hash + sort 的混合架构。这与 PG / DuckDB 的纯递归分区不同。

9. **可观测性差异巨大**：PG 13+ 的 EXPLAIN ANALYZE 直接显示 Disk Usage / Batches，DuckDB 提供 `duckdb_temporary_files()`，ClickHouse 有完整 ProfileEvents；而 SQL Server 的 spill 信息散落在 XEvent / DMV，Trino 的 spill 监控在 0.x 系列长期不完善。

10. **未来方向是磁盘哈希表**：CockroachDB 用 Pebble、Flink 用 RocksDB、RisingWave 用状态后端，把 spill 从「临时文件」演进到「持久化存储」，模糊了哈希表与磁盘表的边界。这条路在 OLTP/OLAP 融合场景下会越来越主流。

## 参考资料

- PostgreSQL: [HashAggregate spill (commit 1f39bce)](https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=1f39bce021540fde00990af55b4432c55ef4b3c7)
- PostgreSQL 13 Release Notes: [HashAggregate spill](https://www.postgresql.org/docs/13/release-13.html)
- PostgreSQL 15 Release Notes: [hash_mem_multiplier default 2.0](https://www.postgresql.org/docs/15/release-15.html)
- Jeff Davis blog: ["Hash Aggregation in Postgres 13"](https://pgsqlpgpool.blogspot.com/2020/05/hashagg-spill-in-postgresql-13.html)
- Spark SQL: [HashAggregateExec source](https://github.com/apache/spark/blob/master/sql/core/src/main/scala/org/apache/spark/sql/execution/aggregate/HashAggregateExec.scala)
- Spark Tungsten: [Project Tungsten blog post](https://databricks.com/blog/2015/04/28/project-tungsten-bringing-spark-closer-to-bare-metal.html)
- ClickHouse: [Aggregator.h](https://github.com/ClickHouse/ClickHouse/blob/master/src/Interpreters/Aggregator.h)
- ClickHouse: [GROUP BY in External Memory](https://clickhouse.com/docs/en/sql-reference/statements/select/group-by#group-by-in-external-memory)
- DuckDB: [Aggregate Hash Tables blog](https://duckdb.org/2024/03/01/aggregate-hash-tables.html)
- Trino: [Spill to Disk](https://trino.io/docs/current/admin/spill.html)
- SQL Server: [Hash Spills](https://learn.microsoft.com/en-us/sql/relational-databases/event-classes/hash-warning-event-class)
- Oracle: [PGA Memory Management](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgdba/tuning-program-global-area.html)
- Snowflake: [Recognizing Disk Spilling](https://community.snowflake.com/s/article/Recognizing-Disk-Spilling)
- Kitsuregawa, M. et al. "Application of Hash to Data Base Machine and Its Architecture" (1983) - GRACE Hash 原始论文
- Graefe, G. "Query Evaluation Techniques for Large Databases" (1993) - 哈希聚合的经典综述
- Müller, I. et al. "Cache-Efficient Aggregation: Hashing Is Sorting" (SIGMOD 2015)
