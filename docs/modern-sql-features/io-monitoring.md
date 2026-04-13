# I/O 监控与读写统计 (I/O Monitoring)

一条慢查询的真相往往藏在 I/O 计数器里：是 1000 万次逻辑读击穿了 CPU 缓存，还是 10 万次物理读拖垮了存储？区分 **物理读（physical read）** 与 **逻辑读（logical read）**，是数据库性能调优最基础也最关键的一步——它决定了你应该扩内存、加 SSD、还是改写 SQL。

## 为什么要区分物理读与逻辑读

任何关系数据库的存取路径都可以抽象为两层：

1. **逻辑读（logical read / buffer get）**：执行器向缓冲池（buffer pool / shared buffers）请求一个数据块。无论该块当前是否在内存，每次请求都计 1 次逻辑读。
2. **物理读（physical read / disk read）**：缓冲池未命中，必须从磁盘（或远程存储、对象存储）读取数据块。每次落盘 I/O 才计 1 次物理读。

两者的差值就是 **缓冲池命中（buffer hit）**。命中率公式：

```
buffer cache hit ratio = 1 - (physical reads / logical reads)
```

为什么这个区分如此重要？

- **逻辑读高、物理读低**：CPU 瓶颈。通常是嵌套循环连接、低效执行计划、或者重复扫描同一块。解决方法是改写 SQL、加索引、用更优的连接算法——加内存没用，因为数据已经在内存里。
- **逻辑读低、物理读高**：存储瓶颈。通常是缓冲池太小、冷查询、或者一次性扫描超大表。解决方法是扩缓冲池、分区裁剪、列存压缩。
- **逻辑读和物理读都高**：双重灾难。常见于报表查询全表扫描数十亿行，缓冲池被冲刷殆尽。
- **逻辑读和物理读都低**：理想状态，通常意味着索引精准命中。

只看 "查询耗时" 是不够的：同一条 SQL 在冷缓存和热缓存下耗时可以差 100 倍，但执行计划本身没有变化。Oracle DBA 圈有一句老话："Tune logical reads, not response time"——逻辑读才是稳定可比较的成本指标。

## 没有 SQL 标准

ISO/IEC 9075 标准从未定义 I/O 监控接口。所有引擎的 I/O 计数都是 **内部插桩（internal instrumentation）** 通过特定视图、表函数或扩展协议暴露：

- PostgreSQL: `pg_stat_*` 视图族 + `pg_stat_statements` 扩展
- Oracle: `V$SESSTAT` / `V$SYSSTAT` / `V$SQLSTATS` / ASH
- SQL Server: `sys.dm_*` 动态管理视图（DMV）
- MySQL: `performance_schema` 与 `INFORMATION_SCHEMA`
- DB2: `MON_GET_*` 表函数
- ClickHouse: `system.events` / `system.metric_log`
- Snowflake: `INFORMATION_SCHEMA.QUERY_HISTORY` + Query Profile
- BigQuery: `INFORMATION_SCHEMA.JOBS_BY_*`

这种碎片化意味着可观测性栈（Datadog、Prometheus exporter、pganalyze、Lightwing 等）必须为每种数据库单独写采集器，没有任何复用空间。

## 支持矩阵

下列矩阵覆盖 49 个数据库引擎。"是"=原生支持，"--"=不支持或需要外部工具，"部分"=有限支持。

### 1. 物理读计数器 / 逻辑读计数器 / 缓冲池命中率

