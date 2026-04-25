# 准入控制与查询排队 (Admission Control and Query Queuing)

一个没有准入控制的数据库，就像一个没有售票员的电影院——所有人都涌进去，最后谁都看不上电影。准入控制 (Admission Control) 是数据库面对过载时保住下限的最后防线：它决定哪些查询可以立即执行、哪些必须排队等待、哪些应该被直接拒绝。对于 OLTP 系统，它是 SLA 的守门人；对于 OLAP 系统，它是资源成本可预测的基石。

## 为什么准入控制是 OLTP/OLAP 可靠性的基础

在高并发场景下，数据库的吞吐量-延迟曲线呈现出典型的"膝部现象"(knee behavior)：

```
吞吐量 ∧
     │        膝部 (knee)
     │       ┌────────────── 理想情况
     │      ╱╲              
     │     ╱  ╲___________   过载崩塌
     │    ╱                
     │   ╱                
     │  ╱                  
     │ ╱                   
     ┼─────────────────────> 并发数
```

- **膝部以下**：并发增加带来吞吐量线性增长
- **膝部附近**：吞吐量达到峰值，延迟开始上升
- **膝部以上**：由于锁竞争、缓存抖动、上下文切换、内存溢出到磁盘等副作用，**吞吐量反而下降**，延迟陡增

没有准入控制时，一个系统的最大 QPS 点和崩塌点之间只差几十个并发。准入控制的核心目标就是让系统"卡在膝部以下"：

1. **OLTP 系统的稳定性**：PostgreSQL 官方反复警告——超过 `max_connections` 的 2-3 倍连接数时，即便使用连接池，仍可能因活跃事务过多拖垮整个集群。数据库内部的 Lock Manager、Buffer Pool、WAL writer 都有隐式的并发上限，超过之后性能是断崖式下降。
2. **OLAP 系统的资源可预测性**：一个没有节制的 BI 查询可能占用 TB 级内存，触发 OOM 连锁反应，拖累所有其他查询。Snowflake/Redshift/BigQuery 都把"排队"作为默认的保护机制——宁可让 P99 查询等 10 秒，也不要让 P50 查询从 100ms 变成 30 秒。
3. **多租户的公平性**：当数十个租户共享同一个集群时，没有准入控制就是"谁会写死循环谁占资源"，必须通过队列、配额、优先级机制保证弱小租户不被饿死。
4. **尾延迟的控制**：Google Almeida 的研究指出，尾延迟的恶化来自"等待队列中已经堆积的长查询"。准入控制可以通过提前拒绝或延后执行重查询，把 P99 压到接近 P50 的量级。
5. **故障恢复的快速性**：无准入控制的系统在宕机恢复后，积压的客户端连接会同时涌入 (thundering herd)，造成二次崩溃。正确的做法是分批准入。

准入控制通常包含以下关键维度：

- **并发上限 (Concurrency Cap)**：同时执行的查询不得超过 N 个
- **排队策略 (Queue Policy)**：超过上限时排队 / 拒绝 / 降级
- **队列超时 (Queue Timeout)**：排队等待的最大时间
- **内存准入 (Memory-based Admission)**：剩余内存不足时拒绝新查询
- **优先级 (Priority)**：不同队列/用户有不同优先级
- **可扩展性指标 (Overload Signal)**：根据 CPU、I/O 延迟、锁等待等动态调节

## 没有 SQL 标准

ISO SQL 标准从未涉及准入控制语法，原因与资源管理相同：这是**运行时行为**而非**数据模型**的一部分。每个引擎有自己的理念：

1. **OLTP 系统**通常将准入控制交给连接池 (PgBouncer, ProxySQL)，数据库本身只有硬上限 `max_connections`
2. **OLAP 数仓**把准入控制深度集成在执行引擎里，与资源组/WLM 紧密耦合
3. **新一代分布式数据库** (CockroachDB, TiDB) 试图内置自适应准入控制，根据 CPU/IO 延迟自动调节

因此本文没有"标准语法"一节——准入控制是数据库领域中碎片化最严重的子领域之一。本文侧重于**概念对比**和**关键参数矩阵**。

相关文章：[资源管理与 WLM](./resource-management-wlm.md)、[连接池](./connection-pooling.md)、[并行查询执行](./parallel-query-execution.md)。

## 支持矩阵

### 1. 最大并发查询数 / 连接数

| 引擎 | 连接上限参数 | 活跃查询上限 | 默认排队 | 版本 |
|------|------------|------------|---------|------|
| PostgreSQL | `max_connections` (默认 100) | 无独立限制 | -- (拒绝) | 全部 |
| MySQL | `max_connections` (默认 151) | 无独立限制 | -- (拒绝) | 全部 |
| MariaDB | `max_connections` (默认 151) | `max_statement_time` | -- (拒绝) | 全部 |
| SQLite | 无 (嵌入式) | 无 | -- | -- |
| Oracle | `processes` / `sessions` | Resource Manager `ACTIVE_SESS_POOL_P1` | 是 | 8i+ |
| SQL Server | `max server connections` | Resource Governor `GROUP_MAX_REQUESTS` | 是 | 2008 Ent+ |
| DB2 | `MAX_CONNECTIONS` / `MAX_COORDAGENTS` | WLM `CONCURRENTDBCOORDACTIVITIES` | 是 | 9.5+ |
| Snowflake | 按 Warehouse 配额 | `MAX_CONCURRENCY_LEVEL` (默认 8) | 是 | GA |
| BigQuery | slots 池 | slot 调度 (无显式查询数上限) | 是 | GA |
| Redshift | `max_connections` (默认 500) | WLM 队列 `query_concurrency` | 是 | GA |
| DuckDB | 嵌入式 | 多线程内部 | -- | -- |
| ClickHouse | `max_connections` (默认 1024) | `max_concurrent_queries` (默认 100) | 是 (23.x+) | 全部 |
| Trino | 协调器 HTTP 连接 | Resource Group `maxRunning` | 是 | 早期 |
| Presto | 同 Trino | 同 Trino | 是 | 早期 |
| Spark SQL | 无显式连接概念 | FAIR Scheduler 池 | 是 | 1.0+ |
| Hive | HiveServer2 `hive.server2.thrift.max.worker.threads` | LLAP queue | 是 | 3.0+ |
| Flink SQL | 不适用 (流处理) | Slot 资源 | -- | -- |
| Databricks | SQL Warehouse 配额 | `max_concurrent_queries` | 是 | GA |
| Teradata | `MaxLoadTasks` / TASM | TASM Workload 并发槽 | 是 | V2R6+ |
| Greenplum | `max_connections` | Resource Group `CONCURRENCY` | 是 | 5.0+ |
| CockroachDB | SQL 池连接 | KV Admission Queue (自适应) | 是 | 22.1+ |
| TiDB | `tidb_max_connections` | Resource Control RU 限流 | 是 | 7.1+ |
| OceanBase | `max_connections` | 资源隔离 | 部分 | 3.x+ |
| YugabyteDB | 继承 PG `max_connections` | YB 内部限流 | 部分 | 2.x+ |
| SingleStore | `max_connection_threads` | Resource Pool `QUERY_TIMEOUT` | 是 | 7.0+ |
| Vertica | `MaxClientSessions` | Resource Pool `MAXCONCURRENCY` | 是 | 早期 |
| Impala | `max_queries` | Admission Control Pool | 是 | 1.3+ |
| StarRocks | `max_connections` | Resource Group `CONCURRENCY_LIMIT` | 是 | 2.2+ |
| Doris | `max_connections` | Workload Group 并发配额 | 是 | 2.0+ |
| MonetDB | `max_clients` (默认 64) | -- | -- | -- |
| CrateDB | `http.max_content_length` | -- | -- | -- |
| TimescaleDB | 继承 PG | -- | -- | -- |
| QuestDB | `cairo.sql.copy.queue.capacity` | -- | -- | -- |
| Exasol | `profile.maxActiveConnections` | Priority Group | 是 | 6.0+ |
| SAP HANA | `max_sql_connections` | Workload Class `TOTAL_STATEMENT_MEMORY_LIMIT` | 是 | SPS09+ |
| Informix | `NETTYPE` 参数 | MGM | 是 | 早期 |
| Firebird | 无显式 | -- | -- | -- |
| H2 | 无 (嵌入式) | -- | -- | -- |
| HSQLDB | 无 | -- | -- | -- |
| Derby | 连接池配置 | -- | -- | -- |
| Amazon Athena | 每账户 slot 配额 | Workgroup `BytesScannedCutoffPerQuery` | 是 | GA |
| Azure Synapse | 每 DWU 并发限额 | Workload Group `REQUEST_MAX_MEMORY_GRANT_PERCENT` | 是 | GA |
| Google Spanner | 自动管理 | 内部流控 | 是 | GA |
| Materialize | 每 Cluster 限制 | CLUSTER 隔离 | -- | GA |
| RisingWave | Compute Node 并发 | -- | -- | GA |
| InfluxDB (SQL) | 查询 deadline | -- | -- | GA |
| Databend | Warehouse 并发 | `max_concurrent_queries` | 是 | GA |
| Yellowbrick | WLM Pool | `maxConcurrency` | 是 | GA |
| Firebolt | Engine 级别 | 自动调度 | 是 | GA |

