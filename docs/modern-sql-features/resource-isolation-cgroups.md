# 资源隔离 (Resource Isolation)

数据库不是孤岛——它运行在物理机、虚拟机、容器之上，与其他工作负载共享 CPU、内存、I/O 带宽。在多租户、混合负载、Sidecar、DaemonSet 场景下，"邻居噪音 (noisy neighbor)"是性能不稳定的头号原因之一：一个失控的 ETL 作业、一个写得不好的报表查询、一个内存泄漏的服务端进程，都可能让整个集群陷入 P99 飙升、连锁退化的死循环。资源隔离 (Resource Isolation) 是把这些"邻居"关进各自笼子的工程实践——它在 OS 层（cgroups、namespaces、Cgroup v2 IO 控制器）、容器层（Docker/Kubernetes 的 limits）、数据库内部（Resource Manager / Workload Group / Resource Group）三个层次共同发力。

## 为什么资源隔离是多租户与混合负载的基础

资源隔离与"准入控制"和"工作负载管理"密切相关，但回答的问题不同：

- **准入控制 (Admission Control)** 回答的是"谁可以进来"——它是一个守门员，根据当前系统负载决定是否接受新查询。
- **工作负载管理 (WLM)** 回答的是"谁优先执行"——它是一个调度器，根据队列、优先级、配额安排执行顺序。
- **资源隔离 (Resource Isolation)** 回答的是"已经在跑的查询互相之间能不能影响对方"——它是一道隔板，确保一个查询不能耗光所有 CPU、不能把内存吃干、不能让磁盘 I/O 排队 10 秒。

没有资源隔离的多租户系统会出现典型的"邻居噪音"现象：

```
共享集群无隔离时:
  租户 A 跑了一个 cross join → CPU 100%
  租户 B 的秒级仪表盘查询 → 因 CPU 排队从 50ms 变成 30s
  租户 C 的 ETL 写入 → 因为 page cache 被踩烂，读延迟 P99 从 5ms 飙到 200ms
  整个集群的 SLA 同时崩塌

有资源隔离时:
  租户 A 占用自己的 CPU 配额 (50%)，跑得慢但不影响别人
  租户 B 的 CPU 配额 (30%) 始终可用，仪表盘维持 50ms
  租户 C 的 I/O 带宽配额 (200 MB/s) 始终可用，写入正常
  P99 不会因单个查询恶化
```

资源隔离的实现层次：

```
┌─────────────────────────────────────────────┐
│ 数据库内部隔离                               │
│   Resource Manager / WLM / Resource Group   │
│   (CPU shares, memory grants, I/O limits)   │
├─────────────────────────────────────────────┤
│ 容器层隔离                                   │
│   Docker limits / Kubernetes resources      │
│   (cpu.limit, memory.limit, blkio)          │
├─────────────────────────────────────────────┤
│ OS 内核层隔离 (Linux)                        │
│   cgroups v1 / v2                           │
│   (cpu.cfs_quota, memory.max, io.max)       │
├─────────────────────────────────────────────┤
│ 硬件层隔离                                   │
│   独立物理机 / NUMA / RDT (CAT, MBA)        │
└─────────────────────────────────────────────┘
```

资源隔离通常包含以下维度：

- **CPU 隔离**：CPU 时间片配额、CPU 绑核、NUMA 亲和性、CPU 权重
- **内存隔离**：内存上限、SGA/PGA 隔离、Page Cache 隔离、cgroup memory.max
- **I/O 隔离**：I/O 带宽限制、IOPS 限制、磁盘队列优先级 (ionice / blkio)
- **网络隔离**：网络带宽限制、TC (Traffic Control)、QoS
- **并发隔离**：每用户/角色/资源组的并发查询数上限
- **容器化感知**：数据库进程能否正确读取 cgroup 限制（避免内存超限被 OOM killer 杀死）

## 没有 SQL 标准

ISO SQL 标准从未涉及资源隔离语法，原因与准入控制、WLM 类似：

1. **资源是物理概念**：标准只关心逻辑数据模型，不涉及 CPU 调度、内存分配等运行时实现
2. **隔离机制依赖 OS 与硬件**：cgroups 是 Linux 特有，Windows 用 Job Object，AIX 用 WLM Manager，平台差异巨大
3. **历史包袱**：Oracle Resource Manager (1999) 早于任何标准化讨论
4. **云原生的冲击**：Snowflake/BigQuery 的"虚拟仓库/槽位"模型与传统的 cgroup 模型完全不同

因此本文不存在"标准语法"一节——所有内容都是厂商特定或 OS/容器层的运维手段。

相关文章：[资源管理与 WLM](./resource-management-wlm.md)、[准入控制](./admission-control.md)、[多租户数据库](./multi-tenant-database.md)、[连接池](./connection-pooling.md)。

## 支持矩阵

### 1. CPU 隔离 (按查询/角色/资源组)

| 引擎 | CPU 隔离 | 配置粒度 | 隔离方式 | 版本 |
|------|---------|---------|---------|------|
| PostgreSQL | -- (依赖 cgroups) | -- | 外部 | -- |
| MySQL | 部分 | Resource Group | THREAD_PRIORITY + VCPU 集 | 8.0+ |
| MariaDB | -- | -- | -- | -- |
| SQLite | -- | -- | -- | -- |
| Oracle | 是 | Consumer Group | CPU shares + caps | 8i+ |
| SQL Server | 是 | Workload Group | `MAX_CPU_PERCENT` / `CAP_CPU_PERCENT` | 2008 EE+ |
| DB2 | 是 | Service Class | `AGENT PRIORITY` + cgroup | 9.5+ |
| Snowflake | 是 (隐式) | Warehouse | T-shirt 尺寸独立计算节点 | GA |
| BigQuery | 是 (隐式) | Reservation | slot 调度 | GA |
| Redshift | 是 | WLM Queue | `query_concurrency` + 内核线程数 | GA |
| DuckDB | 部分 | 全局 | `threads` 设置 | 0.x+ |
| ClickHouse | 是 | User Quota / Profile | `max_threads` + `priority` (nice) | 全部 |
| Trino | 是 | Resource Group | `softCpuLimit` / `hardCpuLimit` | 早期 |
| Presto | 是 | Resource Group | 同 Trino | 0.153+ |
| Spark SQL | 是 | Fair Scheduler Pool | `weight` + `minShare` | 1.0+ |
| Hive | 是 | Resource Plan | `MAPPING` 到 LLAP queue | 3.0+ |
| Flink SQL | 部分 | Slot | TaskManager slot 数 | 1.x+ |
| Databricks | 是 | SQL Warehouse | T-shirt 尺寸 | GA |
| Teradata | 是 | TASM Workload | CPU Skew + AMP 分配 | V2R6+ |
| Greenplum | 是 | Resource Group | `CPU_RATE_LIMIT` / `CPU_HARD_QUOTA_LIMIT` (cgroups) | 5.0+ |
| CockroachDB | 是 | Admission Control | KV slots + SQL slots (CPU 自适应) | 22.1+ |
| TiDB | 是 | Resource Group | RU (Request Unit) 限速 | 7.1+ |
| OceanBase | 是 | Resource Unit | `MIN_CPU` / `MAX_CPU` | 3.x+ |
| YugabyteDB | -- | -- | (继承 PG) | -- |
| SingleStore | 是 | Resource Pool | `SOFT_CPU_LIMIT_PERCENTAGE` / `HARD_CPU_LIMIT_PERCENTAGE` | 7.0+ |
| Vertica | 是 | Resource Pool | `CPUAFFINITYSET` / `CPUAFFINITYMODE` | 7.0+ |
| Impala | 是 | Resource Pool (admission) | `max-running-queries` (无 CPU 直接限制) | 1.3+ |
| StarRocks | 是 | Resource Group | `CPU_WEIGHT` / `CPU_CORE_LIMIT` | 2.2+ |
| Doris | 是 | Workload Group | `cpu_share` / `cpu_hard_limit` | 2.0+ |
| MonetDB | -- | -- | -- | -- |
| CrateDB | -- | -- | -- | -- |
| TimescaleDB | -- | (继承 PG) | -- | -- |
| QuestDB | -- | -- | -- | -- |
| Exasol | 是 | Priority Group | 权重百分比 | 6.0+ |
| SAP HANA | 是 | Workload Class | `STATEMENT_THREAD_LIMIT` | SPS09+ |
| Informix | 是 | VP Class | onmode 命令 | 早期 |
| Firebird | -- | -- | -- | -- |
| H2 | -- | -- | -- | -- |
| HSQLDB | -- | -- | -- | -- |
| Derby | -- | -- | -- | -- |
| Amazon Athena | 隐式 | Workgroup | 共享 slot 池 | GA |
| Azure Synapse | 是 | Workload Group | Resource Class (固定百分比) | GA |
| Google Spanner | 自动 | -- | 内部隔离 | GA |
| Materialize | 是 | Cluster | 独立计算节点 | GA |
| RisingWave | 部分 | Compute Node | 资源限制 | GA |
| InfluxDB (SQL) | -- | -- | -- | GA |
| Databend | 是 | Warehouse | 独立计算 | GA |
| Yellowbrick | 是 | WLM Profile | `cpuShares` / `cpuLimit` | GA |
| Firebolt | 是 | Engine | T-shirt 尺寸 | GA |

