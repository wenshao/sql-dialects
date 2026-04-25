# 内存授予反馈 (Memory Grant Feedback)

一个排序算子需要 1GB 内存：申请 10GB 等于浪费 9GB 让其他查询排队，申请 100MB 又等于强制 spill 到磁盘让自己变慢 100 倍。内存授予 (Memory Grant) 是 OLAP 查询执行的隐形战场，而内存授予反馈 (Memory Grant Feedback) 是数据库自我修正的关键能力——执行完一次后，根据实际峰值内存调整下次的预分配，让"过度授予浪费"和"授予不足 spill"在多轮执行中收敛到最优。

## 为什么内存授予反馈重要

内存授予是 OLAP 数据库执行排序、哈希连接、哈希聚合、窗口函数等阻塞算子前的预分配动作。它的难度在于：**预分配必须发生在执行之前**，但**最优分配量必须基于实际数据分布**——而后者在执行前只能估计。

```
理想场景:
  优化器准确预估 → 分配恰好的内存 → 内存内完成 → 释放给后续查询

过度授予 (Over-grant):
  优化器高估 → 分配 10x 实际需要 → 浪费内存 → 其他查询排队等内存
  典型症状: 高内存压力下并发吞吐下降, RESOURCE_SEMAPHORE 等待飙升

授予不足 (Under-grant):
  优化器低估 → 分配不够 → 排序/哈希溢出到磁盘 (spill) → 慢 10-100x
  典型症状: 单个查询慢得离谱, tempdb / spill 文件爆增
```

无反馈机制时，每次执行都重复同样的错误。**内存授予反馈**让执行引擎在执行结束后记录"我估了 10GB 但实际只用了 1GB"或"我估了 100MB 但实际溢出了 5GB"，并把修正写回到计划缓存——下次同一查询的同一计划，使用修正后的授予。

这是经典的**自适应执行 (Adaptive Query Execution, AQE)** 机制之一，与[自适应查询计划](./adaptive-query-plans.md)、[选择性估计](./selectivity-estimation.md)、[基数反馈](./cardinality-feedback.md)同属"执行后纠正"家族。

## 没有 SQL 标准

ISO SQL 标准从未涉及内存授予的概念，原因与资源管理类似：这是**执行引擎的内部行为**，不属于 SQL 数据模型。每个引擎有自己的术语和机制：

1. **SQL Server** 称之为 "Memory Grant" 和 "Memory Grant Feedback"，是行业内最完整的实现
2. **Oracle** 用 "PGA Memory" 和 "Automatic PGA Management"，由 PGA_AGGREGATE_TARGET 自动管理
3. **DB2** 用 "Sort Heap" (SHEAPTHRES) 和 "Self-Tuning Memory Manager (STMM)"，自动调优排序内存
4. **PostgreSQL** 用 `work_mem`，但是**纯静态**（无反馈机制）
5. **MySQL/MariaDB** 没有"内存授予"概念，按算子单独申请（`sort_buffer_size`、`join_buffer_size`）
6. **Snowflake** 仓库 (Warehouse) 级别隐式管理，无查询级反馈
7. **ClickHouse** 用 `max_memory_usage` 强约束每查询上限
8. **Spark** 用动态资源分配 (Dynamic Resource Allocation) 在 executor 级调整

因此本文以**概念对比**和**关键能力矩阵**为主，重点展示 SQL Server 完整的反馈循环和 Oracle 的自适应 PGA 管理。

相关文章：[自适应查询计划](./adaptive-query-plans.md)、[选择性估计](./selectivity-estimation.md)、[准入控制](./admission-control.md)、[资源管理与 WLM](./resource-management-wlm.md)、[基数反馈](./cardinality-feedback.md)。

## 支持矩阵

### 1. 静态内存授予 (Static Memory Grant)

执行前根据估算分配固定内存，执行中不调整。这是大多数数据库的基础能力。

| 引擎 | 关键参数 | 计算依据 | 默认值 | 版本 |
|------|---------|---------|--------|------|
| PostgreSQL | `work_mem` | 算子级，每个 sort/hash 独立 | 4MB | 全部 |
| MySQL | `sort_buffer_size` / `join_buffer_size` | 每会话 | 256KB / 256KB | 全部 |
| MariaDB | `sort_buffer_size` / `join_buffer_size` | 每会话 | 2MB / 256KB | 全部 |
| SQLite | `cache_size` | 全局 | 2000 页 | 全部 |
| Oracle | `SORT_AREA_SIZE` (手动模式) | 每会话 | 64KB | 9i 之前 |
| SQL Server | Memory Grant (基于行数 × 行宽) | 每查询 | 自动 | 2005+ |
| DB2 | `SORTHEAP` | 每排序算子 | 4096 页 | 全部 |
| Snowflake | 仓库分配 | 仓库级 | 按尺寸 | GA |
| BigQuery | slot 内存隐式 | 每 slot | 不可配 | GA |
| Redshift | WLM `query_concurrency` 隐含 | 队列级 | 队列 | GA |
| DuckDB | `memory_limit` | 全局 | 80% 系统 | 全部 |
| ClickHouse | `max_memory_usage` | 每查询 | 10GB | 全部 |
| Trino | `query.max-memory-per-node` | 每节点 | -- | 早期 |
| Presto | 同 Trino | 每节点 | -- | 早期 |
| Spark SQL | `spark.executor.memory` | executor | 1GB | 1.0+ |
| Hive | `hive.tez.container.size` | container | 1024MB | 0.13+ |
| Flink SQL | `taskmanager.memory.process.size` | taskmanager | 1728MB | 全部 |
| Databricks | 集群配置 | cluster | 按尺寸 | GA |
| Teradata | AMP 工作内存 | 每 AMP | 系统调优 | 全部 |
| Greenplum | `statement_mem` | 每语句 | 125MB | 全部 |
| CockroachDB | `--max-sql-memory` | 节点全局 | 25% 系统 | 全部 |
| TiDB | `tidb_mem_quota_query` | 每查询 | 1GB | 4.0+ |
| OceanBase | `__memory_limit` | 租户级 | 配置 | 全部 |
| YugabyteDB | 继承 PG `work_mem` | 算子 | 4MB | 全部 |
| SingleStore | `maximum_memory` | 节点 | -- | 全部 |
| Vertica | Resource Pool `MEMORYSIZE` | 池级 | 池配置 | 早期 |
| Impala | `MEM_LIMIT` 查询选项 | 每查询 | -- | 全部 |
| StarRocks | `query_mem_limit` | 每查询 | 2GB | 全部 |
| Doris | `exec_mem_limit` | 每查询 | 2GB | 全部 |
| MonetDB | `gdk_mem_maxsize` | 全局 | -- | 全部 |
| CrateDB | `indices.breaker.query.limit` | 节点 | 60% heap | 全部 |
| TimescaleDB | 继承 PG | 算子 | 4MB | 全部 |
| QuestDB | `cairo.sql.map.page.size` | 算子 | 4MB | 全部 |
| Exasol | DBRAM | 数据库实例 | 自动 | 全部 |
| SAP HANA | `global_allocation_limit` | 实例 | 90% 物理 | 全部 |
| Informix | `DS_TOTAL_MEMORY` | 全局 | 自动 | 11.5+ |
| Firebird | `DefaultDbCachePages` | 全局 | 2048 页 | 全部 |
| H2 | `CACHE_SIZE` | 嵌入 | 64MB | 全部 |
| HSQLDB | 嵌入式默认 | -- | -- | -- |
| Derby | `derby.storage.pageCacheSize` | 嵌入 | 1000 页 | 全部 |
| Amazon Athena | DPU 隐式 | DPU | -- | GA |
| Azure Synapse | DWU 隐式 | DWU 等级 | -- | GA |
| Google Spanner | 节点配额 | 节点 | -- | -- |
| Materialize | `--memory-limit` | dataflow | -- | 全部 |
| RisingWave | `--total-memory-bytes` | compute node | 自动 | 全部 |
| InfluxDB (SQL) | -- | -- | -- | -- |
| DatabendDB | `max_memory_usage` | 每查询 | -- | GA |
| Yellowbrick | Workload 隐式 | 队列 | -- | GA |
| Firebolt | engine 配额 | engine | -- | GA |

