# 资源管理与工作负载管理 (Resource Management & WLM)

数据库不是只服务一个用户。当 ETL 批处理、BI 分析、数据科学探索、实时仪表盘和在线交易共享同一个集群时，谁应该获得多少 CPU、多少内存、多少 I/O？谁可以排队等待，谁应该被立即拒绝？这些问题的答案就是工作负载管理 (Workload Management, WLM) ——它决定了一个数据仓库是"昂贵的玩具"还是"生产可用的平台"。

## 为什么资源管理是混合负载数据库的生命线

单一负载下，资源管理几乎可以忽略：MySQL 单库 OLTP、SQLite 嵌入式应用都不需要复杂的资源调度。但现代数据平台的现实是：

1. **混合负载并发**：一个 1TB 的报表查询可能与上千个秒级仪表盘查询同时运行
2. **多租户隔离**：SaaS 厂商在同一集群上托管成百上千的客户
3. **成本可预测性**：无界的查询会在云数仓上烧光预算（一个糟糕的 BigQuery 查询可能扫描 PB 级数据）
4. **SLA 保障**：交互式查询必须在毫秒级响应，而长批处理必须最终完成
5. **失控查询防护**：笛卡儿积、缺失谓词、错误的 JOIN 都可能拖垮整个集群

资源管理通常包含以下维度：

- **资源分配**：CPU、内存、I/O 配额按用户/角色/会话/查询类型分配
- **准入控制**：何时接受新查询、何时排队、何时拒绝
- **优先级调度**：高优先级查询抢占低优先级查询的资源
- **配额执行**：达到限制后是杀死、降级还是仅记录
- **分类器**：基于"谁、做什么、在何种上下文"将查询路由到不同资源池

## 没有 SQL 标准

ISO SQL 标准从未定义资源管理语法。这是数据库管理领域中最为破碎的领域之一：每个引擎都有自己的语法、概念模型和实现机制。原因有三：

1. **资源是物理概念**：标准只关心逻辑数据模型，不涉及 CPU 调度算法
2. **架构差异巨大**：单机 vs MPP vs 云原生（计算存储分离）的资源单位完全不同
3. **历史包袱**：Oracle Resource Manager (1999) 早于任何标准化尝试

因此本文不存在"标准语法"一节——所有内容都是厂商特定的。

## 支持矩阵

### 1. 资源组 / 工作负载类 / 资源池

| 引擎 | 支持 | 概念名称 | 创建语法 | 版本 |
|------|------|---------|---------|------|
| PostgreSQL | -- | 无原生支持 (依赖 cgroups) | -- | -- |
| MySQL | 部分 | Resource Group | `CREATE RESOURCE GROUP` | 8.0+ |
| MariaDB | -- | -- | -- | -- |
| SQLite | -- | -- | -- | -- |
| Oracle | 是 | Consumer Group | `DBMS_RESOURCE_MANAGER` | 8i+ |
| SQL Server | 是 | Workload Group | `CREATE WORKLOAD GROUP` | 2008 Ent+ |
| DB2 | 是 | Workload / Service Class | `CREATE WORKLOAD` | 9.5+ |
| Snowflake | 是 | Warehouse + Resource Monitor | `CREATE WAREHOUSE` | GA |
| BigQuery | 是 | Reservation / Assignment | 无 SQL DDL (bq CLI / API / Terraform) | GA |
| Redshift | 是 | WLM Queue / Auto WLM | 参数组 / `wlm_json_configuration` | GA |
| DuckDB | -- | (单进程内嵌) | -- | -- |
| ClickHouse | 是 | Profile / Quota / Workload | `CREATE WORKLOAD` | 24.x+ |
| Trino | 是 | Resource Group | `etc/resource-groups.json` | 早期 |
| Presto | 是 | Resource Group | `etc/resource-groups.json` | 0.153+ |
| Spark SQL | 是 | Fair Scheduler Pool | `spark.scheduler.pool` | 1.0+ |
| Hive | 是 | Workload Management | `CREATE RESOURCE PLAN` | 3.0+ |
| Flink SQL | 部分 | Slot Sharing Group | API 配置 | 1.x+ |
| Databricks | 是 | SQL Warehouse | UI / API | GA |
| Teradata | 是 | TASM Workload | Viewpoint UI / TASM | V2R6+ |
| Greenplum | 是 | Resource Group / Resource Queue | `CREATE RESOURCE GROUP` | 5.0+ |
| CockroachDB | 部分 | Admission Control (内置) | 集群设置 | 21.2+ |
| TiDB | 是 | Resource Group | `CREATE RESOURCE GROUP` | 7.1+ |
| OceanBase | 是 | Resource Unit / Resource Pool | `CREATE RESOURCE UNIT` | 3.x+ |
| YugabyteDB | -- | (继承 PG，无原生 WLM) | -- | -- |
| SingleStore | 是 | Workload Management Resource Pool | `CREATE RESOURCE POOL` | 7.0+ |
| Vertica | 是 | Resource Pool | `CREATE RESOURCE POOL` | 早期 |
| Impala | 是 | Resource Pool (admission control) | fair-scheduler.xml | 1.3+ |
| StarRocks | 是 | Resource Group | `CREATE RESOURCE GROUP` | 2.2+ |
| Doris | 是 | Resource Group / Workload Group | `CREATE WORKLOAD GROUP` | 2.0+ |
| MonetDB | -- | -- | -- | -- |
| CrateDB | -- | -- | -- | -- |
| TimescaleDB | -- | (继承 PG) | -- | -- |
| QuestDB | -- | -- | -- | -- |
| Exasol | 是 | Priority Group | `CREATE PRIORITY GROUP` | 6.0+ |
| SAP HANA | 是 | Workload Class | `CREATE WORKLOAD CLASS` | SPS09+ |
| Informix | 是 | VP Class / MGM | onmode 命令 | 早期 |
| Firebird | -- | -- | -- | -- |
| H2 | -- | -- | -- | -- |
| HSQLDB | -- | -- | -- | -- |
| Derby | -- | -- | -- | -- |
| Amazon Athena | 是 | Workgroup | API/Console only (no SQL DDL) | GA |
| Azure Synapse | 是 | Workload Group / Resource Class | `CREATE WORKLOAD GROUP` | GA |
| Google Spanner | -- | (内部自动管理) | -- | -- |
| Materialize | 是 | Cluster | `CREATE CLUSTER` | GA |
| RisingWave | -- | -- | -- | -- |
| InfluxDB (SQL) | -- | -- | -- | -- |
| Databend | 是 | Warehouse | `CREATE WAREHOUSE` | GA |
| Yellowbrick | 是 | WLM Profile / Pool | `CREATE WLM PROFILE` | GA |
| Firebolt | 是 | Engine | `CREATE ENGINE` | GA |

> 统计：约 32 个引擎提供原生工作负载管理能力，约 17 个引擎依赖外部机制（cgroups、容器配额）或完全没有。

### 2. CPU / 内存配额