> 统计：约 30 个引擎提供原生 CPU 隔离能力，约 15 个引擎依赖外部 cgroups/容器配额或不支持。

### 2. 内存上限 (按查询/会话)

| 引擎 | 单查询内存上限 | 会话/连接内存上限 | 节点级总内存上限 | 内存超限行为 |
|------|--------------|-----------------|----------------|------------|
| PostgreSQL | `work_mem` (per sort/hash) | `temp_buffers` | `shared_buffers` | 溢出磁盘 / OOM |
| MySQL | `tmp_table_size` / `sort_buffer_size` | `connection_memory_limit` (8.0.28+) | `innodb_buffer_pool_size` | 溢出磁盘 / 错误 |
| Oracle | PGA `_pga_max_size` | Resource Manager `MAX_PGA_LIMIT` | SGA + PGA | 杀会话 |
| SQL Server | `REQUEST_MAX_MEMORY_GRANT_PERCENT` | -- | `max server memory` | 排队 / 溢出 |
| DB2 | WLM `SORTHEAP` | -- | `INSTANCE_MEMORY` | 溢出 |
| Snowflake | -- (按 warehouse 总量) | -- | Warehouse 大小 | Warehouse 排队 |
| BigQuery | 按 slot 隐式 | -- | -- | 溢出 / 错误 |
| Redshift | WLM `mem_to_use` | -- | `wlm_memory_percent_to_use` | 溢出磁盘 |
| ClickHouse | `max_memory_usage` (默认 10GB) | `max_memory_usage_for_user` | `max_server_memory_usage` | 抛异常 |
| Trino | `query.max-memory-per-node` | -- | `query.max-total-memory` | 杀查询 |
| Spark SQL | `spark.executor.memory` | -- | -- | 溢出磁盘 / OOM |
| Teradata | TASM `ResponseTime` | -- | TASM `MemoryLimit` | 延迟/中止 |
| Greenplum | Resource Group `MEMORY_LIMIT` | `statement_mem` | `gp_vmem_protect_limit` | 排队 / OOM |
| CockroachDB | `--max-sql-memory` | -- | `--cache` + `--max-sql-memory` | 杀查询 |
| TiDB | `tidb_mem_quota_query` | -- | `mem-quota-query` | 杀查询 / 溢出 |
| OceanBase | `MEMORY_SIZE` (per Unit) | -- | Tenant memory | 错误 |
| YugabyteDB | 继承 PG | -- | -- | -- |
| SingleStore | Resource Pool `MEMORY_PERCENTAGE` | -- | `maximum_memory` | 溢出 / 错误 |
| Vertica | Pool `MEMORYSIZE` / `MAXMEMORYSIZE` | -- | `memorysize` | 排队 |
| Impala | `MEM_LIMIT` | -- | Pool `max-mem-resources` | 拒绝 |
| StarRocks | Resource Group `MEM_LIMIT` | -- | `mem_limit` | 杀查询 |
| Doris | Workload Group `memory_limit` | -- | -- | 杀查询 |
| Exasol | -- | -- | 自动按 cluster | 中止 |
| SAP HANA | `STATEMENT_MEMORY_LIMIT` | -- | `global_allocation_limit` | 中止 |
| Azure Synapse | `REQUEST_MAX_MEMORY_GRANT_PERCENT` | -- | -- | 排队 |
| Yellowbrick | WLM `memoryRequiredMB` | -- | -- | 中止 |
| Databend | -- | -- | `query_max_memory_usage` | 中止 |
| Firebolt | 按 Engine 自动 | -- | -- | 自动 |

### 3. I/O 带宽限制

| 引擎 | I/O 带宽限制 | 配置粒度 | 实现方式 | 版本 |
|------|------------|---------|---------|------|
| PostgreSQL | -- (依赖 cgroup blkio) | -- | 外部 | -- |
| MySQL | -- (依赖 cgroup blkio) | -- | 外部 | -- |
| Oracle | 是 | Consumer Group | I/O calibration + DBRM | 11g+ |
| SQL Server | 是 (`MIN_IOPS_PER_VOLUME` / `MAX_IOPS_PER_VOLUME`) | Resource Pool | 内部限速 | 2014+ |
| DB2 | 是 | Service Class | `IOPRIORITY` + cgroup | 9.5+ |
| Snowflake | -- (隐式按 warehouse) | -- | -- | GA |
| BigQuery | -- (隐式) | -- | -- | GA |
| Redshift | 是 | WLM Queue | I/O 调度 | GA |
| ClickHouse | 是 | Profile | `max_network_bandwidth` / 磁盘配额 | 22.x+ |
| Trino | -- | -- | 依赖底层存储 | -- |
| Spark SQL | -- | -- | 依赖底层存储 | -- |
| Greenplum | 是 | Resource Group | `MEMORY_SPILL_RATIO` + cgroup blkio | 5.0+ |
| CockroachDB | 是 | Admission Control | LSM L0 文件数自适应限速 | 22.1+ |
| TiDB | 是 | Resource Group | RU 包含读写 IOPS | 7.1+ |
| OceanBase | 是 | Resource Unit | `IOPS_WEIGHT` / `MAX_IOPS` / `MIN_IOPS` | 4.x+ |
| SingleStore | -- | -- | 依赖底层存储 | -- |
| Vertica | 是 | Resource Pool | `RUNTIMEPRIORITY` + 内部调度 | 早期 |
| Impala | -- | -- | 依赖 HDFS/S3 | -- |
| StarRocks | -- | -- | 依赖底层存储 | -- |
| Doris | -- | -- | 依赖底层存储 | -- |
| SAP HANA | 是 | Workload Class | `STATEMENT_DISK_LIMIT` (临时空间) | SPS09+ |
| Yellowbrick | 是 | WLM Profile | `ioPriority` | GA |
| Azure Synapse | 部分 | Resource Class | I/O 调度 | GA |

> I/O 带宽是最难做的隔离维度——传统数据库通常依赖 cgroup `blkio` 子系统或 OS `ionice`，仅少数引擎（Oracle, SQL Server, OceanBase, TiDB）实现了内部 I/O 限速。

### 4. 并发查询限制

| 引擎 | 并发查询上限 | 配置参数 | 默认值 |
|------|------------|---------|-------|
| PostgreSQL | `max_connections` | 100 | 全局 |
| MySQL | `max_connections` | 151 | 全局 |
| Oracle | Resource Manager `ACTIVE_SESS_POOL_P1` | 无默认 | 按 Consumer Group |
| SQL Server | Resource Governor `GROUP_MAX_REQUESTS` | 0 (无限) | 按 Workload Group |
| DB2 | WLM `CONCURRENTDBCOORDACTIVITIES` | 无默认 | 按 Service Class |
| Snowflake | `MAX_CONCURRENCY_LEVEL` | 8 | 按 Warehouse |
| BigQuery | slot 隐式 | -- | 按 Reservation |
| Redshift | `query_concurrency` | 5 | 按 WLM Queue |
| ClickHouse | `max_concurrent_queries` / `max_concurrent_queries_for_user` | 100 / 0 | 全局 + 用户 |
| Trino | `maxRunning` / `maxQueued` | 100 / 1000 | 按 Resource Group |
| Spark SQL | FAIR `minShare` | -- | 按 Pool |
| Hive | LLAP queue size | -- | 按 Resource Plan |
| Teradata | TASM `MaxConcurrency` | 按配置 | 按 Workload |
| Greenplum | Resource Group `CONCURRENCY` | 20 | 按 Group |
| CockroachDB | `kv.admission.sql_kv_response.enabled` | true | 自适应 |
| TiDB | `tidb_max_connections` + RU 限流 | 0 (无限) | 按 Resource Group |
| OceanBase | Tenant `max_session_num` | 按配置 | 按 Tenant |
| SingleStore | Pool `QUEUE_DEPTH` / `MAX_CONCURRENCY` | -- | 按 Pool |
| Vertica | Pool `MAXCONCURRENCY` | -- | 按 Pool |
| Impala | Pool `max-requests` | -- | 按 Pool |
| StarRocks | Resource Group `CONCURRENCY_LIMIT` | -- | 按 Group |
| Doris | Workload Group `max_concurrency` | -- | 按 Group |
| Exasol | Priority Group 并发 | -- | 按 Group |
| SAP HANA | Workload Class `TOTAL_STATEMENT_THREAD_LIMIT` | -- | 按 Class |
| Azure Synapse | Resource Class 并发 | -- | 按 Class |
| Yellowbrick | WLM `maxConcurrency` | -- | 按 Profile |
| Databend | `max_concurrent_queries` | -- | 按 Warehouse |

### 5. cgroups 集成