> 统计：约 45+ 引擎都支持某种形式的内存约束，但只有少数支持"按算子在执行前精确预分配"。

### 2. 运行时内存授予调整 (Runtime Memory Grant Adjustment)

执行过程中，引擎根据实际数据动态扩展或收缩内存授予。

| 引擎 | 是否支持 | 实现机制 | 版本 |
|------|---------|---------|------|
| PostgreSQL | -- | 算子内是 hash table 自动 grow，但无授予调整 | -- |
| MySQL | -- | 单个 buffer 一次申请到位 | -- |
| MariaDB | -- | 同 MySQL | -- |
| Oracle | 是 | PGA 自动管理动态分配工作区 | 9i+ |
| SQL Server | 部分 | 行模式不调整, 批模式可在 batch 内增长 | 2017 部分 / 2019 增强 |
| DB2 | 是 | STMM 自动调整 SORTHEAP | 9.0+ |
| Snowflake | 是 (隐式) | 自动 spill, 内部弹性内存池 | GA |
| BigQuery | 是 | slot 调度自动重分配 | GA |
| Redshift | 是 | 短查询加速 (SQA) 内存重分配 | GA |
| ClickHouse | -- | 固定上限, 触及即报错 | -- |
| Trino | 部分 | revocable memory 可被回收 | 早期 |
| Spark SQL | 是 | AQE + 动态资源分配 | 3.0+ |
| Hive | 是 | LLAP 内存动态分配 | 3.0+ |
| Flink SQL | 部分 | managed memory 内 fluid 分配 | 1.10+ |
| Databricks | 是 | Photon 引擎自适应内存 | GA |
| Teradata | 是 | TASM 工作内存动态调整 | V2R6+ |
| CockroachDB | 部分 | KV 层 admission control 自适应 | 22.1+ |
| Vertica | 是 | Resource Pool spill 后自动扩展 | 早期 |
| Impala | 是 | Admission Control 多次估算调整 | 4.0+ |
| StarRocks | 部分 | 算子级 spill 时动态调整 | 2.5+ |
| Doris | 部分 | 算子级 spill 时动态调整 | 2.0+ |
| Greenplum | -- | 静态 statement_mem | -- |
| Materialize | 是 (隐式) | dataflow 算子动态调度 | 全部 |
| 其他引擎 | -- | 多数仅静态分配 | -- |

### 3. 反馈式调整 (Feedback-based Adjustment)

执行结束后记录实际峰值内存，下次执行同一计划时使用修正后的授予。这是真正意义上的"反馈"。

| 引擎 | 是否支持 | 命名 | 持久化 | 应用范围 | 版本 |
|------|---------|------|--------|---------|------|
| SQL Server | 是 | Memory Grant Feedback (MGF) | 计划缓存 → 持久化 (2019+) | 行模式 + 批模式 | 2017+ (in-batch) / 2019+ (persisted) |
| Oracle | 部分 | Adaptive Statistics + SQL Plan Mgmt | SQL Plan Baselines | 全局 | 12c+ |
| DB2 | 是 (隐式) | STMM 周期性调整 | 实例级 | 全部排序 | 9.0+ |
| Snowflake | -- | 仓库级隐式, 无查询粒度反馈 | -- | -- | -- |
| Redshift | 是 (有限) | Auto WLM 学习查询特征 | 队列级 | 查询模式 | GA |
| BigQuery | 是 (隐式) | slot 调度学习 | 项目级 | 自动 | GA |
| Spark SQL | 是 | AQE Coalesce/Skew Hint 反馈 | 单次 query | stage 内 | 3.0+ |
| Trino | -- | 仅 revocable memory | -- | -- | -- |
| Hive LLAP | 部分 | Container Reuse 缓存上次行为 | session | -- | 3.0+ |
| PostgreSQL | -- | work_mem 完全静态 | -- | -- | -- |
| MySQL | -- | 无内存授予概念 | -- | -- | -- |
| Vertica | 是 (有限) | Workload Analyzer 建议 | DBA 手动 | -- | 早期 |
| TiDB | 部分 | Plan Cache + Memory Tracker | 实例 | spill 触发 | 6.5+ |
| OceanBase | 部分 | 内存追踪 + 计划淘汰 | -- | -- | 4.x+ |
| Impala | 是 | Admission Control 历史样本 | 队列 | per-query class | 4.0+ |
| Databricks | 是 | Photon AQE | 单次 query | stage | GA |
| 其他引擎 | -- | 多数无反馈 | -- | -- | -- |

> SQL Server 的 Memory Grant Feedback 是业界**最完整、最透明**的实现：从 2017 行模式 (in-batch) → 2019 持久化到计划缓存 → 2022 持久化到 Query Store。Oracle 通过 PGA 自动管理实现"半反馈"——不是针对单个查询，而是针对整个工作负载的全局优化。

### 4. 每查询内存上限 (Per-Query Memory Cap)

无论估算多少，单个查询占用内存的硬上限，超过即报错或排队。

| 引擎 | 参数名 | 范围 | 触及行为 | 默认值 |
|------|--------|------|---------|--------|
| PostgreSQL | `work_mem` × 算子数 | 算子 | spill 到 temp file | 4MB × 算子 |
| MySQL | `tmp_table_size` | tmp 表 | 转 MyISAM on-disk | 16MB |
| Oracle | `_pga_max_size` (隐藏) | 进程 | spill | 200MB / 1GB |
| SQL Server | `query_max_memory_grant_size_kb` (RG) | 资源组 | 等待或报错 (8657) | 25% 服务器 |
| DB2 | WLM `SORTMEM_LIMIT` | 工作负载 | 报错 | -- |
| Snowflake | 仓库 RAM | 仓库 | spill 到 SSD/local disk | 仓库尺寸 |
| BigQuery | -- | -- | 自动 spill | -- |
| Redshift | WLM `query_memory_pct` | 队列 | spill | -- |
| ClickHouse | `max_memory_usage` | 每查询 | 报错 (Memory limit exceeded) | 10GB |
| Trino | `query.max-memory` | 整查询 | 报错 (EXCEEDED_MEMORY_LIMIT) | -- |
| Spark SQL | `spark.executor.memory` | executor | spill / OOM | 1GB |
| Hive | `hive.tez.container.size` | container | OOM | 1024MB |
| Flink SQL | task slot 配额 | slot | spill | -- |
| Databricks | cluster 内存 | cluster | spill | -- |
| Teradata | profile `MAXSPOOL` | session | abort | -- |
| Greenplum | `statement_mem` | 每语句 | spill | 125MB |
| CockroachDB | `--max-sql-memory` | 节点 | spill | 25% 系统 |
| TiDB | `tidb_mem_quota_query` | 每查询 | spill / cancel | 1GB |
| OceanBase | session memstore_limit | session | 报错 | -- |
| Vertica | Resource Pool MAXMEMORYSIZE | 池 | 等待 / 报错 | 池 |
| Impala | `MEM_LIMIT` | 每查询 | spill / 报错 | -- |
| StarRocks | `query_mem_limit` | 每查询 | spill / 报错 | 2GB |
| Doris | `exec_mem_limit` | 每查询 | spill / 报错 | 2GB |
| SingleStore | `maximum_memory` | 节点 | 报错 | -- |
| Materialize | dataflow 内存 | dataflow | OOM | -- |
| RisingWave | total-memory-bytes | 节点 | spill | -- |
| Yellowbrick | Workload 配额 | wlm | spill | -- |
| 其他引擎 | -- | -- | -- | -- |