| 引擎 | CPU 配额 | 内存配额 | 配额粒度 | 配额类型 |
|------|---------|---------|---------|---------|
| Oracle | 是 (CPU shares + max %) | 是 (PGA + SGA) | Consumer Group | 比例 + 绝对值 |
| SQL Server | 是 (`MAX_CPU_PERCENT`) | 是 (`MAX_MEMORY_PERCENT`) | Workload Group | 百分比 |
| DB2 | 是 (`AGENT PRIORITY`) | 是 (`SORTHEAP`) | Service Class | 优先级 + 字节 |
| Snowflake | 是 (Warehouse 大小 X-Small...6X-Large) | 隐式（按 size） | Warehouse | T-shirt 尺寸 |
| BigQuery | 是 (slots) | 隐式 | Reservation | slot 数量 |
| Redshift | 是 (`query_concurrency`) | 是 (`memory_percent_to_use`) | WLM Queue | 百分比 |
| ClickHouse | 是 (`max_threads`) | 是 (`max_memory_usage_for_user`) | Profile | 绝对值 |
| Trino | 是 (`hardConcurrencyLimit`) | 是 (`softMemoryLimit`) | Resource Group | 百分比 + 字节 |
| Hive | 是 (CPU shares) | 是 (`query_parallelism`) | Pool | 百分比 |
| Teradata (TASM) | 是 (CPU weight) | 是 | Workload | 权重 + 限制 |
| Greenplum | 是 (`CPU_RATE_LIMIT`) | 是 (`MEMORY_LIMIT`) | Resource Group | 百分比 |
| TiDB | 是 (RU/秒) | 间接 (RU 模型) | Resource Group | Request Unit |
| OceanBase | 是 (`MIN_CPU` / `MAX_CPU`) | 是 (`MEMORY_SIZE`) | Resource Unit | 核数 + 字节 |
| Vertica | 是 (`PLANNEDCONCURRENCY`) | 是 (`MAXMEMORYSIZE`) | Resource Pool | 字节 + 并发 |
| SingleStore | 是 (`SOFT_CPU_LIMIT_PERCENTAGE`) | 是 (`MEMORY_PERCENTAGE`) | Resource Pool | 百分比 |
| Impala | 部分（仅准入） | 是 (`max_memory`) | Pool | 字节 |
| StarRocks | 是 (`cpu_core_limit`) | 是 (`mem_limit`) | Resource Group | 核数 + 百分比 |
| Doris | 是 (`cpu_share`) | 是 (`memory_limit`) | Workload Group | 权重 + 百分比 |
| Exasol | 是 (priority weight) | 是 (`QUERY_TIMEOUT`) | Priority Group | 权重 |
| SAP HANA | 是 (`STATEMENT MEMORY LIMIT`) | 是 (`TOTAL STATEMENT MEMORY LIMIT`) | Workload Class | GB |
| Azure Synapse | 是 (`MIN_PERCENTAGE_RESOURCE`) | 是 (`CAP_PERCENTAGE_RESOURCE`) | Workload Group | 百分比 |
| Yellowbrick | 是 (`MAXCONCURRENCY`) | 是 (`MAXSPILL`) | WLM Profile | 字节 + 并发 |
| Materialize | 是 (Cluster Replica size) | 隐式 | Cluster | 尺寸 |

### 3. 查询优先级 / 准入控制

| 引擎 | 优先级 | 准入控制 | 抢占 |
|------|--------|---------|------|
| PostgreSQL | -- | -- | -- |
| MySQL | `THREAD_PRIORITY` (8.0) | -- | -- |
| Oracle | 是 (CPU emphasis) | 是 (queueing) | 是 |
| SQL Server | 是 (`IMPORTANCE`) | 是 | 协作式 |
| DB2 | 是 (`SERVICE CLASS PRIORITY`) | 是 (Threshold) | 是 |
| Snowflake | 自动 (warehouse 隔离) | 自动 (queueing) | -- |
| BigQuery | 是 (`INTERACTIVE`/`BATCH`) | 是 | -- |
| Redshift | 是 (`query_priority`) | 是 (Auto WLM) | 是 |
| Trino | 是 (`schedulingWeight`) | 是 | -- |
| Hive | 是 | 是 (LLAP) | 是 |
| Teradata | 是 (5 级 + 子级) | 是 | 是（最强大）|
| Vertica | 是 (`PRIORITY`) | 是 | 是 |
| SingleStore | 是 (`QUERY_TIMEOUT`) | 是 | -- |
| Impala | 部分 | 是 (admission daemon) | -- |
| StarRocks | 是 (`type`: short query/long query) | 是 | -- |
| Doris | 是 (`priority`) | 是 | -- |
| Greenplum | 是 (`CPU_RATE_LIMIT`) | 是 | -- |
| Exasol | 是 (weight) | 是 | -- |
| SAP HANA | 是 (`PRIORITY`) | 是 | -- |
| Azure Synapse | 是 (`IMPORTANCE`) | 是 | 是 |
| TiDB | 是 (`PRIORITY` HIGH/LOW) | 是 | -- |
| OceanBase | 是 (`MAX_CONCURRENT`) | 是 | -- |
| ClickHouse | 是 (`priority` 设置) | 是 (queue) | -- |
| CockroachDB | 是 (Admission control + tenant fairness) | 是 (内置) | 是 |
| Yellowbrick | 是 (`PRIORITY`) | 是 | -- |

### 4. 队列与并发限制

| 引擎 | 最大并发 | 队列长度 | 队列超时 |
|------|---------|---------|---------|
| Oracle | `ACTIVE_SESS_POOL_P1` | `QUEUEING_P1` | `MAX_EST_EXEC_TIME` |
| SQL Server | `GROUP_MAX_REQUESTS` | 隐式 | `REQUEST_MAX_CPU_TIME_SEC` |
| Snowflake | `MAX_CONCURRENCY_LEVEL` | 自动 | `STATEMENT_QUEUED_TIMEOUT_IN_SECONDS` |
| BigQuery | 100 (默认) | 隐式 | -- |
| Redshift | `query_concurrency` (1-50) | 200 (auto) | `max_queue_wait_time` |
| Trino | `hardConcurrencyLimit` | `maxQueued` | -- |
| Hive | `query_parallelism` | -- | -- |
| Teradata | per-workload + per-user | per-workload | per-workload |
| Vertica | `MAXCONCURRENCY` | `QUEUETIMEOUT` | 是 |
| Greenplum | `CONCURRENCY` | 是 | 是 |
| Impala | `max_requests` | `max_queued` | `queue_wait_timeout_ms` |
| SingleStore | `QUERY_QUEUE_LIMIT` | 是 | `QUEUE_TIMEOUT` |
| StarRocks | `concurrency_limit` | -- | -- |
| Doris | `max_concurrency` | `max_queue_size` | `queue_timeout` |
| ClickHouse | `max_concurrent_queries_for_user` | -- | -- |
| Exasol | per-priority-group | 是 | 是 |
| SAP HANA | `STATEMENT THREAD LIMIT` | -- | -- |
| Azure Synapse | `REQUEST_MAX_RESOURCE_GRANT_PERCENT` | 是 | `QUERY_EXECUTION_TIMEOUT_SEC` |
| Yellowbrick | `MAXCONCURRENCY` | `MAXROWSPOOL` | 是 |
| TiDB | RU 限速 | -- | -- |
| OceanBase | `MAX_CONCURRENT` | -- | -- |

### 5. 查询超时