| 引擎 | 物理读 | 逻辑读 | 缓冲池命中率 | 暴露方式 |
|------|--------|--------|-------------|---------|
| PostgreSQL | 是 | 是 | 计算 | `pg_stat_database`, `pg_statio_*` |
| MySQL | 是 | 是 | 计算 | `SHOW STATUS`, `performance_schema` |
| MariaDB | 是 | 是 | 计算 | 同 MySQL |
| SQLite | -- | -- | -- | 嵌入式，无后台插桩 |
| Oracle | 是 | 是 | 是 | `V$SYSSTAT`, `V$BUFFER_POOL_STATISTICS` |
| SQL Server | 是 | 是 | 是 | `sys.dm_os_performance_counters`, `STATISTICS IO` |
| DB2 | 是 | 是 | 是 | `MON_GET_BUFFERPOOL` |
| Snowflake | 部分 | -- | -- | Query Profile 中 local/remote disk reads |
| BigQuery | -- | -- | -- | 仅 bytes scanned |
| Redshift | 是 | 是 | 是 | `STL_QUERY`, `SVL_QUERY_METRICS`, `SVV_DISKUSAGE` |
| DuckDB | -- | -- | -- | 嵌入式，无插桩 |
| ClickHouse | 是 | 是 | 是 | `system.events`（数百个 ProfileEvents） |
| Trino | 是 | -- | -- | Query stats，仅物理 bytes |
| Presto | 是 | -- | -- | 同 Trino |
| Spark SQL | 是 | -- | -- | Spark UI / Task metrics |
| Hive | 部分 | -- | -- | Counters via Tez/MR |
| Flink SQL | 是 | -- | -- | Operator metrics |
| Databricks | 是 | -- | -- | Spark UI + Photon metrics |
| Teradata | 是 | 是 | 是 | DBQL `IOCount`, ResUsage |
| Greenplum | 是 | 是 | 计算 | 继承 PG，segment-level |
| CockroachDB | 是 | 是 | 是 | `crdb_internal.node_metrics`, KV stats |
| TiDB | 是 | 是 | 是 | `INFORMATION_SCHEMA.TIKV_STORE_STATUS`, slow log |
| OceanBase | 是 | 是 | 是 | `GV$SYSSTAT`, `GV$OB_SQL_AUDIT` |
| YugabyteDB | 是 | 是 | 是 | 继承 PG + DocDB metrics |
| SingleStore | 是 | 是 | 是 | `INFORMATION_SCHEMA.MV_*` |
| Vertica | 是 | 是 | 是 | `EXECUTION_ENGINE_PROFILES`, `RESOURCE_POOL_STATUS` |
| Impala | 是 | -- | -- | Query Profile |
| StarRocks | 是 | -- | -- | `information_schema.tables_statistics`, FE metrics |
| Doris | 是 | -- | -- | BE metrics + Query Profile |
| MonetDB | 部分 | -- | -- | `sys.queue()`, prelude/epilogue 计时 |
| CrateDB | 是 | -- | -- | `sys.jobs_metrics` |
| TimescaleDB | 是 | 是 | 计算 | 继承 PG |
| QuestDB | 部分 | -- | -- | metrics endpoint (Prometheus) |
| Exasol | 是 | -- | -- | `EXA_DBA_*` 审计表 |
| SAP HANA | 是 | 是 | 是 | `M_BUFFER_CACHE_STATISTICS`, `M_SQL_PLAN_CACHE` |
| Informix | 是 | 是 | 是 | `onstat -p`, `sysmaster` 数据库 |
| Firebird | 部分 | -- | -- | Trace API + `MON$IO_STATS` |
| H2 | -- | -- | -- | 无 |
| HSQLDB | -- | -- | -- | 无 |
| Derby | -- | -- | -- | 无 |
| Amazon Athena | -- | -- | -- | 仅 data scanned (bytes) |
| Azure Synapse | 是 | -- | -- | `sys.dm_pdw_*` DMVs |
| Google Spanner | 部分 | -- | -- | `SPANNER_SYS.*` 表 |
| Materialize | 部分 | -- | -- | `mz_internal` schema |
| RisingWave | 部分 | -- | -- | Prometheus metrics |
| InfluxDB (SQL) | 部分 | -- | -- | `_internal` measurements |
| DatabendDB | 是 | -- | -- | `system.metrics`, query profile |
| Yellowbrick | 是 | 是 | 是 | `sys.query` 视图 |
| Firebolt | 部分 | -- | -- | Query History UI |

> 统计：约 28 个引擎完整暴露物理/逻辑读双指标；MPP 与对象存储型仓库（Snowflake、BigQuery、Trino、Spark）通常只统计 "物理 bytes"，因为缓冲池层级被远程存储抽象掉了。

### 2. 临时文件 I/O / WAL 与 Redo 写入

| 引擎 | 临时文件 I/O | WAL/Redo 写量 | 视图 / 计数 |
|------|-------------|---------------|------------|
| PostgreSQL | 是 | 是 | `pg_stat_database.temp_bytes`, `pg_stat_wal` |
| MySQL | 是 | 是 (binlog/redo) | `Innodb_os_log_written`, `Created_tmp_disk_tables` |
| MariaDB | 是 | 是 | 同 MySQL |
| SQLite | -- | 是 (WAL mode) | PRAGMA wal_checkpoint |
| Oracle | 是 | 是 | `V$TEMPSTAT`, `V$SYSSTAT` 'redo size' |
| SQL Server | 是 | 是 | `sys.dm_io_virtual_file_stats`(tempdb), log bytes flushed |
| DB2 | 是 | 是 | `MON_GET_TABLESPACE`(tempspace), `MON_GET_TRANSACTION_LOG` |
| Snowflake | 是 | -- (云) | Query Profile bytes spilled to local/remote |
| BigQuery | 部分 | -- | shuffle bytes spilled to disk |
| Redshift | 是 | -- | `SVL_QUERY_SUMMARY` (is_diskbased) |
| DuckDB | 部分 | -- | spill 到磁盘但无视图 |
| ClickHouse | 是 | 是 (parts merge) | `ExternalSortWritten`, `WriteBufferFromFile` 系列事件 |
| Trino | 是 | -- | spilled bytes per query |
| Presto | 是 | -- | 同 Trino |
| Spark SQL | 是 | -- | shuffle spill metrics |
| Hive | 是 | -- | Tez counters |
| Flink SQL | 是 | 是 (checkpoint) | RocksDB metrics |
| Databricks | 是 | 是 (Delta log) | Photon metrics |
| Teradata | 是 | 是 | DBC.ResUsageSpma, TJ |
| Greenplum | 是 | 是 | 继承 PG |
| CockroachDB | 是 | 是 (Raft log) | `node_metrics` |
| TiDB | 是 | 是 (Raft) | TiKV metrics |
| OceanBase | 是 | 是 (clog) | `GV$OB_SERVERS` |
| YugabyteDB | 是 | 是 (Raft WAL) | DocDB metrics |
| SingleStore | 是 | 是 | `MV_DISK_USAGE` |
| Vertica | 是 | -- (无 redo) | `STORAGE_USAGE`, WOS/ROS |
| Impala | 是 | -- | Query Profile |
| StarRocks | 是 | 是 | BE metrics |
| Doris | 是 | 是 | BE metrics |
| MonetDB | 是 | 是 | WAL files |
| CrateDB | 是 | 是 | `sys.shards`, translog |
| TimescaleDB | 是 | 是 | 继承 PG |
| QuestDB | 是 | 是 | metrics |
| Exasol | 是 | 是 | `EXA_DBA_AUDIT_SQL` |
| SAP HANA | 是 | 是 | `M_VOLUME_IO_TOTAL_STATISTICS` |
| Informix | 是 | 是 | `onstat -l` |
| Firebird | 是 | 是 | `MON$IO_STATS` |
| H2 | 部分 | -- | -- |
| HSQLDB | -- | 是 | -- |
| Derby | -- | 是 | -- |
| Amazon Athena | -- | -- | -- |
| Azure Synapse | 是 | -- | DMV |
| Google Spanner | -- | -- | -- |
| Materialize | 部分 | 是 | mz_internal |
| RisingWave | 部分 | 是 | metrics |
| InfluxDB (SQL) | 部分 | 是 | _internal |
| DatabendDB | 是 | -- | metrics |
| Yellowbrick | 是 | 是 | sys.query |
| Firebolt | -- | -- | -- |