| 引擎 | cgroups v1 感知 | cgroups v2 感知 | 用法 |
|------|---------------|---------------|------|
| PostgreSQL | 部分 | 部分 (16+) | systemd 切片 + 容器配置 |
| MySQL | 部分 | 部分 (8.0.32+) | systemd 切片 |
| MariaDB | 部分 | 部分 | systemd 切片 |
| Oracle | 是 | 是 (19c+) | Database Resource Manager 上层 |
| SQL Server (Linux) | 是 | 是 (2019+) | Linux 容器配置 |
| DB2 (Linux) | 是 | 是 | WLM Service Class 关联 cgroup |
| ClickHouse | 是 | 是 (22.x+) | 自动检测 + 配置 |
| Trino | 是 | 是 | JVM `-XX:ActiveProcessorCount` |
| Spark | 是 | 是 (3.3+) | YARN/K8s cgroup 集成 |
| Greenplum | 是 (核心) | 是 (6.20+) | Resource Group 直接挂载 cgroup |
| CockroachDB | 是 | 是 | 自动读取 limit 计算缓存 |
| TiDB | 是 | 是 | 自动检测可用 CPU/内存 |
| OceanBase | 是 | 是 | Tenant 隔离层使用 cgroup |
| Doris | 是 | 是 | Workload Group 挂载 cgroup |
| StarRocks | 是 | 是 (3.x+) | Resource Group 挂载 cgroup |
| YugabyteDB | 部分 | 部分 | 容器化部署 |
| Vertica | 是 | 部分 | 通过 systemd |
| Impala | 是 | 是 | YARN cgroup |
| SAP HANA | 是 | 部分 | systemd 集成 |

### 6. 容器感知 (Container-aware Memory & CPU)

| 引擎 | 容器内存感知 | 容器 CPU 感知 | OOM 行为 |
|------|------------|------------|---------|
| PostgreSQL | 部分 | 部分 | OOM killer 杀 backend |
| MySQL | 部分 | 部分 | OOM killer 杀 mysqld |
| Oracle | 是 (19c+) | 是 | 自适应 SGA |
| SQL Server (Linux) | 是 | 是 | 内部限速 |
| ClickHouse | 是 (22.x+) | 是 | 抛异常 |
| Trino | 是 (JVM) | 是 (JVM 8u191+) | OOM Kill 协调器 |
| Spark | 是 | 是 | Executor 重启 |
| CockroachDB | 是 | 是 | 自动读取 cgroup limit |
| TiDB | 是 | 是 | 自动读取 cgroup limit |
| OceanBase | 是 | 是 | Tenant 内 OOM |
| Greenplum | 是 | 是 | 杀查询 |
| Doris | 是 | 是 | 杀查询 |
| StarRocks | 是 | 是 | 杀查询 |
| YugabyteDB | 是 | 是 | 自动读取 |

> **容器感知的陷阱**：早期版本的数据库在容器中读取 `/proc/meminfo` 看到的是宿主机总内存，导致 SGA/buffer pool 配置过大，容器超过 cgroup `memory.limit_in_bytes` 后被 OOM killer 杀死。CockroachDB、TiDB、Oracle 19c+ 都修复了这个问题，自动读取 `/sys/fs/cgroup/memory/memory.limit_in_bytes` 作为可用内存。

## 各引擎资源隔离详解

### Oracle Resource Manager + Database Resource Manager (8i+)

Oracle 是数据库内置资源隔离的鼻祖。早在 Oracle 8i (1999) 即推出了 Database Resource Manager (DBRM)，提供 CPU/会话/I/O 的多维度隔离。

**核心概念**：

```
Resource Plan (资源计划)
  └─ Plan Directives (计划指令)
       └─ Consumer Group (消费者组) ← 用户会话被映射到此
```

**完整配置示例**：

```sql
BEGIN
  -- 1. 创建 Pending Area
  DBMS_RESOURCE_MANAGER.CREATE_PENDING_AREA();

  -- 2. 创建 Consumer Groups
  DBMS_RESOURCE_MANAGER.CREATE_CONSUMER_GROUP(
    consumer_group => 'OLTP_GROUP',
    comment        => '在线交易组');

  DBMS_RESOURCE_MANAGER.CREATE_CONSUMER_GROUP(
    consumer_group => 'BATCH_GROUP',
    comment        => '批处理组');

  DBMS_RESOURCE_MANAGER.CREATE_CONSUMER_GROUP(
    consumer_group => 'REPORT_GROUP',
    comment        => '报表组');

  -- 3. 创建 Plan
  DBMS_RESOURCE_MANAGER.CREATE_PLAN(
    plan    => 'DAYTIME_PLAN',
    comment => '白天工作负载计划');

  -- 4. 创建 Plan Directives
  DBMS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(
    plan                  => 'DAYTIME_PLAN',
    group_or_subplan      => 'OLTP_GROUP',
    mgmt_p1               => 60,            -- CPU 60%
    parallel_degree_limit_p1 => 4,          -- 最多并行度 4
    active_sess_pool_p1   => 50,            -- 50 个活跃会话
    queueing_p1           => 30);           -- 排队最多 30 秒

  DBMS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(
    plan                  => 'DAYTIME_PLAN',
    group_or_subplan      => 'BATCH_GROUP',
    mgmt_p1               => 20,            -- CPU 20%
    parallel_degree_limit_p1 => 16,         -- 高并行度
    max_est_exec_time     => 7200,          -- 估算 > 2h 拒绝
    switch_group          => 'CANCEL_SQL',  -- 超时切换组
    switch_time           => 600,           -- 600 秒后触发
    switch_estimate       => TRUE,
    switch_io_megabytes   => 10240);        -- 读 10GB 后切换

  DBMS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(
    plan                  => 'DAYTIME_PLAN',
    group_or_subplan      => 'REPORT_GROUP',
    mgmt_p1               => 20,            -- CPU 20%
    undo_pool             => 1024);         -- UNDO 1GB

  DBMS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(
    plan                  => 'DAYTIME_PLAN',
    group_or_subplan      => 'OTHER_GROUPS',
    mgmt_p1               => 0);            -- 默认组无 CPU

  -- 5. 验证并提交
  DBMS_RESOURCE_MANAGER.VALIDATE_PENDING_AREA();
  DBMS_RESOURCE_MANAGER.SUBMIT_PENDING_AREA();
END;
/

-- 6. 激活计划
ALTER SYSTEM SET RESOURCE_MANAGER_PLAN = 'DAYTIME_PLAN';
```

**Oracle DBRM 关键指令 (Plan Directive)**：

| 指令 | 含义 |
|------|------|
| `MGMT_P1` ~ `MGMT_P8` | CPU 多级分配（百分比，按层级） |
| `ACTIVE_SESS_POOL_P1` | 同时活跃会话上限 |
| `QUEUEING_P1` | 排队等待超时（秒） |
| `MAX_EST_EXEC_TIME` | 优化器估算执行时间上限 |
| `MAX_IDLE_TIME` | 空闲会话超时（自动 KILL） |
| `MAX_IDLE_BLOCKER_TIME` | 阻塞他人时空闲超时 |
| `PARALLEL_DEGREE_LIMIT_P1` | 最大并行度 |
| `UNDO_POOL` | UNDO 表空间配额（KB） |
| `SWITCH_GROUP` / `SWITCH_TIME` | 运行超时切换 Consumer Group |
| `SWITCH_IO_MEGABYTES` | I/O 超过 N MB 切换组 |
| `SWITCH_ELAPSED_TIME` | 总运行时间超过 N 秒切换组 |

**I/O 隔离 (11g+)**：

```sql
-- 启用 I/O Resource Management
ALTER SYSTEM SET DB_RESOURCE_MANAGER_PLAN = 'DAYTIME_PLAN';

-- 配置 I/O 优先级 (Exadata)
DBMS_RESOURCE_MANAGER.UPDATE_PLAN_DIRECTIVE(
  plan          => 'DAYTIME_PLAN',
  group_or_subplan => 'BATCH_GROUP',
  new_mgmt_p1   => 20,
  new_io_megabytes_per_session => 5000);
```

**会话到 Consumer Group 的映射**：

```sql
-- 按用户名映射
DBMS_RESOURCE_MANAGER.SET_CONSUMER_GROUP_MAPPING(
  attribute => DBMS_RESOURCE_MANAGER.ORACLE_USER,
  value     => 'BATCH_USER',
  consumer_group => 'BATCH_GROUP');

-- 按程序名映射 (优先级高)
DBMS_RESOURCE_MANAGER.SET_CONSUMER_GROUP_MAPPING(
  attribute => DBMS_RESOURCE_MANAGER.MODULE_NAME,
  value     => 'SQL*Plus',
  consumer_group => 'OLTP_GROUP');

-- 按服务名映射
DBMS_RESOURCE_MANAGER.SET_CONSUMER_GROUP_MAPPING(
  attribute => DBMS_RESOURCE_MANAGER.SERVICE_NAME,
  value     => 'reports.example.com',
  consumer_group => 'REPORT_GROUP');
```

**Oracle DBRM 的演进**：

| 版本 | 新特性 |
|------|-------|
| 8i (1999) | 引入 Resource Manager，CPU 隔离 + Active Session Pool |
| 9i | 多级 CPU 分配 (MGMT_P1..P8) |
| 10g | 自适应 (Resource Manager 自动调节) |
| 11g | 引入 Instance Caging (CDB 级 CPU 隔离) + I/O Resource Management (Exadata) |
| 11.2 | Parallel Statement Queuing |
| 12c | Multitenant CDB/PDB 资源隔离 |
| 19c | cgroups v2 自动检测 + 容器感知 |
| 21c | Auto-DOP + Auto Resource Manager |

### SQL Server Resource Governor (2008 EE+)