### 5. Spill 检测 (Spill Detection)

执行过程中检测到内存不足时溢出到磁盘的能力，是反馈机制的关键信号源。

| 引擎 | 检测能力 | 暴露方式 | 反馈联动 | 版本 |
|------|---------|---------|---------|------|
| SQL Server | 是 | XEvent `hash_warning` / `sort_warning`, sys.dm_exec_query_stats | 触发 MGF 调整 | 2017+ |
| Oracle | 是 | V$SQL_WORKAREA, V$SQL_WORKAREA_HISTOGRAM | 触发 PGA 调整 | 9i+ |
| DB2 | 是 | MON_GET_PKG_CACHE_STMT, db.sort_overflows | STMM 自动调整 | 9.5+ |
| PostgreSQL | 是 | EXPLAIN (BUFFERS, ANALYZE) Sort/Hash 显示 disk usage | -- | 9.4+ |
| MySQL | 是 | optimizer_trace 显示 filesort | -- | 5.7+ |
| Snowflake | 是 | QUERY_HISTORY.bytes_spilled_to_local_storage | 仓库自动 | GA |
| Redshift | 是 | SVL_QUERY_REPORT, STL_S3CLIENT_ERROR | -- | GA |
| BigQuery | 是 | INFORMATION_SCHEMA.JOBS_BY_PROJECT | 隐式 | GA |
| ClickHouse | 是 | system.query_log peak_memory_usage | -- | 全部 |
| Trino | 是 | EXPLAIN ANALYZE peak memory | revocable 触发 | 早期 |
| Presto | 是 | 同 Trino | -- | 早期 |
| Spark SQL | 是 | Spark UI / Stage Detail spill 列 | AQE 调整 | 全部 |
| Hive | 是 | TezUI spill metric | LLAP 调整 | 全部 |
| Flink SQL | 是 | Flink UI managed memory | -- | 全部 |
| Databricks | 是 | Photon profile | AQE 调整 | GA |
| Teradata | 是 | DBQL spool size | TASM | V2R6+ |
| Greenplum | 是 | gpcc / spill files 监控 | -- | 全部 |
| CockroachDB | 是 | EXPLAIN ANALYZE memory used | 部分 | 22.1+ |
| TiDB | 是 | TiDB Dashboard, Memory Tracker | spill 触发 | 6.5+ |
| OceanBase | 是 | gv$sql_audit MEM_USED | -- | 4.x+ |
| Vertica | 是 | resource_pool_status spill_kb | -- | 早期 |
| Impala | 是 | Profile Mem Usage | Admission Control 学习 | 全部 |
| StarRocks | 是 | fe.audit.log peak_mem | spill 触发 | 2.5+ |
| Doris | 是 | profile mem_consumption | spill 触发 | 2.0+ |
| MonetDB | -- | -- | -- | -- |
| CrateDB | 是 | circuit breaker | -- | 全部 |
| TimescaleDB | 是 | 继承 PG | -- | 全部 |
| Materialize | 是 | dataflow metric | 隐式 | 全部 |
| RisingWave | 是 | metrics | spill | 全部 |
| 其他引擎 | -- | -- | -- | -- |

## SQL Server: Adaptive Memory Grant 完整循环

SQL Server 是业界唯一拥有**完整 Memory Grant Feedback (MGF) 循环**的主流数据库：估算 → 执行 → 检测 → 反馈 → 持久化 → 再执行。下面详细拆解这个循环。

### 完整反馈循环

```
┌──────────────────────────────────────────────────────────────┐
│  优化器估算 (Cardinality Estimation + Memory Grant Algorithm)  │
│       │                                                       │
│       ▼                                                       │
│  申请 Memory Grant (从 Resource Semaphore)                    │
│       │                                                       │
│       ▼                                                       │
│  执行算子 (Sort/Hash/Window)                                   │
│       │                                                       │
│       ▼                                                       │
│  检测异常:                                                    │
│    - Spill: ideal_grant > granted (under-grant)              │
│    - Waste: used_memory << granted (over-grant)               │
│       │                                                       │
│       ▼                                                       │
│  写入 Memory Grant Feedback (MGF):                            │
│    - 调整 RequestedMemory                                     │
│    - 写回 Plan Cache                                          │
│    - 持久化到 Query Store (2022+)                              │
│       │                                                       │
│       ▼                                                       │
│  下次执行: 使用调整后的授予                                   │
└──────────────────────────────────────────────────────────────┘
```

### 触发条件

```sql
-- MGF 触发的两种异常情景
-- 1. UNDER-GRANT (溢出):
--    实际使用 > 授予, 算子 spill 到 tempdb
--    新授予 = 实际使用 × 1.5 (保守上调, 留 50% 余量)

-- 2. OVER-GRANT (浪费):
--    实际使用 < 授予 × 50%, 浪费 > 1MB
--    新授予 = 实际使用 × 1.5 (下调, 保留小余量)

-- 3. UNSTABLE (不稳定): 
--    多次执行调整方向反复 → 关闭 MGF, 锁定授予
--    内部计数器达到阈值 (默认 5 次反复)
```

### 演进历程

```
SQL Server 2017 (Compatibility Level 140):
  - Batch Mode Memory Grant Feedback
  - 仅适用于列存储索引 + 批处理算子
  - 反馈在 Plan Cache 中, 计划失效则丢失

SQL Server 2019 (Compatibility Level 150):
  - Row Mode Memory Grant Feedback
  - 扩展到行模式算子 (普通排序/哈希)
  - 反馈仍在 Plan Cache 中

SQL Server 2022 (Compatibility Level 160):
  - Memory Grant Feedback Persistence (持久化)
  - 反馈写入 Query Store, 计划失效后仍保留
  - 重启 SQL Server 后反馈仍生效
  - Percentile Memory Grant Feedback (基于百分位的反馈)
```

### 启用与控制

