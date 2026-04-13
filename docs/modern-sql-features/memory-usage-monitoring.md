# 内存使用监控 (Memory Usage Monitoring)

一条失控的 GROUP BY 可以让 200GB 内存的数据库节点在 30 秒内 OOM 重启——多租户工作负载下，每查询、每会话的内存追踪不是性能优化的锦上添花，而是稳定性的生命线。

## 没有 SQL 标准：内部仪表化

ISO/IEC 9075（SQL:2023 及之前的所有版本）从未定义任何关于内存监控的标准语法或视图。原因很简单：内存是实现细节，标准只关心查询的逻辑语义。但所有生产级数据库都必须回答以下问题：

1. 当前哪个会话／查询正在消耗多少内存？
2. 单个查询能用的内存上限是多少？超出后行为如何（spill / abort / OOM）？
3. 哈希、排序、聚合等算子各自消耗了多少内存？
4. 全局内存使用如何分类（buffer pool / 查询工作区 / 元数据缓存 / 计划缓存 / JIT）？
5. 内存压力下是否有可观测的事件流（spill 到磁盘、grant 等待、内存压力 wait event）？

不同引擎选择了截然不同的答案。PostgreSQL 走的是"按算子静态配额"路线（`work_mem`），Oracle 走的是"全局自动管理"路线（`PGA_AGGREGATE_TARGET`），SQL Server 走的是"内存授权 + grant queue"路线（memory grants），ClickHouse 走的是"分层硬限 + SIGKILL"路线，Snowflake 干脆把内存隐藏在 warehouse 大小后面。本文系统对比 49 个引擎在内存监控与限额上的能力。

## 支持矩阵

### 1. 会话级 / 用户级内存限制

| 引擎 | 会话级限额 | 用户级限额 | 资源组限额 | 设置方式 |
|------|-----------|-----------|-----------|---------|
| PostgreSQL | `work_mem` (per op) | `ALTER USER ... SET work_mem` | -- | GUC |
| MySQL | `max_heap_table_size`, `tmp_table_size` | -- | resource_group (CPU only) | session var |
| MariaDB | `max_session_mem_used` (10.5+) | -- | -- | session var |
| SQLite | `PRAGMA hard_heap_limit` | -- | -- | per-connection |
| Oracle | `PGA_AGGREGATE_LIMIT` (实例) | profile `PRIVATE_SGA` | Resource Manager | profile / RM |
| SQL Server | -- | -- | Resource Governor `MAX_MEMORY_PERCENT` | RG pool |
| DB2 | `APPL_MEMORY` | -- | WLM service class | WLM |
| Snowflake | -- | -- | warehouse size | warehouse |
| BigQuery | -- | -- | reservation slots | slots |
| Redshift | `query_group` `wlm_query_slot_count` | -- | WLM queue | WLM |
| DuckDB | `SET memory_limit` | -- | -- | per-connection |
| ClickHouse | `max_memory_usage` | `max_memory_usage_for_user` | -- | profile / setting |
| Trino | `query.max-memory-per-node` | -- | resource group | properties |
| Presto | `query.max-memory-per-node` | -- | resource group | properties |
| Spark SQL | `spark.executor.memory` | -- | dynamic allocation | conf |
| Hive | `hive.tez.container.size` | -- | YARN queue | YARN |
| Flink SQL | `taskmanager.memory.process.size` | -- | slot sharing | conf |
| Databricks | cluster size | -- | cluster policy | UI |
| Teradata | -- | profile `SPOOL` (磁盘工作区) | TASM | TASM |
| Greenplum | `statement_mem` | role default | `gp_resource_group_memory_limit` | resource group |
| CockroachDB | `--max-sql-memory` (节点) | -- | -- | flag |
| TiDB | `tidb_mem_quota_query` | -- | resource group (7.1+) | session var |
| OceanBase | `ob_sql_work_area_percentage` | -- | resource group | session var |
| YugabyteDB | `--memory_limit_hard_bytes` | -- | -- | tserver flag |
| SingleStore | `maximum_memory` | -- | resource pool | resource pool |
| Vertica | `MAXMEMORYSIZE` resource pool | per user pool | resource pool | resource pool |
| Impala | `MEM_LIMIT` query option | per pool | admission control | impalad flag |
| StarRocks | `exec_mem_limit` | resource group | resource group (2.5+) | session var |
| Doris | `exec_mem_limit` | -- | workload group (2.0+) | session var |
| MonetDB | -- | -- | -- | -- |
| CrateDB | `indices.breaker.query.limit` | -- | -- | cluster setting |
| TimescaleDB | 继承 PG | 继承 PG | -- | GUC |
| QuestDB | `cairo.sql.copy.buffer.size` 等 | -- | -- | server.conf |
| Exasol | `QUERY_TIMEOUT`, 用户 RAM 隐含 | priority group | priority group | priority group |
| SAP HANA | `statement_memory_limit` | per user | workload class | workload class |
| Informix | `DS_TOTAL_MEMORY` | -- | -- | onconfig |
| Firebird | `DefaultDbCachePages` (per attachment) | -- | -- | firebird.conf |
| H2 | `MAX_MEMORY_ROWS` | -- | -- | session |
| HSQLDB | `SET FILES NIO SIZE` | -- | -- | session |
| Derby | `derby.storage.pageCacheSize` | -- | -- | property |
| Amazon Athena | -- | -- | workgroup | workgroup |
| Azure Synapse | -- | -- | workload group | workload group |
| Google Spanner | -- | -- | -- | -- |
| Materialize | `cluster size` | -- | cluster | cluster |
| RisingWave | compute node memory | -- | -- | conf |
| InfluxDB | `query-memory-bytes` | -- | -- | conf |
| DatabendDB | `max_memory_usage` | -- | warehouse | session |
| Yellowbrick | resource pool | per user | resource pool | resource pool |
| Firebolt | engine size | -- | engine | engine |

### 2. 单查询内存限额与超限行为