SQL Server 在 2008 企业版引入 Resource Governor，2014 添加了 I/O 限制：

```sql
-- 1. 创建 Resource Pool
CREATE RESOURCE POOL HighPriorityPool
WITH (
    MIN_CPU_PERCENT = 30,           -- 保证最低 30% CPU
    MAX_CPU_PERCENT = 100,          -- 上限 100%
    CAP_CPU_PERCENT = 80,           -- 硬限 80% (即使空闲不可超)
    MIN_MEMORY_PERCENT = 25,
    MAX_MEMORY_PERCENT = 50,
    MIN_IOPS_PER_VOLUME = 0,        -- 2014+
    MAX_IOPS_PER_VOLUME = 5000,     -- 2014+ I/O 限速
    AFFINITY SCHEDULER = (0 TO 7)   -- 绑定到 0-7 号 CPU
);

-- 2. 创建 Workload Group
CREATE WORKLOAD GROUP ReportingGroup
WITH (
    IMPORTANCE = MEDIUM,
    REQUEST_MAX_MEMORY_GRANT_PERCENT = 25,
    REQUEST_MAX_CPU_TIME_SEC = 300,
    REQUEST_MEMORY_GRANT_TIMEOUT_SEC = 30,
    MAX_DOP = 8,
    GROUP_MAX_REQUESTS = 50         -- 并发上限 50
)
USING HighPriorityPool;

-- 3. 创建分类器函数
CREATE FUNCTION dbo.RGClassifier()
RETURNS SYSNAME
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @grp_name SYSNAME;
    IF (SUSER_SNAME() = 'reporting_user')
        SET @grp_name = 'ReportingGroup';
    ELSE IF (APP_NAME() LIKE 'PowerBI%')
        SET @grp_name = 'ReportingGroup';
    ELSE
        SET @grp_name = 'default';
    RETURN @grp_name;
END;
GO

-- 4. 启用并应用
ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = dbo.RGClassifier);
ALTER RESOURCE GOVERNOR RECONFIGURE;
```

**SQL Server Resource Governor 限制能力对比**：

| 能力 | 引入版本 |
|------|---------|
| CPU 百分比 (`MAX_CPU_PERCENT`) | 2008 EE |
| 内存百分比 (`MAX_MEMORY_PERCENT`) | 2008 EE |
| 优先级 (`IMPORTANCE`) | 2008 EE |
| 并发上限 (`GROUP_MAX_REQUESTS`) | 2008 EE |
| 单查询内存授予 (`REQUEST_MAX_MEMORY_GRANT_PERCENT`) | 2008 EE |
| MAX DOP | 2008 EE |
| `CAP_CPU_PERCENT` (硬上限) | 2012 EE |
| I/O 限速 (`MIN_IOPS_PER_VOLUME`/`MAX_IOPS_PER_VOLUME`) | 2014 EE |
| AFFINITY SCHEDULER | 2008 EE |
| 内存授予最小百分比 (`REQUEST_MIN_MEMORY_GRANT_PERCENT`) | 2019 EE |

**关键差异**：
- `MAX_CPU_PERCENT`：CPU 紧张时的上限（空闲时可超）
- `CAP_CPU_PERCENT`：CPU 硬上限（即使空闲不可超）→ 适合多租户场景的硬隔离

### PostgreSQL：无原生资源隔离 (依赖 cgroups)

PostgreSQL 是"少数依赖外部资源隔离的主流引擎"——它本身没有 Resource Manager / Workload Group 的概念，所有资源隔离必须通过 OS 层 cgroups 或外部工具。

**PostgreSQL 内置的有限资源限制**：

```sql
-- 1. 单查询内存
ALTER ROLE analyst SET work_mem = '256MB';      -- 排序/哈希内存
ALTER ROLE analyst SET maintenance_work_mem = '1GB';
ALTER ROLE analyst SET temp_buffers = '64MB';

-- 2. 临时文件配额 (PG 9.2+)
ALTER ROLE analyst SET temp_file_limit = '10GB'; -- 临时文件超过 10GB 拒绝

-- 3. 语句超时
ALTER ROLE analyst SET statement_timeout = '300s';
ALTER ROLE analyst SET lock_timeout = '30s';
ALTER ROLE analyst SET idle_in_transaction_session_timeout = '60s';

-- 4. 连接数限制 (按用户)
ALTER ROLE analyst CONNECTION LIMIT 10;

-- 5. 数据库级连接数
ALTER DATABASE production CONNECTION LIMIT 100;
```

**PostgreSQL + cgroups (典型部署)**：

```bash
# 通过 systemd 切片限制资源
sudo systemctl edit postgresql.service

# 添加：
[Service]
CPUQuota=400%               # 4 核 (cgroups v2)
MemoryMax=32G               # 32GB 内存上限
IOReadBandwidthMax=/dev/sda 500M   # 读带宽 500 MB/s
IOWriteBandwidthMax=/dev/sda 200M  # 写带宽 200 MB/s
TasksMax=8192               # 进程数上限
LimitNOFILE=65536
```

**PostgreSQL 多用户资源隔离的常见模式**：

```bash
# 方案 1：每用户一个 PgBouncer 实例 + 独立 cgroup
# pg_user_a → pgbouncer:6432 (cgroup A: 4 CPU, 16G)
# pg_user_b → pgbouncer:6433 (cgroup B: 8 CPU, 32G)

# 方案 2：单 PG 实例 + per-role 设置 + 应用层隔离
# 局限：无法限制 CPU 实时使用，只能限制 work_mem 等参数

# 方案 3：使用扩展 (有限替代)
# pg_resgroup (Greenplum 派生) - 仅 Greenplum 支持
# pg_qualstats / pg_stat_kcache - 只是观测
```

> PostgreSQL 没有真正的运行时资源隔离是社区争议长达 20 年的话题，主因是其多进程架构（每连接一个 backend 进程）使内置资源隔离实现复杂——PG 14/15/16 引入了一些渐进式改进 (`work_mem` 按 partition 分配等)，但完整的 Resource Manager 仍未到来。

### Greenplum: pg_resgroup (PG 衍生方案)

Greenplum 在 PostgreSQL 8.x 衍生时实现了 `Resource Group`（前身是 `Resource Queue`），是 PG 系数据库中最完整的内置资源隔离方案：

```sql
-- 创建 Resource Group (Greenplum 5.0+)
CREATE RESOURCE GROUP rg_etl WITH (
  CPU_RATE_LIMIT = 30,         -- CPU 30% 软限
  CPU_HARD_QUOTA_LIMIT = 50,   -- CPU 50% 硬限 (cgroups)
  CPUSET = '0-7',              -- 绑定到 0-7 核
  MEMORY_LIMIT = 25,           -- 内存 25%
  MEMORY_SHARED_QUOTA = 50,    -- 共享内存池占比
  MEMORY_SPILL_RATIO = 20,     -- 溢出磁盘阈值
  CONCURRENCY = 10,            -- 并发上限 10
  IO_LIMIT = 'tablespace_default:rbps=200,wbps=100'  -- I/O 限速 (6.21+)
);

-- 创建 Resource Group 给特定角色
CREATE ROLE etl_user WITH LOGIN RESOURCE GROUP rg_etl;
ALTER ROLE existing_user RESOURCE GROUP rg_etl;

-- 查看资源组使用情况
SELECT * FROM gp_toolkit.gp_resgroup_status;
SELECT * FROM gp_toolkit.gp_resgroup_status_per_segment;
```

**Greenplum Resource Group 与 cgroups 的集成**：

```bash
# Greenplum 5.0+ 的 Resource Group 直接挂载到 cgroups v1
# /sys/fs/cgroup/cpu/gpdb/<resgroup_id>/cpu.cfs_quota_us
# /sys/fs/cgroup/memory/gpdb/<resgroup_id>/memory.limit_in_bytes
# /sys/fs/cgroup/cpuset/gpdb/<resgroup_id>/cpuset.cpus

# 启用 Resource Group (默认是 Resource Queue)
gpconfig -c gp_resource_manager -v group
gpstop -ar
```

### TiDB Resource Control (7.1+) — RU 模型深入解读

TiDB 在 7.1 版本 (2023) 引入了基于 **RU (Request Unit)** 的资源控制模型，是分布式数据库中最新的资源隔离实现之一。RU 模型借鉴了 CockroachDB、Cosmos DB 的"统一资源单位"思想。

**RU 的定义**：

```
1 RU =
  1/2 vCore second  +  4 KB read I/O  +  1 KB write I/O  +  network bytes

具体换算（TiDB 7.1 默认）:
  1 个 KV CPU 毫秒 = 1/3 RU
  1 个 SQL CPU 毫秒 = 1 RU
  64 KB 读 I/O = 1 RU
  4 KB 写 I/O = 1 RU
  1 KB 写入网络 = 1 RU

所以一个查询消耗的 RU 是其 CPU + I/O + 网络的加权和
```

**配置 RU 资源组**：