```sql
-- 行模式 MGF 在数据库级别启用
ALTER DATABASE SCOPED CONFIGURATION 
SET ROW_MODE_MEMORY_GRANT_FEEDBACK = ON;

-- 批模式 MGF
ALTER DATABASE SCOPED CONFIGURATION 
SET BATCH_MODE_MEMORY_GRANT_FEEDBACK = ON;

-- MGF 持久化 (SQL Server 2022)
ALTER DATABASE SCOPED CONFIGURATION 
SET MEMORY_GRANT_FEEDBACK_PERSISTENCE = ON;

-- 百分位 MGF (SQL Server 2022)
ALTER DATABASE SCOPED CONFIGURATION 
SET MEMORY_GRANT_FEEDBACK_PERCENTILE_GRANT = ON;

-- 全局禁用 (诊断时使用)
ALTER DATABASE SCOPED CONFIGURATION 
SET MEMORY_GRANT_FEEDBACK_PERSISTENCE = OFF;

-- 单查询禁用 hint
SELECT * FROM sales s JOIN customers c ON s.cid = c.id
OPTION (USE HINT('DISABLE_BATCH_MODE_MEMORY_GRANT_FEEDBACK'));

SELECT * FROM sales s JOIN customers c ON s.cid = c.id
OPTION (USE HINT('DISABLE_ROW_MODE_MEMORY_GRANT_FEEDBACK'));
```

### 观察 MGF 效果

```sql
-- 1. 通过 Extended Events 观察 spill
CREATE EVENT SESSION mgf_observation ON SERVER
ADD EVENT sqlserver.hash_warning,
ADD EVENT sqlserver.sort_warning,
ADD EVENT sqlserver.memory_grant_updated_by_feedback
ADD TARGET package0.event_file(SET filename='mgf.xel');
ALTER EVENT SESSION mgf_observation ON SERVER STATE = START;

-- 2. 通过 sys.dm_exec_query_memory_grants 查看当前授予
SELECT 
    session_id,
    request_id,
    requested_memory_kb,
    granted_memory_kb,
    used_memory_kb,
    max_used_memory_kb,
    ideal_memory_kb,
    grant_time
FROM sys.dm_exec_query_memory_grants;

-- 3. 通过 Query Store 查看持久化反馈 (SQL Server 2022)
SELECT 
    qsq.query_id,
    qsq.last_execution_time,
    qsp.plan_id,
    qsp.last_force_failure_reason_desc,
    qsrs.avg_query_max_used_memory,
    qsrs.last_query_max_used_memory,
    qsrs.avg_log_bytes_used,
    qsfo.feedback_type_desc,
    qsfo.feedback_data
FROM sys.query_store_query qsq
JOIN sys.query_store_plan qsp ON qsq.query_id = qsp.query_id
JOIN sys.query_store_runtime_stats qsrs ON qsp.plan_id = qsrs.plan_id
LEFT JOIN sys.query_store_plan_feedback qsfo ON qsp.plan_id = qsfo.plan_id
WHERE qsfo.feedback_type_desc LIKE '%Memory Grant%';

-- 4. EXPLAIN 中的 MemoryGrant 信息
SET STATISTICS XML ON;
SELECT * FROM sales s JOIN customers c ON s.cid = c.id
ORDER BY s.amount DESC;
-- 在 XML 输出中查找 MemoryGrant 元素:
-- <MemoryGrant SerialRequiredMemory="..." SerialDesiredMemory="..." 
--              RequiredMemory="..." DesiredMemory="..." 
--              RequestedMemory="..." GrantWaitTime="..." GrantedMemory="..." 
--              MaxUsedMemory="..."/>
```

### Resource Governor 与 MGF 交互

```sql
-- Resource Pool 限制 MGF 调整范围
CREATE RESOURCE POOL analytics_pool
WITH (
    MIN_MEMORY_PERCENT = 10,
    MAX_MEMORY_PERCENT = 50,
    MIN_CPU_PERCENT = 10,
    MAX_CPU_PERCENT = 80
);

-- Workload Group 限制单查询内存
CREATE WORKLOAD GROUP analytics_wg
WITH (
    REQUEST_MAX_MEMORY_GRANT_PERCENT = 25,    -- 单查询最多 25% 池内存
    REQUEST_MEMORY_GRANT_TIMEOUT_SEC = 60,    -- 等内存最多 60 秒
    GROUP_MAX_REQUESTS = 20                   -- 并发上限
)
USING analytics_pool;

-- MGF 调整出的新授予不能突破 REQUEST_MAX_MEMORY_GRANT_PERCENT
-- 即使实际需要 5GB, 而池上限是 4GB, 也会 spill
```

### MGF 失败模式

```
1. 计划失效 (Plan Recompile):
   - 统计信息更新 → 计划重编译 → 反馈丢失 (2019 之前)
   - 解决: 2022 持久化到 Query Store

2. 参数嗅探 (Parameter Sniffing):
   - 不同参数值需要差异巨大的内存
   - MGF 反馈基于上次执行参数, 下次参数变化失败
   - 解决: Percentile Grant (基于历史百分位而非单次)

3. 计算列 / 复杂表达式:
   - 优化器无法准确预估行宽 → 反馈方向不稳定
   - MGF 检测到不稳定 → 自动禁用

4. 临时表无统计:
   - 第一次执行无统计 → 优化器估算 1 行
   - MGF 修正后下次正常
```

## Oracle: PGA 自动管理 (Automatic PGA Management)

Oracle 9i 引入 PGA_AGGREGATE_TARGET，实现了"全局 PGA 池 + 自动分配"模式。这不是针对单个 SQL 的反馈，而是针对整个工作负载的自适应分配。

### Manual vs Automatic PGA 对比

```sql
-- 9i 之前: 手动 PGA 管理
ALTER SYSTEM SET WORKAREA_SIZE_POLICY = MANUAL;
ALTER SESSION SET SORT_AREA_SIZE = 1048576;          -- 1MB
ALTER SESSION SET HASH_AREA_SIZE = 2097152;          -- 2MB
ALTER SESSION SET BITMAP_MERGE_AREA_SIZE = 1048576;  -- 1MB

-- 问题: 静态参数, 无法适应不同查询特征, DBA 反复调优

-- 9i 之后: 自动 PGA 管理 (推荐)
ALTER SYSTEM SET WORKAREA_SIZE_POLICY = AUTO;
ALTER SYSTEM SET PGA_AGGREGATE_TARGET = 4G;           -- 全局 PGA 池上限

-- 12c+: 增强自动管理
ALTER SYSTEM SET PGA_AGGREGATE_LIMIT = 8G;            -- 硬上限 (避免 OOM)
-- 注意: PGA_AGGREGATE_TARGET 是软目标, PGA_AGGREGATE_LIMIT 是硬约束
```

### PGA 内部机制

```
PGA_AGGREGATE_TARGET = 4GB:
  ┌────────────────────────────────────────────┐
  │  全局 PGA 池                               │
  │  ├─ 最小工作区 (Minimum Workarea)          │
  │  │   每会话保底, 防止 spill                │
  │  ├─ 自动分配池 (Auto-tuned)                │
  │  │   根据当前活跃查询动态分配             │
  │  │   优先满足重型查询的工作区             │
  │  └─ 紧急余量 (Reserved)                    │
  │     防止 PGA_AGGREGATE_LIMIT 触及          │
  └────────────────────────────────────────────┘

工作区大小决策:
  optimal: 完全在内存中 (最佳)
  one-pass: 一次磁盘溢出 (可接受)
  multi-pass: 多次磁盘溢出 (差)

Oracle 自动调整目标:
  - 优先把工作区调到 optimal
  - 内存紧张时优先牺牲低优先级查询的工作区
```

