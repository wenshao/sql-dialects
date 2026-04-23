# 临时空间管理 (Temporary Space Management)

临时空间是数据库里最沉默的杀手：查询 99% 的时间在 `work_mem` 内高速运行，直到某天排序/哈希溢写触达磁盘限额——执行报错 `could not write to file: disk full`，整个实例的所有会话随之雪崩。理解临时空间的配额、溢写路径、监控视图，是把 OLAP 和混合负载数据库运维稳下来的关键。

## 无 SQL 标准

SQL:2023 标准对临时空间的管理没有任何定义。临时表（`CREATE TEMPORARY TABLE`）是标准的，但**运行时临时存储**——排序/哈希/聚合溢写到磁盘时使用的空间——完全是厂商实现细节：PostgreSQL 称之为 temp files，Oracle 称之为 temporary tablespace，SQL Server 叫 tempdb，MySQL 叫 temp tables + internal temp tables，每家的配额粒度、加密策略、监控视图均不相通。

本文聚焦运行时临时空间（溢写空间，spill space），而非 `CREATE TEMPORARY TABLE` 创建的会话临时表。

## 支持矩阵（综合）

### 溢写能力与配额支持

下表列出 45+ 引擎在临时空间管理方面的主要能力。列含义：

- **算子溢写**：当 `work_mem` 或等效内存不足时，排序/哈希/聚合算子能否溢写到磁盘
- **临时表空间配置**：是否可以单独配置临时文件的物理位置
- **会话级配额**：能否限制单会话的临时空间用量
- **查询级配额**：能否限制单查询的临时空间用量
- **静态加密**：临时文件是否支持落盘加密
- **监控视图**：是否提供系统视图观察临时空间使用情况

| 引擎 | 算子溢写 | 临时表空间配置 | 会话级配额 | 查询级配额 | 静态加密 | 监控视图 |
|------|---------|----------------|-----------|-----------|---------|---------|
| PostgreSQL | 是 | `temp_tablespaces` | `temp_file_limit` | -- | 文件系统层 | `pg_stat_database.temp_files` |
| MySQL | 是 | `innodb_temp_tablespaces_dir` (8.0) | -- | -- | InnoDB 透明 | `INFORMATION_SCHEMA.INNODB_SESSION_TEMP_TABLESPACES` |
| MariaDB | 是 | `aria_log_dir_path` / `tmpdir` | -- | -- | -- | `Created_tmp_disk_tables` 状态变量 |
| SQLite | 是 | `PRAGMA temp_store_directory` | -- | -- | 加密扩展 (SEE) | -- |
| Oracle | 是 | `TEMPORARY TABLESPACE` | -- | `PQ_SLAVE` 资源管理器 | TDE | `V$TEMPSEG_USAGE` / `V$SORT_USAGE` |
| SQL Server | 是 | `tempdb`（独立数据库） | -- | `RESOURCE GOVERNOR` | TDE | `sys.dm_db_file_space_usage` / `sys.dm_db_task_space_usage` |
| DB2 | 是 | `USER/SYSTEM TEMPORARY` tablespace | -- | -- | Native Encryption | `MON_GET_TABLESPACE` |
| Snowflake | 是 | 仓库本地 SSD/NVMe（不可配置） | -- | `STATEMENT_TIMEOUT_IN_SECONDS` 间接限制 | 平台级透明加密 | `QUERY_HISTORY.BYTES_SPILLED_TO_LOCAL_STORAGE` |
| BigQuery | 是 | 不透明 shuffle | -- | 查询槽位 / `MAXIMUM_BYTES_BILLED` | 平台级透明加密 | `INFORMATION_SCHEMA.JOBS.total_slot_ms` |
| Redshift | 是 | 节点本地 SSD（不可配置） | `wlm_query_slot_count` | -- | 集群级加密 | `STL_QUERY_METRICS` / `SVL_QUERY_SUMMARY.is_diskbased` |
| DuckDB | 是 | `PRAGMA temp_directory` | `PRAGMA max_temp_directory_size` | -- | -- | `duckdb_temporary_files()` |
| ClickHouse | 是 | `tmp_path` | `max_temporary_data_on_disk_size_for_user` | `max_temporary_data_on_disk_size_for_query` | 磁盘级加密 | `system.processes` / `system.query_log` |
| Trino | 是 | `spiller-spill-path` | `query.max-total-memory-per-node` | `query.max-memory` | -- | `system.runtime.queries` |
| Presto | 是 | `experimental.spiller-spill-path` | -- | `query.max-memory` | -- | `system.runtime.queries` |
| Spark SQL | 是 | `spark.local.dir` | `spark.executor.memory` | -- | Hadoop 加密区 | Spark UI / `SparkListener` |
| Hive | 是 | `hive.exec.scratchdir` | -- | -- | HDFS TDE | YARN ApplicationMaster |
| Flink SQL | 是 | `io.tmp.dirs` | -- | -- | -- | Flink Web UI |
| Databricks | 是 | `spark.local.dir` (DBFS) | -- | -- | Delta 加密 | Spark UI |
| Teradata | 是 | Spool Space（用户配额） | `SPOOL` 参数 | -- | 平台级加密 | `DBC.DiskSpace` |
| Greenplum | 是 | `temp_tablespaces` | `temp_file_limit` | `gp_workfile_limit_per_query` | -- | `gp_toolkit.gp_workfile_usage_per_query` |
| CockroachDB | 是 | `--temp-dir` | -- | `sql.distsql.temp_storage.workmem` | 存储加密 | `crdb_internal.node_queries` |
| TiDB | 是 | `tmp-storage-path` | `tmp-storage-quota` | `tidb_mem_quota_query` | TiKV 加密 | `INFORMATION_SCHEMA.CLUSTER_STATEMENTS_SUMMARY` |
| OceanBase | 是 | 内部 tenant 临时 tablespace | -- | -- | 存储加密 | `GV$OB_SQL_AUDIT` |
| YugabyteDB | 是 | 继承 PostgreSQL `temp_tablespaces` | 继承 `temp_file_limit` | -- | -- | 继承 PG 视图 |
| SingleStore | 是 | `snapshots_directory` / plancache | `maximum_memory` | `maximum_memory` | 静态加密 | `INFORMATION_SCHEMA.MV_ACTIVITIES` |
| Vertica | 是 | `TEMP` storage location | 资源池 `MEMORYSIZE` | 资源池 `MAXMEMORYSIZE` | 卷级加密 | `DC_RESOURCE_ACQUISITIONS` |
| Impala | 是 | `scratch_dirs` | -- | `mem_limit` | HDFS TDE | `impala-shell` query profile |
| StarRocks | 是 | `storage_root_path/trash` + spill 目录 | -- | `spill_mem_limit_threshold` | -- | `information_schema.loads` |
| Doris | 是 | `storage_root_path` + spill | -- | `enable_spill` + `exec_mem_limit` | -- | `SHOW PROCESSLIST` |
| MonetDB | 是 | `gdk_dbfarm` 下的 BAT 文件 | -- | -- | -- | `sys.queue()` |
| CrateDB | 是 | `path.data` | -- | `breaker.query.limit` | 传输加密 | `sys.jobs` |
| TimescaleDB | 是 | 继承 PG `temp_tablespaces` | 继承 `temp_file_limit` | -- | 文件系统层 | 继承 PG 视图 |
| QuestDB | 是 | 不支持独立配置 | -- | -- | -- | `INFORMATION_SCHEMA` 有限 |
| Exasol | 是 | 节点本地临时区（不可配置） | -- | -- | 平台加密 | `EXA_DBA_SESSIONS` |
| SAP HANA | 是 | 行存 rowstore / 列存 tempblob | -- | `MEMORY_LIMIT_TOTAL` | 数据卷加密 | `M_TEMPORARY_TABLES` |
| Informix | 是 | `DBSPACETEMP` | -- | -- | -- | `onstat -t` |
| Firebird | 是 | `TempDirectories` | -- | -- | -- | `MON$STATEMENTS` |
| H2 | 是 | `CACHE_SIZE` / tempfile in db dir | -- | -- | 文件加密 | -- |
| HSQLDB | 有限 | 不可独立配置 | -- | -- | -- | -- |
| Derby | 有限 | `derby.storage.tempDirectory` | -- | -- | -- | -- |
| Amazon Athena | 是 | 不透明（S3 shuffle） | -- | 查询最大时长 | 平台级加密 | CloudWatch |
| Azure Synapse | 是 | 节点本地 tempdb | `RESOURCE_CLASS` | `RESOURCE_CLASS` | TDE | `sys.dm_pdw_nodes_db_task_space_usage` |
| Google Spanner | 部分 | 不透明 | -- | -- | 平台级加密 | `INFORMATION_SCHEMA.TABLE_OPERATIONS` |
| Materialize | 部分 | `--data-directory` | -- | -- | -- | `mz_internal` 视图 |
| RisingWave | 部分 | 状态存储（非传统溢写） | -- | -- | 对象存储加密 | `rw_catalog.rw_sources` |
| InfluxDB (SQL / IOx) | 是 | 对象存储 + 本地缓存 | -- | -- | 平台加密 | -- |
| DatabendDB | 是 | `spill.storage` | -- | `max_execute_time_in_seconds` | -- | `system.query_log` |
| Yellowbrick | 是 | 节点本地 SSD | `YB_PROFILE` 资源 | `YB_PROFILE` | 平台加密 | `sys.yb_query_history` |
| Firebolt | 是 | 引擎本地 SSD（不可配置） | -- | -- | 平台加密 | `INFORMATION_SCHEMA.QUERY_HISTORY` |