```sql
-- 创建 Resource Group (TiDB 7.1+)
CREATE RESOURCE GROUP rg_etl
  RU_PER_SEC = 5000               -- 每秒 5000 RU
  PRIORITY = MEDIUM               -- HIGH / MEDIUM / LOW
  BURSTABLE = TRUE;               -- 允许突发使用未占用的 RU

CREATE RESOURCE GROUP rg_oltp
  RU_PER_SEC = 10000
  PRIORITY = HIGH
  BURSTABLE = FALSE;              -- 严格不超

-- 给用户绑定资源组
CREATE USER etl_user RESOURCE GROUP rg_etl;
ALTER USER existing_user RESOURCE GROUP rg_etl;

-- 查询会话级别绑定
SET RESOURCE GROUP rg_etl;
SELECT /*+ RESOURCE_GROUP(rg_etl) */ * FROM big_table;

-- 查看 RU 消耗
SELECT * FROM information_schema.resource_groups;
SELECT * FROM mysql.tidb_runaway_queries;
```

**RU 的限速机制**：

```
TiDB 使用令牌桶 (Token Bucket) 算法:
  - 每个 Resource Group 有一个令牌桶，容量 = RU_PER_SEC
  - 请求消耗令牌；令牌不足时等待
  - BURSTABLE = TRUE 时可以"借用"全局空闲 RU
  - PRIORITY 影响令牌分配的优先级

PD (Placement Driver) 负责全局 RU 协调:
  - 每个 TiKV 节点报告本地消耗
  - PD 计算全局可用，分配下一时间窗口的 token
  - 支持跨节点的统一限速
```

**TiDB Resource Control 的演进**：

| 版本 | 新特性 |
|------|-------|
| 6.5 (2022) | 实验性资源管控（无 RU 模型） |
| 7.1 (2023) | GA：RU 模型 + Resource Group + Token Bucket |
| 7.2 | 后台任务资源调度 (auto-analyze, lightning) |
| 7.3 | Runaway Query 自动管理（基于 RU 阈值） |
| 7.4 | 优先级调度增强 |
| 7.5 | 跨集群 RU 配额 (Serverless) |
| 7.6 | 自动 RU 估算 + Recommendations |

**RU 模型 vs 传统模型对比**：

| 维度 | 传统模型 (CPU%/Mem%) | RU 模型 |
|------|--------------------|---------|
| 抽象层次 | 物理资源直接暴露 | 统一抽象单位 |
| 多维度统一 | 需分别配置 CPU/内存/I/O | 一个数字囊括 |
| 跨节点协调 | 复杂 | PD 全局协调 |
| 计费友好 | 难（需汇总多种资源） | 直接按 RU 计费 |
| 用户认知 | 直观（CPU 30%） | 需要学习换算 |
| Serverless 适合 | 不太适合 | 完美契合 |

### CockroachDB Admission Control + Resource Control (22.1+, 2022)

CockroachDB 的资源隔离分两部分：

1. **Admission Control (准入控制)** — KV 层自适应限速 (21.2 引入, 22.1 GA)
2. **Resource Control** — 多租户资源隔离 (Cluster Virtualization, 23.1+)

**Admission Control** 的核心思路是 **基于队列长度的自适应限速**：

```
观测信号:
  - L0 子层级文件数 (LSM 健康度)
  - Goroutine 调度延迟
  - 锁等待队列
  - 内存使用率

控制器:
  - 高优先级查询 (PRIORITY = HIGH)
  - 中优先级 (NORMAL) - 默认
  - 低优先级 (LOW) - 后台任务
  - 用户低 (USER_LOW) - 批处理

机制: 基于 PID 控制器动态调节 KV slot 数
```

**配置示例**：

```sql
-- 全局开启 Admission Control (22.1+ 默认开启)
SET CLUSTER SETTING admission.kv.enabled = true;
SET CLUSTER SETTING admission.sql_kv_response.enabled = true;
SET CLUSTER SETTING admission.sql_sql_response.enabled = true;

-- 设置 SQL 内存配额
SET CLUSTER SETTING sql.distsql.temp_storage.workmem = '256MiB';
SET CLUSTER SETTING server.max_open_transactions_per_gateway = 1000;

-- 23.1+ 多租户隔离
CREATE TENANT 'analytics';
ALTER TENANT 'analytics' GRANT CAPABILITY ALL;
-- (具体 RU 配额通过 cloud control plane 设置)
```

**CockroachDB Admission Control 的特点**：

- **自适应** — 不需要用户配置阈值，根据 LSM 健康度自动调节
- **优先级感知** — 高优先级查询不会被后台任务挤占
- **多副本一致性** — 跨节点的全局协调（每个 store 独立判断）
- **细粒度** — 不仅限速 SQL，还限速底层 KV 写入、Compaction、Backfill

### Snowflake: Warehouse 级隔离

Snowflake 的资源隔离模型与传统数据库截然不同——它通过 **独立计算节点 (Virtual Warehouse)** 实现物理级别的隔离：

```sql
-- 创建独立 Warehouse (T-shirt 尺寸)
CREATE WAREHOUSE etl_wh
  WAREHOUSE_SIZE = 'X-LARGE'           -- 16 节点
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  MIN_CLUSTER_COUNT = 1
  MAX_CLUSTER_COUNT = 10               -- Multi-cluster
  SCALING_POLICY = 'STANDARD';

CREATE WAREHOUSE bi_wh
  WAREHOUSE_SIZE = 'MEDIUM'             -- 4 节点
  AUTO_SUSPEND = 300;

-- 给不同角色绑定不同 Warehouse
GRANT USAGE ON WAREHOUSE etl_wh TO ROLE etl_role;
GRANT USAGE ON WAREHOUSE bi_wh TO ROLE bi_role;

-- 单 Warehouse 内的并发限制
ALTER WAREHOUSE etl_wh SET MAX_CONCURRENCY_LEVEL = 8;
ALTER WAREHOUSE etl_wh SET STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = 300;
ALTER WAREHOUSE etl_wh SET STATEMENT_TIMEOUT_IN_SECONDS = 1800;
```

**Snowflake 资源隔离的特点**：

- **物理隔离** — 每个 Warehouse 是独立的计算集群，CPU/内存/网络物理分离
- **无邻居噪音** — 不同 Warehouse 完全无干扰
- **无需 cgroups** — 因为没有共享主机
- **快速启停** — 按秒计费，自动暂停时不消耗成本
- **缺乏细粒度** — 同一 Warehouse 内的不同查询无法精细隔离

**Snowflake 的"资源监视器" (Resource Monitor)**：

```sql
-- 创建资源监视器（用于 credit 限额）
CREATE RESOURCE MONITOR rm_etl WITH
  CREDIT_QUOTA = 1000               -- 每月 1000 credits
  FREQUENCY = MONTHLY
  START_TIMESTAMP = CURRENT_TIMESTAMP
  TRIGGERS
    ON 75 PERCENT DO NOTIFY
    ON 90 PERCENT DO SUSPEND
    ON 100 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE etl_wh SET RESOURCE_MONITOR = rm_etl;
```

### BigQuery: Slot 模型

BigQuery 的资源单位是 **slot**——一个 slot 大致等于"一个 CPU 上一秒的处理能力"。

```bash
# BigQuery 通过 Reservation 隔离 slots（命令行/API 配置，非 SQL DDL）
bq mk --reservation \
  --project_id=my-project \
  --location=US \
  --slots=500 \
  --ignore_idle_slots=false \
  prod_reservation

bq mk --assignment \
  --reservation_id=projects/my-project/locations/US/reservations/prod_reservation \
  --job_type=QUERY \
  --assignee_id=projects/my-project \
  --assignee_type=PROJECT
```

**BigQuery Slot 的特点**：

- **统一单位** — 所有查询消耗 slots，无需关心 CPU/内存细节
- **自动调度** — Dremel 引擎按 stage 动态分配 slots
- **跨项目共享** — Reservation 可以分配给多个项目
- **空闲 slots 共享** — `ignore_idle_slots=false` 时其他 reservation 可以使用
- **无 cgroups** — 完全 serverless

### ClickHouse: user_quotas + max_memory_usage

ClickHouse 提供基于配置文件的多维度资源隔离：

```xml
<!-- /etc/clickhouse-server/users.xml -->
<users>
    <analyst>
        <profile>analyst_profile</profile>
        <quota>analyst_quota</quota>
        <networks>
            <ip>::/0</ip>
        </networks>
    </analyst>
</users>

<profiles>
    <analyst_profile>
        <max_memory_usage>10000000000</max_memory_usage>          <!-- 10GB 单查询 -->
        <max_memory_usage_for_user>20000000000</max_memory_usage_for_user>  <!-- 20GB 用户总和 -->
        <max_threads>4</max_threads>                               <!-- 最大线程数 -->
        <max_execution_time>300</max_execution_time>               <!-- 5 分钟超时 -->
        <max_rows_to_read>1000000000</max_rows_to_read>            <!-- 10 亿行上限 -->
        <max_bytes_to_read>1099511627776</max_bytes_to_read>       <!-- 1TB -->
        <max_concurrent_queries_for_user>10</max_concurrent_queries_for_user>
        <priority>5</priority>                                      <!-- nice 值 -->
        <readonly>0</readonly>
    </analyst_profile>
</profiles>

<quotas>
    <analyst_quota>
        <interval>
            <duration>3600</duration>
            <queries>1000</queries>
            <errors>10</errors>
            <result_rows>10000000</result_rows>
            <read_rows>1000000000</read_rows>
            <execution_time>3600</execution_time>
        </interval>
    </analyst_quota>
</quotas>
```