| 引擎 | 语法 | 单位 | 作用域 |
|------|------|------|--------|
| PostgreSQL | `SET statement_timeout = '30s'` | ms | 会话/全局 |
| MySQL | `SET max_execution_time = 30000` | ms | 会话（仅 SELECT）|
| MariaDB | `SET max_statement_time = 30` | 秒（小数）| 会话/全局 |
| SQLite | -- (应用层超时) | -- | -- |
| Oracle | `RESOURCE_LIMIT` + `MAX_EST_EXEC_TIME` | 秒 | profile/group |
| SQL Server | `SET LOCK_TIMEOUT` / `query_governor_cost_limit` | ms / 单位 | 会话/服务器 |
| DB2 | `ACTIVITYTOTALTIME` 阈值 | 秒 | service class |
| Snowflake | `STATEMENT_TIMEOUT_IN_SECONDS` | 秒 | 账户/用户/会话/仓库 |
| BigQuery | `--job_timeout` (CLI) / `jobTimeoutMs` | ms | job |
| Redshift | `statement_timeout` / `max_execution_time` (QMR) | ms | 会话/WLM |
| DuckDB | -- (中断 API) | -- | -- |
| ClickHouse | `max_execution_time` | 秒 | 设置/profile |
| Trino | `query_max_run_time` | duration | 会话/全局 |
| Presto | `query.max-run-time` | duration | 配置 |
| Spark SQL | `spark.sql.broadcastTimeout` 等 | 秒 | 配置 |
| Hive | `hive.query.timeout.seconds` | 秒 | 配置 |
| Flink SQL | `pipeline.task.cancellation-timeout` | ms | 配置 |
| Databricks | `STATEMENT_TIMEOUT` | 秒 | warehouse |
| Teradata | `QUERY TIMEOUT FOR` | 秒 | TASM workload |
| Greenplum | `statement_timeout` | ms | 会话/角色 |
| CockroachDB | `statement_timeout` | duration | 会话 |
| TiDB | `MAX_EXECUTION_TIME` (hint) | ms | 会话/语句 |
| OceanBase | `OB_QUERY_TIMEOUT` | 微秒 | 会话 |
| YugabyteDB | `statement_timeout` | ms | 会话 |
| SingleStore | `query_timeout` | 秒 | 会话/资源池 |
| Vertica | `RUNTIMECAP` | INTERVAL | 资源池/角色 |
| Impala | `EXEC_TIME_LIMIT_S` | 秒 | 会话/查询 |
| StarRocks | `query_timeout` | 秒 | 会话 |
| Doris | `query_timeout` | 秒 | 会话/工作负载组 |
| MonetDB | `SET SESSION QUERY_TIMEOUT = 30` | 秒 | 会话 |
| CrateDB | `statement_timeout` (会话) | duration | 会话 |
| TimescaleDB | `statement_timeout` | ms | 继承 PG |
| QuestDB | `query.timeout.sec` | 秒 | 配置 |
| Exasol | `QUERY_TIMEOUT` | 秒 | 会话/优先级 |
| SAP HANA | `STATEMENT_TIMEOUT` | 秒 | workload class |
| Informix | `SET LOCK MODE` / `SQL_TRANSACTION_TIMEOUT` | -- | -- |
| Firebird | `SET STATEMENT TIMEOUT` | ms | 会话/语句 |
| H2 | `SET QUERY_TIMEOUT 5000` | ms | 会话 |
| HSQLDB | -- (JDBC `setQueryTimeout`) | -- | -- |
| Derby | -- | -- | -- |
| Amazon Athena | DML 30 分钟硬限制 | -- | workgroup |
| Azure Synapse | `QUERY_EXECUTION_TIMEOUT_SEC` | 秒 | workload group |
| Google Spanner | `OPTIMIZER_STATISTICS_PACKAGE` (无运行时超时) | -- | RPC 级 |
| Materialize | `statement_timeout` | duration | 会话 |
| RisingWave | `statement_timeout` | ms | 会话 |
| InfluxDB (SQL) | -- | -- | -- |
| Databend | `query_timeout` | 秒 | 会话/角色 |
| Yellowbrick | `RUNTIMECAP` | duration | WLM 规则 |
| Firebolt | `--query-timeout` | 秒 | 配置 |

> 统计：超时是覆盖最广的资源管理能力，约 40+ 引擎提供某种形式的查询超时控制。

### 6. 单查询内存限制

| 引擎 | 参数 | 默认值 | 超出行为 |
|------|------|-------|---------|
| PostgreSQL | `work_mem` (per-operator) | 4MB | 溢出到磁盘 |
| MySQL | `tmp_table_size`, `sort_buffer_size` | 16MB | 溢出/错误 |
| Oracle | `PGA_AGGREGATE_LIMIT` | 自动 | 错误 (ORA-04036) |
| SQL Server | `request_memory_grant_percent` | 25% | 等待/降级 |
| DB2 | `SORTHEAP` (per-sort) | 自动 | 溢出 |
| Snowflake | (按 warehouse size 隐式) | -- | 溢出到 SSD |
| BigQuery | (按 slot 自动) | -- | RESOURCES_EXCEEDED |
| Redshift | `query_working_mem` | 队列分配 | 溢出 |
| ClickHouse | `max_memory_usage` | 10GB | 错误 |
| Trino | `query_max_memory_per_node` | 配置 | 杀死 |
| Hive | `hive.tez.container.size` | 配置 | OOM/杀死 |
| Teradata | per-workload memory limit | TASM | 队列/拒绝 |
| Greenplum | `statement_mem` | 125MB | 溢出 |
| Vertica | `PLANNEDCONCURRENCY` 推算 | 资源池 | 等待 |
| SingleStore | `query_memory_percentage` | 25% | 错误 |
| Impala | `MEM_LIMIT` | 配置 | 错误 |
| StarRocks | `exec_mem_limit` | 2GB | 错误 |
| Doris | `exec_mem_limit` | 2GB | 错误 |
| Exasol | per-priority memory | -- | 排队 |
| SAP HANA | `STATEMENT MEMORY LIMIT` | 0 (不限) | 错误 (sql 4 atemp out of mem) |
| Azure Synapse | resource class 隐式 | static/dynamic | 等待/错误 |
| Yellowbrick | `MAXSPILL` | 配置 | 溢出/错误 |
| Materialize | 按 cluster size 隐式 | -- | OOM |
| Databricks | warehouse size 隐式 | -- | 溢出/错误 |

### 7. 临时存储 (溢出) 限制

| 引擎 | 参数 | 备注 |
|------|------|------|
| PostgreSQL | `temp_file_limit` | per-session 字节限制 |
| Oracle | `MAX_DUMP_FILE_SIZE` / TEMP 表空间配额 | 用户级配额 |
| SQL Server | tempdb 配额（隐式）| 通过文件大小 |
| Snowflake | (隐式 SSD spill，按 warehouse) | -- |
| BigQuery | (隐式 shuffle on disk) | -- |
| Redshift | `query_temp_blocks_to_disk` (QMR rule) | 可作为杀死规则 |
| ClickHouse | `max_bytes_before_external_sort` / `_group_by` | 触发外部算法 |
| Trino | `query.max-total-memory-per-node` (含 spill) | -- |
| Greenplum | `gp_workfile_limit_per_query` / `_per_segment` | -- |
| Vertica | TEMP storage location 配额 | -- |
| Impala | `SCRATCH_LIMIT` (per-query spill) | -- |
| Yellowbrick | `MAXSPILL` | 字节 |
| SAP HANA | (内存数据库，少溢出) | -- |
| Azure Synapse | tempdb 配额按 DWU 级别 | -- |
| Doris | `external_sort_bytes_threshold` | -- |
| StarRocks | spill 设置（实验）| 较新版本 |