> 统计：45+ 引擎中绝大多数都支持算子溢写，但**仅约 12 个引擎同时暴露临时表空间位置 + 会话级配额 + 查询级配额**这三项核心配置。

### 细分能力：算子溢写类型

下表细化每个引擎在排序、哈希聚合、哈希连接三类核心算子上的溢写行为。"原生"指算子本身有分块溢写实现；"退化"指不能溢写只能报错或全量载入内存。

| 引擎 | ORDER BY 溢写 | 哈希聚合溢写 | 哈希连接溢写 | 默认内存阈值 |
|------|--------------|-------------|-------------|-------------|
| PostgreSQL | 原生（外部归并） | 原生（14+ HashAgg spill） | 原生（Hybrid Hash Join） | `work_mem=4MB` |
| MySQL | 原生（filesort） | 原生（tmp table） | 有限（8.0+ 哈希连接溢写） | `tmp_table_size=16MB` |
| MariaDB | 原生（filesort） | 原生 | 有限 | `tmp_table_size=16MB` |
| SQLite | 原生（临时 B-tree） | 有限 | -- | 内存为主 |
| Oracle | 原生（sort segments） | 原生（HASH GROUP BY） | 原生（Hybrid Hash Join） | `PGA_AGGREGATE_TARGET` |
| SQL Server | 原生（tempdb spool） | 原生（Hash Aggregate） | 原生（Hash Match） | tempdb 动态 |
| DB2 | 原生 | 原生 | 原生 | `SORTHEAP` |
| Snowflake | 原生（local SSD） | 原生 | 原生 | 仓库内存 |
| BigQuery | 原生（shuffle） | 原生 | 原生 | Shuffle 分布 |
| Redshift | 原生（node local） | 原生 | 原生 | 节点内存 |
| DuckDB | 原生 | 原生（v0.9+ streaming） | 原生（radix-join spill） | `memory_limit` |
| ClickHouse | `max_bytes_before_external_sort` | `max_bytes_before_external_group_by` | `max_bytes_in_join` | 0（默认不溢写） |
| Trino | 实验性 spill-to-disk | 实验性 | 实验性 | `query.max-memory` |
| Presto | 实验性 | 实验性 | 实验性 | `query.max-memory` |
| Spark SQL | 原生（ExternalSorter） | 原生（AggregationIterator） | 原生（SortMergeJoin / Hash fallback） | `spark.sql.autoBroadcastJoinThreshold` |
| Hive | 原生 | 原生 | 原生 | 分区/分桶策略 |
| Flink SQL | 原生（批模式） | 原生 | 原生 | `taskmanager.memory.managed.size` |
| Databricks | 原生 | 原生 | 原生 | Photon 引擎内存 |
| Teradata | 原生（spool） | 原生 | 原生 | 用户 SPOOL 配额 |
| Greenplum | 原生（workfiles） | 原生 | 原生 | `statement_mem` |
| CockroachDB | 原生（DistSQL） | 原生 | 原生 | `sql.distsql.temp_storage.workmem` |
| TiDB | 原生（v5.0+） | 原生 | 原生（v6.1+） | `tidb_mem_quota_query` |
| OceanBase | 原生 | 原生 | 原生 | 租户内存 |
| YugabyteDB | 继承 PG | 继承 PG | 继承 PG | 继承 PG |
| SingleStore | 原生 | 原生 | 原生 | `maximum_memory` |
| Vertica | 原生 | 原生 | 原生 | 资源池内存 |
| Impala | 原生 | 原生 | 原生 | `mem_limit` |
| StarRocks | 原生（3.0+ spill） | 原生 | 原生 | `spill_mode` |
| Doris | 原生 | 原生（2.1+） | 原生（2.1+） | `enable_spill` |
| MonetDB | 原生（BAT memory-mapped） | 原生 | 原生 | 物理内存 |
| CrateDB | 有限 | 有限 | 有限 | `breaker.query.limit` |
| TimescaleDB | 继承 PG | 继承 PG | 继承 PG | 继承 PG |
| QuestDB | 有限 | 有限 | -- | -- |
| Exasol | 原生 | 原生 | 原生 | 节点内存 |
| SAP HANA | 原生 | 原生 | 原生 | `MEMORY_LIMIT` |
| Informix | 原生 | 原生 | 原生 | `DS_TOTAL_MEMORY` |
| Firebird | 原生 | 有限 | 有限 | `SortMemBlockSize` |
| H2 | 有限 | 有限 | -- | 堆内存 |
| HSQLDB | 有限 | -- | -- | 堆内存 |
| Derby | 有限 | -- | -- | 堆内存 |
| Amazon Athena | 继承 Trino | 继承 Trino | 继承 Trino | 引擎配置 |
| Azure Synapse | 原生 | 原生 | 原生 | `RESOURCE_CLASS` |
| Google Spanner | 部分 | 部分 | -- | 内部 |
| Materialize | 部分 | 部分 | 部分 | `--memory-limit` |
| RisingWave | 原生（状态后端） | 原生 | 原生 | 状态后端配置 |
| InfluxDB (SQL) | 原生 | 原生 | 原生 | 执行器内存 |
| DatabendDB | 原生 | 原生 | 原生 | `spill.storage_level` |
| Yellowbrick | 原生 | 原生 | 原生 | 节点 SSD |
| Firebolt | 原生 | 原生 | 原生 | 引擎 SSD |