### 3. 单查询 I/O 统计 / 实时会话 I/O 视图

| 引擎 | 单查询 I/O（EXPLAIN BUFFERS / STATISTICS IO） | 实时会话 I/O 视图 |
|------|---------------------------------------|-----------------|
| PostgreSQL | `EXPLAIN (ANALYZE, BUFFERS)` | `pg_stat_activity` + `pg_stat_io` (16+) |
| MySQL | `EXPLAIN ANALYZE` (有限) | `performance_schema.events_statements_current` |
| MariaDB | `ANALYZE FORMAT=JSON` | 同 MySQL |
| SQLite | -- | -- |
| Oracle | `gather_plan_statistics` hint, `DBMS_XPLAN.DISPLAY_CURSOR` | `V$SESSION`, `V$SESSION_WAIT`, ASH |
| SQL Server | `SET STATISTICS IO ON` | `sys.dm_exec_requests`, `sys.dm_exec_query_stats` |
| DB2 | `db2exfmt` + monitoring | `MON_GET_CONNECTION` |
| Snowflake | Query Profile (UI/JSON) | `INFORMATION_SCHEMA.QUERY_HISTORY` |
| BigQuery | execution details | `INFORMATION_SCHEMA.JOBS_BY_PROJECT` |
| Redshift | `SVL_QUERY_REPORT` | `STV_INFLIGHT` |
| DuckDB | `EXPLAIN ANALYZE` (有限) | -- |
| ClickHouse | `EXPLAIN PLAN`, `system.query_log` | `system.processes` |
| Trino | `EXPLAIN ANALYZE` | `SYSTEM.RUNTIME.QUERIES` |
| Presto | `EXPLAIN ANALYZE` | `system.runtime.queries` |
| Spark SQL | Spark UI per-stage | running jobs page |
| Hive | Tez UI | YARN UI |
| Flink SQL | Web UI per operator | Web UI |
| Databricks | Spark UI + Query Profile | Cluster UI |
| Teradata | `EXPLAIN`, DBQLSqlTbl | `SESSIONINFO` |
| Greenplum | `EXPLAIN (ANALYZE, BUFFERS)` | `gp_stat_activity` |
| CockroachDB | `EXPLAIN ANALYZE` | `SHOW SESSIONS` |
| TiDB | `EXPLAIN ANALYZE` | `INFORMATION_SCHEMA.PROCESSLIST` |
| OceanBase | `EXPLAIN EXTENDED`, SQL Audit | `GV$OB_PROCESSLIST` |
| YugabyteDB | `EXPLAIN (ANALYZE, DIST)` | `pg_stat_activity` |
| SingleStore | `PROFILE` | `MV_ACTIVITIES` |
| Vertica | `PROFILE`, `EXECUTION_ENGINE_PROFILES` | `SESSIONS` |
| Impala | `PROFILE` | Web UI |
| StarRocks | Query Profile | `SHOW PROC` |
| Doris | Query Profile | `SHOW PROCESSLIST` |
| MonetDB | `TRACE` | `sys.queue()` |
| CrateDB | `EXPLAIN ANALYZE` | `sys.jobs` |
| TimescaleDB | `EXPLAIN BUFFERS` | 继承 PG |
| QuestDB | `EXPLAIN` (有限) | -- |
| Exasol | `PROFILE` | `EXA_DBA_SESSIONS` |
| SAP HANA | `EXPLAIN PLAN`, PlanViz | `M_ACTIVE_STATEMENTS` |
| Informix | `SET EXPLAIN ON` | `onstat -g sql` |
| Firebird | Trace API | `MON$STATEMENTS` |
| H2 | `EXPLAIN ANALYZE` (有限) | -- |
| HSQLDB | -- | -- |
| Derby | -- | -- |
| Amazon Athena | EXPLAIN ANALYZE | -- |
| Azure Synapse | `sys.dm_pdw_request_steps` | `sys.dm_pdw_exec_requests` |
| Google Spanner | Query stats | `SPANNER_SYS.QUERY_STATS_*` |
| Materialize | `EXPLAIN`, `mz_internal` | `mz_active_peeks` |
| RisingWave | `EXPLAIN ANALYZE` | metrics |
| InfluxDB (SQL) | `EXPLAIN ANALYZE` | -- |
| DatabendDB | `EXPLAIN ANALYZE` | `system.processes` |
| Yellowbrick | `EXPLAIN ANALYZE` | `sys.query` |
| Firebolt | Query History UI | -- |