| 引擎 | 参数 | 默认值 | 超限行为 |
|------|-----|--------|---------|
| PostgreSQL | `work_mem` (per op!) | 4MB | spill to temp file |
| MySQL | `tmp_table_size` | 16MB | 转 InnoDB on-disk temp |
| MariaDB | `max_session_mem_used` | 0 (off) | abort 查询 |
| SQLite | `PRAGMA hard_heap_limit` | 0 | SQLITE_NOMEM error |
| Oracle | `_pga_max_size` (隐藏) | auto | 5x average → spill |
| SQL Server | memory grant | 自动计算 | spill or RESOURCE_SEMAPHORE wait |
| DB2 | `SHEAPTHRES_SHR` | auto | spill |
| Snowflake | -- | warehouse 内 | spill to local SSD → remote |
| BigQuery | -- | slot 内 | resources exceeded error |
| Redshift | `query_group` slot | -- | spill to disk |
| DuckDB | `memory_limit` | 80% RAM | OutOfMemoryException |
| ClickHouse | `max_memory_usage` | **10GB** | MEMORY_LIMIT_EXCEEDED |
| Trino | `query.max-memory-per-node` | JVM 比例 | EXCEEDED_LOCAL_MEMORY_LIMIT |
| Presto | `query.max-memory-per-node` | -- | 同 Trino |
| Spark SQL | `spark.executor.memory` | -- | OOM → executor 重启 |
| Hive (Tez) | `hive.tez.container.size` | -- | container kill |
| Flink SQL | `taskmanager.memory.managed.size` | 0.4 | spill / backpressure |
| Databricks | -- | cluster | spill / OOM |
| Teradata | spool space | profile | NO MORE SPOOL SPACE |
| Greenplum | `statement_mem` | 125MB | OOM 或 spill |
| CockroachDB | `sql.distsql.temp_storage.workmem` | 64MB | spill to local store |
| TiDB | `tidb_mem_quota_query` | 1GB | log / cancel / disk spill |
| OceanBase | `ob_sql_work_area_percentage` | 5% | OB_ALLOCATE_MEMORY_FAILED |
| YugabyteDB | 继承 PG `work_mem` | 4MB | spill |
| SingleStore | `query_memory_limit` | -- | abort |
| Vertica | resource pool `MAXMEMORYSIZE` | -- | abort 或 queue |
| Impala | `MEM_LIMIT` | auto | spill 或 abort |
| StarRocks | `exec_mem_limit` | 2GB | MEM_LIMIT_EXCEEDED |
| Doris | `exec_mem_limit` | 2GB | MEM_LIMIT_EXCEEDED |
| MonetDB | -- | -- | malloc 失败 |
| CrateDB | circuit breaker | 60% heap | CircuitBreakingException |
| TimescaleDB | 继承 PG | 4MB | spill |
| QuestDB | -- | -- | -- |
| Exasol | `QUERY_TIMEOUT` 间接 | -- | abort |
| SAP HANA | `statement_memory_limit` | 0 | abort |
| Informix | `DS_TOTAL_MEMORY` 共享 | -- | -454 错误 |
| Firebird | sort buffer (per sort) | 1MB | spill |
| H2 | `MAX_MEMORY_ROWS` | 40000 | spill to temp |
| HSQLDB | -- | -- | OOM |
| Derby | sortBufferMax | -- | spill |
| Amazon Athena | -- | -- | resource exhausted |
| Azure Synapse | workload group | -- | queue 或 abort |
| Google Spanner | -- | -- | resource exhausted |
| Materialize | -- | -- | OOM dataflow restart |
| RisingWave | -- | -- | spill (cloud) / OOM (local) |
| InfluxDB | `query-memory-bytes` | 0 | error |
| DatabendDB | `max_memory_usage` | -- | error |
| Yellowbrick | per pool | -- | spill / queue |
| Firebolt | engine | -- | spill |

> 关键观察：PostgreSQL 的 `work_mem` 是**每算子每后端**而非每查询——这是历史上最容易踩的一个坑，详见后文。

### 3. 算子级内存限额（Hash / Sort / Aggregate）

| 引擎 | Hash 内存 | Sort 内存 | 聚合内存 | 备注 |
|------|----------|----------|---------|------|
| PostgreSQL | `work_mem * hash_mem_multiplier` (13+) | `work_mem` | `work_mem` | 13+ 引入 `hash_mem_multiplier` |
| MySQL | `join_buffer_size` | `sort_buffer_size` | `tmp_table_size` | per-join, per-sort |
| MariaDB | 同 MySQL | 同 MySQL | 同 MySQL | -- |
| Oracle | `_smm_max_size` | 同 hash | 同 hash | PGA 自动分配 |
| SQL Server | grant 内分配 | grant 内分配 | grant 内分配 | 一次 grant 覆盖所有 |
| DB2 | `SORTHEAP` | `SORTHEAP` | `SORTHEAP` | 共享 |
| Snowflake | warehouse | warehouse | warehouse | 黑盒 |
| BigQuery | slot | slot | slot | 黑盒 |
| Redshift | WLM slot | WLM slot | WLM slot | -- |
| DuckDB | 全局 budget | 全局 budget | 全局 budget | streaming hash |
| ClickHouse | `max_bytes_in_join` | `max_bytes_before_external_sort` | `max_bytes_before_external_group_by` | 各算子独立 |
| Trino | `query.max-memory-per-node` | 同左 | 同左 | 共享池 |
| Spark SQL | `spark.sql.shuffle.partitions` 间接 | `spark.sql.windowExec.buffer.spill.threshold` | -- | -- |
| Greenplum | `statement_mem` 内 | 同 | 同 | 共享 |
| CockroachDB | `workmem` | `workmem` | `workmem` | per processor |
| TiDB | `tidb_mem_quota_query` 共享 | -- | -- | -- |
| Vertica | resource pool grant | 同 | 同 | -- |
| Impala | spillable buffer pool | 同 | 同 | reservation 模型 |
| StarRocks | `exec_mem_limit` 共享 | 同 | 同 | -- |
| Doris | `exec_mem_limit` 共享 | 同 | 同 | -- |
| SAP HANA | `statement_memory_limit` 共享 | 同 | 同 | -- |

### 4. 全局内存追踪视图

| 引擎 | 主视图 | 内容 | 版本 |
|------|--------|------|------|
| PostgreSQL | `pg_backend_memory_contexts` | 当前会话内存上下文树 | 14+ |
| PostgreSQL | `pg_stat_activity` | 无内存列（自报缺失）| -- |
| PostgreSQL | `pg_shmem_allocations` | 共享内存分段 | 13+ |
| MySQL | `performance_schema.memory_summary_global_by_event_name` | 按事件聚合 | 5.7.2+ |
| MySQL | `sys.memory_global_total` | 总量 | 5.7+ |
| MariaDB | `information_schema.MEMORY_TABLE` | -- | 10.5+ |
| Oracle | `V$SGASTAT` | SGA 子池 | 全部 |
| Oracle | `V$PGASTAT` | PGA 总览 | 9i+ |
| Oracle | `V$PROCESS_MEMORY` | 每进程分类 | 10g+ |
| Oracle | `V$MEMORY_DYNAMIC_COMPONENTS` | AMM 组件 | 11g+ |
| SQL Server | `sys.dm_os_memory_clerks` | 内存 clerk | 2005+ |
| SQL Server | `sys.dm_os_memory_pools` | 缓存池 | 2005+ |
| SQL Server | `sys.dm_exec_query_memory_grants` | 当前 grant | 2005+ |
| SQL Server | `sys.dm_os_sys_memory` | OS 视角 | 2008+ |
| DB2 | `MON_GET_MEMORY_POOL` | 内存池 | 9.7+ |
| DB2 | `MON_GET_MEMORY_SET` | 内存集 | 9.7+ |
| DB2 | `ADMIN_GET_DBP_MEM_USAGE` | 实例总量 | -- |
| Snowflake | Query Profile UI | peak memory | GA |
| BigQuery | INFORMATION_SCHEMA.JOBS | 无内存列 | -- |
| Redshift | `STV_QUERY_METRICS` | query_temp_blocks_to_disk | -- |
| DuckDB | `pragma_database_size()`, `duckdb_memory()` | 内存使用 | 0.9+ |
| ClickHouse | `system.processes` | memory_usage | 全部 |
| ClickHouse | `system.metric_log` | 历史指标 | 全部 |
| ClickHouse | `system.asynchronous_metrics` | OS 指标 | 全部 |
| Trino | `system.runtime.queries` | memory 字段 | 全部 |
| Spark | Spark UI / metrics | executor memory | 全部 |
| Greenplum | `gp_toolkit.gp_resgroup_status` | resource group | -- |
| CockroachDB | `crdb_internal.node_memory_monitors` | monitor 树 | 21.1+ |
| TiDB | `INFORMATION_SCHEMA.PROCESSLIST` | MEM | 4.0+ |
| TiDB | `INFORMATION_SCHEMA.CLUSTER_MEMORY_USAGE` | 集群 | 5.4+ |
| OceanBase | `GV$OB_MEMORY` | 租户 | 4.0+ |
| Vertica | `RESOURCE_POOL_STATUS` | -- | -- |
| Impala | `/memz` web UI | tcmalloc 详细 | 全部 |
| StarRocks | `INFORMATION_SCHEMA.be_memory_usage` | -- | 2.5+ |
| Doris | `INFORMATION_SCHEMA.backends` | 内存 | -- |
| SAP HANA | `M_SERVICE_MEMORY` | 服务 | -- |
| SAP HANA | `M_HEAP_MEMORY` | heap | -- |