> 关键发现：
>
> - **几乎所有主流关系型引擎都支持三大算子溢写**；未完全支持的主要是内存型 / 嵌入式引擎（HSQLDB、Derby、SQLite、H2 部分）和流引擎（Materialize 部分）。
> - **ClickHouse 和 Trino 在默认配置下不溢写**，必须显式开启（`max_bytes_before_external_group_by`、`spill-enabled=true`），这是很多 OOM 事故的根因。
> - **云数仓（Snowflake/BigQuery/Redshift）完全托管临时空间**，优点是无配置烦恼，缺点是溢写容量与仓库规模绑定、无法单独调优。

## 各引擎深入解析

### PostgreSQL：work_mem、temp_tablespaces 与 temp_file_limit

PostgreSQL 的临时空间模型直接暴露在多个 GUC 参数上，是所有引擎中最透明的设计之一。

#### work_mem：每算子每后端的内存阈值

```sql
-- 全局默认：4MB
SHOW work_mem;

-- 会话级修改
SET work_mem = '256MB';

-- 每个排序 / 哈希 / 聚合算子独立分配 work_mem
-- 单个查询如有 N 个并行排序，最多可占用 N × work_mem
-- 一个复杂 OLAP 查询 + max_parallel_workers_per_gather=4 + 3 个排序算子
-- → 最坏情况内存占用 = 4 × 3 × work_mem
```

#### temp_tablespaces：临时文件位置

```sql
-- 创建独立的临时表空间（通常放在独立 SSD）
CREATE TABLESPACE temp_ssd LOCATION '/mnt/nvme/pgtemp';

-- 指定多个临时表空间，PG 会在它们之间轮询
ALTER SYSTEM SET temp_tablespaces = 'temp_ssd, temp_nvme2';
SELECT pg_reload_conf();

-- 验证
SHOW temp_tablespaces;
```

#### temp_file_limit：单后端临时文件总量配额

```sql
-- 9.2+ 支持，单位为 KB
-- 限制单个会话累积的临时文件总量（不是瞬时）
ALTER SYSTEM SET temp_file_limit = '10GB';

-- 0 = 无限制（默认）
-- 超过限制会报错：ERROR: temporary file size exceeds temp_file_limit
-- 注意：这是针对单个后端进程累积写入的总量，非所有并发会话共享
```

#### log_temp_files：监控溢写

```sql
-- 设置为 0 时记录所有临时文件
-- 设置为 10240（KB）时只记录大于 10MB 的
ALTER SYSTEM SET log_temp_files = '10MB';

-- 日志会出现：
-- LOG: temporary file: path "base/pgsql_tmp/pgsql_tmp1234.0", size 104857600
-- STATEMENT: SELECT ...
```

#### 实时监控视图

```sql
-- 数据库级累积统计
SELECT datname, temp_files, temp_bytes
FROM pg_stat_database
ORDER BY temp_bytes DESC;

-- 会话级正在使用的临时文件（9.4+）
SELECT pid, query, temp_files, temp_bytes
FROM pg_stat_activity
JOIN pg_stat_database ON datname = current_database()
WHERE state = 'active';

-- pgstattuple / pg_ls_tmpdir() 可列出实际文件
SELECT * FROM pg_ls_tmpdir();
```

#### PostgreSQL 14 的 HashAgg 溢写

PostgreSQL 13 之前，HashAgg 哈希表超出 `work_mem` 时不会溢写而是全量占用内存，导致 OOM。14 版本引入 HashAgg spill，行为与 HashJoin 类似：