**ClickHouse 24.x+ 的 Workload 概念**：

```sql
-- 24.x+ 引入 CREATE WORKLOAD
CREATE WORKLOAD etl SETTINGS
  max_memory_usage = '32G',
  max_threads = 16,
  max_concurrent_queries = 20;

CREATE RESOURCE my_disk_io TYPE DISK SETTINGS
  max_bandwidth = '500MB/s';

-- 关联 Workload 与 Resource
ALTER WORKLOAD etl ATTACH RESOURCE my_disk_io;
```

**ClickHouse 的 cgroups 集成**：

```xml
<!-- ClickHouse 22.x+ 自动检测 cgroup -->
<clickhouse>
    <max_server_memory_usage_to_ram_ratio>0.9</max_server_memory_usage_to_ram_ratio>
    <!-- 自动读取 /sys/fs/cgroup/memory/memory.limit_in_bytes -->
</clickhouse>
```

## TiDB Resource Control RU 模型深度解析

RU (Request Unit) 是 TiDB 7.1 引入的革命性概念。下面深入解读其设计：

### 为什么需要 RU 模型

传统资源隔离使用 CPU% / Memory% / IOPS 三个独立维度，存在以下问题：

```
传统多维度配置的痛点:
  1. 用户难以决策: "给租户 A 多少 CPU%? 多少内存?" 
  2. 资源不平衡: CPU 配额耗尽但内存还有 → 浪费
  3. 跨节点协调难: 每个节点独立限速，全局不一致
  4. 计费不直观: 一次查询消耗了 CPU+内存+I/O，怎么累加?
```

RU 模型的目标是**用一个数字描述一切**：

```
RU 公式 (TiDB 7.1 默认):
  RU(query) = α × CPU_ms + β × IO_KB + γ × Network_KB

  其中:
    α (KV CPU): 1 ms = 1/3 RU
    α (SQL CPU): 1 ms = 1 RU  
    β (Read I/O): 64 KB = 1 RU
    β (Write I/O): 4 KB = 1 RU
    γ (Network): 1 KB = 1 RU

实际查询消耗:
  SELECT * FROM big_table WHERE id IN (1,2,3);
    KV CPU: 5 ms → 1.67 RU
    SQL CPU: 2 ms → 2 RU
    Read I/O: 256 KB → 4 RU
    Network: 50 KB → 50 RU
    Total: ~58 RU
```

### RU 的实现原理

```
+---------------------+
|  PD (Placement Driver)  |
|  - 全局 RU 协调器     |
|  - Token Bucket 服务  |
+---------------------+
         ↑
    定期汇报消耗
         ↓
+---------+---------+-----+
|         |         |     |
| TiDB-1  | TiDB-2  | TiDB-3 |
| (本地  | (本地   | (本地   |
| 令牌桶) | 令牌桶)  | 令牌桶)  |
+---------+---------+-----+

工作流程:
  1. 查询启动 → 估算预期 RU
  2. 从本地 token bucket 扣除
  3. 不足时向 PD 请求补充
  4. PD 全局检查是否超过 RU_PER_SEC
  5. 超过则限速 (slow down) 或拒绝
```

### Runaway Query Management

TiDB 7.3+ 基于 RU 的 Runaway Query 自动管理：

```sql
-- 设置自动管理失控查询
ALTER RESOURCE GROUP rg_oltp
  QUERY_LIMIT = (
    EXEC_ELAPSED = '30s',         -- 执行时间 > 30s
    ACTION = KILL                 -- 直接 KILL
  );

ALTER RESOURCE GROUP rg_etl
  QUERY_LIMIT = (
    EXEC_ELAPSED = '5m',
    ACTION = COOLDOWN,            -- 进入冷却（限速）
    WATCH = SIMILAR DURATION '1h' -- 1 小时内类似查询自动 KILL
  );

-- 查看被识别的 runaway queries
SELECT * FROM mysql.tidb_runaway_queries;
SELECT * FROM mysql.tidb_runaway_watch;
```

### RU 估算与定价

```sql
-- TiDB 7.6+ 提供 RU 估算
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 100;
-- 输出包含: estRows, actRows, ru, cpuTime, ioBytes, ...

-- 资源使用统计
SELECT 
  resource_group,
  SUM(ru_consumption) AS total_ru,
  AVG(ru_consumption) AS avg_ru
FROM information_schema.cluster_resource_groups_runaway_history
WHERE time > NOW() - INTERVAL 1 HOUR
GROUP BY resource_group;
```

## Oracle Resource Manager 指令深度解读

Oracle DBRM 的指令系统是数据库资源管理的经典之作，理解它有助于理解所有现代 RM 系统的设计思想。

### 多级 CPU 分配 (MGMT_P1...P8)

```sql
-- 8 级 CPU 优先级
DBMS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(
  plan       => 'MULTI_LEVEL_PLAN',
  group_or_subplan => 'CRITICAL_GROUP',
  mgmt_p1    => 80,        -- L1: 80% 首先满足
  mgmt_p2    => 70,        -- L2: 剩余的 70%
  mgmt_p3    => 60);       -- L3: 再剩余的 60%

-- 工作机制:
-- 第 1 级: 各组按 P1 比例分配 CPU
-- 如果某组没用满，剩余转入第 2 级
-- 在第 2 级按 P2 比例分配
-- 以此类推...
```

### Active Session Pool + Queueing

```sql
-- 同时活跃会话上限 + 排队
DBMS_RESOURCE_MANAGER.UPDATE_PLAN_DIRECTIVE(
  plan       => 'PLAN1',
  group_or_subplan => 'BATCH_GROUP',
  new_active_sess_pool_p1 => 4,    -- 最多 4 个并发
  new_queueing_p1 => 600);          -- 排队超 600 秒报错

-- 第 5 个查询提交时:
-- 1. 检测到 ACTIVE_SESS_POOL_P1 已满
-- 2. 进入排队状态 (V$RSRC_SESSION_INFO)
-- 3. 600 秒内有空闲槽 → 执行
-- 4. 600 秒后无空闲 → ORA-00040 (active time limit)
```

### Switch Group (执行特征切换)

```sql
-- 长查询自动切换到低优先级组
DBMS_RESOURCE_MANAGER.UPDATE_PLAN_DIRECTIVE(
  plan       => 'PLAN1',
  group_or_subplan => 'OLTP_GROUP',
  new_switch_group => 'BATCH_GROUP',
  new_switch_time  => 300,           -- 执行超 300 秒
  new_switch_io_megabytes => 1024,   -- 或读写超 1GB
  new_switch_estimate => TRUE);      -- 根据估算切换

-- OLTP 用户跑 SELECT * FROM 1B_rows:
-- 1. 进入 OLTP_GROUP，享受高优先级
-- 2. 5 分钟后超过 SWITCH_TIME → 切到 BATCH_GROUP
-- 3. 后续执行用 BATCH_GROUP 的 CPU/IO 配额
-- 4. 完成后切回 OLTP_GROUP
```

### Parallel Statement Queuing

```sql
-- 控制并行查询的并发度
DBMS_RESOURCE_MANAGER.UPDATE_PLAN_DIRECTIVE(
  plan       => 'PLAN1',
  group_or_subplan => 'BATCH_GROUP',
  new_parallel_degree_limit_p1 => 16,    -- 单查询并行度 ≤ 16
  new_parallel_target_percentage => 50,   -- 总并行度 ≤ 50% (DOP)
  new_parallel_queue_timeout => 300);     -- 排队超时
```

### I/O Resource Management (Exadata)

```sql
-- Exadata 11g+ 的 I/O 管理
DBMS_RESOURCE_MANAGER.UPDATE_PLAN_DIRECTIVE(
  plan       => 'PLAN1',
  group_or_subplan => 'BATCH_GROUP',
  new_mgmt_p1 => 20,                       -- CPU 20%
  new_io_megabytes_per_session => 5000);   -- 每会话最多 5GB I/O

-- Exadata Cell Server 端配置
-- IORM_PLAN: 限制存储节点的 I/O 优先级
ALTER IORMPLAN dbplan = (
  'OLTP_DB' = (level=1, allocation=70),
  'BATCH_DB' = (level=1, allocation=30));
```

## cgroups + Linux 集成深度解析

理解 cgroups 是理解所有 Linux 数据库资源隔离的基础。

### cgroups 历史

```
cgroups v1 (2007):
  - Linux 2.6.24 引入
  - 多子系统独立挂载: cpu, memory, blkio, net_cls, ...
  - 缺点: 子系统之间难以协调
  
cgroups v2 (2014):
  - Linux 4.5 GA (3.x 实验)
  - 统一层级 (Unified Hierarchy)
  - 简化 API
  - I/O 控制器更强 (io.max, io.latency)
  - 资源压力监控 (PSI: Pressure Stall Information)
```

### cgroups v1 关键控制器