### 5. 每连接 / 每查询内存视图

| 引擎 | 视图 | 字段 |
|------|------|------|
| PostgreSQL | `pg_backend_memory_contexts` | name, used_bytes, free_bytes |
| MySQL | `performance_schema.memory_summary_by_thread_by_event_name` | CURRENT_BYTES_USED |
| Oracle | `V$PROCESS_MEMORY` | CATEGORY, ALLOCATED, USED, MAX_ALLOCATED |
| SQL Server | `sys.dm_exec_query_memory_grants` | requested_memory_kb, granted_memory_kb, used_memory_kb |
| DB2 | `MON_GET_CONNECTION` | APPLICATION_HANDLE 内存指标 |
| ClickHouse | `system.processes` | memory_usage, peak_memory_usage |
| Trino | `system.runtime.queries` | totalMemoryReservation, peakUserMemoryReservation |
| Greenplum | `session_state.session_level_memory_consumption` | -- |
| TiDB | `INFORMATION_SCHEMA.PROCESSLIST` | MEM (per session) |
| OceanBase | `GV$OB_PROCESSLIST` | mem_usage |
| StarRocks | `SHOW PROC '/current_queries'` | memory cost |
| Vertica | `SESSIONS` | memory_used_kb |
| Impala | `/queries` web UI | per-query memory |
| SAP HANA | `M_EXPENSIVE_STATEMENTS` | MEMORY_SIZE |

### 6. 临时文件 / Spill 追踪

| 引擎 | 视图 / 字段 | 触发条件 |
|------|------------|---------|
| PostgreSQL | `pg_stat_database.temp_files`, `temp_bytes` | work_mem 超限 |
| PostgreSQL | `log_temp_files` GUC | 写入日志 |
| MySQL | `performance_schema.events_statements_history.CREATED_TMP_DISK_TABLES` | tmp_table_size 超限 |
| Oracle | `V$SQL_WORKAREA`, `V$TEMPSEG_USAGE` | PGA 不足 |
| SQL Server | `sys.dm_exec_query_stats.total_spills` (2017+) | grant 不足 |
| DB2 | `MON_GET_CONNECTION.SORT_OVERFLOWS` | SORTHEAP 不足 |
| Greenplum | `gp_toolkit.gp_workfile_usage_per_query` | statement_mem 超限 |
| ClickHouse | `system.query_log.read_bytes` 隐含 | external_group_by/sort |
| Trino | `system.runtime.queries.spilledDataSize` | spill enabled |
| Spark | Spark UI "Spill (Memory/Disk)" | 内存不足 |
| CockroachDB | `crdb_internal.node_distsql_flows` | workmem 超限 |
| TiDB | `INFORMATION_SCHEMA.SLOW_QUERY.disk_max` | -- |
| Impala | per-query profile "SpilledPartitions" | reservation 不足 |
| Vertica | `EXECUTION_ENGINE_PROFILES` | -- |
| Snowflake | Query Profile "Bytes spilled to local/remote storage" | warehouse 内存不足 |
| Redshift | `STL_QUERY_METRICS.query_temp_blocks_to_disk` | -- |
| DuckDB | `duckdb_temporary_files()` | memory_limit 超限 |
| StarRocks | profile "SpillBytes" | exec_mem_limit |

### 7. OOM Killer / Abort 行为

| 引擎 | OOM 处理 | 副作用 |
|------|---------|--------|
| PostgreSQL | Linux OOM killer 杀 backend → postmaster 重启所有 | 全库连接断开 |
| PostgreSQL | `oom_score_adj` 可调 | 推荐 -1000 给 postmaster |
| MySQL | OOM killer 杀 mysqld | 实例重启 |
| Oracle | PGA spill / `PGA_AGGREGATE_LIMIT` 后断会话 | 不重启实例 |
| SQL Server | 内存压力 → grant queue 等待 | 不直接 abort |
| DB2 | `STMM` 自动调节，极少 OOM | -- |
| ClickHouse | **SIGKILL** 整个进程 | 服务重启，所有查询断 |
| ClickHouse | `max_memory_usage` 超限 → 抛异常 (软) | 单查询断 |
| Trino | coordinator 杀单查询 | 其他查询继续 |
| Spark | Executor OOM → driver 重新调度 | task 重试 |
| CockroachDB | go runtime panic → 节点重启 | 副本切换 |
| TiDB | `tidb_mem_oom_action` = LOG / CANCEL | 可控 |
| Greenplum | segment 进程死亡 → mirror 接管 | -- |
| Vertica | resource pool reject | queue |
| Impala | spillable buffer 用尽 → cancel query | 单查询 |
| YugabyteDB | tserver OOM → tablet 切换 | -- |
| StarRocks | BE OOM → 重启 BE | 副本切换 |

### 8. JIT 内存追踪（PostgreSQL 特有）

| 引擎 | JIT | 内存追踪 |
|------|-----|---------|
| PostgreSQL | LLVM (11+) | `EXPLAIN (ANALYZE, BUFFERS)` 显示 JIT timing；`pg_backend_memory_contexts` 中 LLVM context |
| PostgreSQL | -- | `jit_above_cost` 控制是否触发 |
| Oracle | 无传统 JIT (PL/SQL native compile) | -- |
| SQL Server | 列存 batch mode 编译 | 内置 |
| ClickHouse | LLVM JIT | `system.jit_compiled_functions` |
| Trino | Bytecode 生成 | JVM heap |
| Spark | Codegen → Janino | JVM heap |
| Impala | LLVM | `/memz` |
| Greenplum | 继承 PG | 同 PG |
| TimescaleDB | 继承 PG | 同 PG |
| YugabyteDB | 继承 PG | 同 PG |
| CockroachDB | -- | -- |
| DuckDB | 无 JIT，向量化解释 | -- |