### 4. 等待时间直方图 / 表/索引级 I/O / NUMA 感知

| 引擎 | 等待事件直方图 | 表/索引级 I/O | NUMA-aware I/O |
|------|--------------|-------------|----------------|
| PostgreSQL | wait_event 字段（无直方图） | `pg_statio_user_tables/indexes` | -- |
| MySQL | `events_waits_summary_global_by_event_name` 含 BUCKET | `table_io_waits_summary_by_table` | -- |
| MariaDB | 同 MySQL | 同 MySQL | -- |
| SQLite | -- | -- | -- |
| Oracle | `V$EVENT_HISTOGRAM` | `V$SEGMENT_STATISTICS` | 是 (NUMA pools) |
| SQL Server | `sys.dm_os_wait_stats`, XEvent histogram | `sys.dm_db_index_usage_stats` | 是 (soft-NUMA) |
| DB2 | `MON_GET_DATABASE` waits | `MON_GET_TABLE`, `MON_GET_INDEX` | 是 |
| Snowflake | -- | -- | -- |
| BigQuery | -- | -- | -- |
| Redshift | `STL_WLM_QUERY` | `STV_TBL_PERM` | -- |
| DuckDB | -- | -- | -- |
| ClickHouse | `system.metric_log` (秒级) | `system.parts` per table | -- |
| Trino | -- | -- | -- |
| Presto | -- | -- | -- |
| Spark SQL | Task metrics | -- | -- |
| Hive | -- | -- | -- |
| Flink SQL | -- | -- | -- |
| Databricks | -- | Delta history | -- |
| Teradata | ResUsage histograms | DBQL ObjectTbl | 是 |
| Greenplum | 继承 PG | 继承 PG | -- |
| CockroachDB | -- | KV-level metrics | -- |
| TiDB | TiKV grafana | `INFORMATION_SCHEMA.TIKV_REGION_PEERS` | -- |
| OceanBase | `GV$SYSTEM_EVENT` | `GV$OB_TABLE_STATISTICS` | 是 |
| YugabyteDB | -- | -- | -- |
| SingleStore | `MV_BLOCKED_QUERIES` | `MV_DISK_USAGE` per table | 是 |
| Vertica | -- | `PROJECTION_USAGE` | -- |
| Impala | -- | -- | -- |
| StarRocks | -- | tablet metrics | -- |
| Doris | -- | tablet metrics | -- |
| MonetDB | -- | -- | -- |
| CrateDB | -- | shard-level | -- |
| TimescaleDB | 继承 PG | per-chunk | -- |
| QuestDB | -- | -- | -- |
| Exasol | -- | -- | -- |
| SAP HANA | `M_SERVICE_THREADS`, `M_EXPENSIVE_STATEMENTS` | `M_TABLE_PERSISTENCE_STATISTICS` | 是 |
| Informix | -- | sysptprof | -- |
| Firebird | Trace | `MON$TABLE_STATS` | -- |
| H2 | -- | -- | -- |
| HSQLDB | -- | -- | -- |
| Derby | -- | -- | -- |
| Amazon Athena | -- | -- | -- |
| Azure Synapse | DMV | -- | -- |
| Google Spanner | -- | -- | -- |
| Materialize | -- | -- | -- |
| RisingWave | -- | -- | -- |
| InfluxDB (SQL) | -- | -- | -- |
| DatabendDB | -- | -- | -- |
| Yellowbrick | -- | -- | -- |
| Firebolt | -- | -- | -- |

> 真正提供等待时间直方图的引擎极少：Oracle `V$EVENT_HISTOGRAM`、SQL Server XEvent + `sys.dm_io_virtual_file_stats`（带 `io_stall` 桶）、Teradata ResUsage、MySQL performance_schema 的 `_HISTOGRAM` 表是工业级实现。

## 引擎深度解析

### PostgreSQL：从 pg_stat_statements 到 pg_stat_io

PostgreSQL 的 I/O 监控体系分为四层：

**第一层 `pg_stat_database`**：库级累计计数：

```sql
SELECT datname, blks_read, blks_hit,
       round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS hit_ratio,
       temp_files, temp_bytes
FROM   pg_stat_database
WHERE  datname = current_database();
```

`blks_read` 是物理读（缓冲池未命中），`blks_hit` 是逻辑读中命中部分。**注意**：`blks_hit + blks_read` 才约等于总逻辑读。

**第二层 `pg_statio_user_tables` / `pg_statio_user_indexes`**：表/索引级 I/O。每张表有 `heap_blks_read`、`heap_blks_hit`、`idx_blks_read`、`idx_blks_hit`、`toast_blks_*`：

```sql
SELECT relname, heap_blks_read, heap_blks_hit,
       idx_blks_read, idx_blks_hit
FROM   pg_statio_user_tables
ORDER  BY heap_blks_read DESC
LIMIT  10;
```

**第三层 `pg_stat_statements` 扩展**：单 SQL 累计 I/O：

```sql
SELECT queryid, calls, total_exec_time,
       shared_blks_hit, shared_blks_read,
       shared_blks_dirtied, shared_blks_written,
       temp_blks_read, temp_blks_written,
       blk_read_time, blk_write_time
FROM   pg_stat_statements
ORDER  BY shared_blks_read DESC
LIMIT  20;
```