> 统计：约 36 个引擎具有显式的并发上限配置，约 30 个引擎在超限时会主动排队而非直接拒绝。

### 2. 队列等待超时 / 排队策略

| 引擎 | 超时参数 | 默认值 | 超时后行为 |
|------|---------|-------|-----------|
| PostgreSQL | 无内置 (依赖 PgBouncer `query_wait_timeout`) | -- | PgBouncer 返回错误 |
| MySQL | `lock_wait_timeout` / `wait_timeout` | 31536000 / 28800 | 连接断开 |
| Oracle | Resource Manager `MAX_EST_EXEC_TIME` / `QUEUEING_P1` | 无默认 | 取消查询 |
| SQL Server | `REQUEST_MAX_CPU_TIME_SEC` | 0 (不限) | 取消 |
| DB2 | `WLM_QUEUE_TIMEOUT` | 无默认 | 取消 |
| Snowflake | `STATEMENT_QUEUED_TIMEOUT_IN_SECONDS` | 0 (无限) | 取消并返回错误 |
| BigQuery | `--max_rows_per_request` + slot 等待 | 自动 | 超时取消 |
| Redshift | `queue_wait_time` (`max_query_queue_time`) | -- | 取消 |
| ClickHouse | `queue_max_wait_ms` | 5000 (5s) | 抛异常 |
| Trino | `queued_time_limit` (资源组) | 1h | CANCELLED |
| Spark SQL | 无内置 | -- | -- |
| Hive | `hive.server2.tez.session.lifetime` | -- | -- |
| Teradata | TASM `MaxResponseTime` | 按配置 | 中止 |
| Greenplum | `gp_resqueue_priority` / 超时 | -- | 取消 |
| CockroachDB | `admission.sql_kv_response.enabled` | 动态 | 保持排队 |
| TiDB | `tidb_resource_control_strict_mode` | ON | RU 耗尽后降速 |
| SingleStore | `QUERY_TIMEOUT` (Pool) | 0 | 取消 |
| Vertica | `QUEUETIMEOUT` | 300s | 拒绝 |
| Impala | `queue_wait_timeout_ms` | 60000 (60s) | 拒绝 |
| StarRocks | `query_queue_pending_timeout_second` | 300 | 拒绝 |
| Doris | `query_queue_timeout` | 500s | 拒绝 |
| Exasol | `QUERY_TIMEOUT` | 无 | 中止 |
| SAP HANA | `statement_memory_limit` | 0 | 中止 |
| Azure Synapse | `REQUEST_MAX_MEMORY_GRANT_TIMEOUT_SEC` | 0 | 取消 |
| Yellowbrick | `queueTimeLimit` | 按 Pool | 中止 |
| Databend | `query_queued_timeout_in_seconds` | 300 | 取消 |
| Firebolt | 自动 | -- | 取消 |

### 3. 内存准入控制 (Memory-based Admission)

内存准入控制通过**查询开始前估算内存需求**，仅在集群内存充足时准入，否则排队或拒绝。

| 引擎 | 内存估算/预留 | 估算来源 | 内存不足行为 |
|------|-------------|---------|-------------|
| PostgreSQL | -- | -- | 单查询内存由 `work_mem` 控制，无集群级准入 |
| Oracle | PGA 自动管理 | 历史统计 | 溢出磁盘 |
| SQL Server | `REQUEST_MAX_MEMORY_GRANT_PERCENT` | 优化器估算 | 排队或降级 |
| DB2 | WLM `ADMISSION_CTRL` | 优化器 | 排队 |
| Snowflake | -- (按 warehouse 总量) | -- | Warehouse 级排队 |
| Redshift | WLM `memory_percent_to_use` | WLM 静态分配 | 溢出到磁盘 |
| ClickHouse | `max_server_memory_usage` / `max_memory_usage_for_user` | 实时占用 | 抛异常 |
| Trino | `query.max-memory-per-node` / `query.max-total-memory` | 优化器 + 运行时 | 排队 |
| Teradata | TASM `ResponseTime` goal | 历史统计 | 延迟 |
| Greenplum | Resource Group `MEMORY_LIMIT` | 优化器估算 | 排队 |
| Impala | `RM_INITIAL_MEM` / `MEM_LIMIT` | 优化器 | **核心准入条件** |
| Vertica | Resource Pool `QUERYBUDGET` | 优化器 | 排队 |
| Azure Synapse | `REQUEST_MIN_MEMORY_GRANT_PERCENT` | 固定百分比 | 排队 |
| SAP HANA | `TOTAL_STATEMENT_MEMORY_LIMIT` | 运行时 | 中止 |
| SingleStore | Resource Pool `MEMORY_PERCENTAGE` | 运行时 | 溢出 |