### 8. 查询成本拒绝 (Pre-execution Rejection)

| 引擎 | 参数 / 机制 | 拒绝条件 |
|------|------------|---------|
| PostgreSQL | -- (无原生) | -- |
| Oracle | `MAX_ESTIMATED_EXEC_TIME` | 优化器估计执行时间过长 |
| SQL Server | `query_governor_cost_limit` | 优化器成本超过阈值 |
| DB2 | `ESTIMATEDSQLCOST` 阈值 | 优化器 timeron 成本 |
| Snowflake | `RESOURCE_MONITOR` (credit cap) | warehouse 累计 credits 超限 |
| BigQuery | `maximumBytesBilled` | 扫描字节数预估 |
| BigQuery | `--maximum_bytes_billed` (CLI/会话) | 预计扫描字节超阈值 |
| Redshift | QMR rule on `query_cpu_time` 等 | 阈值规则 |
| Trino | `query.max-scan-physical-bytes` | 扫描字节数 |
| Hive | `hive.exec.max.dynamic.partitions` 等 | 各种限制 |
| Teradata | TASM "filter" 规则 | 任意条件（最强大）|
| Greenplum | -- | -- |
| Vertica | `EXECUTIONPARALLELISM` | -- |
| SingleStore | `MAX_QUEUE_DEPTH` | -- |
| Impala | `max_query_mem_limit` (admission) | 内存预估 |
| Doris | `query_cost_limit` | -- |
| Exasol | `QUERY_TIMEOUT` (估算)| -- |
| SAP HANA | `MAX_ESTIMATED_MEMORY` | 估算内存 |
| Yellowbrick | WLM 规则 | 多维度 |

### 9. 资源分类器

分类器决定一个新到达的查询应该落入哪个资源池。维度通常包括：

| 引擎 | 用户 | 角色 | 应用名 | 客户端 IP | 查询类型 | 估算成本 | 自定义 |
|------|------|------|-------|---------|---------|---------|--------|
| Oracle | 是 | 是 | 是 (`MODULE`) | 是 | 是 | 是 | PL/SQL 函数 |
| SQL Server | 是 (`SUSER_NAME()`) | 是 | 是 (`APP_NAME()`) | 是 (`HOST_NAME()`) | -- | -- | T-SQL 函数 |
| DB2 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Snowflake | 是 (warehouse 选择) | 是 | -- | -- | -- | -- | -- |
| BigQuery | 是 (assignment to project/folder) | -- | -- | -- | 是 (job_type) | -- | -- |
| Redshift | 是 | 是 | 是 (query group) | -- | -- | 是 | 是 (Lambda UDF) |
| Trino | 是 | 是 | 是 | 是 | 是 | 是 | 选择器规则 |
| Teradata (TASM) | 是 | 是 | 是 | 是 | 是 | 是 (估算)| 是（最丰富的分类器）|
| Vertica | 是 | 是 | -- | -- | -- | -- | -- |
| SingleStore | 是 | 是 | -- | -- | -- | -- | -- |
| Impala | 是 | 是 | 是 (request_pool) | -- | -- | -- | -- |
| StarRocks | 是 | 是 | -- | 是 | -- | 是 | 是 |
| Doris | 是 | 是 | -- | -- | 是 | 是 | 分类器 |
| Greenplum | 是 (角色) | 是 | -- | -- | -- | -- | -- |
| SAP HANA | 是 | 是 | 是 | 是 | 是 | 是 | 是 (语句属性)|
| Azure Synapse | 是 | 是 | 是 | -- | 是 (label) | -- | 是 |
| Yellowbrick | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Hive | 是 | 是 | -- | -- | 是 | -- | -- |

## 各引擎详细语法

### PostgreSQL —— 依赖 OS 与扩展

PostgreSQL 设计哲学坚持"一个进程一个连接"，从未提供原生 WLM。资源管理通过三个层次实现：

```sql
-- 1. 会话/角色级 GUC 参数
ALTER ROLE etl_user SET work_mem = '512MB';
ALTER ROLE etl_user SET statement_timeout = '2h';
ALTER ROLE bi_user  SET statement_timeout = '30s';
ALTER ROLE bi_user  SET temp_file_limit = '10GB';

-- 2. 数据库级
ALTER DATABASE warehouse SET statement_timeout = '1h';

-- 3. 单语句
SET LOCAL work_mem = '1GB';
SET LOCAL statement_timeout = '5min';
```

OS 层：cgroups v2 限制 PostgreSQL 后端进程的 CPU、内存、I/O；systemd `MemoryMax=`、`CPUQuota=` 是常见手段。容器化部署中，Kubernetes resource limits 是事实标准。

第三方扩展：`pg_qualstats`、`pg_wait_sampling`、`pg_top` 用于诊断；商业版 EDB 提供 EDB Resource Manager（CPU/dirty rate 限制）。

### Oracle Database Resource Manager —— 资源管理的鼻祖

Oracle 在 8i (1999) 引入 Database Resource Manager (DBRM)，是关系数据库领域最早的全功能 WLM。

```sql
-- 1. 创建 pending area
BEGIN
  DBMS_RESOURCE_MANAGER.CREATE_PENDING_AREA();
END;
/

-- 2. 创建消费者组
BEGIN
  DBMS_RESOURCE_MANAGER.CREATE_CONSUMER_GROUP(
    consumer_group => 'OLTP_USERS',
    comment        => 'High priority OLTP users');
  DBMS_RESOURCE_MANAGER.CREATE_CONSUMER_GROUP(
    consumer_group => 'BATCH_USERS',
    comment        => 'Long running batch jobs');
END;
/

-- 3. 创建资源计划
BEGIN
  DBMS_RESOURCE_MANAGER.CREATE_PLAN(
    plan    => 'DAYTIME_PLAN',
    comment => 'Plan for business hours');

  DBMS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(
    plan                  => 'DAYTIME_PLAN',
    group_or_subplan      => 'OLTP_USERS',
    comment               => 'OLTP gets 80% CPU',
    mgmt_p1               => 80,
    parallel_degree_limit_p1 => 4,
    active_sess_pool_p1   => 50,
    queueing_p1           => 60,            -- 60s queue timeout
    max_est_exec_time     => 600,           -- reject if estimated > 10 min
    undo_pool             => 1000000);       -- 1GB undo

  DBMS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(
    plan             => 'DAYTIME_PLAN',
    group_or_subplan => 'BATCH_USERS',
    mgmt_p1          => 20);
END;
/

-- 4. 用户映射
BEGIN
  DBMS_RESOURCE_MANAGER.SET_CONSUMER_GROUP_MAPPING(
    attribute => DBMS_RESOURCE_MANAGER.ORACLE_USER,
    value     => 'APP_USER',
    consumer_group => 'OLTP_USERS');
END;
/

-- 5. 提交并激活
BEGIN
  DBMS_RESOURCE_MANAGER.VALIDATE_PENDING_AREA();
  DBMS_RESOURCE_MANAGER.SUBMIT_PENDING_AREA();
END;
/

ALTER SYSTEM SET RESOURCE_MANAGER_PLAN = 'DAYTIME_PLAN';
```

Oracle 的关键特性：
- **多级资源计划**（subplan 嵌套）
- **基于估算执行时间的拒绝**（`MAX_EST_EXEC_TIME`）：在执行前根据优化器估算拒绝
- **CPU 抢占**（`mgmt_p1` ~ `mgmt_p8` 八级优先级）
- **Instance Caging**：通过 `CPU_COUNT` 限制单个实例 CPU 数量
- **基于会话状态的动态切换**（`SWITCH_GROUP`）