```bash
# CPU 子系统
/sys/fs/cgroup/cpu/postgres/
├── cpu.cfs_quota_us          # CPU 配额 (微秒) -1 = 无限
├── cpu.cfs_period_us         # 调度周期 (默认 100000 = 100ms)
├── cpu.shares                # CPU 权重 (默认 1024)
└── cpuset.cpus               # 可使用的 CPU 核

# Memory 子系统
/sys/fs/cgroup/memory/postgres/
├── memory.limit_in_bytes     # 内存上限
├── memory.soft_limit_in_bytes # 软限制
├── memory.swappiness         # swap 倾向 0-100
├── memory.oom_control        # 是否禁用 OOM killer
└── memory.usage_in_bytes     # 当前使用 (只读)

# Block I/O 子系统
/sys/fs/cgroup/blkio/postgres/
├── blkio.throttle.read_bps_device    # 读带宽 字节/秒
├── blkio.throttle.write_bps_device   # 写带宽
├── blkio.throttle.read_iops_device   # 读 IOPS
├── blkio.throttle.write_iops_device  # 写 IOPS
└── blkio.weight                       # I/O 权重
```

### cgroups v2 统一接口

```bash
# v2 单层级管理
/sys/fs/cgroup/postgres.slice/
├── cpu.max                   # "100000 100000" (quota period)
├── cpu.weight                # 100 (default)
├── cpuset.cpus               # 0-7
├── memory.max                # 32G
├── memory.high               # 30G (软限)
├── memory.low                # 16G (保证)
├── io.max                    # "8:0 rbps=500M wbps=200M"
├── io.weight                 # 100
└── cgroup.procs              # 当前 PID 列表

# 启用 controllers
echo "+cpu +memory +io" > /sys/fs/cgroup/cgroup.subtree_control
```

### systemd 与数据库的集成

```ini
# /etc/systemd/system/postgresql.service.d/limits.conf
[Service]
# CPU
CPUQuota=400%               # 4 核
CPUWeight=80                # cgroups v2 权重 (1-10000)

# Memory
MemoryMax=32G               # 硬限
MemoryHigh=30G              # 软限
MemorySwapMax=0             # 禁用 swap

# I/O
IOReadBandwidthMax=/dev/sda 500M
IOWriteBandwidthMax=/dev/sda 200M
IOWeight=80

# 进程数
TasksMax=8192
LimitNOFILE=65536

# OOM 优先级
OOMScoreAdjust=-500         # 不容易被 OOM killer 杀
```

### 容器中数据库的内存检测

数据库进程在容器中需要正确读取 cgroup 限制：

```c
// 错误的方式 (PostgreSQL 14- / MySQL 8.0.32-)
unsigned long total_mem = sysconf(_SC_PHYS_PAGES) * sysconf(_SC_PAGESIZE);
// 在容器中读到的是宿主机内存！

// 正确的方式 (CockroachDB / TiDB / Oracle 19c+)
char buf[256];
// cgroups v1
FILE *f = fopen("/sys/fs/cgroup/memory/memory.limit_in_bytes", "r");
// cgroups v2
// FILE *f = fopen("/sys/fs/cgroup/memory.max", "r");
fscanf(f, "%s", buf);
unsigned long container_mem = parse_size(buf);

// 然后用 min(host_mem, container_mem) 作为可用内存
```

### Pressure Stall Information (PSI)

cgroups v2 引入的 PSI 是数据库自适应限速的金矿：

```bash
# 系统级 PSI
cat /proc/pressure/cpu
# some avg10=0.34 avg60=0.23 avg300=0.15 total=12345
# full avg10=0.05 avg60=0.03 avg300=0.02 total=678

cat /proc/pressure/memory
# some avg10=8.92 avg60=4.30 avg300=2.10 ...

cat /proc/pressure/io
# some avg10=15.32 ...

# 解读:
# some: 至少一个任务被阻塞的时间百分比
# full: 所有任务都被阻塞的时间百分比
# avg10/60/300: 10/60/300 秒滑动平均
```

CockroachDB 22.1+ 的 Admission Control 利用 PSI 信号自动调节准入率。

### Kubernetes 资源限制

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  template:
    spec:
      containers:
      - name: postgres
        image: postgres:16
        resources:
          requests:
            cpu: "4"           # cpuset 4 cores guaranteed
            memory: "16Gi"
          limits:
            cpu: "8"           # cpu.max 8 cores hard limit
            memory: "32Gi"     # memory.max 32GB
            ephemeral-storage: "100Gi"
        # K8s 1.31+ 支持 IO 限制
        # io.max via runc/containerd
```

**Kubernetes QoS 类**：

| QoS Class | 条件 | OOM 行为 |
|-----------|------|---------|
| Guaranteed | requests == limits | 最后被 OOM 杀 |
| Burstable | requests < limits | 中间 |
| BestEffort | 无 requests/limits | 第一个被 OOM 杀 |

### 数据库工作负载的 cgroups 最佳实践

```bash
# 推荐配置 (Linux + cgroups v2 + systemd):

[postgresql.slice]
CPUWeight=80                 # 不用 CPUQuota，用 weight 让出空闲
MemoryHigh=28G               # 软限：先告警/swap
MemoryMax=32G                # 硬限：超过被 OOM
IOWeight=80                  # I/O 权重而非硬限
TasksMax=8192                # 防止 fork bomb
OOMScoreAdjust=-500          # 数据库优先级高

[batch_etl.slice]
CPUWeight=20                 # 让 OLTP 优先用 CPU
MemoryMax=8G
IOWeight=20
OOMScoreAdjust=200           # 优先被杀
```

## OS 层资源隔离工具对比

### Linux 工具链

| 工具 | 功能 | 数据库适用度 |
|------|------|------------|
| cgroups v1/v2 | CPU/内存/I/O 隔离 | 高（所有数据库） |
| nice / renice | CPU 调度优先级 | 中（粗粒度） |
| ionice | I/O 调度优先级 | 中 |
| taskset | CPU 亲和性 | 高 |
| numactl | NUMA 亲和性 | 高（大内存数据库） |
| ulimit | 进程资源限制 | 低（仅基础） |
| systemd slices | cgroups + 服务管理 | 高 |
| Docker / Containerd | 容器隔离 | 高 |
| Kubernetes | 编排 + cgroups | 高 |
| LXC / LXD | 完整容器 | 中 |

### 其他平台

| 平台 | 隔离机制 |
|------|---------|
| Windows | Job Objects + Resource Manager |
| macOS | launchd + cpulimit (有限) |
| FreeBSD | rctl + jail |
| AIX | WLM Manager + WPAR |
| Solaris | Zones + Resource Pools + FSS |

## 资源隔离的常见陷阱

### 陷阱 1: cgroup memory.max 设置过低

```
症状: 数据库频繁 OOM Kill 重启
原因: 
  1. shared_buffers / SGA 配置 + work_mem × 连接数 + 临时文件 > memory.max
  2. 内核 page cache 也算入 memory.max (cgroups v1)

解决:
  - 留出 30% buffer
  - 监控 memory.usage_in_bytes 和 memory.max_usage_in_bytes
  - cgroups v2 用 memory.high (软限) 而非 memory.max
```

### 陷阱 2: CPU quota 导致延迟突增

```
症状: P99 延迟从 50ms 变成 500ms
原因:
  - cpu.cfs_quota_us 在周期内用完后被 throttle
  - 短查询命中 throttle 边界 → 等待下个 period

解决:
  - 用 cpu.weight 而非 cpu.cfs_quota_us
  - 缩短 cpu.cfs_period_us (从 100ms → 10ms)
  - 增加 quota buffer
```

### 陷阱 3: blkio 限速导致死锁

```
症状: WAL fsync 超时，事务无法提交
原因:
  - blkio 限速 + WAL 写入 + Checkpoint 抢同一带宽
  - I/O 队列填满，新 I/O 等待

解决:
  - 不要对数据库的 WAL/redo 设备做严格限速
  - 用 IOWeight 而非 io.max
  - 区分数据卷与日志卷
```

### 陷阱 4: 容器内不读 cgroup limits

```
症状: 数据库配置 buffer pool = 100GB，但容器只有 32GB → OOM Kill

解决:
  - 老版本: 在容器启动脚本中读 cgroup 后启动数据库
    BUFFER_POOL_SIZE=$(echo "$(cat /sys/fs/cgroup/memory.max) * 0.4 / 1024 / 1024" | bc)
  - 新版本: 用支持 cgroup 自检测的引擎 (CockroachDB, TiDB, Oracle 19c+)
```

### 陷阱 5: NUMA 跨节点开销

```
症状: 内存大但 CPU 利用率低，QPS 上不去
原因: NUMA 不亲和导致跨节点内存访问

解决:
  numactl --cpunodebind=0 --membind=0 postgres ...
  
  或在 systemd:
  [Service]
  CPUAffinity=0-15      # 只用第一个 NUMA 节点
  NUMAPolicy=bind
  NUMAMask=0
```

## 设计争议

### 软限 vs 硬限

```
软限 (soft limit):
  - 资源紧张时按比例限制
  - 资源空闲时可超过
  - 优点: 资源利用率高
  - 缺点: 多租户隔离不彻底

硬限 (hard limit):
  - 永远不能超过
  - 优点: 严格隔离
  - 缺点: 资源浪费 (即使空闲也不能用)

经验:
  - SaaS 多租户: 用硬限 (公平 + 计费)
  - 内部工作负载: 用软限 (利用率)
  - 关键 OLTP: 用 reservations + 软限