> Impala 是内存准入控制的经典案例：查询提交后，协调器根据优化器估算的内存需求**先排队**，直到目标资源池有足够空闲内存才准入，避免 OOM。

### 4. 优先级队列

| 引擎 | 优先级维度 | 优先级级别数 | 抢占支持 |
|------|----------|------------|---------|
| Oracle | CPU 份额 + 绝对值 | 8 个 Consumer Group 级别 | 非抢占 |
| SQL Server | `IMPORTANCE`: LOW/MEDIUM/HIGH | 3 | 非抢占 |
| DB2 | `AGENT PRIORITY` | -20 ~ +20 | OS 级 |
| Snowflake | Multi-Cluster Warehouse + 缩放策略 | 通过多 Warehouse 实现 | 非抢占 |
| Redshift | WLM 队列优先级 (5 档: HIGHEST~LOWEST) | 5 | 抢占 (后台) |
| ClickHouse | `priority` 设置 (0-N, 0 最高) | 无限 | 非抢占 |
| Trino | 资源组 `schedulingPolicy: priority/fair/weighted` | 自定义 | 非抢占 |
| Hive | Resource Plan `SCHEDULING_POLICY` | 自定义 | 抢占 |
| Spark SQL | FAIR Scheduler `weight` | 数值型 | 非抢占 |
| Teradata | TASM Workload 优先级 | 5 级 | 动态 |
| Greenplum | Resource Group `CPU_RATE_LIMIT` | 百分比 | 非抢占 |
| CockroachDB | KV 优先级 (`HIGH`/`NORMAL`/`LOW`/`USER_LOW`) | 4 | 是 (KV 层) |
| TiDB | Resource Group `PRIORITY`: HIGH/MEDIUM/LOW + `BURSTABLE` | 3 级 | 非抢占 |
| SingleStore | Resource Pool `SOFT_CPU_LIMIT_PERCENTAGE` | 百分比 | 非抢占 |
| Vertica | Resource Pool `PRIORITY` (-100 ~ 100) | 连续数值 | 非抢占 |
| Impala | Admission Control `max-requests` / `max-queued` | Pool 级 | 非抢占 |
| StarRocks | Resource Group `CPU_WEIGHT` | 1-1024 | 非抢占 |
| Doris | Workload Group `cpu_share` | 1-1024 | 非抢占 |
| Azure Synapse | Workload Group `IMPORTANCE`: LOW~HIGH | 5 级 | 抢占 |
| SAP HANA | Workload Class `PRIORITY` | 0-9 | 非抢占 |
| Exasol | Priority Group 权重 | 百分比 | 非抢占 |
| Yellowbrick | WLM Profile `priority` | 多级 | 动态 |

## 各引擎准入控制详解

### PostgreSQL：`max_connections` 硬上限 + PgBouncer 的外部排队

PostgreSQL 本身没有真正意义上的内置准入控制，它采用的是**硬上限 + 拒绝**模型：

```sql
-- 查看当前上限
SHOW max_connections;        -- 默认 100

-- 运行时查看连接
SELECT count(*) FROM pg_stat_activity;

-- 超过 max_connections 时，新连接直接报错：
-- FATAL:  sorry, too many clients already
```

PostgreSQL 的连接每个对应一个 OS 进程 (fork 模型)，因此 `max_connections` 远比其他数据库更"金贵"：

```
每个连接开销：
  - 进程内存: ~10MB (+ work_mem × 操作数)
  - 文件句柄: 若干
  - 共享内存: lock entries, subtransaction slots

超过 300-500 连接后开销已显著：
  - CPU: 进程调度负担
  - 内存: N × 10MB 的固定开销
  - Lock Manager: 更大的锁表，更长的锁竞争
```

标准做法是使用 **PgBouncer** 作为连接池：

```ini
# PgBouncer 配置示例 (pgbouncer.ini)
[databases]
mydb = host=127.0.0.1 dbname=mydb

[pgbouncer]
pool_mode = transaction            # 事务级池化（而非会话级）
max_client_conn = 10000            # 允许 10000 客户端连接
default_pool_size = 20             # 但后端仅保持 20 个活跃连接
reserve_pool_size = 5              # 备用槽

query_wait_timeout = 120           # 排队等待超过 120 秒则失败
server_idle_timeout = 600
```

这里 `query_wait_timeout` 就是 PostgreSQL 生态中最接近准入控制的机制：**客户端发来的查询如果 PgBouncer 后端池满了，就会在 PgBouncer 里排队，超过 `query_wait_timeout` 才失败**。

PostgreSQL 17 开始引入了一些新的硬参数 (例如连接保留给 `reserved_connections`)，但核心仍然是"硬限制 + 外部池化"的思路。

### Oracle：Resource Manager 的 Active Session Pool

Oracle Database Resource Manager 是准入控制的鼻祖之一，自 8i (1999) 即已提供：

```sql
-- 创建资源计划
BEGIN
  DBMS_RESOURCE_MANAGER.CREATE_PENDING_AREA();

  DBMS_RESOURCE_MANAGER.CREATE_PLAN(
    plan    => 'DAYTIME_PLAN',
    comment => '白天工作负载计划');

  DBMS_RESOURCE_MANAGER.CREATE_CONSUMER_GROUP(
    consumer_group => 'OLTP_GROUP',
    comment        => '在线交易组');

  DBMS_RESOURCE_MANAGER.CREATE_CONSUMER_GROUP(
    consumer_group => 'BATCH_GROUP',
    comment        => '批处理组');

  -- 关键：设置 Active Session Pool
  DBMS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(
    plan                  => 'DAYTIME_PLAN',
    group_or_subplan      => 'BATCH_GROUP',
    active_sess_pool_p1   => 4,         -- 最多 4 个活跃会话
    queueing_p1           => 600,       -- 排队最多 600 秒
    max_est_exec_time     => 3600,      -- 估算执行时间 > 1h 的直接拒绝
    mgmt_p1               => 20);       -- CPU 20%

  DBMS_RESOURCE_MANAGER.VALIDATE_PENDING_AREA();
  DBMS_RESOURCE_MANAGER.SUBMIT_PENDING_AREA();
END;
/

-- 激活计划
ALTER SYSTEM SET RESOURCE_MANAGER_PLAN = 'DAYTIME_PLAN';
```

Oracle 的关键准入参数：

| 参数 | 作用 |
|------|------|
| `ACTIVE_SESS_POOL_P1` | 该组同时活跃会话的上限 (超过则排队) |
| `QUEUEING_P1` | 排队等待超时 (秒)，超过后会话报错 |
| `MAX_EST_EXEC_TIME` | 优化器估算执行时间 > 该值则拒绝 |
| `MAX_IDLE_TIME` | 空闲会话被自动杀死 |
| `PARALLEL_DEGREE_LIMIT_P1` | 允许的最大并行度 |

这是**内存感知 + 优化器估算感知**的准入控制典型案例：Oracle 会在执行前用 CBO 估算查询成本，如果明显超标就**提前拒绝**。

### SQL Server：Resource Governor 与 GROUP_MAX_REQUESTS