### SQL Server Resource Governor (2008 Enterprise+)

```sql
-- 1. 创建资源池
CREATE RESOURCE POOL bi_pool
WITH (MIN_CPU_PERCENT = 20,
      MAX_CPU_PERCENT = 50,
      CAP_CPU_PERCENT = 80,           -- hard cap
      MIN_MEMORY_PERCENT = 10,
      MAX_MEMORY_PERCENT = 30,
      MAX_IOPS_PER_VOLUME = 5000);

-- 2. 创建工作负载组
CREATE WORKLOAD GROUP bi_group
WITH (IMPORTANCE = MEDIUM,
      REQUEST_MAX_MEMORY_GRANT_PERCENT = 25,
      REQUEST_MAX_CPU_TIME_SEC = 600,
      REQUEST_MEMORY_GRANT_TIMEOUT_SEC = 60,
      MAX_DOP = 4,
      GROUP_MAX_REQUESTS = 25)
USING bi_pool;

-- 3. 分类器函数（必须 schemabinding）
CREATE FUNCTION dbo.classify_workload()
RETURNS SYSNAME WITH SCHEMABINDING
AS BEGIN
  DECLARE @grp SYSNAME;
  IF (APP_NAME() LIKE 'PowerBI%')        SET @grp = 'bi_group';
  ELSE IF (SUSER_NAME() = 'etl_account') SET @grp = 'etl_group';
  ELSE                                   SET @grp = 'default';
  RETURN @grp;
END;

ALTER RESOURCE GOVERNOR
  WITH (CLASSIFIER_FUNCTION = dbo.classify_workload);

ALTER RESOURCE GOVERNOR RECONFIGURE;
```

注意事项：分类器函数对每个新连接执行一次，不能太重；Resource Governor 仅 Enterprise 版本可用；外部 (R/Python) 工作负载用 `EXTERNAL RESOURCE POOL`。

### SAP HANA Workload Class

```sql
CREATE WORKLOAD CLASS "REPORTING_WC"
SET 'PRIORITY'                     = '3',
    'STATEMENT MEMORY LIMIT'       = '10',  -- GB
    'STATEMENT THREAD LIMIT'       = '8',
    'TOTAL STATEMENT MEMORY LIMIT' = '50',
    'STATEMENT TIMEOUT'            = '600';

CREATE WORKLOAD MAPPING "REPORTING_MAP"
WORKLOAD CLASS "REPORTING_WC"
SET 'USER NAME'        = 'BI_USER',
    'APPLICATION NAME' = 'Tableau',
    'CLIENT'           = '%';
```

HANA 的特色：内存数据库特性使 `STATEMENT MEMORY LIMIT` 是核心指标；支持基于 `SCHEMA NAME` 的分类。

### Teradata Active System Management (TASM)

TASM 是行业最复杂、最强大的 WLM 系统。它通过 Viewpoint UI 配置（可导出 XML），核心概念：

- **Workload**：一组类似查询的逻辑分组
- **Workload Definition**：定义如何识别这类查询
- **Throttle**：并发限制
- **Filter**：拒绝规则
- **Exception**：执行中触发的动作（降级、杀死、警报）

```sql
-- TASM 的 SQL 接口示例 (通过 DBC.ResUsage)
SELECT WorkloadName, NumQueries, AvgCPUTime, ExceptionCount
FROM DBC.ResUsageSPMA
WHERE TheDate = CURRENT_DATE
ORDER BY NumQueries DESC;
```

TASM 五级调度：Tactical (毫秒级 OLTP) → Priority (高优先级) → Normal → Background → Maintenance。每个 workload 可定义：
- **Initiation rules**：何时启动（队列、拒绝、延迟）
- **Active rules**：执行中检查 CPU/IO/spool 使用
- **Completion rules**：完成后的会计
- **Period changes**：基于时间的策略切换（业务时间 vs 夜间）

TASM 的"独门绝技"：**State-based management**——根据系统健康状态（节点故障、AMP worker task 耗尽）自动切换资源计划。

### Snowflake Warehouses + Resource Monitors

Snowflake 的资源管理与传统数据库截然不同：**计算资源是独立、可独立伸缩、按秒计费的虚拟仓库（virtual warehouse）**。

```sql
-- 1. 创建多个 warehouse 实现工作负载隔离
CREATE WAREHOUSE etl_wh
  WAREHOUSE_SIZE = 'X-LARGE'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  MIN_CLUSTER_COUNT = 1
  MAX_CLUSTER_COUNT = 1
  SCALING_POLICY = 'STANDARD';

CREATE WAREHOUSE bi_wh
  WAREHOUSE_SIZE = 'MEDIUM'
  MIN_CLUSTER_COUNT = 1
  MAX_CLUSTER_COUNT = 5            -- multi-cluster warehouse
  SCALING_POLICY = 'STANDARD'
  AUTO_SUSPEND = 300;

-- 2. 资源监视器：限制 credits 消耗
CREATE RESOURCE MONITOR bi_monitor
  WITH CREDIT_QUOTA = 1000          -- 月度配额
       FREQUENCY = MONTHLY
       START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY
           ON 90 PERCENT DO SUSPEND
           ON 100 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE bi_wh SET RESOURCE_MONITOR = bi_monitor;

-- 3. 用户/角色级超时
ALTER USER bi_user SET STATEMENT_TIMEOUT_IN_SECONDS = 600;
ALTER USER bi_user SET STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = 60;

-- 4. 默认 warehouse
ALTER USER bi_user SET DEFAULT_WAREHOUSE = bi_wh;
```

Snowflake 特点：
- **Warehouse 大小是 T-shirt 尺寸**：X-Small (1 credit/h) → 6X-Large (512 credit/h)，每级翻倍
- **Multi-cluster warehouse**：高并发场景自动横向扩展
- **Resource Monitor**：唯一硬性成本上限手段，触发 SUSPEND 后所有查询失败
- **没有传统意义上的 "queue" 概念**：超出并发，warehouse 自动加 cluster，或 query 排队等待

### BigQuery —— Reservations 与 Slots

BigQuery 的资源单位是 **slot**（虚拟 CPU 单位）。两种计费模式：

1. **On-demand**：按扫描字节计费，slot 由 Google 共享池动态分配
2. **Capacity (Reservations)**：购买固定 slot 容量，可分配到不同 reservation

> **重要**：BigQuery Reservations **没有 SQL DDL**——`CREATE CAPACITY` / `CREATE RESERVATION` / `CREATE ASSIGNMENT` 等语句并不存在。容量提交、预留与分配只能通过 `bq` CLI、`gcloud`、REST API (`bigqueryreservation.googleapis.com`) 或 Terraform (`google_bigquery_reservation` 等资源) 管理。

```bash
# 1) 创建 capacity commitment（一次性购买）
bq mk --project_id=admin --location=US \
  --capacity_commitment --plan=ANNUAL --slots=500

# 2) 创建预留
bq mk --project_id=admin --location=US \
  --reservation --slots=300 --ignore_idle_slots=false \
  analytics_reservation

# 3) 分配项目到预留
bq mk --project_id=admin --location=US \
  --reservation_assignment \
  --reservation_id=admin:US.analytics_reservation \
  --assignee_type=PROJECT --assignee_id=my-project \
  --job_type=QUERY
```