字段含义：

- `shared_blks_hit`：缓冲池命中的块数（逻辑读 - 物理读）
- `shared_blks_read`：物理读的块数
- `shared_blks_dirtied`：本次执行将多少干净块改为脏块
- `shared_blks_written`：执行过程中同步写出的块数（罕见，通常由 bgwriter 完成）
- `temp_blks_read/written`：排序、哈希溢出到磁盘的临时块
- `blk_read_time/write_time`：仅当 `track_io_timing = on` 才填充

**第四层 `EXPLAIN (ANALYZE, BUFFERS)`**：单次执行的精确 I/O：

```sql
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT * FROM orders WHERE customer_id = 12345;

-- Output 节选:
--   Buffers: shared hit=42 read=8 dirtied=1
--   I/O Timings: read=2.103
```

PostgreSQL 16 引入 **`pg_stat_io`** 视图，按 backend type × object × context 分桶：

```sql
SELECT backend_type, object, context,
       reads, writes, extends, hits, evictions
FROM   pg_stat_io
WHERE  reads > 0;
```

它解决了一个长期痛点：不再需要 hack 才能区分 autovacuum、bgwriter、客户端 backend 各自产生了多少 I/O。

### Oracle：consistent gets 与 physical reads 的精确语义

Oracle 的 I/O 计数器以 **统计量名（statistic name）** 形式暴露在 `V$SYSSTAT`（实例累计）和 `V$SESSTAT`（会话级）中。最重要的几个：

| 统计名 | 含义 |
|--------|------|
| `session logical reads` | 总逻辑读 = `db block gets` + `consistent gets` |
| `db block gets` | 当前模式（current mode）读，常见于 DML |
| `consistent gets` | 一致性读（CR），Oracle 多版本读核心 |
| `physical reads` | 从磁盘（或 ASM/exadata cell）读取的块 |
| `physical reads cache` | 进入 buffer cache 的物理读 |
| `physical reads direct` | 绕过 buffer cache 的直接路径读（大表全扫描） |
| `physical writes` | bgwriter / DBWR 写出脏块 |
| `redo size` | 生成的 redo 字节数 |

查看当前会话 I/O：

```sql
SELECT sn.name, ms.value
FROM   v$mystat ms JOIN v$statname sn ON sn.statistic# = ms.statistic#
WHERE  sn.name IN ('session logical reads',
                   'db block gets',
                   'consistent gets',
                   'physical reads',
                   'physical reads direct',
                   'redo size');
```

**单 SQL 维度**：

```sql
SELECT sql_id, executions, buffer_gets, disk_reads,
       buffer_gets/decode(executions,0,1,executions) AS gets_per_exec,
       disk_reads/decode(executions,0,1,executions)  AS reads_per_exec
FROM   v$sqlstats
ORDER  BY buffer_gets DESC FETCH FIRST 20 ROWS ONLY;
```

Oracle 的 **Active Session History (ASH)** 每秒采样一次活动会话，记录其 SQL、wait event、当前对象。`V$ACTIVE_SESSION_HISTORY` 是排查瞬时 I/O 风暴最强工具：

```sql
SELECT event, wait_class, COUNT(*)
FROM   v$active_session_history
WHERE  sample_time > sysdate - interval '10' minute
   AND wait_class = 'User I/O'
GROUP  BY event, wait_class
ORDER  BY COUNT(*) DESC;
```

### SQL Server：STATISTICS IO 与文件级 DMV

SQL Server 的入门级 I/O 工具是 `SET STATISTICS IO ON`，它会把每条语句的 I/O 报告打印到消息窗口：

```sql
SET STATISTICS IO ON;
SELECT * FROM Sales.SalesOrderDetail WHERE ProductID = 776;

-- Table 'SalesOrderDetail'. Scan count 1, logical reads 1240,
-- physical reads 4, page server reads 0, read-ahead reads 1196,
-- lob logical reads 0, lob physical reads 0, lob read-ahead reads 0.
```

字段含义：

- `logical reads`：从 buffer pool 读取的 8KB 页数
- `physical reads`：从磁盘读取的页数（同步）
- `read-ahead reads`：预读机制读取的页数（异步，提前进入缓存）
- `lob logical/physical reads`：LOB 页的统计

**文件级 I/O**（`sys.dm_io_virtual_file_stats`）记录每个数据库文件自启动以来的累计 I/O 与 stall：

```sql
SELECT DB_NAME(database_id) AS db,
       file_id,
       num_of_reads, num_of_bytes_read, io_stall_read_ms,
       num_of_writes, num_of_bytes_written, io_stall_write_ms,
       io_stall_read_ms / nullif(num_of_reads, 0) AS avg_read_stall_ms
FROM   sys.dm_io_virtual_file_stats(NULL, NULL)
ORDER  BY io_stall_read_ms DESC;
```

`io_stall_*_ms` 是 SQL Server 等待存储响应的总时间，是判断存储瓶颈最直接的指标。

**SQL 维度累计**：`sys.dm_exec_query_stats` 提供 `total_logical_reads`、`total_physical_reads`、`total_logical_writes`：