### 9. 共享缓冲区 vs 进程私有内存

| 引擎 | 共享内存 | 私有内存 | 比例典型值 |
|------|---------|---------|----------|
| PostgreSQL | `shared_buffers` | per-backend (work_mem * N) | 25% 共享，每连接 4MB+ |
| MySQL InnoDB | `innodb_buffer_pool_size` | per-thread (sort_buffer 等) | 70% 共享 |
| Oracle | SGA (`SGA_TARGET`) | PGA (`PGA_AGGREGATE_TARGET`) | 60/40 典型 |
| SQL Server | buffer pool (max server memory) | workspace (grants) | buffer pool 主导 |
| DB2 | bufferpool, package cache | application heap, sort heap | STMM 自动 |
| ClickHouse | mark cache, uncompressed cache | per-query | 主要私有 |
| Snowflake | (cloud, 隐藏) | -- | 黑盒 |
| BigQuery | (cloud, 隐藏) | -- | 黑盒 |
| Trino | (JVM heap 共享) | per-query 配额 | -- |
| Spark | block manager | task memory | unified memory |
| Greenplum | shared_buffers | statement_mem | -- |
| TiDB | block cache (TiKV) | tidb_mem_quota_query | -- |
| OceanBase | memstore + block cache | sql work area | 50/50 |
| Vertica | ROS containers | resource pool | -- |
| Impala | buffer pool reservation | per-query | unified |
| StarRocks | page cache | per-query | -- |
| Doris | 同 StarRocks | -- | -- |

> 统计：49 个引擎中，约 28 个提供细粒度的每查询/每会话内存视图，约 15 个仅提供全局或模糊指标，约 6 个（Snowflake、BigQuery、Spanner、Athena、Materialize、Firebolt）几乎完全黑盒化。

## 详细引擎实现

### PostgreSQL：work_mem 的隐藏陷阱

PostgreSQL 的内存模型是所有主流数据库中最容易被误解的。核心配置 `work_mem`（默认 4MB）的语义是：

> "每个查询的每个排序、哈希表、位图扫描操作允许使用的最大内存。"

注意三个"每"：**每查询**、**每后端**、**每算子**。

```sql
-- 极端例子：一个查询同时存在多个 work_mem 消费者
EXPLAIN ANALYZE
SELECT a.x, b.y, c.z, COUNT(*)
FROM big_a a
  JOIN big_b b ON a.k = b.k    -- Hash Join 1: work_mem
  JOIN big_c c ON b.k = c.k    -- Hash Join 2: work_mem
WHERE a.created > '2025-01-01'
ORDER BY a.x, b.y               -- Sort: work_mem
GROUP BY a.x, b.y, c.z;         -- HashAggregate: work_mem
```

如果 `work_mem = 64MB` 且 100 个并发连接，理论上限为 `100 * 64MB * 4 算子 = 25.6GB`——远超人们对"每会话 64MB"的直觉。生产环境大量 OOM 事件源自此。

PostgreSQL 13 引入 `hash_mem_multiplier`（默认 1.0，13.x 后默认 2.0）解决哈希算子相对内存敏感的问题：

```sql
SET hash_mem_multiplier = 4.0;  -- Hash 算子可用 work_mem * 4
SET work_mem = '32MB';          -- 排序仍是 32MB，哈希是 128MB
```

PostgreSQL 14 引入 `pg_backend_memory_contexts`，可以细致查看当前后端的内存上下文树：

```sql
SELECT name, level, total_bytes, used_bytes, free_bytes
FROM pg_backend_memory_contexts
ORDER BY total_bytes DESC LIMIT 10;
```

PostgreSQL 17 进一步增强：可以查看其他后端的内存上下文（`pg_log_backend_memory_contexts(pid)` → 写入日志）。但截至 17，PostgreSQL **没有任何视图**直接给出"会话 X 当前正在使用多少内存"——`pg_stat_activity` 没有内存列。监控工具只能通过 OS 层（`/proc/<pid>/status` 的 RSS）间接获取。

**临时文件追踪**：

```sql
SELECT datname, temp_files, pg_size_pretty(temp_bytes) AS temp_bytes
FROM pg_stat_database
WHERE temp_files > 0;

-- 查询级：通过 log_temp_files 写入日志
SET log_temp_files = 0;  -- 记录所有 temp file 使用
```

`temp_file_limit` 控制单个会话最多能写多少 temp 文件——超出后查询 abort，避免单查询撑爆磁盘。

PostgreSQL 15 引入 `backend_flush_after`，控制后端何时主动 fsync 脏页，间接减小 OS page cache 压力。

### Oracle：PGA 自动管理

Oracle 是最早把内存管理"自动化"的数据库。从 9i 开始引入 PGA 自动管理：

```sql
ALTER SYSTEM SET PGA_AGGREGATE_TARGET = 8G;
ALTER SYSTEM SET PGA_AGGREGATE_LIMIT = 16G;  -- 12c+ 硬限
```

`PGA_AGGREGATE_TARGET` 是软目标，Oracle 在多个会话间动态分配工作区内存。单个会话的工作区上限由隐藏参数 `_pga_max_size`（通常是 200MB 或 PGA_TARGET 的 5%）控制。当一个排序/哈希预估超过 `_smm_max_size` 时，Oracle 自动 spill 到 temp tablespace。

**核心视图**：

```sql
-- 全局 PGA 状态
SELECT name, value FROM V$PGASTAT;
-- aggregate PGA target parameter   8589934592
-- aggregate PGA auto target        6442450944
-- total PGA inuse                  3221225472
-- total PGA allocated              4294967296
-- maximum PGA allocated            7516192768
-- ...

-- 每进程内存分类
SELECT pid, category, allocated, used, max_allocated
FROM V$PROCESS_MEMORY
WHERE pid = 47;
-- CATEGORY: SQL, PL/SQL, OLAP, JAVA, Freeable, Other

-- SGA 子池
SELECT pool, name, bytes FROM V$SGASTAT
ORDER BY bytes DESC FETCH FIRST 10 ROWS ONLY;

-- 11g+ AMM (Automatic Memory Management) 动态组件
SELECT component, current_size, min_size, max_size
FROM V$MEMORY_DYNAMIC_COMPONENTS;
```

11g 引入的 AMM (`MEMORY_TARGET`) 在 SGA 和 PGA 间自动分配。但在 Linux 上 AMM 与 HugePages 不兼容，生产环境通常关闭 AMM，使用 ASMM (`SGA_TARGET`) + 自动 PGA。

**Workarea 视图**用于排查具体 SQL 的内存行为：

```sql
SELECT sql_id, operation_type, policy, last_memory_used, last_execution
FROM V$SQL_WORKAREA
WHERE last_execution = 'ONE PASS' OR last_execution = 'MULTI-PASSES'
ORDER BY last_memory_used DESC;
-- ONE PASS / MULTI-PASSES 表示 spill 到 disk
```

### SQL Server：Memory Grants 模型

SQL Server 是唯一在执行前**预估**内存需求并"授权"的主流引擎。优化器为每个查询计算 `requested_memory_kb`，由 `RESOURCE_SEMAPHORE` 管理 grant 队列。