### 观察 PGA 行为

```sql
-- 1. PGA 当前使用
SELECT * FROM V$PGASTAT;
-- 关键指标:
-- aggregate PGA target parameter: 配置的 PGA_AGGREGATE_TARGET
-- aggregate PGA auto target: 当前自动分配池大小
-- total PGA inuse: 所有进程当前使用
-- maximum PGA used for auto workareas: 历史峰值 (auto)

-- 2. 工作区直方图
SELECT 
    LOW_OPTIMAL_SIZE / 1024 AS low_kb,
    HIGH_OPTIMAL_SIZE / 1024 AS high_kb,
    OPTIMAL_EXECUTIONS,
    ONEPASS_EXECUTIONS,
    MULTIPASSES_EXECUTIONS,
    TOTAL_EXECUTIONS
FROM V$SQL_WORKAREA_HISTOGRAM
ORDER BY LOW_OPTIMAL_SIZE;
-- 理想结果: 99% optimal, 极少 onepass, 几乎没有 multipass

-- 3. 当前活跃工作区
SELECT 
    sql_id,
    operation_type,
    policy,                         -- AUTO / MANUAL
    estimated_optimal_size / 1024 AS optimal_kb,
    estimated_onepass_size / 1024 AS onepass_kb,
    last_memory_used / 1024 AS last_used_kb,
    last_execution,                 -- OPTIMAL / ONE PASS / MULTI-PASS
    last_tempseg_size,
    is_active
FROM V$SQL_WORKAREA_ACTIVE;

-- 4. PGA 使用建议 (Oracle 自动收集统计)
SELECT 
    pga_target_for_estimate / 1024 / 1024 AS estimated_pga_mb,
    pga_target_factor,
    estd_extra_bytes_rw,
    estd_pga_cache_hit_percentage,
    estd_overalloc_count
FROM V$PGA_TARGET_ADVICE;
-- pga_target_factor = 0.5 / 1.0 / 2.0 / 4.0 (相对当前的倍数)
-- 推荐选择 cache_hit_percentage > 90% 的最小 PGA 值
```

### Oracle 12c+: 自适应 SQL 计划

```sql
-- 自适应执行计划 (与 PGA 配合)
ALTER SYSTEM SET OPTIMIZER_ADAPTIVE_PLANS = TRUE;
ALTER SYSTEM SET OPTIMIZER_ADAPTIVE_STATISTICS = TRUE;

-- 自动 SQL Tuning
EXEC DBMS_AUTO_SQLTUNE.EXECUTE_AUTO_TUNING_TASK();

-- 查看自动调优建议
SELECT * FROM DBA_ADVISOR_FINDINGS 
WHERE TASK_NAME = 'SYS_AUTO_SQL_TUNING_TASK';

-- 应用 SQL Plan Baseline 锁定好的计划
EXEC DBMS_SPM.LOAD_PLANS_FROM_CURSOR_CACHE(sql_id => 'abc123');
```

## DB2: STMM 自动调优排序内存

DB2 的 Self-Tuning Memory Manager (STMM) 是另一种"半反馈"机制：不针对单个 SQL，而是周期性调整 SHEAPTHRES（排序内存阈值）。

### STMM 配置

```sql
-- 启用 STMM
UPDATE DATABASE CONFIGURATION USING SELF_TUNING_MEM ON;

-- 把 SHEAPTHRES 设为 AUTOMATIC, 让 STMM 调整
UPDATE DATABASE CONFIGURATION USING SHEAPTHRES_SHR AUTOMATIC;

-- 单个排序的最大内存
UPDATE DATABASE CONFIGURATION USING SORTHEAP AUTOMATIC;

-- 缓冲池也自动调整
ALTER BUFFERPOOL IBMDEFAULTBP SIZE AUTOMATIC;
```

### STMM 调整周期

```
每隔 ~3 分钟, STMM 进行一轮调整:
  1. 收集各内存消费者的统计:
     - SORTHEAP: spill 次数, 平均/最大 spill 大小
     - 缓冲池: 命中率
     - PCKCACHESZ: 包缓存命中率
     - LOCKLIST: 锁等待时间
  
  2. 计算"内存收益":
     - 给 SORTHEAP 多 10% 内存可减少多少 spill
     - 给缓冲池多 10% 内存可提高多少命中率
  
  3. 重新分配:
     - 从收益低的消费者拿出内存
     - 给收益高的消费者
     - 渐进调整 (一次最多 ±20%), 避免抖动
  
  4. 持久化:
     - 调整结果写入实例配置
     - 重启 DB2 后保留
```

### 观察 STMM 行为

```sql
-- 当前各内存区大小
SELECT 
    MEMBER,
    POOL_ID,
    POOL_SECONDARY_ID,
    POOL_CUR_SIZE / 1024 / 1024 AS current_mb,
    POOL_CONFIG_SIZE / 1024 / 1024 AS configured_mb,
    POOL_WATERMARK / 1024 / 1024 AS peak_mb
FROM TABLE(MON_GET_MEMORY_POOL(NULL, NULL, -1));

-- 排序统计
SELECT 
    TOTAL_SORTS,
    POST_THRESHOLD_SORTS,
    SORT_OVERFLOWS,
    POST_SHRTHRESHOLD_SORTS,
    SHARED_SORT_HEAP_HIGH_WATERMARK
FROM TABLE(MON_GET_DATABASE(-1));

-- STMM 日志 (sqllib/db2dump/stmm.log)
-- 显示每次调整的决策依据和调整量
```

## SQL Server Memory Grant 算法详解

为理解反馈机制，先理解原始授予算法。

### 算法核心公式

```
Memory Grant = Required Memory + Additional Memory

Required Memory:
  最小可执行算子的内存 (例: hash table 第一个分区)
  保证至少能开始执行, 即使 spill 也能继续

Additional Memory:
  基于估算的额外缓存
  公式因算子而异:
    Hash Match: estimated_rows * estimated_row_size * 1.2 (含哈希链开销)
    Sort: estimated_rows * estimated_row_size * 2 (含排序工作区)
    Window: estimated_rows * estimated_row_size * (window_frame_factor)
```

### 关键参数

```sql
-- 服务器级
sp_configure 'min server memory (MB)', 4096;     -- SQL Server 最小内存
sp_configure 'max server memory (MB)', 32768;    -- SQL Server 最大内存
sp_configure 'min memory per query (KB)', 1024;  -- 每查询最小授予

-- Resource Pool 级
CREATE RESOURCE POOL my_pool
WITH (
    MAX_MEMORY_PERCENT = 50,
    MIN_MEMORY_PERCENT = 10
);

-- Workload Group 级 (单查询占比)
CREATE WORKLOAD GROUP my_wg
WITH (
    REQUEST_MAX_MEMORY_GRANT_PERCENT = 25     -- 单查询最多 25% 池内存
)
USING my_pool;

-- 计算单查询最大授予:
-- max_grant = pool_max_memory * REQUEST_MAX_MEMORY_GRANT_PERCENT / 100
```