```sql
SELECT TOP 20
       qs.execution_count,
       qs.total_logical_reads,
       qs.total_physical_reads,
       qs.total_logical_reads / qs.execution_count AS avg_logical,
       SUBSTRING(st.text, qs.statement_start_offset/2 + 1,
         (CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
          ELSE qs.statement_end_offset END - qs.statement_start_offset)/2 + 1) AS sql_text
FROM   sys.dm_exec_query_stats qs
CROSS  APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER  BY qs.total_logical_reads DESC;
```

### MySQL / MariaDB：performance_schema 与 InnoDB 计数

MySQL 5.5 起的 `performance_schema` 提供文件级 I/O 视图：

```sql
SELECT file_name, event_name,
       count_read, sum_number_of_bytes_read,
       count_write, sum_number_of_bytes_write,
       sum_timer_read/1e9 AS read_ms,
       sum_timer_write/1e9 AS write_ms
FROM   performance_schema.file_summary_by_instance
ORDER  BY sum_timer_wait DESC
LIMIT  20;
```

`event_name` 包括 `wait/io/file/innodb/innodb_data_file`、`wait/io/file/sql/binlog` 等。

**InnoDB 缓冲池命中率**：经典公式

```sql
SELECT
  ROUND(100 * (1 -
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status
     WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status
     WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
  ), 4) AS innodb_buffer_pool_hit_ratio_pct;
```

这里 `Innodb_buffer_pool_read_requests` 是 **逻辑读请求数**，`Innodb_buffer_pool_reads` 是 **真正落盘的物理读次数**。

**`SHOW ENGINE INNODB STATUS`** 输出更详细的 BUFFER POOL AND MEMORY 段：

```
Buffer pool size   524288
Buffer pool size, bytes 8589934592
Free buffers       12345
Database pages     510000
Old database pages 188123
Modified db pages  942
...
Pages read 1234567, created 23456, written 789012
0.00 reads/s, 0.00 creates/s, 0.00 writes/s
Buffer pool hit rate 998 / 1000, young-making rate 0 / 1000 not 0 / 1000
```

**表/索引级 I/O**：

```sql
SELECT object_schema, object_name,
       count_read, count_write, count_fetch,
       sum_timer_wait/1e9 AS total_ms
FROM   performance_schema.table_io_waits_summary_by_table
ORDER  BY sum_timer_wait DESC LIMIT 20;
```

### DB2：MON_GET 表函数家族

DB2 的监控接口完全由 **MON_GET_** 表函数构成，比传统 snapshot 方式更轻量、更安全。核心函数：

```sql
-- 缓冲池命中率
SELECT bp_name,
       pool_data_l_reads,         -- 数据逻辑读
       pool_data_p_reads,         -- 数据物理读
       100 * (1 - DECIMAL(pool_data_p_reads,15,2)/
                   NULLIF(pool_data_l_reads,0)) AS data_hit_ratio
FROM   TABLE(MON_GET_BUFFERPOOL('', -2));

-- 表空间 I/O
SELECT tbsp_name, tbsp_type,
       pool_data_p_reads, pool_index_p_reads,
       direct_reads, direct_writes
FROM   TABLE(MON_GET_TABLESPACE('', -2));

-- 单 SQL
SELECT stmt_text, num_executions,
       rows_read, rows_returned,
       total_cpu_time, pool_data_l_reads, pool_data_p_reads
FROM   TABLE(MON_GET_PKG_CACHE_STMT(NULL, NULL, NULL, -2))
ORDER  BY pool_data_p_reads DESC FETCH FIRST 20 ROWS ONLY;
```

### ClickHouse：ProfileEvents 的洪流

ClickHouse 把所有计数器都放进 **ProfileEvents** 体系，全局视图是 `system.events`，按秒采样的视图是 `system.metric_log`，单查询则在 `system.query_log` 的 `ProfileEvents` Map 列里：

```sql
SELECT event, value
FROM   system.events
WHERE  event LIKE '%Read%' OR event LIKE '%Write%'
ORDER  BY value DESC
LIMIT  20;
```

关键 I/O 事件：

- `ReadBufferFromFileDescriptorRead` / `ReadBufferFromFileDescriptorReadBytes`：直接 read() 调用
- `OSReadBytes` / `OSReadChars`：内核计数（来自 `/proc/self/io`）
- `DiskReadElapsedMicroseconds`
- `MarkCacheHits` / `MarkCacheMisses`：稀疏索引 mark cache
- `UncompressedCacheHits` / `UncompressedCacheMisses`
- `S3ReadRequestsCount` / `S3ReadBytes`（对象存储）
- `MergeTreeDataWriterRows` / `MergeTreeDataWriterCompressedBytes`

单查询级 I/O：

```sql
SELECT query,
       ProfileEvents['ReadBufferFromFileDescriptorReadBytes'] AS bytes_read_local,
       ProfileEvents['S3ReadBytes']                            AS bytes_read_s3,
       ProfileEvents['OSCPUVirtualTimeMicroseconds']           AS cpu_us
FROM   system.query_log
WHERE  type = 'QueryFinish' AND event_time > now() - 600
ORDER  BY bytes_read_local DESC LIMIT 20;
```

ClickHouse 的 ProfileEvents 数量超过 600 个，是所有数据库中最丰富的——但也意味着你需要文档配合才能解读。

### Snowflake：bytes scanned 与 local/remote disk

Snowflake 是云原生分层存储（remote 对象存储 + local SSD 缓存 + warehouse 内存缓存），传统 "physical reads vs logical reads" 概念被替换为 **bytes scanned / partitions scanned / local disk IO / remote disk IO**：