SQL Server 从 2008 Enterprise 开始支持 Resource Governor：

```sql
-- 1. 创建资源池
CREATE RESOURCE POOL poolAnalytics
WITH (
    MIN_CPU_PERCENT = 20,
    MAX_CPU_PERCENT = 60,
    MIN_MEMORY_PERCENT = 20,
    MAX_MEMORY_PERCENT = 60
);

-- 2. 创建工作负载组 (关键：GROUP_MAX_REQUESTS 即并发请求上限)
CREATE WORKLOAD GROUP wgAnalytics
WITH (
    IMPORTANCE = LOW,                       -- 优先级：LOW/MEDIUM/HIGH
    REQUEST_MAX_MEMORY_GRANT_PERCENT = 25,  -- 单查询最多占用 Pool 25% 内存
    REQUEST_MAX_CPU_TIME_SEC = 600,         -- 单查询 CPU 上限
    REQUEST_MEMORY_GRANT_TIMEOUT_SEC = 30,  -- 内存分配等待超时
    MAX_DOP = 4,                            -- 最大并行度
    GROUP_MAX_REQUESTS = 10                 -- 该组最大并发查询数 (准入上限)
) USING poolAnalytics;

-- 3. 创建分类器函数
CREATE FUNCTION fn_Classifier() RETURNS SYSNAME
WITH SCHEMABINDING AS
BEGIN
    DECLARE @grp SYSNAME;
    IF (SUSER_NAME() LIKE 'bi_%')
        SET @grp = 'wgAnalytics';
    ELSE
        SET @grp = 'default';
    RETURN @grp;
END;

-- 4. 注册分类器并启用
ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = dbo.fn_Classifier);
ALTER RESOURCE GOVERNOR RECONFIGURE;
```

`GROUP_MAX_REQUESTS` 就是 SQL Server 的并发准入上限。超过后新查询会在内部队列等待，如果 `REQUEST_MEMORY_GRANT_TIMEOUT_SEC` 超时则取消。

### Snowflake：Warehouse 级别的查询排队

Snowflake 的准入控制设计最为典型地体现了"云数仓"的思路——**自动扩容 + 排队超时**：

```sql
-- 创建 Warehouse 并设置并发度
CREATE WAREHOUSE analytics_wh
    WAREHOUSE_SIZE = 'LARGE'
    MAX_CLUSTER_COUNT = 5          -- 多集群 Warehouse：最多 5 个集群
    MIN_CLUSTER_COUNT = 1          -- 最少 1 个
    SCALING_POLICY = 'STANDARD'    -- STANDARD 或 ECONOMY
    AUTO_SUSPEND = 60
    MAX_CONCURRENCY_LEVEL = 8;     -- 每集群最多 8 并发查询

-- 关键会话参数：排队超时
ALTER SESSION SET STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = 600;
ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = 3600;
```

Snowflake 的准入机制：

```
新查询到达
    │
    ▼
路由到 Warehouse
    │
    ▼
┌──────────────────┐
│ 活跃查询 < MAX_CONCURRENCY_LEVEL?
└──────────────────┘
      │ 否                     │ 是
      ▼                       ▼
 ┌─────────┐            立即执行
 │ 排队队列 │
 └─────────┘
      │
      ▼
 等待 STATEMENT_QUEUED_TIMEOUT_IN_SECONDS
      │
      ├─ 有空闲 slot → 执行
      ├─ Multi-Cluster 扩容 → 新集群上执行
      └─ 超时 → 返回错误
```

Snowflake 的关键参数：

| 参数 | 作用 | 默认 |
|------|------|------|
| `MAX_CONCURRENCY_LEVEL` | 每集群最大并发查询数 (准入上限) | 8 |
| `STATEMENT_QUEUED_TIMEOUT_IN_SECONDS` | 排队超时 | 0 (无限) |
| `STATEMENT_TIMEOUT_IN_SECONDS` | 查询执行超时 | 172800 (2 天) |
| `MAX_CLUSTER_COUNT` | Multi-Cluster 扩容上限 | 1 |
| `SCALING_POLICY` | 扩容策略 (STANDARD/ECONOMY) | STANDARD |

### Redshift：WLM 队列与自动 WLM

Redshift 的 Workload Management (WLM) 是最早的多队列设计：

```json
// WLM 配置 (通过参数组或 Console 配置)
[
  {
    "query_group": ["etl"],
    "query_group_wild_card": 0,
    "user_group": ["etl_users"],
    "query_concurrency": 5,            // 队列并发 = 5
    "memory_percent_to_use": 50,
    "query_wait_time": 300,            // 排队 300s 超时
    "priority": "high"
  },
  {
    "query_group": ["bi"],
    "query_concurrency": 15,
    "memory_percent_to_use": 30,
    "priority": "normal"
  },
  {
    "query_group": [],
    "auto_wlm": true                   // 自动 WLM (推荐)
  }
]
```

Redshift Auto WLM (推荐模式) 会根据机器学习模型自动分配每个查询到合适的队列，无需手动调优。

准入流程：

```
查询提交
    │
    ├─ WLM 规则匹配 (user_group/query_group)
    ▼
目标队列
    │
    ├─ 队列活跃查询 < query_concurrency? → 立即执行
    ├─ 否 → 排队
    │       │
    │       ├─ max_query_queue_time 内有 slot → 执行
    │       └─ 超时 → 返回错误
```

Redshift 从 2020 年开始引入 **Concurrency Scaling**：排队查询可以透明地在后台自动创建的集群上运行，无需等待主集群 slot。

### BigQuery：Slot 与 Reservation

BigQuery 不使用传统的队列概念，而是使用**槽位 (slot)** 作为计算单元：

```sql
-- 按需 (on-demand) 模式：每项目默认 2000 slot
-- Reservation 模式：预留固定 slot

-- 创建 Reservation
CREATE RESERVATION analytics_reservation
OPTIONS (
    capacity = 500,                    -- 500 slot
    location = 'US',
    ignore_idle_slots = FALSE          -- 允许空闲 slot 借给其他 Reservation
);

-- 分配 Project 到 Reservation
CREATE ASSIGNMENT analytics_reservation.assignment
OPTIONS (
    assignee = 'projects/my-analytics-project',
    job_type = 'QUERY'
);
```

BigQuery 准入机制：

```
查询提交
    │
    ▼
Dry Run: 估算 slot 需求
    │
    ▼
Reservation 有可用 slot? 
    │ 是               │ 否
    ▼                 ▼
立即执行      Idle Slot Sharing?
                │ 是                  │ 否
                ▼                    ▼
              从其他 Reservation       排队
              借 slot                  (slot 释放后执行)
```

BigQuery 的准入控制是**隐式的**：查询会一直保持在"pending"状态直到有足够 slot 启动。不像 Snowflake 有明确的 timeout，BigQuery 的排队更接近"异步调度"。

### CockroachDB：内置自适应准入控制

CockroachDB 从 22.1 开始提供真正意义上的**自适应准入控制** (Admission Control)——这是传统数据库中极为罕见的设计：