### Resource Semaphore 等待

```sql
-- 当多个查询同时请求大内存, 总和超过池上限时, 后来者排队
SELECT 
    pool_id,
    name,
    target_memory_kb,
    used_memory_kb,
    granted_memory_kb,
    available_memory_kb,
    queued_request_count,
    timeout_error_count
FROM sys.dm_exec_query_resource_semaphores;

-- RESOURCE_SEMAPHORE 等待事件
SELECT 
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    max_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE wait_type IN ('RESOURCE_SEMAPHORE', 'RESOURCE_SEMAPHORE_QUERY_COMPILE');
```

## PostgreSQL: 完全静态的 work_mem

PostgreSQL 是大型数据库中**唯一完全没有内存反馈机制**的引擎。

```sql
-- 全局
ALTER SYSTEM SET work_mem = '64MB';

-- 会话
SET work_mem = '256MB';

-- 单查询 hint (通过 LOCAL)
BEGIN;
SET LOCAL work_mem = '512MB';
SELECT ...;
COMMIT;

-- 角色级
ALTER ROLE analyst SET work_mem = '128MB';
```

### work_mem 的陷阱

```
1. 算子级 (不是查询级):
   一个查询有 N 个 sort/hash 算子
   总内存 ~= N * work_mem (没有上限)
   
   例: 10 个 hash join 的查询, work_mem=64MB
   总内存 ~= 640MB
   
   如果 100 并发, 最多消耗 64GB!

2. 没有反馈:
   优化器低估时永远 spill
   下次还是同样的低估 → 同样 spill
   DBA 必须手动观察 EXPLAIN ANALYZE 调整

3. 通用建议:
   work_mem = (RAM - shared_buffers - other_overhead) / max_connections / 算子数
   保守配置: work_mem = 物理RAM * 25% / max_connections
```

### EXPLAIN 中的 spill 信号

```sql
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM large_table ORDER BY col;

-- 关键指标:
-- Sort Method: external merge  Disk: 102400kB    -- spill 到磁盘
-- 期望:
-- Sort Method: quicksort  Memory: 64MB           -- 内存内完成

-- Hash 算子的 spill 信号:
-- Buckets: 16384 (originally 1024)  Batches: 8 (originally 1)  Memory Usage: 16384kB
-- Batches > 1 表示 spill (多趟磁盘)
```

### 第三方扩展尝试

```
1. pg_stat_statements: 仅记录查询统计, 无反馈
2. pg_qualstats: 记录 WHERE 子句使用统计, 用于索引建议
3. AQO (Adaptive Query Optimization 扩展):
   - 第三方 Postgres Pro 项目
   - 记录查询执行结果, 用机器学习模型修正基数估计
   - 间接影响 work_mem 决策
4. PostgreSQL 17+ 路线图:
   - 仍在讨论 adaptive memory 的可行性
   - 主流意见: 与 work_mem 算子模型不兼容, 需要重大架构调整
```

## MySQL: 无内存授予概念

MySQL/MariaDB 完全没有"查询级内存授予"的概念。每个算子直接用自己的全局参数。

```sql
-- 排序内存 (每会话)
SET SESSION sort_buffer_size = 4194304;        -- 4MB

-- 连接缓冲 (Block Nested-Loop Join)
SET SESSION join_buffer_size = 262144;         -- 256KB

-- 临时表内存阈值
SET SESSION tmp_table_size = 16777216;         -- 16MB
SET SESSION max_heap_table_size = 16777216;    -- 16MB

-- Read Buffer (顺序扫描)
SET SESSION read_buffer_size = 131072;         -- 128KB

-- Read RND Buffer (索引扫描)
SET SESSION read_rnd_buffer_size = 262144;     -- 256KB

-- Bulk Insert Buffer
SET SESSION bulk_insert_buffer_size = 8388608; -- 8MB
```

### MySQL spill 监控

```sql
-- 排序统计
SHOW SESSION STATUS LIKE 'Sort_%';
-- Sort_merge_passes: 多趟磁盘排序次数 (> 0 表示 spill)
-- Sort_range / Sort_rows / Sort_scan: 各类排序次数

-- 临时表落盘
SHOW SESSION STATUS LIKE 'Created_tmp_%';
-- Created_tmp_disk_tables: 转 on-disk 的临时表数
-- Created_tmp_tables: 总临时表数
-- 比例高 → 增加 tmp_table_size

-- Performance Schema 事件
SELECT * FROM performance_schema.events_statements_history
WHERE SUM_SORT_MERGE_PASSES > 0;
```

### 与 SQL Server 的差异

```
SQL Server:                            MySQL:
  - 查询级 memory grant                  - 算子级 buffer
  - 优化器估算总需要                     - 每算子独立申请
  - Resource Semaphore 排队              - 无排队, 直接申请
  - 反馈机制 MGF                          - 无反馈
  - spill 到 tempdb                       - spill 到 mysql tmpdir
```

## Snowflake: 仓库级隐式管理

Snowflake 完全屏蔽了内存授予的细节，仓库 (Warehouse) 级别管理。

```sql
-- 创建仓库时指定尺寸
CREATE WAREHOUSE my_wh WITH 
    WAREHOUSE_SIZE = 'LARGE'      -- X-Small ~ 6X-Large
    MAX_CLUSTER_COUNT = 4;        -- 多集群最大节点数

-- 尺寸与内存对应 (Snowflake 文档不公开精确值, 估算):
-- X-Small:  ~16GB RAM
-- Small:    ~32GB RAM
-- Medium:   ~64GB RAM
-- Large:    ~128GB RAM
-- X-Large:  ~256GB RAM
-- 2X-Large: ~512GB RAM
-- 每升一档, 内存翻倍, 价格也翻倍
```

### Snowflake spill 观察

```sql
-- 查询历史中的 spill 信息
SELECT 
    query_id,
    query_text,
    warehouse_size,
    bytes_spilled_to_local_storage,    -- spill 到本地 SSD
    bytes_spilled_to_remote_storage,   -- spill 到 S3 (极慢)
    execution_time / 1000 AS exec_sec
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time > DATEADD(day, -1, CURRENT_TIMESTAMP())
  AND bytes_spilled_to_remote_storage > 0
ORDER BY bytes_spilled_to_remote_storage DESC;

-- spill 到 remote = 严重内存不足, 升级仓库尺寸
-- spill 到 local = 轻度内存不足, 可接受
```

### 与查询级反馈的差异

```
Snowflake 没有查询级反馈, 因为:
1. 仓库尺寸由用户主动选择 (而非自动)
2. 仓库 → 计算节点是固定映射, 内存按节点分配
3. 仓库内多查询并发时, 内存分配是隐式的, 用户不可见
4. 反馈循环在 Snowflake 内部 (调度器优化), 但不暴露给用户

用户感知的"反馈" = 看到 spill → 手动升级仓库
```

## ClickHouse: 强约束的 max_memory_usage

ClickHouse 的内存管理风格非常"严格"——每个查询有硬上限，超过即报错。