```sql
SELECT query_id,
       bytes_scanned,
       percentage_scanned_from_cache,   -- warehouse-level result cache hit
       partitions_scanned,
       partitions_total,
       bytes_spilled_to_local_storage,
       bytes_spilled_to_remote_storage,
       execution_time
FROM   snowflake.account_usage.query_history
WHERE  start_time > dateadd(hour, -1, current_timestamp)
ORDER  BY bytes_scanned DESC
LIMIT  20;
```

`percentage_scanned_from_cache` 是 warehouse SSD 缓存命中比例。`bytes_spilled_to_local_storage` 与 `bytes_spilled_to_remote_storage` 是排序/聚合溢出指标。Query Profile UI 会进一步显示每个算子的 "Local Disk IO" 与 "Remote Disk IO"。

### BigQuery：bytes_billed 与 INFORMATION_SCHEMA

BigQuery 的 I/O 是按 **bytes billed**（计费字节数）计量的——这本质上等于扫描的列存数据量。监控查询：

```sql
SELECT job_id, user_email,
       total_bytes_processed,
       total_bytes_billed,
       total_slot_ms,
       cache_hit
FROM   `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE  creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
ORDER  BY total_bytes_billed DESC
LIMIT  20;
```

执行细节中的 `shuffle output bytes` 和 `shuffle output bytes spilled` 是定位 shuffle 瓶颈的关键。

### Teradata：DBQL IOCount

Teradata 的 Database Query Log (DBQL) 记录了每条 SQL 的 `TotalIOCount`、`AMPCPUTime`、`SpoolUsage`：

```sql
SELECT QueryID, UserName,
       TotalIOCount, AMPCPUTime, SpoolUsage,
       NumOfActiveAMPs
FROM   DBC.DBQLogTbl
WHERE  StartTime > CURRENT_TIMESTAMP - INTERVAL '1' HOUR
ORDER  BY TotalIOCount DESC
SAMPLE 20;
```

ResUsage SPMA/SVPR 视图则按节点/AMP 提供秒级 I/O 直方图。

### Trino / Presto：query stats per task

Trino 不维护缓冲池命中率（无传统 buffer pool），但每个查询和任务都有详细 stats：

```sql
SELECT query_id, state,
       total_bytes, total_rows,
       physical_input_bytes, physical_input_rows,
       processed_input_bytes,
       output_bytes, output_rows,
       elapsed_time
FROM   system.runtime.queries
ORDER  BY physical_input_bytes DESC
LIMIT  20;
```

`physical_input_bytes` 是从 connector（HDFS、S3、Hive）真正读取的字节数；`processed_input_bytes` 是经过 predicate pushdown 后实际进入算子的数据量。

## PostgreSQL shared_blks_hit vs shared_blks_read 深度剖析

`pg_stat_statements` 中的 `shared_blks_hit` 与 `shared_blks_read` 是 PostgreSQL 调优的核心指标，但它们的语义存在多个容易踩坑的细节。

**1. 单位是 8KB 的 buffer block，不是行**

```sql
SELECT shared_blks_hit, shared_blks_read,
       (shared_blks_hit + shared_blks_read) * 8 / 1024 AS total_mb
FROM   pg_stat_statements WHERE queryid = ...;
```

要换算成 MB 必须乘以 `block_size` (默认 8192)。对于编译时改了 `--with-blocksize=16` 的实例，需要相应调整。

**2. read 不等于物理 I/O**

`shared_blks_read` 仅表示"未在 PostgreSQL shared buffers 中找到"。该块完全可能存在于操作系统 page cache 里，因此 read 的真实磁盘代价取决于 OS 缓存。要判断真正的物理 I/O，必须开启 `track_io_timing = on` 然后看 `blk_read_time`：

```sql
ALTER SYSTEM SET track_io_timing = on;
SELECT pg_reload_conf();
```

**默认是 off**——这是 PostgreSQL 长期被批评的一点。原因是早期 Linux 上 `gettimeofday` 较慢，开启会有 1-3% 性能损耗；但现代内核（vDSO 加速）几乎无开销，建议生产环境开启。

**3. hit + read 不一定等于实际逻辑读次数**

并行查询会把 buffer access 计数到 leader 的统计中，但子进程的 access 是否聚合取决于 PG 版本（≥13 已正确聚合）。

**4. 计算"伪命中率"**

```sql
SELECT queryid,
       shared_blks_hit,
       shared_blks_read,
       round(100.0 * shared_blks_hit /
             nullif(shared_blks_hit + shared_blks_read, 0), 2) AS hit_pct
FROM   pg_stat_statements
WHERE  shared_blks_hit + shared_blks_read > 1000
ORDER  BY shared_blks_read DESC
LIMIT  20;
```

低于 95% 的查询是 "shared_buffers 大小不足" 或 "首次冷查询" 的强信号。

**5. dirtied 与 written 的区别**

- `shared_blks_dirtied`：本次执行**首次将一个干净块改脏**的次数。重复修改同一块只算一次。
- `shared_blks_written`：执行过程中**该 backend 同步**写出的块数。这通常很低——绝大多数写由后台 bgwriter/checkpointer 完成。如果 `shared_blks_written` 持续偏高，意味着 bgwriter 跟不上，需要调 `bgwriter_lru_maxpages`、`bgwriter_delay`。

## Oracle 缓冲池命中率公式

Oracle 文档给出的缓冲池命中率（buffer cache hit ratio）公式：

```
hit ratio = 1 - (
  (physical reads cache - physical reads cache prefetch)
  /
  (consistent gets from cache + db block gets from cache)
)
```

简化形式：

```sql
SELECT round(100 * (
    1 - (sum(decode(name,'physical reads cache', value, 0)) -
         sum(decode(name,'physical reads cache prefetch', value, 0))) /
        (sum(decode(name,'consistent gets from cache', value, 0)) +
         sum(decode(name,'db block gets from cache', value, 0)))
  ), 2) AS buffer_cache_hit_ratio_pct