```sql
-- 启用准入控制 (22.1+ 默认启用)
SET CLUSTER SETTING admission.kv.enabled = true;
SET CLUSTER SETTING admission.sql_kv_response.enabled = true;
SET CLUSTER SETTING admission.sql_sql_response.enabled = true;

-- 观察准入控制状态
SELECT * FROM crdb_internal.cluster_queues;
```

CockroachDB 的设计哲学：**根据系统过载信号 (CPU 延迟、IO 延迟) 动态调整准入率**。

```
┌────────────────────────────────────┐
│      每 250ms 采集过载信号          │
│                                    │
│  - 每 CPU 平均等待时间               │
│  - Pebble (LSM) L0 文件数           │
│  - Pebble 内存表大小                │
│  - Raft log 提交延迟                │
└────────────┬───────────────────────┘
             ▼
┌────────────────────────────────────┐
│   PID 控制器根据信号调整每秒 token   │
│   (令牌桶)                           │
└────────────┬───────────────────────┘
             ▼
  ┌──────────┼──────────┐
  │          │          │
  ▼          ▼          ▼
KV Queue  SQL Queue  Elastic Queue
(按优先级排序：HIGH/NORMAL/LOW)
```

CockroachDB 的**优先级维度**：

| 优先级 | 用途 | 典型场景 |
|-------|------|---------|
| `HIGH` | 关键系统任务 | 心跳、leaseholder 续约 |
| `NORMAL` | 常规用户流量 | OLTP 事务 |
| `LOW` / `USER_LOW` | 批处理 | BACKUP, IMPORT, CHANGEFEED |
| `BULK_LOW` (内部) | LSM 压缩、rebalance | 后台任务 |

**抢占语义**：CockroachDB 的准入控制是**真正的抢占式**——当系统检测到过载 (CPU 延迟 > 阈值) 时，即便 `NORMAL` 队列有查询在执行，新的 `LOW` 优先级请求会被延后，确保 `HIGH` 任务可以优先获得 token。

### TiDB：Resource Control 与 RU

TiDB 7.1 引入了 Resource Control 功能，基于 Request Unit (RU) 的统一计量：

```sql
-- 启用资源控制
SET GLOBAL tidb_enable_resource_control = 'ON';

-- 创建资源组
CREATE RESOURCE GROUP IF NOT EXISTS etl_group
    RU_PER_SEC = 500       -- 每秒 500 RU
    PRIORITY = LOW         -- 优先级 (HIGH/MEDIUM/LOW)
    BURSTABLE;             -- 允许突发超限

CREATE RESOURCE GROUP IF NOT EXISTS bi_group
    RU_PER_SEC = 2000
    PRIORITY = MEDIUM;

CREATE RESOURCE GROUP IF NOT EXISTS oltp_group
    RU_PER_SEC = 10000
    PRIORITY = HIGH;

-- 将用户绑定到资源组
ALTER USER etl_user RESOURCE GROUP etl_group;
ALTER USER bi_user  RESOURCE GROUP bi_group;

-- 会话级切换
SET RESOURCE GROUP bi_group;
```

**什么是 RU？** TiDB 把读写操作、CPU 消耗、存储开销折算为统一的 RU (Request Unit) 单位：

```
1 RU = 1 次 read / 1MB 顺序读 / 3 ms CPU / ...

例如：
  - 一次点查: ~1 RU
  - 一次 100 万行扫描: ~10000 RU
  - 一次跨 region 事务: 额外成本
```

准入机制：

```
查询提交
    │
    ▼
估算 RU 消耗
    │
    ▼
Resource Group 令牌桶是否有足够 RU?
    │ 是          │ 否
    ▼            ▼
立即执行    BURSTABLE?
              │ 是          │ 否
              ▼            ▼
            借用全局 RU    降速等待
            (允许超配额)
```

TiDB 的优势是**细粒度**：不只按查询数限流，而是按实际资源消耗精确控制。

### ClickHouse：基于并发与内存的双重准入

ClickHouse 的准入控制配置分散在多个维度：

```sql
-- 服务器级最大并发 (config.xml)
<max_concurrent_queries>100</max_concurrent_queries>

-- 用户级配额 (users.xml)
<profiles>
  <default>
    <max_memory_usage>10000000000</max_memory_usage>      <!-- 10 GB / 查询 -->
    <max_memory_usage_for_user>50000000000</max_memory_usage_for_user>  <!-- 50 GB / 用户 -->
    <max_concurrent_queries_for_user>20</max_concurrent_queries_for_user>
    <priority>1</priority>                                <!-- 0 最高 -->
    <queue_max_wait_ms>5000</queue_max_wait_ms>           <!-- 排队 5s 超时 -->
  </default>
  <analytics>
    <priority>5</priority>
    <max_concurrent_queries_for_user>5</max_concurrent_queries_for_user>
  </analytics>
</profiles>

-- 配额 (限流)
<quotas>
  <default>
    <interval>
      <duration>3600</duration>
      <queries>1000</queries>              <!-- 每小时最多 1000 查询 -->
      <errors>100</errors>
      <result_rows>1000000000</result_rows>
      <read_rows>10000000000</read_rows>
      <execution_time>3600</execution_time>
    </interval>
  </default>
</quotas>
```

ClickHouse 24.x+ 引入了更通用的 `CREATE WORKLOAD`：

```sql
-- 创建 Workload (24.x+)
CREATE WORKLOAD analytics
SETTINGS
    max_requests = 10,
    max_bytes = 1000000000;

-- 应用到查询
SET workload = 'analytics';
SELECT count(*) FROM huge_table;
```

### Trino / Presto：Resource Groups 与 JSON 配置

Trino/Presto 通过资源组 (Resource Groups) 实现分层准入控制：

```json
// etc/resource-groups.json
{
  "rootGroups": [
    {
      "name": "global",
      "softMemoryLimit": "80%",
      "hardConcurrencyLimit": 100,      // 全局并发上限
      "maxQueued": 1000,                // 全局排队上限
      "schedulingPolicy": "weighted_fair",
      "subGroups": [
        {
          "name": "adhoc",
          "softMemoryLimit": "50%",
          "hardConcurrencyLimit": 20,
          "maxQueued": 200,
          "schedulingPolicy": "fair",
          "schedulingWeight": 100       // 权重
        },
        {
          "name": "etl",
          "softMemoryLimit": "50%",
          "hardConcurrencyLimit": 10,
          "maxQueued": 100,
          "schedulingWeight": 50,
          "queuedTimeLimit": "1h",      // 排队超时
          "runningTimeLimit": "4h"      // 执行超时
        }
      ]
    }
  ],
  "selectors": [
    { "user": "bi_.*",  "group": "global.adhoc" },
    { "user": "etl_.*", "group": "global.etl"   }
  ]
}
```

**schedulingPolicy** 的选择：

| 策略 | 行为 |
|------|------|
| `fair` | 公平调度：每个子组轮流获得 slot |
| `weighted` | 按 `schedulingWeight` 比例分配 |
| `weighted_fair` | 权重 + 公平 (推荐) |
| `query_priority` | 按查询 session 中指定的 priority |