```sql
-- 当前所有 memory grants
SELECT
  session_id, request_id,
  requested_memory_kb, granted_memory_kb,
  used_memory_kb, max_used_memory_kb,
  ideal_memory_kb,
  query_cost, dop,
  wait_time_ms,
  resource_semaphore_id
FROM sys.dm_exec_query_memory_grants;
```

`requested` > `granted` 时查询在 `RESOURCE_SEMAPHORE` 上等待。如果等待超过 `query_wait` 配置，查询失败。

**MEMORYGRANT 提示**（2012+）：

```sql
SELECT * FROM Orders o JOIN Customers c ON o.cid = c.id
ORDER BY o.total
OPTION (MIN_GRANT_PERCENT = 10, MAX_GRANT_PERCENT = 50);
```

`MIN_GRANT_PERCENT` 强制最小 grant 防止 spill；`MAX_GRANT_PERCENT` 防止单查询独占。这是 SQL Server 区别于其他引擎的独特能力——其他引擎通常只能设置上限，无法保证下限。

**Memory clerks** 是 SQL Server 内存的分类：

```sql
SELECT type, name, pages_kb, virtual_memory_committed_kb
FROM sys.dm_os_memory_clerks
WHERE pages_kb > 0
ORDER BY pages_kb DESC;
-- MEMORYCLERK_SQLBUFFERPOOL  (buffer pool)
-- CACHESTORE_SQLCP           (plan cache)
-- USERSTORE_DBMETADATA       (metadata)
-- MEMORYCLERK_SQLQERESERVATIONS (grant reservations)
```

2017+ 在 `sys.dm_exec_query_stats` 增加 `total_spills`、`min_spills`、`max_spills` 等字段，可历史追踪 spill 模式。

### MySQL：performance_schema 内存仪表化

MySQL 5.7.2 (2013) 引入 performance_schema 内存仪表化，覆盖 InnoDB、查询缓存、临时表等子系统。要启用某些 instrument 需要在配置中开启：

```sql
UPDATE performance_schema.setup_instruments
SET ENABLED='YES', TIMED='YES'
WHERE NAME LIKE 'memory/%';
```

**全局视图**：

```sql
SELECT event_name,
       current_count_used,
       sys.format_bytes(current_number_of_bytes_used) AS current_bytes,
       sys.format_bytes(high_number_of_bytes_used)    AS high_bytes
FROM performance_schema.memory_summary_global_by_event_name
ORDER BY current_number_of_bytes_used DESC LIMIT 20;
-- memory/innodb/buf_buf_pool       128.00 GiB
-- memory/innodb/log0buf            16.00 MiB
-- memory/sql/THD::main_mem_root    ...
```

**按线程视图**：

```sql
SELECT thread_id, event_name,
       sys.format_bytes(SUM_NUMBER_OF_BYTES_ALLOC - SUM_NUMBER_OF_BYTES_FREE) AS used
FROM performance_schema.memory_summary_by_thread_by_event_name
WHERE thread_id = 47
ORDER BY (SUM_NUMBER_OF_BYTES_ALLOC - SUM_NUMBER_OF_BYTES_FREE) DESC
LIMIT 10;
```

MySQL 的内存模型是 InnoDB buffer pool 主导的："`innodb_buffer_pool_size` 应该占 RAM 的 50-75%"是经典建议。`tmp_table_size` 和 `max_heap_table_size` 控制内存临时表大小（哪个小取哪个），超出后 8.0 默认转为 InnoDB on-disk temp（5.7 默认 MyISAM）。

MariaDB 10.5 引入 `max_session_mem_used`（默认 0），是 MySQL 系列中第一个真正的会话级硬限。

### DB2：Self-Tuning Memory Manager

DB2 的 STMM（Self-Tuning Memory Manager，9.1+）是最激进的自动内存管理。多数内存参数可设为 `AUTOMATIC`，DB2 在运行时根据工作负载调整：

```sql
UPDATE DB CFG FOR mydb USING DATABASE_MEMORY AUTOMATIC;
UPDATE DB CFG FOR mydb USING SHEAPTHRES_SHR AUTOMATIC;
UPDATE DB CFG FOR mydb USING SORTHEAP AUTOMATIC;
```

**核心监控函数**：

```sql
SELECT memory_pool_type,
       memory_pool_used,
       memory_pool_used_hwm
FROM TABLE(MON_GET_MEMORY_POOL(NULL, NULL, -2));

SELECT memory_set_type,
       memory_set_size,
       memory_set_used
FROM TABLE(MON_GET_MEMORY_SET(NULL, NULL, -2));

-- 实例总览
SELECT * FROM TABLE(ADMIN_GET_DBP_MEM_USAGE(-1));
```

DB2 的内存分层是：instance memory → database memory → application memory → application heap。每层都有 `MON_GET_*` 函数。

### ClickHouse：分层硬限 + SIGKILL

ClickHouse 的内存模型在 OLAP 引擎里非常独特——**显式、分层、严格**。三层关键设置：

```xml
<!-- users.xml -->
<profiles>
  <default>
    <max_memory_usage>10000000000</max_memory_usage>            <!-- per query: 10GB -->
    <max_memory_usage_for_user>20000000000</max_memory_usage_for_user>
    <max_memory_usage_for_all_queries>50000000000</max_memory_usage_for_all_queries>
  </default>
</profiles>
```

`max_memory_usage` 默认 10GB。每查询独立追踪。超限抛异常（不是 abort 整个 server）。

**算子级限额**：

```xml
<max_bytes_before_external_group_by>5000000000</max_bytes_before_external_group_by>
<max_bytes_before_external_sort>5000000000</max_bytes_before_external_sort>
<max_bytes_in_join>5000000000</max_bytes_in_join>
```

设置后 GROUP BY / ORDER BY / JOIN 在超过阈值时**自动 spill** 到磁盘，而不是抛异常。

**监控视图**：

```sql
-- 当前正在执行的查询
SELECT query_id, user, formatReadableSize(memory_usage) AS mem,
       formatReadableSize(peak_memory_usage) AS peak
FROM system.processes ORDER BY memory_usage DESC;

-- 历史
SELECT query_id, type, formatReadableSize(memory_usage),
       formatReadableSize(peak_memory_usage)
FROM system.query_log
WHERE event_time > now() - 3600
  AND type IN ('QueryFinish', 'ExceptionWhileProcessing')
ORDER BY peak_memory_usage DESC LIMIT 20;

-- 服务器整体
SELECT metric, value FROM system.asynchronous_metrics
WHERE metric LIKE '%Memory%';
```

**关键陷阱**：当 server 整体超过 `max_server_memory_usage` 时，ClickHouse 选择最大内存查询并向其抛异常。但如果系统整体内存压力到达 OS 层 OOM killer，**Linux 直接 SIGKILL ClickHouse 进程**，所有查询同时断连——这就是为什么 ClickHouse 推荐配置 `max_server_memory_usage_to_ram_ratio = 0.9` 留出 buffer。

### Snowflake：黑盒中的 Query Profile