```hcl
# Terraform 等价写法
resource "google_bigquery_capacity_commitment" "commit" {
  capacity_commitment_id = "my-commit"
  location               = "US"
  slot_count             = 500
  plan                   = "ANNUAL"
}

resource "google_bigquery_reservation" "analytics" {
  name              = "analytics-reservation"
  location          = "US"
  slot_capacity     = 300
  ignore_idle_slots = false
}

resource "google_bigquery_reservation_assignment" "analytics" {
  reservation = google_bigquery_reservation.analytics.id
  assignee    = "projects/my-project"
  job_type    = "QUERY"
}
```

真正可用的 SQL 部分仅限于 **查询级控制**：

```sql
-- 查询级成本上限（合法 SQL）
SELECT * FROM big_table
OPTIONS (maximum_bytes_billed = 10000000000);  -- 10 GB

-- 通过 SET 设置 query label，用于成本归因/路由
SET @@dataset_project_id = 'my-project';
SET @@query_label = 'team:analytics,priority:high';
```

会话/语句级的 `maximum_bytes_billed` 是 BigQuery 防止"扫表灾难"的核心手段——超出限制查询直接拒绝，不消耗任何 slots。

### Redshift WLM (Manual & Auto)

```json
// 参数组中的 wlm_json_configuration
[
  {
    "name": "etl_queue",
    "user_group": ["etl_users"],
    "query_group": ["etl"],
    "query_concurrency": 5,
    "memory_percent_to_use": 50,
    "query_priority": "highest",
    "max_execution_time": 7200000,
    "rules": [
      {"rule_name": "long_running_kill",
       "predicate": [{"metric_name":"query_execution_time","operator":">","value":3600}],
       "action": "abort"}
    ]
  },
  {
    "name": "bi_queue",
    "user_group": ["bi_users"],
    "query_concurrency": 15,
    "memory_percent_to_use": 30,
    "query_priority": "normal"
  }
]
```

**Auto WLM**（2018 默认）：Redshift 通过机器学习自动决定每个查询的内存与并发，移除手动 queue 配置的痛苦。仍可定义 query priority (LOWEST → HIGHEST) 与 query monitoring rules (QMR)。

QMR 规则可以基于 `query_cpu_time`, `query_blocks_read`, `query_temp_blocks_to_disk`, `return_row_count`, `nested_loop_join_row_count` 等 metric，超出时执行 LOG / HOP / ABORT / CHANGE_QUERY_PRIORITY。

### Vertica Resource Pools

```sql
CREATE RESOURCE POOL bi_pool
  MEMORYSIZE '20G'
  MAXMEMORYSIZE '40G'
  EXECUTIONPARALLELISM 8
  PRIORITY 100
  RUNTIMEPRIORITY MEDIUM
  RUNTIMEPRIORITYTHRESHOLD 5      -- 秒，超过则切换 priority
  PLANNEDCONCURRENCY 10
  MAXCONCURRENCY 20
  QUEUETIMEOUT '5 minutes'
  RUNTIMECAP '30 minutes';

GRANT USAGE ON RESOURCE POOL bi_pool TO bi_role;
ALTER USER bi_user SET RESOURCE POOL bi_pool;
```

Vertica 的独特之处：**RUNTIMEPRIORITYTHRESHOLD**——查询如果运行超过阈值时间，自动降级为低优先级，避免长查询占用高优先级资源。

### Greenplum Resource Groups

```sql
-- 创建资源组（基于 cgroups）
CREATE RESOURCE GROUP etl_group WITH (
  CPU_RATE_LIMIT = 30,             -- 30% 系统 CPU
  MEMORY_LIMIT = 40,               -- 40% 系统内存
  CONCURRENCY = 10,
  MEMORY_SHARED_QUOTA = 20,        -- 共享内存池 %
  MEMORY_SPILL_RATIO = 10);

ALTER ROLE etl_user RESOURCE GROUP etl_group;

-- 旧式资源队列（pre-5.x）仍可用
CREATE RESOURCE QUEUE bi_queue
  WITH (ACTIVE_STATEMENTS = 5,
        MEMORY_LIMIT = '2GB',
        PRIORITY = HIGH,
        MAX_COST = 10000000.0);    -- 优化器成本拒绝
```

### ClickHouse Profiles, Quotas, Workloads

```xml
<!-- users.xml -->
<profiles>
  <bi_profile>
    <max_memory_usage>10000000000</max_memory_usage>
    <max_threads>8</max_threads>
    <max_execution_time>300</max_execution_time>
    <max_rows_to_read>1000000000</max_rows_to_read>
    <readonly>1</readonly>
    <priority>5</priority>
  </bi_profile>
</profiles>

<quotas>
  <bi_quota>
    <interval>
      <duration>3600</duration>
      <queries>1000</queries>
      <errors>10</errors>
      <result_rows>100000000</result_rows>
      <execution_time>3600</execution_time>
    </interval>
  </bi_quota>
</quotas>
```

ClickHouse 24.x 引入 SQL 级 WORKLOAD：

```sql
CREATE RESOURCE network_io (READ DISK s3, WRITE DISK s3);

CREATE WORKLOAD all;
CREATE WORKLOAD production IN all
  SETTINGS weight = 3, max_speed = 1000000000 FOR network_io;
CREATE WORKLOAD development IN all
  SETTINGS weight = 1;
```

### Databricks SQL Warehouses

Databricks 类似 Snowflake 的 warehouse 模型：

```sql
-- 通过 REST API / UI / Terraform 创建
-- SQL 级仅支持参数控制
SET STATEMENT_TIMEOUT = 600;        -- 秒
```

Warehouse 类型：
- **Classic SQL Warehouse**：传统集群
- **Pro SQL Warehouse**：Photon 启用
- **Serverless SQL Warehouse**：秒级启动，自动伸缩

### Apache Impala —— Admission Control

```xml
<!-- fair-scheduler.xml -->
<allocations>
  <queue name="etl">
    <maxResources>50000 mb, 10 vcores</maxResources>
    <maxRunningApps>10</maxRunningApps>
  </queue>
  <queue name="bi">
    <maxResources>20000 mb, 5 vcores</maxResources>
    <maxRunningApps>50</maxRunningApps>
  </queue>
</allocations>

<!-- llama-site.xml -->
<property>
  <name>impala.admission-control.pool-default-query-options.bi</name>
  <value>mem_limit=2gb,query_timeout_s=600</value>
</property>
```

```sql
-- 会话级
SET REQUEST_POOL = 'bi';
SET MEM_LIMIT = '4GB';
SET EXEC_TIME_LIMIT_S = 300;
```

### Spark SQL —— Fair Scheduler Pools

```xml
<!-- fairscheduler.xml -->
<allocations>
  <pool name="production">
    <schedulingMode>FAIR</schedulingMode>
    <weight>3</weight>
    <minShare>10</minShare>
  </pool>
  <pool name="dev">
    <schedulingMode>FIFO</schedulingMode>
    <weight>1</weight>
  </pool>
</allocations>
```

```scala
// 应用层设置
spark.sparkContext.setLocalProperty("spark.scheduler.pool", "production")
```

Spark 调度池粒度是 **stage**，不是查询。

### PolarDB / OceanBase Resource Groups