```sql
-- 每查询内存上限 (默认 10GB)
SET max_memory_usage = 5000000000;        -- 5GB

-- 用户级上限
SET max_memory_usage_for_user = 50000000000;  -- 50GB (该用户所有查询总和)

-- 服务器级上限
SET max_server_memory_usage = 100000000000;   -- 100GB
SET max_server_memory_usage_to_ram_ratio = 0.9;  -- 90% RAM

-- spill 控制 (默认禁用)
SET max_bytes_before_external_group_by = 1000000000;  -- 1GB
SET max_bytes_before_external_sort = 1000000000;
SET max_bytes_before_remerge_sort = 1000000000;
SET join_algorithm = 'partial_merge,direct,parallel_hash,hash';  -- 包含 spill 算法
```

### 触及上限的行为

```sql
-- 报错示例:
-- DB::Exception: Memory limit (for query) exceeded: 
-- would use 10.00 GiB (attempt to allocate chunk of 4194304 bytes), 
-- maximum: 10.00 GiB

-- 查看内存使用历史
SELECT 
    query,
    memory_usage,
    peak_memory_usage,
    read_bytes,
    written_bytes
FROM system.query_log
WHERE event_time > now() - INTERVAL 1 HOUR
  AND peak_memory_usage > 1000000000   -- > 1GB
ORDER BY peak_memory_usage DESC
LIMIT 100;
```

### 与反馈机制的对比

```
ClickHouse 哲学:
  - 强约束 + 显式控制 (无隐式反馈)
  - 用户必须明确声明可接受的内存上限
  - 触及即报错, 强制用户升级硬件或重构查询
  - spill 是 opt-in 而非 opt-out

设计取舍:
  + 简单, 可预测
  + 不会"莫名其妙"占用大量内存
  - 大查询需要手动调参
  - 无法在多次执行中自我修正
```

## Spark SQL: 动态资源分配 + AQE

Spark 是分布式引擎中**反馈机制最完整**的代表。

### Dynamic Resource Allocation (动态资源分配)

```scala
// Executor 级别动态调整 (不是单查询级)
spark.dynamicAllocation.enabled = true
spark.dynamicAllocation.minExecutors = 2
spark.dynamicAllocation.maxExecutors = 100
spark.dynamicAllocation.initialExecutors = 4
spark.dynamicAllocation.executorIdleTimeout = 60s

// 工作原理:
// 1. 待处理 task 多 → 申请更多 executor
// 2. executor 空闲 60s → 释放
// 3. shuffle 数据保护: 释放 executor 时保留 shuffle 文件
```

### Adaptive Query Execution (AQE)

```scala
// AQE 启用 (Spark 3.0+)
spark.sql.adaptive.enabled = true

// AQE 子能力:
spark.sql.adaptive.coalescePartitions.enabled = true   // 自动合并小分区
spark.sql.adaptive.skewJoin.enabled = true             // 自动处理倾斜
spark.sql.adaptive.localShuffleReader.enabled = true   // 本地 shuffle 优化
spark.sql.adaptive.optimizer.excludedRules = ""        // 自定义规则

// AQE 反馈循环:
//   stage 1 完成 → 收集实际行数/大小 → 重新规划 stage 2
//   例: 估算 100M 行 → 实际 10M 行 → stage 2 减少 partition
//       原 200 partition → 自动合并到 20 partition
```

### Photon 引擎 (Databricks)

```scala
// Photon 是 Databricks 商业 vectorized 引擎
// 在 AQE 基础上增强:
// 1. 算子级内存自适应 (列存储 batch 大小调整)
// 2. JIT 编译生成的代码考虑实际数据分布
// 3. spill 到 NVMe SSD 时自动 prefetch

// 启用 (仅 Databricks):
spark.databricks.photon.enabled = true
```

### Spark 反馈观察

```scala
// Spark UI / Stage Detail 中的 metrics:
//   spill (memory) bytes
//   spill (disk) bytes
//   peak execution memory
//   shuffle read / write bytes

// SQL tab 显示 AQE 调整:
//   "skipped" stage (被 AQE 优化掉)
//   "coalesce" 操作显示合并前后 partition 数
```

## Trino / Presto: revocable memory

Trino 引入了"可回收内存 (revocable memory)"概念，允许执行引擎主动回收内存。

```properties
# 内存上限
query.max-memory = 50GB
query.max-memory-per-node = 10GB
query.max-total-memory = 80GB
query.max-total-memory-per-node = 16GB

# 可回收内存比例
memory.heap-headroom-per-node = 1GB
spill-enabled = true
spiller-spill-path = /tmp/trino-spill
```

### revocable memory 工作原理

```
1. 算子申请内存:
   - 不可回收 (user memory): 哈希表核心数据
   - 可回收 (revocable memory): hash partition 中可 spill 的部分

2. 系统内存压力时:
   - 协调器选择最大可回收算子
   - 通知算子 "spill"
   - 算子序列化数据到磁盘, 释放内存

3. 后续读取:
   - 从磁盘反序列化, spill-merge 模式
```

### 与 SQL Server MGF 的对比

```
SQL Server MGF:           Trino revocable memory:
  - 反馈下次执行             - 单次执行内 spill
  - 持久化到 plan cache       - 单次查询作用域
  - 自动学习                  - 仅响应内存压力
  - 适合 OLTP/OLAP 混合       - 偏 OLAP 大查询
```

## 关键发现

### 1. 反馈成熟度排序

```
完整反馈 (估算 → 执行 → 检测 → 修正 → 持久化):
  SQL Server (最成熟)
    ├─ 2017: in-batch 反馈 (单次执行内)
    ├─ 2019: 行模式扩展, plan cache 持久化
    └─ 2022: Query Store 持久化, 跨重启保留

半反馈 (全局优化, 非单 SQL):
  Oracle PGA Auto Management
  DB2 STMM

执行内反馈 (单次执行调整):
  Spark SQL AQE
  Databricks Photon
  Hive LLAP
  Trino revocable memory

无反馈 (静态分配):
  PostgreSQL work_mem
  MySQL/MariaDB 算子 buffer
  ClickHouse max_memory_usage
  Snowflake (仓库尺寸用户控制)
  大多数嵌入式数据库
```

### 2. 反馈与执行模型的关系

```
有反馈机制的引擎共同点:
  1. 有"查询计划缓存" (Plan Cache) 概念
  2. 计划与统计/反馈数据可关联
  3. 优化器与执行器解耦, 优化器接受反馈输入

无反馈机制的引擎共同点:
  1. 一次性优化 (no plan cache or simple cache)
  2. 算子级而非查询级内存管理
  3. 优化器不消费运行时统计

PostgreSQL 的特殊性:
  - 有 plan cache (extended query protocol)
  - 但 work_mem 是参数而非授予
  - 算子模型与"反馈一个数字"不兼容
```

### 3. 持久化的代价

```
SQL Server 2017-2019: 反馈在 plan cache
  优点: 实现简单
  缺点: 计划失效 (统计更新, ALTER TABLE) 即丢失
        实例重启即丢失
        高频统计变化的库反馈难以稳定

SQL Server 2022: 反馈持久化到 Query Store
  优点: 跨重启保留
        计划失效后仍可应用
        DBA 可观察反馈历史
  缺点: Query Store 写入有 I/O 开销
        Query Store 需要单独管理 (清理策略)
        百分位反馈算法更复杂
```

### 4. 参数嗅探的反馈陷阱