```

### CPU 隔离 vs 容器编排

```
有 Resource Manager 的引擎 (Oracle, SQL Server, ClickHouse):
  - 内部细粒度隔离 (per-query, per-role)
  - 单实例多租户

无内置的引擎 (PostgreSQL):
  - 必须靠容器/cgroup 隔离
  - 多实例多租户 (每租户一个 PG)

业界趋势:
  - 云数仓 (Snowflake) → 物理隔离 (Virtual Warehouse)
  - 分布式数据库 (TiDB, CRDB) → 内部自适应 (RU, Admission Control)
  - 传统 RDBMS (Oracle) → DBRM + Multitenant CDB/PDB
```

### Resource Group 的粒度

```
按角色 (User Role):
  - 简单, 与认证系统集成
  - 缺点: 同一角色不同业务无法区分

按会话 (Session):
  - 更灵活
  - 配置复杂

按查询特征:
  - SQL Server 的 Classifier Function
  - Oracle 的 Mapping Rules
  - 最强大但最难管理

业界趋势: 多维度结合 (角色 + 会话 + 查询特征)
```

### 自适应 vs 静态配置

```
静态配置 (Oracle DBRM, Resource Governor):
  - 用户预先设定百分比/绝对值
  - 优点: 可预测, 易理解
  - 缺点: 调参困难, 无法应对突变

自适应 (CockroachDB Admission Control):
  - 根据 LSM 健康度/PSI 自动调节
  - 优点: 无需用户调参
  - 缺点: 黑盒, 难以预测
  
混合 (TiDB Resource Control):
  - 用户配置 RU_PER_SEC, BURSTABLE
  - 系统在配额内自适应
```

## 关键发现

### 1. 资源隔离是数据库领域中碎片化最严重的子领域

每个引擎都有自己的概念体系：

```
Oracle:    Plan → Consumer Group → Plan Directive
SQL Server: Resource Pool → Workload Group → Classifier
DB2:       Service Class → Workload → Threshold
Snowflake: Warehouse → Resource Monitor
BigQuery:  Reservation → Assignment → Slot
TiDB:      Resource Group → RU → Token Bucket
CRDB:      Admission Control → KV Slot → Priority
ClickHouse: Profile → Quota → Workload
```

### 2. PostgreSQL 与 MySQL 是"反例"

主流 OSS RDBMS 至今没有真正的内置资源隔离：

- **PostgreSQL**：完全依赖 cgroups + PgBouncer，社区争论 20 年
- **MySQL 8.0**：有 Resource Group 但仅限 CPU 亲和性 + 优先级
- **MariaDB**：完全无内置

这反映了 OSS 数据库的生态——隔离被外包给容器/K8s 而非数据库本身。

### 3. 云原生数仓走"物理隔离"路线

Snowflake / BigQuery / Databricks 都是通过独立计算节点实现隔离：

```
传统模型: 单一集群 + 内部 Resource Manager
云原生模型: 多个独立计算单元 (Warehouse / Engine / Cluster) + 物理隔离
```

优点：无邻居噪音，按使用计费，自动扩缩容。
缺点：成本可能更高，跨 Warehouse 的查询需要复制数据。

### 4. RU 模型是分布式数据库的新趋势

TiDB 7.1 (2023) 开始的 RU 模型代表了新一代隔离：

```
统一抽象: 一个数字描述 CPU + 内存 + I/O + 网络
全局协调: PD 跨节点统一分配
计费友好: 直接用 RU 计费
适合 Serverless: 自动按使用量分配资源
```

未来可能影响 CockroachDB、OceanBase、PolarDB 等其他分布式数据库。

### 5. cgroups v2 + PSI 改变了自适应隔离

cgroups v2 (2014 GA, 真正普及在 2020+) 引入的 PSI (Pressure Stall Information) 让数据库可以读取细粒度的"资源压力"信号：

```
传统: 阈值告警 (CPU > 80% 限流)
新一代: PSI 反馈 (CPU 阻塞率 > 5% 限流)
```

CockroachDB 22.1 已经开始使用，未来更多引擎会跟进。

### 6. 容器感知是必须能力

主流引擎在 2018-2022 年间陆续修复了"容器内读宿主机内存"的问题：

| 引擎 | 修复版本 | 年份 |
|------|---------|------|
| Oracle | 19c | 2019 |
| SQL Server (Linux) | 2017 | 2017 |
| MySQL | 8.0.32 | 2023 |
| PostgreSQL | 部分 16 | 2023 |
| ClickHouse | 22.x | 2022 |
| CockroachDB | 早期 | 2017 |
| TiDB | 早期 | 2018 |

未修复的版本在 K8s 上需要应用层 wrapper。

### 7. I/O 隔离最弱

CPU 隔离普及度高，内存隔离普及度中，**I/O 隔离普及度最低**。原因：

```
CPU: cgroup cpu 控制器成熟，所有引擎都能用
Memory: cgroup memory 控制器成熟，但 page cache 处理复杂
I/O: blkio 控制器在多设备/多队列下不准，io.max 也有局限
     大部分引擎依赖底层存储 (S3, EBS) 的 IOPS 配额
```

仅 Oracle (Exadata)、SQL Server 2014+、OceanBase、TiDB 实现了内部 I/O 限速。

### 8. 多租户场景的最佳实践

```
小规模 (< 10 租户):
  - 单实例 + Resource Manager (Oracle / SQL Server / TiDB)
  
中规模 (10-100 租户):
  - 容器化 + cgroup 硬隔离 (PostgreSQL / MySQL)
  - 或 Multitenant CDB/PDB (Oracle)
  
大规模 (> 100 租户):
  - 物理多集群 (Snowflake Warehouse)
  - K8s + Operator + 自动化
  - Serverless (Aurora Serverless / TiDB Serverless / Cosmos DB)
```

### 9. 隔离的代价：性能开销

```
cgroups v1: ~2-5% 性能开销 (基础)
cgroups v2: ~1-3% (优化)
KVM/容器: ~3-7%
裸金属 + Resource Manager: ~5-10% (Oracle DBRM)
完全物理隔离 (Snowflake): ~0% 但成本高
```

强隔离需要付出性能代价，工程权衡是核心。

### 10. 引擎选型建议

| 场景 | 推荐 | 原因 |
|------|------|------|
| 严苛 OLTP 多租户 | Oracle DBRM + CDB/PDB | 成熟、细粒度 |
| 大规模分析 | Snowflake / BigQuery | 物理隔离、Serverless |
| 混合负载 + 自适应 | CockroachDB / TiDB | RU 模型 / Admission Control |
| 实时 OLAP | ClickHouse + cgroup | 低延迟 + 简单 |
| 严格资源配额 | SQL Server Resource Governor | I/O + CPU + 内存全维度 |
| 容器化 OSS | PostgreSQL + cgroup v2 | K8s 集成成熟 |
| Serverless | TiDB / Cosmos DB / Aurora SLS | RU 模型 |
| 极致简单 | DuckDB / SQLite | 嵌入式无隔离需求 |

## 参考资料

- Oracle: [Database Resource Manager](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-resources-with-database-resource-manager.html)
- Oracle: [DBMS_RESOURCE_MANAGER](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_RESOURCE_MANAGER.html)
- SQL Server: [Resource Governor](https://learn.microsoft.com/en-us/sql/relational-databases/resource-governor/resource-governor)
- SQL Server: [CREATE WORKLOAD GROUP](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-workload-group-transact-sql)
- PostgreSQL: [Resource Consumption](https://www.postgresql.org/docs/current/runtime-config-resource.html)
- DB2: [Workload Management](https://www.ibm.com/docs/en/db2/11.5?topic=management-introduction-db2-workload)
- Greenplum: [Resource Groups](https://docs.greenplum.org/6-23/admin_guide/workload_mgmt_resgroups.html)
- TiDB: [Resource Control](https://docs.pingcap.com/tidb/stable/tidb-resource-control)
- TiDB: [Resource Control Deep Dive](https://www.pingcap.com/blog/tidb-resource-control-architecture/)
- CockroachDB: [Admission Control](https://www.cockroachlabs.com/docs/stable/admission-control.html)
- CockroachDB: [Multi-tenancy and Cluster Virtualization](https://www.cockroachlabs.com/blog/admission-control-in-cockroachdb/)
- Snowflake: [Warehouses](https://docs.snowflake.com/en/user-guide/warehouses)
- BigQuery: [Reservations and Slots](https://cloud.google.com/bigquery/docs/reservations-intro)
- ClickHouse: [Quotas and Settings Profiles](https://clickhouse.com/docs/en/operations/quotas)
- Linux: [Control Groups v2](https://www.kernel.org/doc/Documentation/admin-guide/cgroup-v2.rst)
- Linux: [Pressure Stall Information](https://www.kernel.org/doc/Documentation/accounting/psi.rst)
- systemd: [Resource Control Unit Settings](https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html)
- Kubernetes: [Resource Management for Pods](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- Vertica: [Resource Pool Architecture](https://www.vertica.com/docs/latest/HTML/Content/Authoring/AdministratorsGuide/ResourceManager/ResourcePoolArchitecture.htm)
- OceanBase: [Tenant Resource Management](https://www.oceanbase.com/docs/common-oceanbase-database-cn-1000000000034082)