PolarDB MySQL 兼容版继承了 MySQL 8.0 的 Resource Group：

```sql
CREATE RESOURCE GROUP bi_rg
  TYPE = USER
  VCPU = 0-7
  THREAD_PRIORITY = 5;

SET RESOURCE GROUP bi_rg FOR 12345;     -- thread id
```

OceanBase 资源管理基于 multi-tenancy 的 Resource Unit：

```sql
-- 创建资源规格
CREATE RESOURCE UNIT unit1
  MIN_CPU = 4, MAX_CPU = 8,
  MEMORY_SIZE = '8G',
  LOG_DISK_SIZE = '24G',
  MAX_IOPS = 10000, MIN_IOPS = 1000;

-- 创建资源池
CREATE RESOURCE POOL pool1
  UNIT = 'unit1', UNIT_NUM = 2,
  ZONE_LIST = ('z1','z2','z3');

-- 创建租户
CREATE TENANT bi_tenant
  RESOURCE_POOL_LIST = ('pool1'),
  PRIMARY_ZONE = 'z1';
```

OceanBase 的 WLM 是**租户级**——不同业务对应不同租户，强隔离。

### Azure Synapse Analytics —— Resource Classes & Workload Groups

经典模型：8 个静态/动态 resource classes (smallrc → xlargerc, staticrc10..80)，决定查询的内存份额。

```sql
EXEC sp_addrolemember 'largerc', 'etl_user';
```

新模型（2019+）：Workload Groups 和 Workload Classifiers：

```sql
CREATE WORKLOAD GROUP wgDataLoads
WITH (
  MIN_PERCENTAGE_RESOURCE = 30,
  CAP_PERCENTAGE_RESOURCE = 60,
  REQUEST_MIN_RESOURCE_GRANT_PERCENT = 5,
  REQUEST_MAX_RESOURCE_GRANT_PERCENT = 25,
  IMPORTANCE = HIGH,
  QUERY_EXECUTION_TIMEOUT_SEC = 7200);

CREATE WORKLOAD CLASSIFIER wcDataLoads
WITH (
  WORKLOAD_GROUP = 'wgDataLoads',
  MEMBERNAME = 'etl_login',
  IMPORTANCE = HIGH);
```

### MySQL 8.0 Resource Groups

MySQL 8.0 的 Resource Group 仅支持 CPU 亲和性与线程优先级（Linux），无内存配额：

```sql
CREATE RESOURCE GROUP batch_rg
  TYPE = USER
  VCPU = 0-3
  THREAD_PRIORITY = 19;

SET RESOURCE GROUP batch_rg FOR 12345;

-- 或在查询中
SELECT /*+ RESOURCE_GROUP(batch_rg) */ * FROM t;
```

### TiDB Resource Control (7.1+)

TiDB 7.1 GA 的 Resource Control 引入 **Request Unit (RU)** 抽象统一 CPU/IO：

```sql
CREATE RESOURCE GROUP rg_etl
  RU_PER_SEC = 5000
  PRIORITY = HIGH
  BURSTABLE;

CREATE USER 'etl'@'%' RESOURCE GROUP rg_etl;

-- 或语句级
SELECT /*+ RESOURCE_GROUP(rg_etl) */ * FROM t;
```

RU 是抽象单位（1 RU ≈ 一定 CPU + 一定 KV read/write）。

### StarRocks / Doris Resource Groups

```sql
-- StarRocks
CREATE RESOURCE GROUP rg_bi
TO (user='bi', role='analyst', source_ip='10.0.0.0/24')
WITH (
  'cpu_core_limit' = '8',
  'mem_limit' = '30%',
  'concurrency_limit' = '20',
  'big_query_cpu_second_limit' = '300',
  'big_query_scan_rows_limit' = '1000000000',
  'big_query_mem_limit' = '10737418240',
  'type' = 'normal');

-- Doris
CREATE WORKLOAD GROUP wg_bi
PROPERTIES (
  'cpu_share' = '20',
  'memory_limit' = '30%',
  'enable_memory_overcommit' = 'true',
  'max_concurrency' = '50',
  'max_queue_size' = '100',
  'queue_timeout' = '5000');
```

两者都支持 **Big Query Detection**——在执行中检测查询是否超出 CPU/扫描行数等阈值，自动杀死。

## Snowflake Warehouse Sizing vs BigQuery Slot Reservations 深度对比

二者都是云数仓的 WLM 巅峰，但模型完全相反。

### 计算单位

| 维度 | Snowflake Warehouse | BigQuery Slots |
|------|---------------------|---------------|
| 计费单位 | Credit (按秒) | Slot-second (commitment) 或 byte (on-demand) |
| 最小粒度 | X-Small = 1 credit/h ≈ 1 节点 | 100 slot 起步预留 |
| 横向扩展 | Multi-cluster (1-10 cluster) | Slot autoscaling within reservation |
| 纵向扩展 | T-shirt 尺寸（10 级，每级 2x）| 调整 reservation 大小 |
| 启动时间 | 秒级 (auto-resume) | 即时（slots 已就绪）|

### 隔离模型

| 维度 | Snowflake | BigQuery |
|------|-----------|----------|
| 隔离单位 | 完全独立的 warehouse（独立 RAM/缓存）| Reservation 内 slot 互相竞争 |
| 共享 storage | 是（同一份数据）| 是 |
| Cache 共享 | 否（warehouse 各自的 SSD 缓存）| 是（result cache 全局）|
| 突发 | Multi-cluster 自动加 cluster | `ignore_idle_slots = false` 借用空闲 |

### 成本控制

| 控制点 | Snowflake | BigQuery |
|--------|-----------|----------|
| 硬性上限 | Resource Monitor (credit cap → SUSPEND) | `maximum_bytes_billed` (拒绝) + commitment 上限 |
| 软性提醒 | Monitor 触发 NOTIFY | Cloud Billing alerts |
| 单查询成本 | 无（按 warehouse 时间）| 按扫描字节明确 |
| 失控查询防护 | `STATEMENT_TIMEOUT_IN_SECONDS` | `maximum_bytes_billed` (执行前预估)|

### 失控查询场景

**场景**：分析师写了 `SELECT * FROM 100tb_table` 漏写 WHERE。

- **Snowflake**：在 X-Large warehouse 上跑 30 分钟，消耗约 8 credits ≈ 数十美元，等到 timeout 前都不会停。除非 Resource Monitor 触发 SUSPEND。
- **BigQuery**：如果设置了 `maximum_bytes_billed = 10GB`，**查询直接拒绝，零成本**。否则按 100TB × $5/TB ≈ $500 收费。

这是 BigQuery 显著优于 Snowflake 的一个点：**预执行成本控制**。

### 并发模型

- **Snowflake**：单 warehouse 默认 8 并发（`MAX_CONCURRENCY_LEVEL`），溢出查询排队 (`STATEMENT_QUEUED_TIMEOUT_IN_SECONDS`)；多 cluster warehouse 在排队时启动新 cluster。
- **BigQuery**：单项目默认 100 并发，slot 在 reservation 内 fair share 调度，无严格队列。

### 何时选择哪种模型

| 工作负载 | 推荐 |
|---------|------|
| 已知规模、稳定流量 | BigQuery commitment（更便宜）|
| 突发、不可预测 | Snowflake auto-suspend warehouse |
| 严格成本控制 | BigQuery `maximum_bytes_billed` |
| 多团队隔离 | Snowflake 多 warehouse |
| Ad-hoc 探索 | BigQuery on-demand |
| 长批处理 ETL | Snowflake X-Large (短时间高并发)|
| BI 仪表盘高并发 | Snowflake multi-cluster |