```sql
-- 强制观察 HashAgg spill
SET work_mem = '4MB';
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, COUNT(*)
FROM orders
GROUP BY customer_id;

-- 输出示例：
-- HashAggregate  (cost=...)
--   Batches: 9  Memory Usage: 4145kB  Disk Usage: 12288kB
--   ...
-- 其中 "Disk Usage" 就是溢写到临时文件的数据量
```

### Oracle：TEMPORARY TABLESPACE 与 TEMP_UNDO_ENABLED

Oracle 的临时空间以 **temporary tablespace** 为核心，9i 起支持多个，默认名为 `TEMP`。

#### 创建与管理临时表空间

```sql
-- 创建临时表空间（必须是 TEMPFILE，不是 DATAFILE）
CREATE TEMPORARY TABLESPACE temp_olap
    TEMPFILE '/u01/app/oracle/oradata/orcl/temp_olap01.dbf' SIZE 10G
    AUTOEXTEND ON NEXT 1G MAXSIZE 100G
    EXTENT MANAGEMENT LOCAL UNIFORM SIZE 1M;

-- 将用户分配到特定临时表空间
ALTER USER analyst TEMPORARY TABLESPACE temp_olap;

-- 数据库级默认
ALTER DATABASE DEFAULT TEMPORARY TABLESPACE temp_olap;

-- 临时表空间组（多个临时表空间可聚合）
CREATE TEMPORARY TABLESPACE temp_grp1 TEMPFILE ... TABLESPACE GROUP tg_olap;
ALTER USER analyst TEMPORARY TABLESPACE tg_olap;
```

#### TEMP_UNDO_ENABLED（12c+）

全局临时表（GTT）的 undo 默认写入常规 undo 表空间，12c 引入 `temp_undo_enabled` 可将 GTT undo 重定向到临时表空间：

```sql
ALTER SESSION SET TEMP_UNDO_ENABLED = TRUE;

-- 优点：
-- 1. 减少常规 undo 压力
-- 2. GTT 操作不产生 redo（临时 undo 也不产生 redo）
-- 3. Active Data Guard 上可写 GTT
```

#### 监控视图

```sql
-- 临时段使用情况
SELECT tablespace_name, total_blocks, used_blocks, free_blocks
FROM v$sort_segment;

-- 按会话查看临时空间占用
SELECT s.sid, s.username, u.tablespace, u.blocks * 8192 / 1024 / 1024 AS mb
FROM v$session s
JOIN v$tempseg_usage u ON s.saddr = u.session_addr
ORDER BY u.blocks DESC;

-- 历史 AWR 视图
SELECT snap_id, instance_number, sort_usage_total
FROM dba_hist_tempstatxs;
```

#### sort_area_size 已废弃

11g 起，Oracle 推荐使用 **PGA_AGGREGATE_TARGET** 自动管理工作区：

```sql
-- 不推荐（手动模式）
ALTER SESSION SET workarea_size_policy = MANUAL;
ALTER SESSION SET sort_area_size = 104857600;

-- 推荐（自动模式，默认）
ALTER SYSTEM SET workarea_size_policy = AUTO;
ALTER SYSTEM SET pga_aggregate_target = '10G';
ALTER SYSTEM SET pga_aggregate_limit = '20G';  -- 12c+ 硬上限
```

### SQL Server：tempdb 深度调优

SQL Server 把临时空间独立成一个数据库——**tempdb**，它服务所有用户数据库的：

- 内部工作表（排序、哈希、假脱机）
- 用户临时表与表变量
- 版本存储（RCSI、行版本控制）
- 在线索引重建

#### tempdb 配置原则

```sql
-- 查看 tempdb 文件
SELECT name, physical_name, size * 8 / 1024 AS size_mb, growth
FROM tempdb.sys.database_files;

-- 最佳实践：多文件（从 2016 起 setup 向导默认每核一个文件，上限 8）
-- 手动添加数据文件：
ALTER DATABASE tempdb
    ADD FILE (NAME = 'tempdev2', FILENAME = 'D:\tempdb\tempdb_2.ndf',
              SIZE = 2GB, FILEGROWTH = 512MB);

-- tempdb 建议放在独立高速存储（NVMe SSD）
-- 预分配足够空间，避免运行时自增长（加锁代价高）
```

#### 2016 之前的 TF 1117/1118

SQL Server 2016 之前，为了减少 tempdb 分配竞争，常用两个追踪标志：

- **TF 1118**：所有分配都用完整盘区（8 页），避免 SGAM 页争用
- **TF 1117**：文件组内文件统一自增长，确保负载均匀

```sql
-- SQL Server 2012/2014
DBCC TRACEON (1117, 1118, -1);

-- 2016 起这两个行为默认开启，不再需要
-- 对 tempdb 尤其如此：
-- MIXED_PAGE_ALLOCATION = OFF（等效 1118）
-- AUTOGROW_ALL_FILES（等效 1117）
ALTER DATABASE tempdb
    MODIFY FILEGROUP [PRIMARY] AUTOGROW_ALL_FILES;
```

#### 监控 tempdb

```sql
-- 文件空间使用
SELECT file_id, type_desc,
       (unallocated_extent_page_count * 8) / 1024 AS free_mb,
       (version_store_reserved_page_count * 8) / 1024 AS version_store_mb,
       (user_object_reserved_page_count * 8) / 1024 AS user_obj_mb,
       (internal_object_reserved_page_count * 8) / 1024 AS internal_obj_mb
FROM sys.dm_db_file_space_usage;

-- 当前会话/任务占用
SELECT session_id, task_alloc_GB = (user_objects_alloc_page_count +
                                     internal_objects_alloc_page_count) * 8.0 / 1024 / 1024
FROM sys.dm_db_task_space_usage
WHERE session_id > 50
ORDER BY task_alloc_GB DESC;

-- tempdb 争用等待（PAGELATCH_xx on 2:1:x 或 2:1:y）
SELECT TOP 10 *
FROM sys.dm_os_waiting_tasks
WHERE resource_description LIKE '2:%';
```

#### Resource Governor 限额

```sql
-- 创建资源池和工作负载组限制 tempdb 使用
CREATE RESOURCE POOL olap_pool WITH (MAX_MEMORY_PERCENT = 40);

CREATE WORKLOAD GROUP olap_group
WITH (
    MAX_DOP = 8,
    REQUEST_MAX_MEMORY_GRANT_PERCENT = 25,
    REQUEST_MEMORY_GRANT_TIMEOUT_SEC = 60
) USING olap_pool;

-- 2019+ 支持 tempdb 限额（MAX_IOPS_PER_VOLUME 等 IO 限制）
```