### Spark SQL：FIFO 与 FAIR Scheduler

Spark 的调度器可以配置为 FIFO 或 FAIR：

```scala
// 启用 FAIR 调度器
spark.conf.set("spark.scheduler.mode", "FAIR")
spark.conf.set("spark.scheduler.allocation.file", "/path/to/fairscheduler.xml")
```

```xml
<!-- fairscheduler.xml -->
<?xml version="1.0"?>
<allocations>
  <pool name="production">
    <schedulingMode>FAIR</schedulingMode>
    <weight>2</weight>
    <minShare>5</minShare>         <!-- 最少保证 5 个 core -->
  </pool>
  <pool name="adhoc">
    <schedulingMode>FIFO</schedulingMode>
    <weight>1</weight>
    <minShare>1</minShare>
  </pool>
</allocations>
```

```scala
// 提交作业到指定池
spark.sparkContext.setLocalProperty("spark.scheduler.pool", "production")
spark.sql("SELECT ...").collect()
```

FIFO vs FAIR：

```
FIFO (默认):
  Query A (大) → Query B (小) → Query C (小)
  若 A 占用全部资源，B 和 C 需等 A 完成

FAIR:
  Query A (大) + Query B (小) + Query C (小) 并行
  每个池按权重分享资源，小查询不被大查询饿死
```

### Teradata：TASM (Teradata Active System Management)

Teradata TASM 是工业界最复杂、最全面的准入控制系统之一：

```
TASM 关键组件:
  1. Workload Definitions (WD): 基于会话属性分类
  2. Workload Management Rules: 准入、调度规则
  3. Throttle Rules: 并发数、CPU 分配
  4. Filter Rules: 过滤 (如阻止特定时段的大查询)
  5. Exception Rules: 异常处理 (自动降级、杀死、告警)
```

主要配置通过 Viewpoint UI 进行，但 TASM 提供了强大的：

- **多维度分类**：用户、应用、查询带、时间窗口、数据访问模式
- **时间窗口**：白天 OLTP 优先，夜间 ETL 优先
- **自动降级**：长查询自动切换到低优先级队列
- **异常检测**：查询超时自动 kill 并通知 DBA

### 其他引擎

**DB2** (WLM):
```sql
CREATE WORKLOAD wl_reports APPLNAME('reports_app')
    SERVICE CLASS sc_analytics;

ALTER SERVICE CLASS sc_analytics
    ADMISSION RESOURCE PROFILE
      CONCURRENTDBCOORDACTIVITIES 20
      QUEUETIMEOUT 300;
```

**Vertica** (Resource Pool):
```sql
CREATE RESOURCE POOL analytics
  MEMORYSIZE '10G'
  MAXMEMORYSIZE '30G'
  MAXCONCURRENCY 8
  QUEUETIMEOUT 300
  PRIORITY 50;
```

**Impala** (admission control，基于内存准入):
```xml
<!-- fair-scheduler.xml -->
<allocations>
  <queue name="bi">
    <maxRunningApps>10</maxRunningApps>
    <maxQueuedApps>50</maxQueuedApps>
    <maxMemory>50gb</maxMemory>
  </queue>
</allocations>
```

**StarRocks** (Resource Group):
```sql
CREATE RESOURCE GROUP bi_group
    TO (user='bi_user')
    WITH (
        "cpu_weight" = "10",
        "mem_limit" = "30%",
        "concurrency_limit" = "20",
        "big_query_cpu_second_limit" = "300"
    );
```

## Snowflake Warehouse Queuing 深度剖析

### 何时开始排队？

Snowflake 的排队触发点有三个：

```
触发条件:
  1. 活跃查询数 ≥ MAX_CONCURRENCY_LEVEL (默认 8)
  2. Warehouse 内存不足 (查询溢出到本地 SSD 或远端存储)
  3. Multi-Cluster 未启用或已达 MAX_CLUSTER_COUNT
```

### 查询状态机

```
QUEUED_PROVISIONING    <- 等待 Warehouse 恢复 (从 SUSPENDED 中)
       ↓
QUEUED                 <- 排队等待 slot
       ↓
RUNNING                <- 执行中
       ↓
SUCCESS / FAILED / CANCELED / EXECUTING_RESULT_RECALCULATION
```

监控排队：

```sql
-- 查看正在排队的查询
SELECT 
    query_id,
    query_text,
    warehouse_name,
    execution_status,
    queued_provisioning_time,
    queued_repair_time,
    queued_overload_time,
    total_elapsed_time
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE execution_status IN ('QUEUED', 'QUEUED_PROVISIONING')
    AND start_time >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
ORDER BY queued_overload_time DESC;

-- 排队时间分布
SELECT 
    warehouse_name,
    DATE_TRUNC('hour', start_time) AS hour,
    AVG(queued_overload_time) / 1000 AS avg_queue_sec,
    MAX(queued_overload_time) / 1000 AS max_queue_sec,
    COUNT(*) AS query_count
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
    AND queued_overload_time > 0
GROUP BY warehouse_name, hour
ORDER BY avg_queue_sec DESC;
```

### Multi-Cluster Warehouse 的自动扩缩容

```sql
CREATE WAREHOUSE bi_wh
    WAREHOUSE_SIZE = 'MEDIUM'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 10
    SCALING_POLICY = 'STANDARD';    -- STANDARD 或 ECONOMY
```

**STANDARD 模式** (快速响应):
```
触发扩容: 任何查询排队 > 6 秒
触发缩容: 集群空闲 2-3 分钟
特点: 最小化排队时间，适合交互式 BI
```

**ECONOMY 模式** (节省成本):
```
触发扩容: 排队查询数足以让新集群 6 分钟都满载
触发缩容: 集群空闲 5-6 分钟
特点: 更高排队容忍度，换取成本降低
```

### 实战建议

1. **不要默认让 `STATEMENT_QUEUED_TIMEOUT_IN_SECONDS` 为 0**。设为合理值 (如 600s)，避免客户端永远等待。
2. **对交互式 BI 设小的 `MAX_CONCURRENCY_LEVEL` (4-6)**，保证单个查询有更多资源；对批处理设大 (10-15)。
3. **监控 `QUEUED_OVERLOAD_TIME / TOTAL_ELAPSED_TIME` 比例**。若长期 > 10%，考虑扩容或改 Multi-Cluster。
4. **区分 `QUEUED_PROVISIONING` (冷启动) 和 `QUEUED_OVERLOAD` (过载)**：前者是 Warehouse 从 SUSPENDED 恢复的时间，可以通过 `MIN_CLUSTER_COUNT = 1` 且不暂停来消除。

## CockroachDB Admission Control 深度剖析

### 自适应准入控制的设计哲学

传统数据库的准入控制往往是**静态配置**的：设置 `max_concurrent = 20`，超过就排队。但实际系统的"过载点"是随工作负载变化的——同样 20 并发，点查 vs 分析查询的资源占用天差地别。

CockroachDB (22.1+) 采用**信号驱动**的准入控制：