FROM   v$sysstat
WHERE  name IN ('physical reads cache',
                'physical reads cache prefetch',
                'consistent gets from cache',
                'db block gets from cache');
```

**为什么要减 prefetch**：Oracle 预读（read ahead）会在用户实际请求之前把块装入 cache，这部分不应被算作"未命中"。

**陷阱**：缓冲池命中率不是越高越好。一条全表扫描数十亿行的 SQL 会把命中率刷到 99.99%，但根本问题是它压根不该全表扫描。Oracle 性能大师 Cary Millsap 多年前就指出："Hit ratio is the most useless metric you'll ever monitor"——它必须与 SQL 执行计划、segment-level 统计配合使用，不能孤立解读。

实战中应同时看：

- `V$BUFFER_POOL_STATISTICS`：分缓冲池（KEEP / RECYCLE / DEFAULT）的命中率
- `V$SEGMENT_STATISTICS`：单对象的物理读、逻辑读、buffer busy waits
- `V$SQLSTATS`：单 SQL 的 `disk_reads / executions`

## 关键发现 / 关键发现

1. **没有 SQL 标准**：49 个引擎中没有任何两个家族使用相同的 I/O 监控接口。Oracle 用 V$ 视图、PostgreSQL 用 pg_stat_*、SQL Server 用 sys.dm_*、DB2 用 MON_GET_*、ClickHouse 用 system.events——可观测性工具必须为每种引擎单独开发采集器。

2. **物理读 vs 逻辑读区分仅存在于传统 buffer pool 引擎**：约 28 个引擎（PostgreSQL、Oracle、SQL Server、MySQL、DB2、SAP HANA、Vertica、Teradata、SingleStore、OceanBase 等）维护明确的 logical/physical 双指标；MPP 与对象存储型仓库（Snowflake、BigQuery、Trino、Spark、Athena）只暴露 "bytes scanned"，因为它们没有传统意义上的共享缓冲池。

3. **PostgreSQL track_io_timing 默认 off 是历史遗留陷阱**：不开启则 `blk_read_time` 全为 0，`EXPLAIN (ANALYZE, BUFFERS, TIMING)` 也无法显示真实 I/O 耗时。生产环境强烈建议 `ALTER SYSTEM SET track_io_timing = on`。

4. **Oracle 的术语精确度领先**：`session logical reads = consistent gets + db block gets`、`physical reads cache vs physical reads direct` 的语义在所有商业数据库中最为完备，配合 ASH/AWR 形成了行业标杆。其他引擎几十年来都在追赶这套体系。

5. **SQL Server 的 io_stall 是被低估的金指标**：`sys.dm_io_virtual_file_stats` 的 `io_stall_read_ms / io_stall_write_ms` 直接告诉你存储响应有多慢，比 IOPS 或吞吐量更能反映用户感受到的延迟。

6. **MySQL 的 InnoDB hit rate 公式简单但易误用**：`1 - reads/read_requests` 是全局累计，无法定位"哪条 SQL 击穿了缓冲池"；必须结合 `events_statements_summary_by_digest` 才能还原到 SQL 维度。

7. **嵌入式数据库几乎全无 I/O 插桩**：SQLite、DuckDB、H2、HSQLDB、Derby 都不维护缓冲池命中率视图。DuckDB 作为 OLAP 嵌入式新秀，监控完全依赖 `EXPLAIN ANALYZE` 输出。

8. **ClickHouse ProfileEvents 是数量冠军**：超过 600 个内置事件，覆盖磁盘、网络、压缩、缓存、合并、复制各个层面，是开源数据库中 I/O 可观测性最丰富的。

9. **Snowflake / BigQuery 重新定义了 I/O 计费**：bytes scanned、bytes billed、partitions pruned 取代了传统 hit ratio，因为存储和计算解耦后，"是否命中本地 SSD" 只是成本结构的一部分，更重要的是 partition pruning 是否生效。

10. **等待时间直方图非常稀缺**：真正提供桶化等待时间分布的只有 Oracle `V$EVENT_HISTOGRAM`、SQL Server 扩展事件、Teradata ResUsage 与 MySQL `events_waits_summary_by_account_by_event_name`（含 BUCKET 列）。其余引擎只有累计计数，无法看 P99 尾延迟。

11. **NUMA 感知 I/O 是企业级特性**：Oracle、SQL Server (soft-NUMA)、DB2、SAP HANA、Teradata、SingleStore、OceanBase 提供 NUMA-aware 缓冲池或线程绑定；开源世界中只有 ClickHouse 部分支持。

12. **缓冲池命中率不是灵丹妙药**：高命中率可能掩盖低效全表扫描；低命中率可能只是冷启动。正确的姿势是 SQL-level 物理读 + 等待事件 + 执行计划三位一体诊断，而不是盯着全局命中率调参数。