### MySQL：双层临时空间模型

MySQL 的临时空间很特殊，分为**内存临时表**和**磁盘临时表**两层，且有多种存储后端。

#### 内存临时表：tmp_table_size / max_heap_table_size

```sql
-- 内存临时表的最大大小，取两者较小值
SET GLOBAL tmp_table_size = 256 * 1024 * 1024;       -- 256MB
SET GLOBAL max_heap_table_size = 256 * 1024 * 1024;

-- 注意：这是单个隐式临时表的上限，不是会话总量
-- 超过上限时转为磁盘临时表
```

#### 磁盘临时表：innodb_temp_data_file_path

5.7 起 MySQL 使用 InnoDB 的 ibtmp1 文件作为所有磁盘临时表的共享存储：

```sql
-- my.cnf
[mysqld]
innodb_temp_data_file_path = ibtmp1:12M:autoextend:max:10G

-- 格式：filename:initial_size:autoextend:max:max_size
-- 重启后 ibtmp1 会被重置
```

#### MySQL 8.0 的会话临时表空间

8.0 引入**会话临时表空间**（session temp tablespace），每个会话独立文件，避免 ibtmp1 争用：

```sql
-- 查看池的目录
SHOW VARIABLES LIKE 'innodb_temp_tablespaces_dir';
-- 默认：#innodb_temp/

-- 查看会话级使用情况
SELECT * FROM INFORMATION_SCHEMA.INNODB_SESSION_TEMP_TABLESPACES;

-- 每个会话分配两个文件池成员（用户创建的 + 优化器内部的）
-- 会话结束时文件归还池
```

#### 监控与计数器

```sql
-- 磁盘溢写统计（会话级）
SHOW SESSION STATUS LIKE 'Created_tmp%';
-- Created_tmp_tables         10    -- 总临时表数
-- Created_tmp_disk_tables    2     -- 其中转为磁盘的

-- 理想比例：Created_tmp_disk_tables / Created_tmp_tables < 5%
-- 过高通常是 tmp_table_size 过小或 SQL 存在大结果集

-- 查询级别：需要开启 performance_schema
SELECT * FROM performance_schema.events_statements_history_long
WHERE CREATED_TMP_DISK_TABLES > 0;
```

### DB2：TEMPORARY tablespace

```sql
-- DB2 有两类临时表空间：
-- SYSTEM TEMPORARY：用于优化器工作区（排序、哈希等）
-- USER TEMPORARY：用于 DECLARE GLOBAL TEMPORARY TABLE

-- 创建 SYSTEM TEMPORARY tablespace
CREATE SYSTEM TEMPORARY TABLESPACE temp_large
    PAGESIZE 32K
    MANAGED BY AUTOMATIC STORAGE
    BUFFERPOOL bp32k
    EXTENTSIZE 32
    PREFETCHSIZE AUTOMATIC;

-- 监控临时表空间使用
SELECT TBSP_NAME, TBSP_TYPE, TBSP_USED_PAGES, TBSP_TOTAL_PAGES
FROM TABLE(MON_GET_TABLESPACE('', -2))
WHERE TBSP_CONTENT_TYPE IN ('SYSTEMP', 'USRTEMP');

-- SORTHEAP：单个排序/哈希算子内存
UPDATE DBM CFG USING SHEAPTHRES 0;             -- 启用自调优
UPDATE DB CFG FOR mydb USING SORTHEAP AUTOMATIC;
UPDATE DB CFG FOR mydb USING SHEAPTHRES_SHR AUTOMATIC;
```

### Snowflake：仓库本地 SSD，几乎无配置

Snowflake 把临时空间完全封装在虚拟仓库（Virtual Warehouse）内部，溢写到仓库节点的本地 SSD/NVMe，不允许用户显式配置。

```sql
-- 查看查询是否有磁盘溢写
SELECT query_id, query_text,
       bytes_spilled_to_local_storage,
       bytes_spilled_to_remote_storage
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE bytes_spilled_to_local_storage > 0
ORDER BY bytes_spilled_to_local_storage DESC
LIMIT 20;

-- 两级溢写：
-- local  : 仓库节点的本地 SSD（快）
-- remote : 云对象存储（慢，说明仓库规模太小）

-- 唯一的"调优"手段就是扩容仓库
ALTER WAREHOUSE olap_wh SET WAREHOUSE_SIZE = 'LARGE';
```

Snowflake 的设计哲学是"用钱换性能"：扩容仓库即获得更多内存和本地 SSD。

### BigQuery：不透明 shuffle

BigQuery 的 Dremel 架构使用分布式 shuffle，溢写完全隐藏。用户能感知到的只有：

- **Resources exceeded during query execution**：查询超出资源
- **slot_ms**：执行消耗的槽位毫秒
- **shuffle_output_bytes**：shuffle 输出总量

```sql
-- 通过 INFORMATION_SCHEMA.JOBS 观察
SELECT job_id, query, total_slot_ms, total_bytes_processed
FROM `region-us`.INFORMATION_SCHEMA.JOBS
WHERE error_result.reason = 'resourcesExceeded';

-- 缓解 shuffle 压力的手段：
-- 1. 使用 APPROX_COUNT_DISTINCT 替代 COUNT(DISTINCT)
-- 2. 聚合前先预聚合（两阶段 GROUP BY）
-- 3. 使用 CLUSTERED BY 减少 shuffle 量
```

### Spark SQL：spark.local.dir

Spark 的临时空间由执行器（Executor）本地磁盘承载：

```properties
# spark-defaults.conf

# 本地临时目录（支持多目录用逗号分隔）
spark.local.dir=/mnt/ssd1,/mnt/ssd2,/mnt/ssd3

# Shuffle 服务（独立进程共享 shuffle 数据）
spark.shuffle.service.enabled=true
spark.shuffle.service.port=7337

# 溢写阈值（Tungsten UnsafeExternalSorter）
spark.shuffle.memoryFraction=0.2
spark.shuffle.spill.compress=true
spark.shuffle.spill.numElementsForceSpillThreshold=-1
```