Snowflake 不暴露任何内存配置——内存量等于 warehouse 大小。X-Small 约 16GB，每升一档翻倍。**没有 per-query memory cap**：一个查询如果太大，会先 spill 到本地 SSD，再 spill 到 remote storage，最后失败。

唯一的内存可观测性来自 Query Profile UI 和 `QUERY_HISTORY`：

```sql
SELECT query_id,
       bytes_scanned,
       bytes_spilled_to_local_storage,
       bytes_spilled_to_remote_storage,
       execution_time
FROM snowflake.account_usage.query_history
WHERE bytes_spilled_to_remote_storage > 0
ORDER BY bytes_spilled_to_remote_storage DESC LIMIT 20;
```

`bytes_spilled_to_remote_storage > 0` 是 Snowflake 上"内存不足"的唯一硬信号——意味着该查询应该升级 warehouse 或重写。

### BigQuery：完全无内存指标

BigQuery 的 slot 模型彻底抹掉了内存概念。`INFORMATION_SCHEMA.JOBS_BY_PROJECT` 提供 `slot_ms`、`total_bytes_processed`，但没有任何内存字段。当查询失败时可能看到 `Resources exceeded during query execution: Not enough memory`，但无法事先预估或限制。这是 serverless 内存模型的代价。

## PostgreSQL 每查询内存陷阱深入

考虑一个真实的生产事故。集群配置：

```
shared_buffers     = 32GB
work_mem           = 256MB        -- "每会话 256MB，应该够用"
max_connections    = 400
total RAM          = 256GB
```

DBA 的心理账本：32GB shared + 400 * 256MB = 32 + 100 = 132GB，剩 124GB 给 OS cache。安全。

实际上线后某天集群 OOM。事后分析一条慢查询：

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.name, SUM(o.amount), COUNT(DISTINCT p.id)
FROM users u
  JOIN orders o    ON u.id = o.user_id      -- HashJoin #1
  JOIN payments p  ON o.id = p.order_id     -- HashJoin #2
  JOIN refunds r   ON p.id = r.payment_id   -- HashJoin #3
  LEFT JOIN reviews rv ON o.id = rv.order_id -- HashJoin #4
WHERE u.created > '2025-01-01'
GROUP BY u.name                              -- HashAggregate
ORDER BY SUM(o.amount) DESC;                 -- Sort
```

这一条 SQL 包含 4 个 HashJoin、1 个 HashAggregate、1 个 Sort = **6 个 work_mem 消费者**。在 PG 13+ 配合 `hash_mem_multiplier = 2.0` 后：

```
单查询内存 = 4 * (256MB * 2) + 256MB + 256MB = 2.5GB
高峰 80 个并发执行同类查询 = 200GB
```

加上 32GB shared_buffers，超过 RAM。OOM killer 触发，杀掉 postmaster，整个集群重启，所有连接断开。

**正确的容量规划公式**：

```
worst_case_RAM = shared_buffers
               + max_connections * avg_workmem_consumers * work_mem * hash_multiplier
               + autovacuum_max_workers * maintenance_work_mem
               + wal_buffers + temp_buffers * connections
               + OS_cache_reserve (推荐 RAM * 0.2)
```

**实战缓解**：

1. 把 `work_mem` 设为保守值（4-16MB），通过 `SET LOCAL work_mem` 在已知大查询中临时提升
2. 使用 `pg_stat_statements` 找出 `temp_blks_written > 0` 的查询，逐个调优
3. 配置 `temp_file_limit` 保护磁盘
4. PG 14+ 通过 `pg_backend_memory_contexts` 定期采样大内存后端
5. 关键：设置 postmaster 的 `oom_score_adj = -1000`，避免 OOM killer 杀主进程

## ClickHouse 内存限额层次深入

ClickHouse 的内存模型是 4 层硬限叠加，理解层次关系是稳定运行的前提：

```
Layer 1: 单算子 spill 阈值
  max_bytes_before_external_group_by   -- spill, 不抛异常
  max_bytes_before_external_sort
  max_bytes_in_join                    -- 注意: 这是硬限不是 spill 阈值

Layer 2: 单查询限额
  max_memory_usage = 10GB (default)
  超限 → MEMORY_LIMIT_EXCEEDED (单查询)

Layer 3: 单用户限额
  max_memory_usage_for_user = 0 (默认无限)
  跨该用户所有并发查询求和

Layer 4: 服务器全局限额
  max_server_memory_usage = total_RAM * max_server_memory_usage_to_ram_ratio (0.9)
  超限 → 选最大查询抛异常

Layer 5 (OS): Linux OOM killer
  超过 cgroup memory.limit_in_bytes 或物理 RAM
  → SIGKILL clickhouse-server (所有查询断)
```

层次的微妙之处：`max_memory_usage_for_user` 是**软限**，因为 ClickHouse 在算子边界检查，正在分配的算子可能短暂超过；`max_memory_usage` 是**硬限**，每次 allocator 调用都检查；服务器级 `max_server_memory_usage` 通过定期采样判定。

**追踪内存超限**：

```sql
-- 哪些用户/profile 最容易触发 OOM
SELECT user, count() AS oom_count
FROM system.query_log
WHERE event_time > now() - 86400
  AND exception LIKE '%MEMORY_LIMIT%'
GROUP BY user
ORDER BY oom_count DESC;

-- 分析 spill 行为
SELECT query_id, query,
       formatReadableSize(memory_usage) AS mem,
       formatReadableSize(read_bytes) AS read,
       ProfileEvents['ExternalGroupByWritePart'] AS gb_spills,
       ProfileEvents['ExternalSortWritePart']    AS sort_spills
FROM system.query_log
WHERE event_time > now() - 3600
  AND (gb_spills > 0 OR sort_spills > 0);