## 关键发现

### 1. WLM 是数据库领域最不标准化的部分

ISO SQL 没有也不太可能定义 WLM。原因不仅是技术性的（资源是物理概念），更是商业性的——WLM 是企业数据库的高价值差异化功能。Oracle Resource Manager (1998)、Teradata TASM、SQL Server Resource Governor 都是各自厂商的核心卖点。

### 2. 三种主流架构模型

- **共享集群 + 配额**：Oracle, SQL Server, Teradata, Vertica, Greenplum, Synapse。资源是共享的，通过百分比/权重切分。配置复杂但灵活。
- **隔离 warehouse**：Snowflake, Databricks, Firebolt, Materialize。计算单元独立可伸缩，配置简单但缺乏细粒度。
- **Slot/RU 抽象**：BigQuery, TiDB。资源被抽象为统一单位，调度公平但难以预测单查询性能。

### 3. 准入控制是核心能力

成熟的 WLM 系统都具备**预执行准入控制**——根据估算成本、当前并发、用户身份决定是否立即执行。Oracle (`MAX_EST_EXEC_TIME`)、SQL Server (`query_governor_cost_limit`)、Teradata TASM、BigQuery (`maximum_bytes_billed`) 都体现这一点。这比"启动后再杀死"高效得多。

### 4. 资源监控规则 (QMR) 是第二道防线

执行中检测异常并自动响应：Redshift QMR、Teradata exception、StarRocks/Doris big query detection、Vertica RUNTIMEPRIORITYTHRESHOLD。这些规则可以基于 CPU 时间、扫描行数、溢出大小等动态指标。

### 5. 分类器决定路由的灵活性

最强大的分类器（Teradata、Oracle、SQL Server、SAP HANA）支持**用户 + 角色 + 应用名 + 客户端 IP + 查询类型 + 估算成本**的组合判断。最弱的（MySQL、Snowflake）只能基于用户。分类器的灵活性直接决定了一个 WLM 能否承载真正的混合负载。

### 6. 内存管理风格的两极分化

- **硬限制**：Oracle, SQL Server, ClickHouse, Snowflake (隐式), BigQuery (隐式), HANA。超出即报错。
- **软限制 + 溢出**：PostgreSQL (work_mem), Greenplum, Trino, Spark, DuckDB。慢但能完成。

云数仓时代倾向于硬限制（避免一个查询拖慢整个 warehouse），而 OLTP 数据库倾向于溢出（保证查询完成）。

### 7. 时间维度的策略切换

Teradata、Oracle 支持基于时间的资源计划切换（白天 OLTP 优先、夜间 ETL 优先），这是传统企业数据库的特色。云数仓很少提供——因为通常通过启停不同 warehouse 实现等效效果。

### 8. 嵌入式数据库无 WLM

SQLite、DuckDB、H2、HSQLDB、Derby 都没有 WLM——它们是单进程库，资源管理由宿主应用负责。这是合理的设计取舍。

### 9. PostgreSQL 的设计哲学决定了缺位

PostgreSQL 的 process-per-connection 架构使原生 WLM 困难——没有中央调度器。社区依赖 OS cgroups、连接池 (PgBouncer)、`work_mem` per-role 设置组合实现。商业派生（EDB, Greenplum, Yellowbrick）补足了这一缺口。

### 10. RU 抽象是新趋势

TiDB Request Unit、BigQuery Slot 都是把 CPU + IO + 网络抽象为统一可计量单位，便于多租户公平分配与计费。这是云原生数据库的方向，但抽象的代价是**性能预测困难**——RU 不能直接对应"我的查询会跑多快"。

### 11. 失控查询防护是企业必备

任何一个生产数据仓库都会遇到失控查询。最佳实践：
- 设置全局 `statement_timeout`（防御性默认 1h）
- 设置内存上限（避免 OOM 拖垮节点）
- 启用 QMR 规则检测异常模式
- 云数仓上启用 `maximum_bytes_billed` / Resource Monitor

### 12. 最强 WLM 的称号属于 Teradata

Teradata TASM 是综合维度最强的 WLM：状态感知、时段切换、五级调度、丰富的分类器、完善的 exception 处理、与系统健康状态联动。代价是**复杂度**——配置 TASM 需要专门的 DBA 培训，不是一个 SQL DDL 能解决的事情。这也是为什么云数仓选择简化模型（Snowflake warehouse、BigQuery slot）：用户体验远比理论灵活性重要。

## 参考资料

- Oracle: [Database Resource Manager](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-resources-with-oracle-database-resource-manager.html)
- SQL Server: [Resource Governor](https://learn.microsoft.com/en-us/sql/relational-databases/resource-governor/resource-governor)
- DB2: [Workload Management](https://www.ibm.com/docs/en/db2/11.5?topic=management-introduction-db2-workload)
- Snowflake: [Warehouses](https://docs.snowflake.com/en/user-guide/warehouses), [Resource Monitors](https://docs.snowflake.com/en/user-guide/resource-monitors)
- BigQuery: [Reservations](https://cloud.google.com/bigquery/docs/reservations-intro), [`maximum_bytes_billed`](https://cloud.google.com/bigquery/docs/best-practices-costs)
- Redshift: [Workload Management](https://docs.aws.amazon.com/redshift/latest/dg/cm-c-implementing-workload-management.html), [Auto WLM](https://docs.aws.amazon.com/redshift/latest/dg/automatic-wlm.html)
- Vertica: [Resource Pools](https://www.vertica.com/docs/latest/HTML/Content/Authoring/AdministratorsGuide/ResourceManager/ResourceManager.htm)
- Greenplum: [Resource Groups](https://docs.vmware.com/en/VMware-Greenplum/index.html)
- ClickHouse: [Quotas](https://clickhouse.com/docs/en/operations/quotas), [Workload Scheduling](https://clickhouse.com/docs/en/operations/workload-scheduling)
- Trino: [Resource Groups](https://trino.io/docs/current/admin/resource-groups.html)
- Hive: [Workload Management](https://cwiki.apache.org/confluence/display/Hive/Workload+Management)
- Teradata: [TASM Overview](https://docs.teradata.com/r/Teradata-VantageTM-Workload-Management-User-Guide)
- SAP HANA: [Workload Classes](https://help.sap.com/docs/SAP_HANA_PLATFORM/6b94445c94ae495c83a19646e7c3fd56/5066181717df4110931271d1efe5ec5c.html)
- Azure Synapse: [Workload Groups](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-workload-isolation)
- Impala: [Admission Control](https://impala.apache.org/docs/build/html/topics/impala_admission.html)
- TiDB: [Resource Control](https://docs.pingcap.com/tidb/stable/tidb-resource-control)
- StarRocks: [Resource Group](https://docs.starrocks.io/docs/administration/resource_group/)
- Doris: [Workload Group](https://doris.apache.org/docs/admin-manual/workload-group/)
- OceanBase: [Resource Isolation](https://en.oceanbase.com/docs/common-oceanbase-database-10000000001225327)
- MySQL: [Resource Groups](https://dev.mysql.com/doc/refman/8.0/en/resource-groups.html)
- Yellowbrick: [Workload Management](https://docs.yellowbrick.com/)