```sql
-- SQL 层观察
SET spark.sql.adaptive.enabled=true;
SET spark.sql.adaptive.skewJoin.enabled=true;

-- 通过 Spark UI 的 Stage 详情观察 Shuffle Read/Spill 大小
-- Spill 出现 = 内存不足，考虑：
--   1. 增大 executor memory
--   2. 增加 shuffle partitions（spark.sql.shuffle.partitions）
--   3. 使用 broadcast join 避免大 shuffle
```

### ClickHouse：显式阈值的两把钥匙

ClickHouse 默认不溢写，必须显式开启：

```sql
-- 全局或用户级
SET max_bytes_before_external_group_by = 10000000000;   -- 10GB
SET max_bytes_before_external_sort = 10000000000;
SET max_bytes_in_join = 10000000000;
SET join_algorithm = 'partial_merge';                    -- 支持溢写的连接算法

-- 临时文件路径
-- config.xml
-- <tmp_path>/var/lib/clickhouse/tmp/</tmp_path>

-- 查询级限额（25.x+）
SET max_temporary_data_on_disk_size_for_query = 100000000000;  -- 100GB
SET max_temporary_data_on_disk_size_for_user  = 500000000000;  -- 500GB

-- 监控
SELECT query_id, user, memory_usage, current_database, query
FROM system.processes
WHERE memory_usage > 1000000000;

-- 历史溢写查询
SELECT query, memory_usage, read_bytes, result_bytes
FROM system.query_log
WHERE type = 'QueryFinish'
  AND has(ProfileEvents.Names, 'ExternalAggregationWritePart')
ORDER BY event_time DESC
LIMIT 20;
```

**ClickHouse 风险提示**：默认 `max_bytes_before_external_group_by = 0` 表示**不溢写**，大数据量 GROUP BY 会直接 OOM。生产环境强烈建议显式配置，官方推荐值约为 `max_memory_usage / 2`。

### DuckDB：memory_limit + temp_directory

```sql
-- 设置内存上限与临时目录
PRAGMA memory_limit = '8GB';
PRAGMA temp_directory = '/mnt/fastssd/duckdb_tmp';

-- 限制临时目录最大占用（v0.9+）
PRAGMA max_temp_directory_size = '100GB';

-- 查看当前溢写文件
SELECT * FROM duckdb_temporary_files();

-- DuckDB 的 HashAgg / Sort 内置 streaming 溢写
-- v0.9 引入 disk-spilling 对所有算子（out-of-core）
-- v0.10 引入 spilling for window functions
```

### Trino / Presto：实验性 spill-to-disk

```properties
# etc/config.properties
experimental.spill-enabled=true
experimental.spiller-spill-path=/mnt/spill
experimental.spiller-max-used-space-threshold=0.9
experimental.spiller-threads=4

# 查询级内存限制（内存超出时触发 spill）
query.max-memory=20GB                    # 查询全局内存
query.max-total-memory=30GB
query.max-memory-per-node=5GB
query.max-total-memory-per-node=10GB
```

Trino 的 spill 长期处于实验状态，很多产线使用者选择完全关闭它，依靠扩容集群解决内存问题。

### CockroachDB / TiDB：分布式 SQL 的临时空间

**CockroachDB**：

```sql
-- 节点级临时目录
-- 启动参数：--temp-dir=/mnt/nvme/cockroach-temp

-- 会话级工作内存
SET CLUSTER SETTING sql.distsql.temp_storage.workmem = '256MB';
SET CLUSTER SETTING sql.distsql.temp_storage.enabled = true;
```

**TiDB**：

```sql
-- tidb.toml
-- tmp-storage-path = "/tmp/tidb/tmp-storage"
-- tmp-storage-quota = 10737418240   -- 10GB per node

-- 查询级内存
SET tidb_mem_quota_query = 10737418240;
-- 超过时策略：0=日志, 1=取消, 2=杀查询, 3=节流
SET tidb_mem_oom_action = 'CANCEL';

-- 开启 spill
SET tidb_enable_tmp_storage_on_oom = 1;
```

## PostgreSQL 临时文件管理深度解析

PostgreSQL 是理解引擎临时空间的最佳教材，其实现透明、文档详尽，下面拆解几个关键细节。

### 临时文件的命名与位置

```
临时文件路径：$PGDATA/base/pgsql_tmp/pgsql_tmp<pid>.<fileid>
或临时表空间路径：<tablespace_location>/PG_<version>/pgsql_tmp/pgsql_tmp<pid>.<fileid>

示例：
base/pgsql_tmp/pgsql_tmp12345.0    -- 后端 pid=12345 的第 0 个文件
base/pgsql_tmp/pgsql_tmp12345.1    -- 第 1 个文件（单文件超过 1GB 后分片）
```

- 单个临时文件上限 1GB，超过后自动分片
- 正常结束时自动清理；进程崩溃遗留的文件由 checkpointer 周期性清理

### work_mem 与 hash_mem_multiplier

PostgreSQL 15 引入 `hash_mem_multiplier`，让哈希算子可以使用 N 倍 work_mem：

```sql
-- work_mem = 4MB, hash_mem_multiplier = 2.0
-- 则 HashJoin / HashAgg 实际可用 8MB，排序仍然 4MB
ALTER SYSTEM SET hash_mem_multiplier = 2.0;
SELECT pg_reload_conf();

-- 这样设计的原因：哈希算子需要更多内存才能避免多批次溢写
-- 而排序外部归并成本较低，可保持较小 work_mem
```

### 外部归并排序

PostgreSQL 排序的溢写策略：

```
内存阶段（work_mem 以内）：
  使用快速排序 / replacement selection

溢写阶段（超出 work_mem）：
  1. 生成多个已排序的 run（每个 run 占据 work_mem）
  2. 多路归并（merge）这些 run
  3. 如果 run 太多（> 排序缓冲可容纳），需要多轮归并

EXPLAIN ANALYZE 输出示例：
  Sort Method: external merge  Disk: 52480kB
  (内存不足，溢写了 52MB，使用外部归并)

  Sort Method: quicksort  Memory: 3891kB
  (内存内完成)
```

### HashJoin 的批次溢写