```
传统 MGF 的隐藏 bug:
  查询 SELECT * FROM t WHERE region = @r
  
  执行 1: @r = 'US' (大区域, 实际 100M 行) → MGF 修正到 10GB
  执行 2: @r = 'XX' (小区域, 实际 1K 行)   → 用 10GB 严重浪费
  执行 3: @r = 'US' (大区域)               → 又触发 spill (cache 已有 10GB?)
  
  问题: 反馈把"参数 X 的需求"误认为"该计划的需求"

SQL Server 2022 解决方案: Percentile Memory Grant
  - 跟踪历史 N 次执行的实际内存分布
  - 取 P75 / P90 作为下次授予 (而非 max)
  - 接受偶尔小溢出, 换取整体内存利用率
  - DBA 可调整百分位阈值
```

### 5. Cloud-native vs 传统数据库

```
传统数据库 (单机 / 共享存储):
  - 内存是稀缺资源, 必须精确管理
  - 反馈机制价值高, 直接影响并发吞吐
  - SQL Server / Oracle / DB2 投入巨大

Cloud-native 数仓 (Snowflake / BigQuery):
  - 弹性计算, 加内存就加机器
  - 价值分摊到 spill 监控 + 仓库自动伸缩
  - 单查询级反馈优先级低

Cloud-native 但成本敏感 (Databricks):
  - 介于两者之间
  - AQE + Photon 仍重视执行内反馈
  - 但不持久化到下次执行 (架构差异)
```

### 6. Spill 检测的两种哲学

```
A. Spill 是异常 (报错):
  ClickHouse: 触及 max_memory_usage 直接报错
  StarRocks/Doris: 默认严格上限
  优点: 资源用量可预测
  缺点: 大查询失败率高, 用户必须主动调参

B. Spill 是降级 (减速):
  PostgreSQL/MySQL/SQL Server/Oracle: 自动 spill
  Snowflake/BigQuery: 自动 spill (用户不可见)
  优点: 查询不会失败
  缺点: 慢查询难以发现 (除非看 metrics)

混合策略:
  Trino: spill-enabled 是开关, 默认开启但可关闭
  TiDB: spill 后还有 cancel 上限
```

### 7. 内存反馈与 AI/ML 优化的趋势

```
传统反馈: 简单规则 (上次溢出 → 加 50%)

下一代趋势 (研究方向):
  1. Microsoft Research / SQL Server:
     基于神经网络的基数估计 + 内存预测
  
  2. Oracle 23c+:
     ML-based PGA Advisor
     根据查询特征向量预测内存需求
  
  3. CockroachDB / TiDB:
     自适应 admission control 根据 latency 反向调内存
  
  4. Databricks:
     Photon 引擎结合 AQE 做"per-vector" 自适应
  
  5. 学术界:
     Bao (Microsoft): 强化学习选 hint
     Neo (MIT): 神经查询优化器
```

### 8. 选型与最佳实践建议

| 场景 | 推荐引擎 | 配置策略 |
|------|---------|---------|
| OLTP 混合, 查询模式稳定 | SQL Server | 启用 MGF + Query Store 持久化 |
| 复杂 OLAP, 工作负载混合 | Oracle | PGA_AGGREGATE_TARGET 自动 + Plan Baselines |
| OLAP 仓储, 工作负载固定 | Vertica / Greenplum | 严格 Resource Pool 配置 |
| 弹性云仓储, 成本敏感 | Snowflake | 用 Multi-Cluster + 仓库自动伸缩 |
| 开源 OLTP, 高度可控 | PostgreSQL | 保守 work_mem + 监控 EXPLAIN ANALYZE |
| 开源 OLAP, 极致性能 | ClickHouse | 严格 max_memory_usage + 拒绝大查询 |
| 大规模 ETL/批处理 | Spark SQL | 启用 AQE + 动态资源分配 |
| 实时流处理 | Flink SQL | 调优 managed memory, 监控背压 |

### 9. 监控指标的优先级

```
必须监控:
  1. spill 次数 / spill 数据量 (发现 under-grant)
  2. 平均 grant vs 平均 used (发现 over-grant)
  3. memory wait 时间 (RESOURCE_SEMAPHORE 类等待)
  4. peak memory usage P99 (容量规划)

进阶监控:
  5. MGF 反馈次数 / 反馈方向稳定性
  6. 参数嗅探导致的反馈震荡
  7. Resource Pool 触及上限频率
  8. 长时间运行查询的内存增长曲线

告警阈值参考:
  - spill 数据量 / scan 数据量 > 10% → 严重
  - average grant / average used > 3x → 优化器估计偏差大
  - memory wait > 1% query time → 内存竞争
```

### 10. 反馈机制的局限

```
反馈无法解决的问题:
  1. 第一次执行 (cold start): 仍依赖优化器估算
  2. 数据急剧变化: 反馈滞后于数据
  3. 参数嗅探 (单计划多参数): 需要 percentile 才能缓解
  4. 隐藏依赖: 反馈基于历史, 不能预测未来

反馈机制 + 其他能力的协同:
  反馈 + 自适应执行 (AQE) → 执行内 + 跨次双重修正
  反馈 + 计划基线 (Plan Baseline) → 锁定好计划 + 持续微调
  反馈 + 资源治理 (Resource Governor) → 上限保护 + 智能授予
```

## 参考资料

- SQL Server: [Memory Grant Feedback](https://learn.microsoft.com/en-us/sql/relational-databases/performance/intelligent-query-processing-feedback)
- SQL Server: [Memory Grants](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-query-memory-grants-transact-sql)
- SQL Server: [Resource Governor](https://learn.microsoft.com/en-us/sql/relational-databases/resource-governor/resource-governor)
- Oracle: [Automatic PGA Memory Management](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgdba/tuning-database-memory.html)
- Oracle: [V$PGASTAT, V$SQL_WORKAREA](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/dynamic-performance-views.html)
- DB2: [Self-Tuning Memory Manager](https://www.ibm.com/docs/en/db2/11.5?topic=memory-self-tuning-manager-stmm)
- DB2: [SHEAPTHRES_SHR](https://www.ibm.com/docs/en/db2/11.5?topic=parameters-sheapthres-shr-sort-heap-threshold-shared-sorts)
- PostgreSQL: [work_mem](https://www.postgresql.org/docs/current/runtime-config-resource.html#GUC-WORK-MEM)
- PostgreSQL: [EXPLAIN ANALYZE](https://www.postgresql.org/docs/current/using-explain.html)
- MySQL: [sort_buffer_size](https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html#sysvar_sort_buffer_size)
- Snowflake: [Warehouse sizing](https://docs.snowflake.com/en/user-guide/warehouses-overview)
- ClickHouse: [Memory settings](https://clickhouse.com/docs/en/operations/settings/query-complexity)
- Trino: [Memory management](https://trino.io/docs/current/admin/properties-resource-management.html)
- Spark SQL: [AQE](https://spark.apache.org/docs/latest/sql-performance-tuning.html#adaptive-query-execution)
- Databricks: [Dynamic Resource Allocation](https://docs.databricks.com/en/clusters/configure.html)
- Microsoft Research: "Predicate-based Cardinality Estimation" (2018)
- VLDB 2019: "Plan Stitch: Harnessing the Best of Many Plans" (Microsoft)
- Bao: "Bao: Learning to Steer Query Optimizers" (CIDR 2020)