```

ClickHouse 22.x 后引入 `MemoryTracker` 的层次化追踪，每个查询的 `MemoryTracker` 是用户 `MemoryTracker` 的 child，用户的又是全局的 child，分配时沿链上推。如果某层超限，分配失败，查询抛异常但其他查询不受影响——这是 ClickHouse 比 PostgreSQL 在 OLAP 多租户场景更稳定的核心原因。

## 关键发现

### 1. 标准缺失，实现差异巨大

49 个引擎在内存监控上没有任何共通语法或视图。监控工具必须为每个数据库单独写一套适配器。这与查询语法的高度标准化形成鲜明对比，反映了"内存属于实现细节"的设计哲学。

### 2. 单查询限额模型有三大流派

- **静态算子配额（PostgreSQL 学派）**：每算子固定预算，简单但容易低估总量。优点是可预测、配置清晰。
- **动态自动管理（Oracle/DB2 学派）**：实例总额 + 自动分配。优点是 DBA 友好，缺点是黑盒、难排错。
- **显式分层硬限（ClickHouse/Trino 学派）**：每查询、每用户、全局多层限额。OLAP 多租户最稳定。

### 3. PostgreSQL 的 work_mem 是历史包袱

`work_mem` 的"per operator per backend"语义是 PostgreSQL 内存事故的头号来源。社区多年讨论改为查询级配额，但兼容性顾虑使其至今未变。13 引入的 `hash_mem_multiplier`、14 引入的 `pg_backend_memory_contexts`、17 引入的 `pg_log_backend_memory_contexts(pid)` 都是渐进式改进。

### 4. SQL Server 是唯一支持 grant 双向控制的引擎

`MIN_GRANT_PERCENT` / `MAX_GRANT_PERCENT` 提示让查询作者可以**保证最小内存**而不仅仅是限制最大内存。这在大型 ETL 场景非常宝贵——其他引擎只能祈祷优化器估算准确。

### 5. ClickHouse 的 SIGKILL 风险被低估

ClickHouse 文档反复强调 `max_memory_usage` 是"安全的"，但实际生产环境中的 OOM 几乎都是因为某个未被追踪的内存（mark cache、字典、内核 page cache 写回）撞到 OS 层 OOM killer，导致整个进程 SIGKILL。务必：(a) 配置 cgroup 内存限制；(b) `max_server_memory_usage_to_ram_ratio` 设为 0.8-0.9；(c) 对 mark cache、uncompressed cache 也设上限。

### 6. 云数据仓库选择了"黑盒 + spill"

Snowflake、BigQuery、Athena、Firebolt 等彻底放弃了 per-query 内存配置——内存随计算单元（warehouse / slot / engine）大小线性变化，超量就 spill 到本地 SSD 或远端存储。代价是无法精细控制单查询行为，优势是 DBA 不需要做容量规划。

### 7. MySQL 的内存追踪起步晚但已成熟

MySQL 5.7.2 (2013) 才引入 performance_schema 内存仪表化，比 Oracle V$PROCESS_MEMORY 晚十几年。但 8.0 后已经覆盖几乎所有子系统，可以做到 byte-level 精度的诊断。生产环境强烈建议开启全部 `memory/%` instruments。

### 8. JIT 内存追踪是新前沿

PostgreSQL 11 引入 LLVM JIT 后，`EXPLAIN ANALYZE` 多了 `JIT: Functions: N, Generation: ms, Inlining: ms, Optimization: ms, Emission: ms` 行。但 LLVM 的 IR 缓冲区、机器码 buffer 都计入 backend RSS，可能让看似简单的查询出乎意料地占用 100+ MB。`jit_above_cost` 默认 100000 是合理保护，但批量查询场景仍可能失控——必要时可整体关闭 JIT。

### 9. 临时文件 spill 是预警信号

几乎所有引擎都把 spill 视为"功能完整性兜底"而非"性能问题信号"。但实际上，spill 一旦出现就意味着查询从 ms 级变为 s 级或更慢。建议把 `temp_files > 0`、`bytes_spilled > 0`、`SORT_OVERFLOWS > 0` 作为告警指标，而非"等到查询失败再说"。

### 10. 选型建议

| 场景 | 推荐引擎 | 关键原因 |
|------|---------|---------|
| 多租户 OLTP，需细粒度限额 | TiDB / OceanBase / SQL Server | 资源组/grant 模型成熟 |
| 多租户 OLAP，需稳定隔离 | ClickHouse / Trino | 显式分层硬限 |
| 单租户分析，DBA 资源稀缺 | Snowflake / BigQuery | 内存自动管理 |
| 大量小查询 + JIT 加速 | PostgreSQL（关 JIT 或调高 jit_above_cost）| 灵活但需调优 |
| 内存敏感的 ETL（保证 grant）| SQL Server | MIN_GRANT_PERCENT 独有 |
| 嵌入式 / 单进程分析 | DuckDB | memory_limit + spill 简洁 |

## 附录 A：监控查询速查表

### 1. PostgreSQL 全栈内存巡检

```sql
-- A1. 全局共享内存分配
SELECT name, pg_size_pretty(allocated_size) AS size
FROM pg_shmem_allocations
ORDER BY allocated_size DESC LIMIT 15;

-- A2. 当前后端的上下文树（仅本会话）
SELECT name, level, pg_size_pretty(total_bytes) AS total,
       pg_size_pretty(used_bytes) AS used, ident
FROM pg_backend_memory_contexts
ORDER BY total_bytes DESC LIMIT 20;

-- A3. 17+ 远程触发某个后端 dump 内存上下文到日志
SELECT pg_log_backend_memory_contexts(12345);

-- A4. 检测 temp file 写入异常的查询
SELECT queryid, calls,
       pg_size_pretty(temp_blks_written * 8192) AS temp_written,
       pg_size_pretty(local_blks_written * 8192) AS local_written
FROM pg_stat_statements
WHERE temp_blks_written > 0
ORDER BY temp_blks_written DESC LIMIT 10;

-- A5. 通过 OS 间接获取每后端 RSS（PG 没有内置视图）
-- 需要在 OS 层执行：
-- ps -o pid,rss,comm -p $(pgrep -d, -f "postgres:")
```

### 2. SQL Server 内存压力诊断

```sql
-- B1. 当前所有 grant 等待
SELECT s.session_id, s.login_name, r.command, g.requested_memory_kb,
       g.granted_memory_kb, g.wait_time_ms,
       (SELECT TOP 1 text FROM sys.dm_exec_sql_text(r.sql_handle)) AS sql
FROM sys.dm_exec_query_memory_grants g
  JOIN sys.dm_exec_requests r ON g.session_id = r.session_id
  JOIN sys.dm_exec_sessions s ON g.session_id = s.session_id
WHERE g.granted_memory_kb IS NULL OR g.wait_time_ms > 0
ORDER BY g.requested_memory_kb DESC;

-- B2. 内存压力指标
SELECT object_name, counter_name, cntr_value
FROM sys.dm_os_performance_counters
WHERE counter_name IN (
  'Total Server Memory (KB)',
  'Target Server Memory (KB)',
  'Memory Grants Pending',
  'Memory Grants Outstanding'
);

-- B3. Top 10 plan cache 消耗
SELECT TOP 10 cacheobjtype, objtype,
       SUM(size_in_bytes)/1024/1024 AS mb,
       COUNT(*) AS plans
FROM sys.dm_exec_cached_plans
GROUP BY cacheobjtype, objtype
ORDER BY mb DESC;
```

### 3. Oracle PGA 工作区分析

```sql
-- C1. PGA 是否足够（hit ratio 应 >95%）
SELECT * FROM V$PGA_TARGET_ADVICE
ORDER BY pga_target_for_estimate;

-- C2. 当前哪些会话正在 multi-pass spill
SELECT s.sid, s.username, sw.operation_type, sw.policy,
       sw.actual_mem_used, sw.tempseg_size
FROM V$SQL_WORKAREA_ACTIVE sw
  JOIN V$SESSION s ON sw.sid = s.sid
WHERE sw.tempseg_size IS NOT NULL;

-- C3. 历史 workarea 执行模式
SELECT operation_type,
       optimal_executions, onepass_executions, multipasses_executions,
       ROUND(100 * optimal_executions /
             NULLIF(optimal_executions+onepass_executions+multipasses_executions, 0), 2) AS optimal_pct