```
┌──────────────────────────────────────────────┐
│            过载信号 (Overload Signals)         │
├──────────────────────────────────────────────┤
│ 1. CPU Scheduling Delay                        │
│    (goroutine 等待 CPU 的平均时间)              │
│    阈值: > 1ms → 过载                           │
│                                                │
│ 2. Pebble LSM L0 Files                         │
│    (L0 堆积表示 compaction 跟不上)              │
│    阈值: > 1000 files → 过载                   │
│                                                │
│ 3. Pebble Memtable Count                       │
│    (memtable 增长表示 flush 跟不上)             │
│    阈值: > 4 memtables → 过载                   │
│                                                │
│ 4. IO Latency (Disk P99)                       │
│    阈值: > 100ms → 过载                         │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│        PID 控制器 (250ms 周期)                  │
│                                                │
│  根据信号偏差调整 token 发放速率                 │
│    err = target - current                      │
│    rate += Kp * err + Ki * Σerr + Kd * Δerr    │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│         令牌桶 (Token Buckets)                  │
├──────────────────────────────────────────────┤
│  HIGH   Queue: token_high                      │
│  NORMAL Queue: token_normal                    │
│  LOW    Queue: token_low                       │
│                                                │
│  每个队列按优先级等待 token                      │
└──────────────────────────────────────────────┘
```

### 优先级层次

CockroachDB 的准入队列按优先级分为多个 FIFO 队列：

```
优先级 (从高到低):
  1. HIGH       - 系统内部任务 (lease transfer, heartbeat)
  2. NORMAL     - 用户 OLTP 事务
  3. USER_LOW   - 用户指定低优先级的查询
  4. LOW        - 批处理 (BACKUP, IMPORT)
  5. BULK_LOW   - Pebble compaction, rebalance (elastic)
```

应用指定查询优先级：

```sql
-- 会话级别
SET default_transaction_priority = LOW;

-- 事务级别
BEGIN PRIORITY LOW;
INSERT INTO large_table SELECT * FROM staging_table;
COMMIT;

-- 或使用 SQL hint
SELECT /*+ PRIORITY=LOW */ count(*) FROM billion_rows_table;
```

### KV vs SQL 层的准入

CockroachDB 的准入控制分两层：

```
┌─────────────────────┐
│   SQL 层 (客户端)     │
│   (SQL parse, opt)   │
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ SQL Admission Queue │
│ admission.sql_      │
│ kv_response.enabled │
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│   KV 层 (分布式)      │
│   (Raft, Pebble)    │
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ KV Admission Queue  │
│ admission.kv.       │
│ enabled             │
└─────────────────────┘
```

这种双层设计的好处：

1. **前端保护**：SQL 层的准入保护 SQL 协议层不被压垮
2. **后端保护**：KV 层的准入保护底层存储引擎 (Pebble LSM) 不因写入过多而 compaction 崩溃
3. **弹性任务隔离**：BACKUP/CHANGEFEED 等弹性任务走独立队列，不影响前台 OLTP

### 实战监控

```sql
-- 查看当前准入队列状态
SELECT * FROM crdb_internal.cluster_queues;

-- 关键指标 (通过 Prometheus/Grafana 监控):
--   admission.wait_durations.kv           KV 层等待时间
--   admission.wait_durations.sql          SQL 层等待时间
--   admission.requested.kv                KV 请求总数
--   admission.admitted.kv                 KV 准入数
--   admission.errored.kv                  KV 拒绝数
--   admission.granter.cpu_load_short      短周期 CPU 负载
--   admission.granter.elastic_io_tokens   弹性 IO token 数
```

### 与传统准入控制的对比

| 特性 | 传统 (静态并发数) | CockroachDB (自适应) |
|------|-----------------|---------------------|
| 配置难度 | 需为每种负载调参 | 自动，零调优 |
| 突发负载 | 静态上限无弹性 | 根据实时信号动态放开 |
| 混合负载 | 难处理 OLTP+OLAP 混合 | 按优先级天然隔离 |
| 抢占 | 通常不支持 | 支持 (低优先级让位给高) |
| 成本 | PID 控制器有 CPU 开销 | ~1% CPU 额外开销 |

## 准入控制的常见设计模式

### 1. 漏桶 vs 令牌桶

**漏桶 (Leaky Bucket)**：请求以固定速率离开桶，突发时溢出
```
请求 → [ 桶 ] → 以固定速率 r 离开
```
**令牌桶 (Token Bucket)**：按速率生成令牌，请求消耗令牌
```
每秒生成 r 个令牌 → [ 桶 ] ← 请求消耗令牌
```
差异：令牌桶允许突发 (bucket 累积的令牌可一次用完)；漏桶不允许突发。

TiDB 的 RU 限流、Redshift 的 Concurrency Scaling 都基于**令牌桶**模型。CockroachDB 也使用令牌桶，但桶容量根据过载信号动态调节。

### 2. 排队策略：FIFO / LIFO / Priority / Weighted Fair Queueing

| 策略 | 优点 | 缺点 | 典型应用 |
|------|------|------|---------|
| FIFO | 简单、公平 | 大查询阻塞小查询 | Spark FIFO |
| LIFO | 最新请求最快响应 | 老请求饥饿 | 很少使用 |
| Priority | 高优先级保障 | 低优先级饥饿 | Oracle, CockroachDB |
| Weighted Fair | 按权重分享 slot | 实现复杂 | Trino, Spark FAIR |

### 3. 准入预测 vs 准入反馈

**预测型** (Predictive)：查询开始前估算资源需求，如果超出池容量则拒绝
- 代表：Impala (内存准入)、Oracle (`MAX_EST_EXEC_TIME`)
- 优点：避免 OOM
- 缺点：依赖优化器估算精度

**反馈型** (Feedback)：运行时根据实际负载动态调节
- 代表：CockroachDB、Linux CPU scheduler
- 优点：不依赖估算
- 缺点：可能短时过载

### 4. 拒绝 vs 排队 vs 降级

| 方式 | 客户端体验 | 系统稳定性 |
|------|----------|-----------|
| 拒绝 | 立即失败，需重试 | 最稳定 |
| 排队 | 等待后执行 | 次稳定 |
| 降级 | 以降低优先级/资源执行 | 灵活 |

OLTP 系统倾向拒绝 (故障快速反馈)；OLAP 系统倾向排队 (BI 查询可以等)。Oracle Resource Manager、CockroachDB 都支持**降级**策略。

### 5. 基于 SLA 的动态准入 (Google Cortex 风格)

现代云数仓 (Snowflake、BigQuery、Redshift) 正在实验**基于 SLA** 的准入：

```
每个查询有目标 SLA (如 P95 < 1s)
    ↓
系统预测查询的实际延迟
    ↓
若预测延迟 < SLA → 立即准入
若预测延迟 ≥ SLA → 扩容 / 降级 / 拒绝
```

BigQuery 的 "BI Engine" 自动将热数据放入内存加速；Redshift Auto WLM 根据历史训练模型预测查询复杂度。