```
构建阶段（build side）：
  1. 估算构建侧大小
  2. 划分为 nbatch 个批次
  3. 如果整个构建侧能放进 work_mem * hash_mem_multiplier，nbatch = 1
  4. 否则动态增加 nbatch（默认 1 → 2 → 4 → 8 ...）

探测阶段（probe side）：
  每个批次的构建数据加载到哈希表，探测侧对应批次逐行探测

EXPLAIN ANALYZE 输出：
  Hash Join  (cost=... rows=... width=...)
    Hash Cond: (t1.id = t2.id)
    ->  Seq Scan on ...
    ->  Hash
          Buckets: 4096  Batches: 16  Memory Usage: 256kB
          (被分成了 16 个批次，说明构建侧 → 工作内存的 16 倍)
```

### HashAgg spill（14+）

```sql
-- 强制触发 HashAgg spill 观察
SET work_mem = '1MB';
SET hash_mem_multiplier = 1.0;
SET enable_sort = off;   -- 强制用 HashAgg

EXPLAIN (ANALYZE, BUFFERS) SELECT c, COUNT(*)
FROM large_table GROUP BY c;

-- 输出含关键字段：
-- HashAggregate  (... groups=1000000)
--   Group Key: c
--   Planned Partitions: 32  Batches: 5  Memory Usage: 1057kB  Disk Usage: 8192kB
--   ...
-- Planned Partitions 指预计的分区数
-- Batches 指实际处理的批次数
-- Disk Usage 是溢写到临时文件的总量
```

## SQL Server tempdb 优化全景

### 多文件分配：从经验法则到自动化

**2016 之前**（手动配置）：

- 每个 CPU 核对应一个 tempdb 数据文件，上限 8 个（不再扩展到物理核数）
- 所有文件初始大小、自增长参数必须完全一致
- TF 1118 强制完整盘区分配；TF 1117 强制均衡增长

```sql
-- SQL Server 2014 典型配置
ALTER DATABASE tempdb MODIFY FILE (NAME=tempdev,  SIZE=8GB, FILEGROWTH=512MB);
ALTER DATABASE tempdb ADD FILE (NAME=tempdev2, FILENAME='T:\tempdb2.ndf', SIZE=8GB, FILEGROWTH=512MB);
ALTER DATABASE tempdb ADD FILE (NAME=tempdev3, FILENAME='T:\tempdb3.ndf', SIZE=8GB, FILEGROWTH=512MB);
ALTER DATABASE tempdb ADD FILE (NAME=tempdev4, FILENAME='T:\tempdb4.ndf', SIZE=8GB, FILEGROWTH=512MB);

DBCC TRACEON (1117, 1118, -1);
```

**2016 起**（setup 自动化 + 默认行为）：

- 安装向导会自动为每个核心创建一个 tempdb 文件（上限 8）
- `MIXED_PAGE_ALLOCATION = OFF` 默认开启（等同 TF 1118）
- `AUTOGROW_ALL_FILES` 默认开启（等同 TF 1117）

```sql
-- 验证配置
SELECT name, physical_name, size * 8 / 1024 AS size_mb,
       growth, is_percent_growth
FROM tempdb.sys.database_files;

SELECT name, is_mixed_page_allocation_on, is_autogrow_all_files
FROM sys.databases WHERE name = 'tempdb';
```

### 内存优化 tempdb 元数据（2019+）

```sql
-- 2019 引入 tempdb 元数据内存优化，显著缓解高并发小事务场景
ALTER SERVER CONFIGURATION
    SET MEMORY_OPTIMIZED TEMPDB_METADATA = ON;

-- 验证
SELECT SERVERPROPERTY('IsTempdbMetadataMemoryOptimized');
```

### 监控与诊断

```sql
-- tempdb 空间分解
SELECT
    SUM(unallocated_extent_page_count) * 8 / 1024 AS free_mb,
    SUM(version_store_reserved_page_count) * 8 / 1024 AS version_store_mb,
    SUM(user_object_reserved_page_count) * 8 / 1024 AS user_objects_mb,
    SUM(internal_object_reserved_page_count) * 8 / 1024 AS internal_objects_mb,
    SUM(mixed_extent_page_count) * 8 / 1024 AS mixed_extent_mb
FROM sys.dm_db_file_space_usage;

-- 谁在占用 tempdb？
SELECT t.session_id, s.login_name, s.host_name, s.program_name,
       (t.user_objects_alloc_page_count + t.internal_objects_alloc_page_count) * 8 / 1024 AS alloc_mb,
       (t.user_objects_dealloc_page_count + t.internal_objects_dealloc_page_count) * 8 / 1024 AS dealloc_mb
FROM sys.dm_db_task_space_usage t
JOIN sys.dm_exec_sessions s ON t.session_id = s.session_id
WHERE (t.user_objects_alloc_page_count + t.internal_objects_alloc_page_count) > 0
ORDER BY alloc_mb DESC;

-- 争用检测：观察 PAGELATCH_* 等待
SELECT resource_description, wait_duration_ms
FROM sys.dm_os_waiting_tasks
WHERE wait_type LIKE 'PAGELATCH%'
  AND resource_description LIKE '2:%';
-- 2:N:1 = tempdb 数据文件 N 的 PFS 页（可能表示分配争用）
-- 2:N:2 = tempdb 数据文件 N 的 GAM 页
-- 2:N:3 = tempdb 数据文件 N 的 SGAM 页
```

## 关键设计议题

### 1. 溢写阈值：内存还是磁盘？

几种主流策略：

- **按算子设置内存上限**（PostgreSQL work_mem、MySQL tmp_table_size）：简单但不精细
- **按查询设置内存上限**（Trino query.max-memory、TiDB tidb_mem_quota_query）：查询可控
- **按用户/角色设置内存上限**（Redshift WLM、Teradata profile）：多租户友好
- **全局池 + 自动调度**（Oracle PGA_AGGREGATE_TARGET、DB2 STMM）：自动化程度高但不透明
- **云托管**（Snowflake、BigQuery）：完全不可调，扩容仓库即可

### 2. 查询级 vs 会话级配额

- **查询级**最精确（CH 的 `max_temporary_data_on_disk_size_for_query`、TiDB 查询级内存），但对长会话不友好
- **会话级**适合 BI 工具场景（PG 的 `temp_file_limit`，但累积语义易误解）
- **用户级**配合资源池（Vertica、SQL Server RG、Teradata SPOOL）是最健壮的多租户方案