FROM V$SQL_WORKAREA_HISTOGRAM
WHERE operation_type IS NOT NULL
ORDER BY operation_type;
```

### 4. ClickHouse 持续监控

```sql
-- D1. 实时 OOM 风险
SELECT formatReadableSize(memory_usage) AS now,
       formatReadableSize(peak_memory_usage) AS peak,
       formatReadableSize(memory_usage_for_user) AS user_now
FROM system.processes
ORDER BY memory_usage DESC;

-- D2. 服务器内存压力时间序列
SELECT event_time,
       formatReadableSize(CurrentMetric_MemoryTracking) AS tracked,
       formatReadableSize(CurrentMetric_OSMemoryAvailable) AS os_avail
FROM system.metric_log
WHERE event_time > now() - 3600
ORDER BY event_time DESC LIMIT 60;

-- D3. 哪些查询最容易触发内存预警
SELECT user, normalizedQueryHash(query) AS h,
       any(query) AS sample_query,
       count() AS exec,
       avg(memory_usage) AS avg_mem,
       max(peak_memory_usage) AS peak_mem
FROM system.query_log
WHERE event_time > now() - 86400 AND type = 'QueryFinish'
GROUP BY user, h
ORDER BY peak_mem DESC LIMIT 20;
```

### 5. MySQL 8.0 内存巡检

```sql
-- E1. 全局内存 TOP 消费者
SELECT event_name,
       sys.format_bytes(current_alloc) AS current,
       sys.format_bytes(high_alloc) AS high
FROM sys.memory_global_by_current_bytes
LIMIT 20;

-- E2. 按用户聚合内存（找出"内存大户"）
SELECT user,
       sys.format_bytes(current_allocated) AS allocated,
       sys.format_bytes(current_max_alloc) AS max_alloc
FROM sys.memory_by_user_by_current_bytes
ORDER BY current_allocated DESC LIMIT 10;

-- E3. 慢查询触发了多少次磁盘临时表
SELECT sql_text, created_tmp_disk_tables, created_tmp_tables
FROM performance_schema.events_statements_history_long
WHERE created_tmp_disk_tables > 0
ORDER BY created_tmp_disk_tables DESC LIMIT 20;
```

## 附录 B：cgroup 与容器化注意事项

容器化部署引入新的内存风险层。所有支持 cgroup 的引擎都必须正确配置 memory.limit_in_bytes，否则数据库基于 `/proc/meminfo` 的容量探测会读到宿主机的 RAM 而非 cgroup 限制：

```
错误: pod 限额 8GB，但 PostgreSQL 探测到 256GB
     work_mem auto-tuned to 64MB，max_connections=400
     实际使用 25GB → cgroup OOM kill → pod 重启
```

不同引擎的 cgroup 兼容性：

| 引擎 | cgroup-aware | 备注 |
|------|-------------|------|
| PostgreSQL | 部分 | shared_buffers 不会自动适配，需手动设 |
| MySQL 8.0+ | 部分 | innodb_dedicated_server=ON 自动调 |
| Oracle 21c+ | 是 | 支持 cgroup v2 |
| SQL Server (Linux) | 是 | 通过 mssql.conf 显式设定 |
| ClickHouse | 是 | 自动检测 cgroup limit |
| MongoDB | 是 | wiredTiger cache 适配 |
| Redis | 是 | maxmemory 显式 |
| Elasticsearch | 否 | JVM heap 必须手动设为 cgroup 一半 |

**最佳实践**：永远不要依赖数据库的"自动检测"。在容器中显式设置每个内存相关参数为 cgroup limit 的固定比例（如 50-60%），并预留 20-30% 给非 buffer pool 用途和 OS 文件缓存。

## 附录 C：内存监控的可观测性集成

生产监控通常需要把数据库内存指标导出到 Prometheus / Grafana / Datadog。常见 exporter：

| 引擎 | Exporter | 关键指标 |
|------|---------|---------|
| PostgreSQL | postgres_exporter | pg_stat_database_temp_bytes, pg_settings_shared_buffers_bytes |
| MySQL | mysqld_exporter | mysql_global_status_innodb_buffer_pool_bytes_data |
| Oracle | oracledb_exporter | oracledb_pga_total, oracledb_sga_pool_bytes |
| SQL Server | sql_exporter | mssql_memory_grants_pending |
| ClickHouse | 内置 prometheus endpoint | ClickHouseMetrics_MemoryTracking |
| MongoDB | mongodb_exporter | mongodb_memory_resident |
| Redis | redis_exporter | redis_memory_used_bytes |

**关键告警规则**示例（Prometheus）：

```yaml
- alert: PostgresHighTempFiles
  expr: rate(pg_stat_database_temp_files[5m]) > 1
  for: 5m
  annotations:
    summary: "PostgreSQL spilling to temp files (work_mem too low?)"

- alert: ClickHouseMemoryNearLimit
  expr: ClickHouseMetrics_MemoryTracking / ClickHouseAsyncMetrics_OSMemoryTotal > 0.85
  for: 2m

- alert: SQLServerMemoryGrantsPending
  expr: mssql_memory_grants_pending > 0
  for: 1m
```

## 参考资料

- PostgreSQL: [Resource Consumption - work_mem](https://www.postgresql.org/docs/current/runtime-config-resource.html)
- PostgreSQL: [pg_backend_memory_contexts](https://www.postgresql.org/docs/current/view-pg-backend-memory-contexts.html)
- PostgreSQL: [hash_mem_multiplier (13+)](https://www.postgresql.org/docs/13/runtime-config-resource.html)
- Oracle: [PGA Memory Management](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgdba/tuning-program-global-area.html)
- Oracle: [V$PROCESS_MEMORY](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-PROCESS_MEMORY.html)
- SQL Server: [sys.dm_exec_query_memory_grants](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-query-memory-grants-transact-sql)
- SQL Server: [Query Hints - MIN_GRANT_PERCENT / MAX_GRANT_PERCENT](https://learn.microsoft.com/en-us/sql/t-sql/queries/hints-transact-sql-query)
- MySQL: [Performance Schema Memory Summary Tables](https://dev.mysql.com/doc/refman/8.0/en/performance-schema-memory-summary-tables.html)
- DB2: [MON_GET_MEMORY_POOL](https://www.ibm.com/docs/en/db2/11.5?topic=routines-mon-get-memory-pool-table-function)
- ClickHouse: [Settings - max_memory_usage](https://clickhouse.com/docs/en/operations/settings/query-complexity)
- ClickHouse: [system.processes](https://clickhouse.com/docs/en/operations/system-tables/processes)
- Trino: [Memory Management](https://trino.io/docs/current/admin/properties-memory-management.html)
- Snowflake: [Query Profile - Spilling](https://docs.snowflake.com/en/user-guide/ui-query-profile)
- Greenplum: [statement_mem and Resource Groups](https://docs.vmware.com/en/VMware-Greenplum/index.html)
- TiDB: [tidb_mem_quota_query](https://docs.pingcap.com/tidb/stable/system-variables#tidb_mem_quota_query)
- CockroachDB: [Memory Allocation](https://www.cockroachlabs.com/docs/stable/recommended-production-settings)