## 关键发现

1. **"标准" 不存在**：SQL 标准完全没有准入控制语法。每个引擎各自为政，语法差异巨大。这是与资源管理 (WLM) 相同的"硬件抽象不透明"导致的历史局面。

2. **OLTP 与 OLAP 的根本分歧**：
   - OLTP (PostgreSQL、MySQL、Oracle) 以**硬连接数上限**为主，辅以连接池 (PgBouncer、ProxySQL) 在外部排队。理念：宁可拒绝新连接，也要保住已连上的请求性能。
   - OLAP (Snowflake、Redshift、BigQuery、Trino) 以**队列 + 超时**为主，支持长时间排队，理念：BI 查询延迟 10 秒可接受，崩掉整个集群不可接受。

3. **内存准入是 OLAP 特有需求**：Impala、Vertica、Trino、SQL Server 都有内存准入机制，利用优化器估算内存需求来提前排队或拒绝。OLTP 系统的单查询内存通常可预测，内存准入需求小。

4. **自适应准入控制是新趋势**：CockroachDB 22.1+、TiDB 7.1+ 引入了基于过载信号的自适应准入控制，相比静态配置更适合混合负载。这是数据库运维复杂度降低的重要标志。

5. **优先级抢占罕见**：多数引擎的优先级只影响**调度顺序**，不支持真正的抢占 (正在执行的低优先级查询不会被暂停)。例外：CockroachDB KV 层、Azure Synapse Workload Group、Teradata TASM。

6. **云数仓的弹性扩容正在改变准入控制范式**：Snowflake Multi-Cluster Warehouse、Redshift Concurrency Scaling、BigQuery Flex Slot 都通过**临时扩容**取代了传统"排队等待"——只要愿意付更多钱就能跳过队列。

7. **排队超时参数常被忽视**：`STATEMENT_QUEUED_TIMEOUT_IN_SECONDS` 默认为 0 (无限等待) 是 Snowflake 的常见坑。ClickHouse 默认 5s 更激进。生产环境务必设置合理超时，避免客户端无限 hang。

8. **分类器是准入控制的灵魂**：SQL Server 的 Classifier Function、Redshift 的 WLM 规则、Trino 的 Selectors、Oracle 的 Consumer Group Mapping——把查询路由到正确队列是准入控制的第一步，但也是最容易配错的地方。

9. **PgBouncer 是 PostgreSQL 生态的准入控制事实标准**：PG 本身没有内置准入控制，社区通过 PgBouncer (或 Pgpool-II) 实现外部池化 + 排队。这意味着准入控制逻辑和 DB 解耦，便于独立扩展，但也增加了部署复杂度。

10. **SQL Server Resource Governor 是 OLTP 数据库中的准入控制典范**：通过 `GROUP_MAX_REQUESTS` + `REQUEST_MAX_MEMORY_GRANT_PERCENT` + 分类器函数的组合，SQL Server 在单个实例内实现了细粒度的多租户准入，是 PG/MySQL 望尘莫及的。

11. **HTAP 数据库的双层准入是未来方向**：TiDB 用 RU 统一度量 TiKV (OLTP) 和 TiFlash (OLAP) 的消耗；CockroachDB 用 KV/SQL 双层队列隔离。HTAP 系统的挑战是如何让 OLTP 和 OLAP 在同一集群内各自保证 SLA，准入控制是核心手段。

12. **Impala 的内存准入模型值得借鉴**：查询提交后，协调器根据优化器估算**先排队**，直到目标资源池有足够空闲内存才准入。这避免了"查询执行到一半因 OOM 崩溃导致所有中间结果浪费"的问题——内存不够宁可让它等着。

13. **Teradata TASM 仍是工业界最完整的 WLM/准入控制产品**：它支持时间窗口、异常检测、自动降级、多维度分类，覆盖了准入控制的所有维度。其他引擎至今仍在追赶。

14. **自适应准入控制的代价是可观测性下降**：CockroachDB 的 PID 控制器根据实时信号调整，DBA 很难预测"为什么这个查询被排队"。需要强大的 Metrics 和 Tracing 才能 debug。这是"零调优"的代价。

15. **云原生的按秒计费改变了准入控制的经济账**：传统数据库的准入控制是为了"保护集群不宕机"；云数仓的准入控制是为了"控制每秒的美元支出"。Snowflake 的 MAX_CLUSTER_COUNT 本质上是预算上限，而非技术上限。

## 参考资料

- PostgreSQL: [Connection Settings](https://www.postgresql.org/docs/current/runtime-config-connection.html)
- PgBouncer: [query_wait_timeout](https://www.pgbouncer.org/config.html)
- Oracle: [Database Resource Manager](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-resources-with-oracle-database-resource-manager.html)
- SQL Server: [Resource Governor](https://learn.microsoft.com/en-us/sql/relational-databases/resource-governor/resource-governor)
- Snowflake: [Warehouse Considerations - Queuing](https://docs.snowflake.com/en/user-guide/warehouses-considerations)
- Snowflake: [STATEMENT_QUEUED_TIMEOUT_IN_SECONDS](https://docs.snowflake.com/en/sql-reference/parameters#statement-queued-timeout-in-seconds)
- Amazon Redshift: [WLM Queue Configuration](https://docs.aws.amazon.com/redshift/latest/dg/cm-c-defining-queries.html)
- BigQuery: [Reservations and Slot Commitments](https://cloud.google.com/bigquery/docs/reservations-intro)
- CockroachDB: [Admission Control](https://www.cockroachlabs.com/docs/stable/architecture/admission-control.html)
- CockroachDB Blog: [Choosing the right admission control policy](https://www.cockroachlabs.com/blog/admission-control-in-cockroachdb/)
- TiDB: [Use Resource Control to Achieve Resource Isolation](https://docs.pingcap.com/tidb/stable/tidb-resource-control)
- Teradata TASM: [Active System Management](https://docs.teradata.com/r/Teradata-VantageTM-Workload-Management-User-Guide)
- Spark: [Job Scheduling (FAIR Scheduler)](https://spark.apache.org/docs/latest/job-scheduling.html)
- Trino: [Resource Groups](https://trino.io/docs/current/admin/resource-groups.html)
- Vertica: [Managing Workloads with Resource Pools](https://docs.vertica.com/latest/en/admin/resource-manager/)
- Impala: [Admission Control and Query Queuing](https://impala.apache.org/docs/build/html/topics/impala_admission.html)
- DB2: [Workload Management](https://www.ibm.com/docs/en/db2/11.5?topic=management-workload)
- Azure Synapse: [Workload Groups](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-workload-group-transact-sql)
- SAP HANA: [Workload Management](https://help.sap.com/docs/SAP_HANA_PLATFORM/6b94445c94ae495c83a19646e7c3fd56/a6eda4e12d544355be0081a13d396b61.html)
- Almeida et al. "Characterizing, Modeling, and Benchmarking RocksDB Key-Value Workloads at Facebook" (FAST '20)
- Dean & Barroso, "The Tail at Scale" (CACM 2013)