### 3. 临时文件加密

- **Oracle TDE、SQL Server TDE** 原生支持 tempdb 加密
- **PostgreSQL** 无内建加密，只能依赖文件系统层（LUKS、eCryptfs）或存储加密
- **ClickHouse** 通过 `<encryption>` 磁盘配置支持
- **云引擎**（Snowflake、BigQuery、Redshift）平台级透明加密

### 4. 溢写对执行时间的放大效应

```
没有溢写：
  HashJoin 1B × 1B 行，work_mem 足够 → 10 秒

一次溢写：
  内存不足，分为 2 batch → 15 秒（写 + 读一次临时文件）

多次溢写：
  分为 16 batch → 60 秒（I/O 成倍增长）

溢写到慢盘：
  HDD 上的临时目录 → 可能超过 10 倍延迟
```

经验法则：临时空间的磁盘 IOPS 与吞吐比数据目录更重要。生产环境应考虑：

- 将 temp_tablespaces / tempdb / spill-path 放到独立 NVMe
- 监控临时空间的写入 IOPS 和平均延迟
- 避免临时空间与 WAL 共享磁盘（两者都高并发写）

### 5. 流式引擎的"状态"即"临时空间"

Flink、RisingWave、Materialize 等流式引擎的 windowed aggregation、interval join 等算子的"状态"实际上就是持续的临时存储：

- **Flink**：RocksDB state backend 使用本地 SSD
- **RisingWave**：Hummock 状态存储，落地到对象存储 + 本地缓存
- **Materialize**：Arrangements 保存在 `--data-directory`

这些"临时空间"的生命周期与传统批查询不同——它们持续存在直到算子被取消，容量需求取决于窗口大小和 key 基数，而非单次查询的数据量。

## 关键发现

1. **45+ 引擎中几乎所有主流引擎都支持算子溢写**，但默认配置下的**ClickHouse 和 Trino 都不自动溢写**，这是生产 OOM 事故的主要陷阱。
2. **PostgreSQL 的设计最透明也最危险**：`work_mem` 是"每算子每后端"语义，一个并行 + 多算子查询可能实际占用 N × M × work_mem，远超预期。
3. **SQL Server tempdb 是共享资源**：版本存储、用户临时表、内部工作表全部挤在同一个数据库，所以其多文件、预分配、独立存储的调优指南非常丰富。
4. **MySQL 8.0 的会话级临时表空间**是大幅改进：5.7 的 ibtmp1 全局共享会在高并发下争用严重。
5. **Oracle 的临时表空间组**是少见的把多个临时文件视为一个逻辑单元的设计，对大查询并行 I/O 友好。
6. **云数仓把临时空间完全托管**，优点是省心，缺点是溢写到远程存储时性能骤降（Snowflake 的 `bytes_spilled_to_remote_storage` 是扩容仓库的强烈信号）。
7. **查询级临时空间配额**是防止单查询拖垮整个集群的关键，但**仅约 10 个引擎**（ClickHouse、TiDB、Trino、Vertica、Impala、SingleStore、Greenplum、CockroachDB、Doris、StarRocks）原生支持。
8. **临时空间加密**在合规敏感场景越来越重要：Oracle TDE、SQL Server TDE、DB2 Native Encryption 直接支持；PostgreSQL、MySQL 必须依赖底层文件系统加密。
9. **监控视图的粒度差异巨大**：PostgreSQL `pg_stat_database.temp_files` 只有累积量；Snowflake `QUERY_HISTORY` 有单查询溢写字节；ClickHouse `system.query_log` 可追溯到每次溢写事件。选型应优先考虑可观测性能力。
10. **把临时空间放到独立的高 IOPS 磁盘** 是所有引擎通用的性能优化：对 PG 用 `temp_tablespaces`，对 SQL Server 用专属 `tempdb` 磁盘，对 Spark 用多 `spark.local.dir`，对 ClickHouse 用独立的 `tmp_path` 磁盘配置。

## 参考资料

- PostgreSQL: [Resource Consumption](https://www.postgresql.org/docs/current/runtime-config-resource.html)
- PostgreSQL: [temp_file_limit](https://www.postgresql.org/docs/current/runtime-config-resource.html#GUC-TEMP-FILE-LIMIT)
- PostgreSQL: [Monitoring temp files](https://www.postgresql.org/docs/current/monitoring-stats.html)
- Oracle: [Managing Temporary Tablespaces](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-tablespaces.html)
- Oracle: [TEMP_UNDO_ENABLED](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/TEMP_UNDO_ENABLED.html)
- SQL Server: [tempdb Database](https://learn.microsoft.com/en-us/sql/relational-databases/databases/tempdb-database)
- SQL Server: [Optimizing tempdb Performance](https://learn.microsoft.com/en-us/sql/relational-databases/databases/tempdb-database#performance-improvements-in-tempdb)
- MySQL: [The InnoDB Temporary Tablespace](https://dev.mysql.com/doc/refman/8.0/en/innodb-temporary-tablespace.html)
- MySQL: [Session Temporary Tablespaces](https://dev.mysql.com/doc/refman/8.0/en/innodb-session-temporary-tablespaces.html)
- DB2: [Temporary table spaces](https://www.ibm.com/docs/en/db2/11.5?topic=spaces-temporary-table)
- Snowflake: [Recognizing Disk Spilling](https://docs.snowflake.com/en/user-guide/ui-snowsight-activity#spillage)
- ClickHouse: [Settings for External Aggregation/Sort](https://clickhouse.com/docs/en/operations/settings/query-complexity)
- Trino: [Spill to Disk](https://trino.io/docs/current/admin/spill.html)
- Spark: [Tuning Spark - Memory Management](https://spark.apache.org/docs/latest/tuning.html#memory-management-overview)
- DuckDB: [Spilling to Disk](https://duckdb.org/docs/guides/performance/environment)
- CockroachDB: [Disk-Spilling Operations](https://www.cockroachlabs.com/docs/stable/vectorized-execution)
- TiDB: [Memory Control and Temporary Storage](https://docs.pingcap.com/tidb/stable/configure-memory-usage)
