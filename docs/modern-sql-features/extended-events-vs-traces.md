# 扩展事件与 SQL 跟踪 (Extended Events and SQL Traces)

当慢查询日志只能告诉你"哪些 SQL 慢"，而执行计划只能告诉你"它本来打算怎么跑"，**只有 SQL 跟踪能告诉你"它实际发生了什么"**：每一次行获取、每一次锁等待、每一次解析硬解析、每一次递归 SQL——以微秒级精度逐事件还原。从 Oracle 1980 年代的 10046 trace、SQL Server 1998 年的 SQL Profiler，到 2008 年 Microsoft 推出的 Extended Events（xEvents），再到今天围绕 eBPF/USDT 探针的现代化追踪潮流——SQL 跟踪从未进入标准，却是数据库引擎诊断学最具厚度的领域。

## 没有 SQL 标准

ISO/IEC 9075 SQL 标准（SQL:1992 至 SQL:2023）**没有任何关于 SQL 跟踪、扩展事件、Profiler 或运行时事件订阅的内容**。所有引擎都是各自演化：

- Oracle 在 v6（约 1988）就引入 SQL Trace（事件号 10046），是数据库 SQL 跟踪的开山鼻祖
- Microsoft 在 SQL Server 7.0（1998）推出 SQL Profiler + SQL Trace
- Microsoft 在 SQL Server 2008 推出 Extended Events（xEvents）作为低开销替代
- Microsoft 在 SQL Server 2012 主推 xEvents 并将 SQL Profiler 标记为废弃
- Microsoft 在 SQL Server 2022 完全移除了对扩展事件 GUI 之外的旧 Profiler 工具的官方推荐
- MySQL 在 5.5（2010）引入 Performance Schema 框架，5.6（2013）暴露事件表
- PostgreSQL 至今（2026）没有原生跟踪机制，依赖 `auto_explain` / `pg_stat_statements` / 第三方 eBPF
- ClickHouse 引入 `query_log` / `trace_log` / OpenTelemetry 一体化设计

由于没有标准，**事件命名、过滤语法、缓冲机制、输出目标、文件格式、订阅模型完全异构**。本文系统对比 45+ 主流引擎在跟踪/扩展事件层面的能力差异，并深入剖析 SQL Server xEvents 与 Oracle 10046 这两个范式典范。

## 跟踪 vs 慢查询日志 vs 等待事件 vs 审计：定位边界

为了避免概念混淆，先厘清四种不同的"运行时观察机制"：

| 维度 | 慢查询日志 | 等待事件 | 审计日志 | **SQL 跟踪 / xEvents** |
|------|----------|---------|---------|---------------------|
| 触发模型 | 阈值过滤（执行时长 > N） | 轮询/采样累计 | 规则匹配（每条 DDL/DML） | 事件订阅（任意预定义事件点） |
| 输出粒度 | 每条慢 SQL | 等待类型计数器 | 每条受审 SQL | 每个事件（解析、I/O、锁、错误...） |
| 典型开销 | 阈值外为零，命中后较低 | 极低（采样） / 中（同步累计） | 中（每事件落盘） | 可调（条件、过滤、缓冲） |
| 主要用途 | 长尾捕获、慢 SQL 分析 | 资源等待诊断 | 合规、安全溯源 | 深度行为还原、性能内核诊断 |
| 代表实现 | MySQL slow_query_log / PG log_min_duration_statement | Oracle V$SESSION_WAIT / SQL Server sys.dm_os_wait_stats | Oracle AUDIT / SQL Server CREATE SERVER AUDIT | **SQL Server xEvents / Oracle 10046 / MySQL Performance Schema** |

跟踪机制的差异化能力在于：**任意事件点订阅 + 结构化字段 + 低开销 + 二进制缓冲 + 运行时动态启停**。这正是 Oracle 10046 与 SQL Server xEvents 设计的核心。

## 支持矩阵 (45+ 引擎)

### 1. 原生跟踪机制总览

| 引擎 | 原生跟踪机制 | 关键名称 | 引入版本 | 当前状态 |
|------|------------|---------|---------|---------|
| SQL Server | 是 | Extended Events (xEvents) | 2008 | 主推（SQL Trace 已弃用 2012） |
| Oracle | 是 | SQL Trace 10046 + tkprof | v6 (~1988) | 仍主流 + Real-Time SQL Monitoring |
| MySQL | 是 | Performance Schema events | 5.5 (2010) / 5.6 表（2013） | 主推 |
| MariaDB | 是 | Performance Schema (继承 MySQL) + Audit/Slow | 5.5+ | 主推 |
| PostgreSQL | 部分 | auto_explain + pg_stat_statements + eBPF/USDT | 8.4 (2009) | 无原生跟踪框架 |
| DB2 | 是 | db2trc + Event Monitor + db2pd | 早期 | 主推 |
| SQLite | 否 | sqlite3_trace_v2 (C API) | 3.14 (2016) | C 回调，非 SQL |
| Snowflake | 部分 | QUERY_HISTORY + ACCESS_HISTORY 视图 | GA | 服务端管理 |
| BigQuery | 部分 | INFORMATION_SCHEMA.JOBS_* + Cloud Logging | GA | 服务端管理 |
| Redshift | 部分 | STL_QUERY / SVL_QLOG / SYS_QUERY_HISTORY | 早期 | 视图为主 |
| ClickHouse | 是 | query_log + trace_log + opentelemetry_span_log | 早期 / 1.1+ | 主推 |
| Trino | 部分 | EventListener SPI (插件) | 早期 | 需要扩展实现 |
| Presto | 部分 | EventListener SPI | 早期 | 需要扩展实现 |
| Spark SQL | 是 | QueryExecutionListener + SparkListener + event log | 1.x+ | 主推 |
| Hive | 部分 | HiveServer2 hooks (pre/post/exec/failure) | 早期 | 主推（hook 框架） |
| Flink SQL | 部分 | JobListener + Metrics Reporter | 1.x+ | 通过 Metrics |
| Databricks | 是 | Spark + Unity Catalog event log + system.query.history | GA | 主推 |
| Teradata | 是 | DBQL (Query Logging) + DUL + tdbms trace | V2R5+ | 主推 |
| CockroachDB | 是 | EXPLAIN ANALYZE + crdb_internal.cluster_queries | 19+ | 主推 |
| TiDB | 是 | TopSQL + Statements Summary + tidb-trace | 4.0+ | 主推 |
| OceanBase | 是 | GV$OB_SQL_AUDIT + trace_log | 早期 | 主推 |
| YugabyteDB | 部分 | yb_pg_stat_statements + yb_query_diagnostics | 2.6+ | PG 兼容 + 扩展 |
| Greenplum | 部分 | gp_workfile + 继承 PG 机制 | 6.x+ | 继承 PG |
| Citus | 部分 | citus_stat_statements + 继承 PG | 6.x+ | 继承 PG |
| SingleStore | 是 | INFORMATION_SCHEMA.PROFILE + plancache + tracelog | 7.x+ | 主推 |
| Vertica | 是 | DC_REQUESTS_ISSUED / DC_EXECUTION_ENGINE_PROFILES | 早期 | DC（Data Collector）框架 |
| Sybase ASE | 是 | sp_sysmon + MDA + showplan + diagserver | 12.5+ | 历史悠久 |
| SAP HANA | 是 | SQL Plan Cache + Expensive Statements + Trace | 1.0+ | 主推 |
| Informix | 是 | onstat -g sql + sqexplain.out | 早期 | 主推 |
| Firebird | 是 | Trace API（trace.conf） | 2.5 (2010) | 主推 |
| H2 | 部分 | TRACE_LEVEL_FILE / TRACE_LEVEL_SYSTEM_OUT | 早期 | 简易 |
| HSQLDB | 否 | -- | -- | 不支持 |
| Derby | 部分 | derby.log + 用户跟踪 | 早期 | 简易 |
| Amazon Athena | 部分 | CloudWatch Logs + CloudTrail | GA | 服务端 |
| Azure Synapse | 部分 | sys.dm_pdw_exec_requests + xEvents（部分） | GA | 兼容 SQL Server 子集 |
| Google Spanner | 部分 | Cloud Trace + Cloud Audit Logs | GA | 服务端 |
| Materialize | 部分 | mz_internal.mz_recent_activity_log | GA | 视图 |
| RisingWave | 部分 | rw_catalog.rw_query_log（有限） | 早期 | 视图 |
| Yellowbrick | 部分 | sys.log_query / sys.log_session | GA | 视图 |
| DuckDB | 部分 | PRAGMA enable_profiling + EXPLAIN ANALYZE | 0.x+ | 进程内 |
| Impala | 部分 | impalad logs + Web UI profile | 早期 | 文本 profile |
| Doris | 是 | fe.audit.log + Profile + tracing (OpenTelemetry) | 1.2+ | 主推 |
| StarRocks | 是 | fe.audit.log + Query Profile | 2.x+ | 主推 |
| TimescaleDB | 部分 | 继承 PG + telemetry + auto_explain | 继承 PG | 继承 PG |
| QuestDB | 部分 | server log + Web Console | 早期 | 简易 |
| Exasol | 部分 | EXA_DBA_PROFILE_RUNNING + EXA_USER_AUDIT_SQL | 早期 | 视图 |
| CrateDB | 部分 | sys.jobs / sys.jobs_log / OpenTracing 集成 | 3.x+ | 视图 |
| Databend | 部分 | system.query_log / system.profile | GA | 视图 |
| Firebolt | 部分 | information_schema.query_history | GA | 视图 |
| InfluxDB (SQL) | 否 | -- | -- | 流处理模型 |
| Exasol | 部分 | EXASTATS / 性能视图 | 早期 | 视图 |

> 统计：约 18 个引擎提供完整的事件订阅/跟踪框架（Oracle 10046、SQL Server xEvents、MySQL Performance Schema、DB2 db2trc、ClickHouse trace_log、Spark/Databricks event log 等），约 22 个引擎仅提供"系统视图 + 慢日志 + 简单 hook"的混合方案，约 5 个引擎完全没有跟踪能力（SQLite、HSQLDB、InfluxDB SQL 等）。**PostgreSQL 是少数没有原生 SQL 级跟踪框架的主流引擎**——必须依赖 auto_explain + pg_stat_statements 组合或外部 eBPF 工具。

### 2. 结构化事件过滤（Predicate / WHERE / Filter）

跟踪的核心难点不是"启用"而是"如何只采集你关心的事件"。下表对比各引擎的结构化过滤能力。

| 引擎 | 过滤语法 | 字段类型 | 复合条件 | 动态修改 |
|------|---------|---------|---------|---------|
| SQL Server xEvents | `WHERE` 谓词（C-like） | 全字段 + Action | AND/OR/嵌套 | ALTER EVENT SESSION |
| Oracle 10046 | event level / 模块/动作过滤 | level 1/4/8/12 | 通过 DBMS_MONITOR | DBMS_SESSION/DBMS_MONITOR |
| MySQL Performance Schema | setup_consumers + setup_instruments + threads | 表行（用 UPDATE） | 多表 JOIN 控制 | 在线 UPDATE |
| MariaDB Performance Schema | 同 MySQL | 同 MySQL | 同 MySQL | 在线 UPDATE |
| PostgreSQL auto_explain | 阈值（duration） + 采样率 | 阈值 + format/timing | 全部或全无 | reload |
| DB2 db2trc | mask + 组件号 + 接收器 | 函数/事件层级 | mask 表达式 | db2trc clear/dump |
| ClickHouse | log_queries / log_queries_min_type / log_query_threads | 多个布尔/阈值 | session 设置 | 立即 |
| SingleStore | profile_for_debug + plan_cache | -- | -- | -- |
| Vertica DC | DC_REQUESTS_ISSUED 直接 SQL 查询 | 全字段 | SQL WHERE | 视图查询 |
| Spark | QueryExecutionListener 代码过滤 | onSuccess/onFailure | 代码逻辑 | 重启 Driver |
| Trino | EventListener queryCreatedEvent / queryCompletedEvent | 全字段 | 代码逻辑 | 重启 |
| Hive | hook 类自定义 | HiveSemanticAnalyzerHook 等 | 代码 | 重启 |
| Firebird Trace | trace.conf 正则 + connection/statement 过滤 | 文本配置 | AND（隐含） | 启用新会话 |
| Snowflake | -- (服务端，只能 WHERE on QUERY_HISTORY) | -- | SQL WHERE | -- |
| BigQuery | -- (Cloud Logging filter) | -- | 日志 filter 语法 | -- |
| TiDB TopSQL | tidb_top_sql_max_statement_count 等 | 数值 | -- | SET | 

xEvents 的 WHERE 谓词最接近"在内核态过滤"——即事件触发后立刻判断是否丢弃，未命中的事件几乎零开销；Oracle 通过 level + 模块/动作维度过滤；MySQL Performance Schema 走另一条路：用 SQL UPDATE setup_* 表来开关 instruments 与 threads，在配置修改后引擎按表内容决定是否记录。

### 3. 输出目标：环形缓冲 / 文件 / 系统视图

跟踪输出的组织方式直接决定了它的开销与可观测性。

| 引擎 | 环形缓冲 (ring buffer) | 文件输出 | 系统视图/表 | OpenTelemetry/外部 |
|------|----------------------|---------|------------|------------------|
| SQL Server xEvents | `ring_buffer` target | `event_file` (.xel 二进制) | `sys.dm_xe_*` | Azure Monitor |
| Oracle 10046 | -- (内存 trace per session) | `<sid>_ora_<pid>.trc` 文本 | `V$DIAG_ALERT_EXT` 等 | OEM/Cloud Control |
| MySQL Performance Schema | `events_*_history` (定长环) | -- | `events_statements_*` | 通过 exporter |
| MariaDB | 同 MySQL | -- | 同 MySQL | exporter |
| PostgreSQL auto_explain | -- | server log | -- | otel_collector |
| DB2 db2trc | -- (内存或文件) | `db2trc dump` 二进制 | `MON_GET_*` 函数 | -- |
| ClickHouse | -- | query_log MergeTree 表 | system.query_log / system.trace_log | OpenTelemetry 内置 |
| Spark / Databricks | -- | event log JSON 文件 | system.query.history | -- |
| Trino / Presto | -- | EventListener 自定义 | system.runtime.queries | EventListener |
| Snowflake | -- | -- | INFORMATION_SCHEMA.QUERY_HISTORY + ACCOUNT_USAGE | -- |
| BigQuery | -- | Cloud Logging | INFORMATION_SCHEMA.JOBS | Cloud Logging |
| Vertica DC | DC tables 内置环形 | flex 表 | DC_*视图 | -- |
| TiDB | TopSQL 内存 ring | tidb-slow.log | INFORMATION_SCHEMA.* | OpenTelemetry |
| OceanBase | 内存 ring (sql_audit) | observer.log | GV$OB_SQL_AUDIT | -- |
| Firebird Trace | -- | 文本/二进制日志 | MON$STATEMENTS | -- |
| SingleStore | tracelog 环 | -- | INFORMATION_SCHEMA.PROFILE | -- |
| Doris/StarRocks | -- | fe.audit.log | INFORMATION_SCHEMA.* | OpenTelemetry（Doris） |
| SAP HANA | -- | M_EXPENSIVE_STATEMENTS_TRACE 文件 | M_EXPENSIVE_STATEMENTS | -- |

xEvents 的 `ring_buffer` 设计很关键：默认 4MB 的内存环，新事件覆盖旧事件，用于实时排查；同时可挂 `event_file` 落盘到 `.xel` 二进制做持久化。Oracle 10046 输出的是文本 trace 文件，需 `tkprof` 工具二次解析；MySQL Performance Schema 的 history 表本身就是定长环（默认 events_statements_history.size = 10），新行覆盖旧行；ClickHouse 把 query_log 直接做成 MergeTree 表，原生 SQL 查询历史。

### 4. 弃用状态与替代方案

跟踪机制的演化往往伴随着旧机制的弃用。

| 引擎 | 旧机制 | 弃用版本 | 替代机制 | 当前状态 |
|------|-------|---------|---------|---------|
| SQL Server | SQL Trace + SQL Profiler | 2012（标记为 deprecated） | Extended Events (xEvents) | xEvents 是唯一新增功能位置 |
| SQL Server | SQL Profiler GUI 工具 | 2022 SSMS 18+（保留但不推荐） | XEvents Profiler (SSMS 17+) + Azure Data Studio | XEvents Profiler 是 GUI 替代 |
| Oracle | DBMS_SUPPORT (event 10046) | 兼容保留 | DBMS_MONITOR + DBMS_SESSION + Real-Time SQL Monitoring | 多套并存 |
| MySQL | mysqld 的 `general_log` 文件 | 仍可用 | Performance Schema | 慢查询用 PS，全量审计用 audit plugin |
| PostgreSQL | -- (从未有原生 SQL Profiler) | -- | auto_explain + pg_stat_statements | 长期话题 |
| DB2 | snapshot monitor (SQL_API) | 9.7（DEPRECATED） | MON_GET_* 表函数 + db2trc | 表函数路线 |
| Sybase ASE | sp_sysmon | 仍可用 | MDA Monitor Tables | 二者并存 |
| Firebird | gds.log 简易日志 | 2.5 起 | Trace API (trace.conf) | Trace API |

SQL Server 是这条线上信号最清晰的厂商：从 2012 起，**xEvents 是 SQL Server 团队加新事件的唯一位置**，所有自 2008 R2 之后引入的诊断点（资源管理、内存、查询统计、Always On 等）都只通过 xEvents 暴露。SQL Profiler 在 SQL Server 2022 被进一步弱化（不再有新功能），SSMS 18+ 推荐使用 "XEvents Profiler"（SSMS 17.3 加入）作为兼具事件订阅与传统 Profiler 体验的工具。

### 5. 跟踪开销模型对比

跟踪机制最敏感的争议就是开销。下表给出典型负载下的相对开销级别。

| 引擎 / 机制 | 阈值外开销 | 命中后开销 | 高频事件适用 | 生产推荐 |
|------------|----------|----------|-------------|--------|
| SQL Server xEvents (ring_buffer) | < 1% | 1-3% | 是 | 是（默认 system_health 始终运行） |
| SQL Server SQL Profiler | -- | 5-30%（GUI），3-10%（server-side trace） | 否 | 不推荐（已弃用） |
| Oracle 10046 level 1 | -- | 1-3% | 是 | 是（需要时） |
| Oracle 10046 level 12（绑定+等待） | -- | 5-15% | 谨慎 | 仅诊断 |
| Oracle Real-Time SQL Monitoring | < 1% | < 1% | 是 | 是（自动） |
| MySQL Performance Schema (默认) | < 5% | < 10% | 是 | 是（默认开） |
| MySQL Performance Schema (全启) | -- | 10-25% | 否 | 仅诊断 |
| PostgreSQL auto_explain | 几乎零 | 5-20%（log_analyze=on） | 部分 | 阈值开 |
| DB2 db2trc | -- | 高（5-30%） | 否 | 仅诊断 |
| ClickHouse query_log | < 1% | < 1% | 是 | 是（默认开） |
| Vertica DC | < 1% | < 1% | 是 | 是（默认开） |
| Spark event log | < 1% | 1-3% | 是 | 是 |

xEvents 与 ClickHouse query_log 是两个"始终开启"的代表：低阈值过滤 + 高效缓冲 + 异步落盘。Oracle 10046 处于中间地带——按需启用，默认关闭。MySQL Performance Schema 走"默认部分开启 + UPDATE 表配置"路线。

## SQL Server Extended Events 架构深度剖析

xEvents 是过去 15 年中 RDBMS 跟踪机制设计上**最成熟、最系统化**的范式。

### 设计目标（来自官方设计文档）

1. **可扩展**：引擎模块可自由声明事件，不必修改核心
2. **低开销**：未启用时零开销，启用后内核态过滤
3. **结构化**：事件 = 类型化字段，可用 SQL 直接查询
4. **可组合**：事件 + 谓词 + 动作 + 目标自由组合
5. **可观察**：全部状态通过 `sys.dm_xe_*` DMV 透明可见

### 五大核心抽象

```
Event  --(triggers)-->  Predicate  --(if true)-->  Action  --(execute)-->  Target
 |                          |                          |                       |
事件源                     谓词过滤                   附加动作                 输出目标
```

| 抽象 | 描述 | 典型示例 |
|------|------|---------|
| **Event** | 内核中预定义的"事件点"（约 1500+ 个） | sql_statement_completed, wait_info, lock_acquired, error_reported |
| **Predicate** | 内核态过滤表达式 | `WHERE duration > 1000000 AND database_id = 5` |
| **Action** | 命中事件后执行的附加采集（消耗 CPU） | sql_text, plan_handle, callstack, tsql_stack, session_id |
| **Target** | 事件的输出目的地 | ring_buffer / event_file / histogram / pair_matching / event_counter |
| **Session** | 上述四者的封装单位（一次跟踪 = 一个 session） | system_health（默认会话） |

### 创建一个典型的 xEvent Session

```sql
-- 捕获所有耗时 > 1 秒的语句完成事件，并记录 SQL 文本和会话
CREATE EVENT SESSION [LongRunningQueries] ON SERVER
ADD EVENT sqlserver.sql_statement_completed (
    ACTION (
        sqlserver.sql_text,
        sqlserver.session_id,
        sqlserver.client_app_name,
        sqlserver.database_name,
        sqlserver.plan_handle
    )
    WHERE (
        duration > 1000000  -- 微秒
        AND database_id > 4 -- 排除系统库
    )
)
ADD TARGET package0.event_file (
    SET filename = N'C:\xevents\LongRunningQueries.xel',
        max_file_size = 100,    -- MB
        max_rollover_files = 10
)
ADD TARGET package0.ring_buffer (
    SET max_memory = 4096        -- KB
)
WITH (
    MAX_MEMORY = 4096 KB,
    EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY = 30 SECONDS,
    MAX_EVENT_SIZE = 0 KB,
    MEMORY_PARTITION_MODE = NONE,
    TRACK_CAUSALITY = ON,
    STARTUP_STATE = OFF
);

-- 启动会话
ALTER EVENT SESSION [LongRunningQueries] ON SERVER STATE = START;

-- 查询 ring_buffer 数据
SELECT
    target_data = CAST(target_data AS XML)
FROM sys.dm_xe_session_targets st
INNER JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
WHERE s.name = 'LongRunningQueries'
  AND st.target_name = 'ring_buffer';

-- 停止并删除
ALTER EVENT SESSION [LongRunningQueries] ON SERVER STATE = STOP;
DROP EVENT SESSION [LongRunningQueries] ON SERVER;
```

关键的 `EVENT_RETENTION_MODE` 三档：

| 模式 | 行为 | 适用 |
|------|------|------|
| ALLOW_SINGLE_EVENT_LOSS | 缓冲满则丢弃单个事件 | 默认，生产推荐 |
| ALLOW_MULTIPLE_EVENT_LOSS | 缓冲满则丢弃整批事件 | 极高频事件 |
| NO_EVENT_LOSS | 缓冲满则阻塞产生事件的线程 | 仅诊断，禁止生产 |

### 事件 / 谓词 / 动作 / 目标的元数据查询

```sql
-- 查看所有可用事件（约 1500+）
SELECT
    p.name AS package_name,
    o.name AS event_name,
    o.description
FROM sys.dm_xe_objects o
JOIN sys.dm_xe_packages p ON o.package_guid = p.guid
WHERE o.object_type = 'event'
ORDER BY p.name, o.name;

-- 查看某事件的所有列
SELECT name, type_name, description
FROM sys.dm_xe_object_columns
WHERE object_name = 'sql_statement_completed'
ORDER BY column_id;

-- 查看可用的 actions
SELECT name, description
FROM sys.dm_xe_objects
WHERE object_type = 'action'
ORDER BY name;

-- 查看可用的 targets
SELECT name, description
FROM sys.dm_xe_objects
WHERE object_type = 'target'
ORDER BY name;

-- 当前所有运行的 session
SELECT
    s.name,
    s.create_time,
    s.event_retention_mode_desc,
    s.max_dispatch_latency,
    s.max_memory
FROM sys.dm_xe_sessions s;
```

### 内核态过滤的开销优势

xEvents 的 WHERE 谓词在事件**触发那一刻**立即判断（在事件载荷尚未完整组装前），未命中的事件几乎不耗 CPU——这是它相对 SQL Trace 的关键优势。SQL Trace 的过滤发生在事件被序列化、传给 trace provider 之后，浪费了大量装配开销。

```sql
-- 高效：内核态过滤
... WHERE duration > 1000000 AND database_id = 5

-- 低效：在 Action 中过滤已经装配好的字段
... ACTION (sql_text) WHERE sql_text LIKE '%foo%'
-- sql_text 是 Action（事件后才执行），不能在 Predicate 里高效使用
```

### system_health：默认始终运行的诊断会话

```sql
-- system_health 是 SQL Server 默认随实例启动的 xEvents 会话
SELECT name, startup_state, total_buffer_size
FROM sys.dm_xe_sessions
WHERE name = 'system_health';

-- 它始终捕获以下关键事件：
--   error_reported (severity >= 20)
--   xml_deadlock_report
--   sp_server_diagnostics_component_result
--   wait_info (重大等待)
--   sql_text/plan_handle 等 actions
```

`system_health` 是 SQL Server 团队对 xEvents 自身可靠性的最强背书：**内置始终运行**，覆盖所有重大事故场景。

### XEvents Profiler（替代旧 SQL Profiler GUI）

SSMS 17.3（2018）引入 **XEvents Profiler** 作为旧 SQL Profiler 的现代替代：

- 无需创建/管理 session，提供"Standard"和"TSQL"两个预置模板
- 实时事件流展示，类似旧 Profiler 视觉
- 后台使用 `event_stream` target，不写文件
- 与 SSMS 集成，无需独立 GUI 工具
- SQL Server 2012 及以上均支持

```sql
-- XEvents Profiler 内部实际创建的 session（命名约定）
CREATE EVENT SESSION [QuickSessionStandard] ON SERVER
ADD EVENT sqlserver.attention,
ADD EVENT sqlserver.existing_connection,
ADD EVENT sqlserver.login,
ADD EVENT sqlserver.logout,
ADD EVENT sqlserver.rpc_completed,
ADD EVENT sqlserver.sql_batch_completed,
ADD EVENT sqlserver.sql_batch_starting
WITH (TRACK_CAUSALITY = ON);
```

### XEL 二进制文件解析

XEL 文件是 xEvents 的持久化格式（.xel 扩展名）。可通过两种方式读取：

```sql
-- 1. 用 sys.fn_xe_file_target_read_file
SELECT
    object_name AS event_name,
    CAST(event_data AS XML) AS event_xml
FROM sys.fn_xe_file_target_read_file(
    'C:\xevents\LongRunningQueries*.xel',  -- 通配符匹配 rollover
    NULL, NULL, NULL
);

-- 2. SSMS GUI 双击 .xel 文件直接打开
-- 3. 用 PowerShell 模块 Read-SqlXEvent
```

XEL 格式的设计权衡：

- **二进制**：比 .trc 更紧凑（约 30-50% 体积减少）
- **可附加**：rollover 时无需关闭文件
- **跨服务器**：可拷到任意服务器解析（不依赖原服务器元数据）
- **元数据嵌入**：每个事件包含 schema 引用，独立解析无歧义

## Oracle SQL Trace 10046 深度剖析

10046 是 Oracle 引擎内部最有名的"事件号"——它是诊断 SQL 性能问题的瑞士军刀。

### 历史与演化

```
v6 (1988)          : 引入 SQL Trace（事件 10046）
Oracle 7 (1992)    : 引入 V$ session 视图体系
Oracle 8i (1998)   : 引入 DBMS_SUPPORT.START_TRACE
Oracle 9i (2001)   : 引入扩展 SQL Trace（绑定值、等待事件 - level 8/12）
Oracle 10g (2003)  : 引入 DBMS_MONITOR（推荐 API），AWR/ASH
Oracle 11g (2007)  : 引入 Real-Time SQL Monitoring (V$SQL_MONITOR)
Oracle 12c (2013)  : 增强 SQL Monitor 报告
Oracle 19c (2019)  : Real-Time Statistics + Automatic Index
```

### 10046 Level 详解

```sql
-- Level 1: 基础 SQL Trace（解析、执行、获取的耗时）
ALTER SESSION SET EVENTS '10046 trace name context forever, level 1';

-- Level 4: 加上绑定变量值
ALTER SESSION SET EVENTS '10046 trace name context forever, level 4';

-- Level 8: 加上等待事件
ALTER SESSION SET EVENTS '10046 trace name context forever, level 8';

-- Level 12: 绑定 + 等待（最完整）
ALTER SESSION SET EVENTS '10046 trace name context forever, level 12';

-- 关闭
ALTER SESSION SET EVENTS '10046 trace name context off';
```

不同 level 的开销：

| Level | 包含内容 | CPU 开销 | 文件大小 |
|-------|---------|---------|---------|
| 1 | parse / exec / fetch + 耗时 | 1-3% | 中 |
| 4 | + bind variables | 2-5% | 较大 |
| 8 | + wait events | 3-8% | 较大 |
| 12 | + bind + wait | 5-15% | 大 |

### 推荐 API：DBMS_MONITOR

`DBMS_MONITOR`（10g+）是官方推荐方式，比直接用 `ALTER SESSION SET EVENTS` 更结构化：

```sql
-- 1. 跟踪当前会话
EXEC DBMS_MONITOR.SESSION_TRACE_ENABLE(
    session_id => 123,
    serial_num => 45678,
    waits      => TRUE,
    binds      => TRUE,
    plan_stat  => 'ALL_EXECUTIONS'
);

-- 2. 跟踪一个客户端标识符（应用层标签）
EXEC DBMS_MONITOR.CLIENT_ID_TRACE_ENABLE(
    client_id => 'OrderProcessor:User42',
    waits     => TRUE,
    binds     => TRUE
);

-- 3. 跟踪一个 service / module / action
EXEC DBMS_MONITOR.SERV_MOD_ACT_TRACE_ENABLE(
    service_name => 'OLTP',
    module_name  => 'SalesOrderModule',
    action_name  => 'INSERT_ORDER',
    waits        => TRUE,
    binds        => TRUE
);

-- 4. 数据库级（慎用）
EXEC DBMS_MONITOR.DATABASE_TRACE_ENABLE(waits => TRUE, binds => TRUE);

-- 关闭
EXEC DBMS_MONITOR.SESSION_TRACE_DISABLE(session_id => 123, serial_num => 45678);
```

### tkprof：trace 文件解析利器

10046 输出的是文本 trace 文件（位于 `USER_DUMP_DEST` 或 `DIAGNOSTIC_DEST/diag/rdbms/.../trace`），需 `tkprof` 解析：

```bash
# 基本用法
tkprof orcl_ora_12345.trc output.txt sys=no sort=exeela explain=scott/tiger

# 关键参数
#   sys=no            : 排除递归 SQL（系统调用）
#   sort=exeela       : 按 elapsed 时间倒序
#   explain=user/pw   : 同时生成执行计划
#   waits=yes         : 输出等待事件汇总（默认 yes）
#   record=record.sql : 把所有非递归 SQL 写入文件
```

tkprof 输出片段示例：

```
SQL ID: 9876xyz
SELECT * FROM orders WHERE customer_id = :1

call     count       cpu    elapsed       disk      query    current        rows
------- ------  -------- ---------- ---------- ---------- ----------  ----------
Parse        1      0.00       0.00          0          0          0           0
Execute      1      0.00       0.00          0          0          0           0
Fetch     1000      0.42       8.37        200       9000          0       10000
------- ------  -------- ---------- ---------- ---------- ----------  ----------
total     1002      0.42       8.37        200       9000          0       10000

Misses in library cache during parse: 0
Optimizer mode: ALL_ROWS

Elapsed times include waiting on following events:
  Event waited on                Times Waited   Max. Wait  Total Waited
  ----------------------------- ------------- ----------- -----------
  db file sequential read                 200       0.05         5.20
  SQL*Net message to client              1000       0.00         0.01
  SQL*Net message from client            1000       0.02         3.00
```

每一行都对应：

- **call**：parse / execute / fetch 三阶段
- **count**：调用次数
- **cpu**：CPU 时间（秒）
- **elapsed**：实际耗时
- **disk**：物理 I/O 块数
- **query**：一致性读块数（CR）
- **current**：当前模式读块数（CU）
- **rows**：行数

### Real-Time SQL Monitoring（11g+）

10046 的现代化替代之一是 **Real-Time SQL Monitoring**（Oracle 11g, 2007 引入）：

```sql
-- 默认情况：自动监控满足以下条件的 SQL
--   * 并行执行
--   * CPU 或 I/O 时间 > 5 秒
--   * 显式 /*+ MONITOR */ hint

-- 查询当前正在监控的 SQL
SELECT sql_id, sid, status, elapsed_time, cpu_time, buffer_gets
FROM V$SQL_MONITOR
WHERE status IN ('EXECUTING', 'DONE')
ORDER BY elapsed_time DESC;

-- 生成 HTML/Text 报告
SET LONG 1000000
SET PAGESIZE 0
SELECT DBMS_SQLTUNE.REPORT_SQL_MONITOR(
    sql_id        => 'xyz123abc',
    type          => 'HTML',
    report_level  => 'ALL'
) FROM dual;

-- 强制监控某 SQL
SELECT /*+ MONITOR */ * FROM big_table;

-- 强制不监控
SELECT /*+ NO_MONITOR */ * FROM small_table;
```

Real-Time SQL Monitoring 的核心优势是**无需开启跟踪**——它默认就在，按 hint 或自动阈值激活，输出 V$SQL_MONITOR / V$SQL_PLAN_MONITOR 视图。开销 < 1%。

### 10046 与 SQL Monitor 对比

| 维度 | 10046 SQL Trace | Real-Time SQL Monitoring |
|------|----------------|--------------------------|
| 引入版本 | v6 (~1988) | 11g (2007) |
| 输出 | 文本 trace 文件 | V$SQL_MONITOR / V$SQL_PLAN_MONITOR |
| 解析工具 | tkprof | DBMS_SQLTUNE.REPORT_SQL_MONITOR |
| 开销 | 1-15%（按 level） | < 1% |
| 默认状态 | 关闭 | 自动激活满足阈值的 SQL |
| 历史保留 | 文件级（手动管理） | V$SQL_MONITOR 默认保留最近 ~ 5000 计划 |
| 等待事件 | level 8 / 12 包含 | 内置 |
| 绑定变量 | level 4 / 12 包含 | 内置（条件支持） |
| 实时性 | 事后解析 | 实时（秒级延迟） |
| 推荐场景 | 深度还原（DBA 现场） | 默认运行 + 现场观察 |

## MySQL Performance Schema 简述

MySQL 5.5（2010）引入的 Performance Schema 是 MySQL 自己的"xEvents"，但走了一条与 SQL Server 不同的路径：用 SQL 表配置和查询。

```sql
-- 启用语句事件采集
UPDATE performance_schema.setup_instruments
SET ENABLED = 'YES', TIMED = 'YES'
WHERE NAME LIKE 'statement/%';

UPDATE performance_schema.setup_consumers
SET ENABLED = 'YES'
WHERE NAME LIKE 'events_statements_%';

-- 查询执行时间最长的语句
SELECT
    DIGEST_TEXT,
    COUNT_STAR,
    AVG_TIMER_WAIT / 1000000 AS avg_us,
    SUM_TIMER_WAIT / 1000000 AS total_us
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 10;

-- 查询某线程当前正在执行的语句
SELECT THREAD_ID, EVENT_NAME, SQL_TEXT, TIMER_WAIT
FROM performance_schema.events_statements_current
WHERE THREAD_ID = 12345;

-- 历史（环形缓冲）
SELECT * FROM performance_schema.events_statements_history
WHERE THREAD_ID = 12345 ORDER BY EVENT_ID DESC;
```

MySQL Performance Schema 的设计权衡：

- **优点**：纯 SQL 接口，所有 BI 工具可用；与 information_schema 一致风格
- **缺点**：配置粒度粗（按 instrument 名称模糊匹配）；启用全部 instruments 开销 10-25%
- **历史**：events_statements_history（每线程 10 行环）/ events_statements_history_long（全局 10000 行环）

## PostgreSQL：没有原生跟踪框架

PostgreSQL 是主流引擎中**唯一没有原生 SQL 跟踪框架**的——这是社区长期争议的话题。可用方案：

### auto_explain（8.4+, 2009）

```sql
-- postgresql.conf 或会话级
LOAD 'auto_explain';
SET auto_explain.log_min_duration = '1s';     -- 阈值
SET auto_explain.log_analyze     = ON;         -- 实际执行统计
SET auto_explain.log_buffers     = ON;         -- 缓冲使用
SET auto_explain.log_timing      = ON;         -- 算子计时
SET auto_explain.log_verbose     = ON;
SET auto_explain.log_format      = 'JSON';
SET auto_explain.sample_rate     = 0.1;        -- 10% 采样

-- 之后所有耗时 > 1s 的 SQL 会把执行计划写入 server log
```

### pg_stat_statements（8.4+, 2009）

```sql
-- shared_preload_libraries = 'pg_stat_statements'
CREATE EXTENSION pg_stat_statements;

SELECT
    queryid,
    LEFT(query, 80) AS query_text,
    calls,
    total_exec_time,
    mean_exec_time,
    rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
```

`pg_stat_statements` 在内存中维护规范化后的 SQL 模板（normalized）+ 累计统计。它不等于跟踪——只有聚合数据，没有逐次事件。

### eBPF 方案：现代 PG 跟踪的事实标准

PostgreSQL 通过 `--enable-dtrace` 编译选项暴露大量 USDT (User Statically-Defined Tracing) 探针：

```bash
# 列出 PG 进程暴露的探针
sudo bpftrace -l 'usdt:/usr/lib/postgresql/16/bin/postgres:*'

# 例：跟踪事务提交
postgresql:transaction__commit
postgresql:transaction__abort
postgresql:transaction__start

# 锁事件
postgresql:lock__wait__start
postgresql:lock__wait__done

# 查询执行
postgresql:query__start
postgresql:query__done
postgresql:query__parse__start
postgresql:query__parse__done
postgresql:query__plan__start
postgresql:query__plan__done
postgresql:query__execute__start
postgresql:query__execute__done

# 缓冲区
postgresql:buffer__read__start
postgresql:buffer__read__done
postgresql:buffer__flush__start
postgresql:buffer__flush__done
```

`bpftrace` 跟踪示例：

```bash
# 统计每个查询的执行延迟分布
sudo bpftrace -e '
  usdt:/usr/lib/postgresql/16/bin/postgres:query__start {
    @start[pid] = nsecs;
  }
  usdt:/usr/lib/postgresql/16/bin/postgres:query__done /@start[pid]/ {
    @latency_us = hist((nsecs - @start[pid]) / 1000);
    delete(@start[pid]);
  }
'
```

这种"内核外旁路跟踪"的优势：

1. **生产零修改**：无需重启 PG、无需修改配置
2. **任意维度过滤**：bpftrace/SystemTap 脚本随心所欲
3. **低开销**：USDT 探针未启用时是 NOP 指令
4. **跨进程**：可同时跟踪 PG + 应用 + 内核

### 第三方工具

- `pg_query_state`：扩展，可远程获取某查询的当前进度
- `pg_show_plans`：扩展，列出所有 backend 的当前执行计划
- `pgwatch2` / `pgsentinel`：定时采样 + 高频活动会话监控
- `pg_stat_kcache`：内核态资源（disk read、CPU）追踪

## ClickHouse：query_log + trace_log + opentelemetry 一体化

ClickHouse 是少数把"跟踪"完全做成 SQL 表的 OLAP 引擎。

```sql
-- 默认开启，写入 system.query_log 表（MergeTree 引擎）
SELECT
    type,
    event_date,
    query_duration_ms,
    read_rows,
    read_bytes,
    memory_usage,
    query
FROM system.query_log
WHERE event_date = today()
  AND type = 'QueryFinish'
  AND query_duration_ms > 1000
ORDER BY query_duration_ms DESC
LIMIT 10;

-- trace_log: 自动采样 CPU 调用栈（类似 perf）
SELECT
    event_date,
    trace_type,    -- CPU / Memory / MemorySample / MemoryPeak / ProfileEvent
    count(),
    arrayMap(x -> demangle(addressToSymbol(x)), trace) AS stack
FROM system.trace_log
WHERE event_date = today()
GROUP BY event_date, trace_type, stack
ORDER BY count() DESC
LIMIT 10;

-- 启用 OpenTelemetry 追踪
SET opentelemetry_start_trace_probability = 1.0;
SELECT * FROM big_table WHERE id = 100;

SELECT * FROM system.opentelemetry_span_log
WHERE trace_id = ...
ORDER BY start_time_us;
```

ClickHouse 的设计哲学：**"日志即数据"**——所有诊断都通过查询自己的系统表完成，不需要第三方工具。

## DB2 db2trc

DB2 的 db2trc 是 IBM 风格的二进制追踪工具，类似 Oracle 10046 + 可选过滤。

```bash
# 启用追踪（mask 表达式过滤组件）
db2trc on -m '*.*.*.*.*' -l 8M -t

# 限定特定接收器
db2trc on -i 8M -t  # 内存缓冲 8MB

# 转储到文件
db2trc dump trace.dmp
db2trc off

# 解析（生成可读输出）
db2trc fmt trace.dmp trace.fmt
db2trc flw trace.dmp trace.flw  # 函数调用流
db2trc fmt -c trace.dmp trace.cfmt  # 简化格式
```

DB2 的另一个跟踪入口是 **Event Monitor**：

```sql
-- 创建语句事件监视器，输出到 .evt 文件
CREATE EVENT MONITOR slow_stmts FOR STATEMENTS
WHERE EXECUTABLE_ID IS NOT NULL
WRITE TO FILE '/tmp/slow_stmts'
MAXFILES 10 MAXFILESIZE 100
BUFFERSIZE 32 BLOCKED;

SET EVENT MONITOR slow_stmts STATE = 1;

-- 或写入表
CREATE EVENT MONITOR slow_stmts2 FOR STATEMENTS
WRITE TO TABLE
    EVENT_STATEMENT (TABLE STMT_EVT),
    CONTROL (TABLE CTL_EVT);
```

## eBPF / USDT：现代化跟踪的范式转移

近 5 年（2021-2026）跟踪机制最大的趋势是**从"引擎内置"转向"操作系统级 USDT 探针 + eBPF 旁路"**。

### 为什么这是范式转移

```
传统：
  引擎内置事件框架 → 写到引擎自身的缓冲/文件 → 引擎管理过滤、采样、序列化

现代：
  引擎只发布 USDT 标记（NOP 指令） → eBPF 程序在内核态挂钩 → 用户态 BPF 工具消费
```

优势：

1. **零生产改动**：无需重启数据库、无需修改配置
2. **跨进程**：单一 BPF 程序可同时跟踪数据库、应用、内核网络/磁盘
3. **可编程**：bpftrace 脚本只需几行，性能极高
4. **官方背书**：BCC 项目（Linux）、bpftrace、Datadog/Grafana 等都已工业化
5. **未启用时零成本**：USDT 探针未挂钩时是 NOP 指令，CPU 几乎无影响

### 主流引擎的 USDT 探针支持

| 引擎 | USDT 支持 | 编译选项 / 默认 | 探针数 |
|------|---------|----------------|-------|
| PostgreSQL | 是 | `--enable-dtrace`（多数包默认开） | ~ 50 个 |
| MySQL | 是 | 编译时启用 dtrace | ~ 90 个 |
| MariaDB | 是 | 同 MySQL | ~ 90 个 |
| Oracle | 是 | DTrace（Solaris 起源），Linux 上需 perf/SystemTap | 大量 |
| SQL Server | 是（Linux 版本） | 内置 | 部分 |
| ClickHouse | 是 | 内置 | 中等 |
| MongoDB | 是 | 内置 | 中等 |

### bpftrace 一行神器示例

```bash
# 1. 哪些 PG 查询最慢
sudo bpftrace -e '
  usdt:postgres:query__start { @start[pid] = nsecs }
  usdt:postgres:query__done /@start[pid]/ {
    @lat = hist((nsecs - @start[pid]) / 1000);
    delete(@start[pid]);
  }'

# 2. MySQL 哪些 SQL 命中了 InnoDB 行锁等待
sudo bpftrace -e '
  usdt:mysqld:innodb__lock__wait__start { @[probe] = count(); }'

# 3. PG 锁等待时间分布（按表）
sudo bpftrace -e '
  usdt:postgres:lock__wait__start { @start[pid] = nsecs; }
  usdt:postgres:lock__wait__done /@start[pid]/ {
    @[arg0] = hist((nsecs - @start[pid]) / 1000);
    delete(@start[pid]);
  }'

# 4. 关联系统调用与 PG 查询（关键能力）
sudo bpftrace -e '
  usdt:postgres:query__start { @qstart[pid] = nsecs; @sql[pid] = str(arg0); }
  tracepoint:syscalls:sys_enter_read /@qstart[pid]/ { @reads[@sql[pid]] = count(); }
  usdt:postgres:query__done /@qstart[pid]/ { delete(@qstart[pid]); delete(@sql[pid]); }'
```

### eBPF 时代的"新慢查询日志"

像 Datadog Database Monitoring、Pixie、Coroot、Pyroscope 这类商业/开源工具，已经不再依赖数据库内置跟踪——它们直接用 eBPF 在主机上挂钩，自动关联 SQL、TCP、磁盘、CPU 调用栈，做到"开箱即用、生产无侵入"。

未来 5 年，**SQL 引擎自身的跟踪 API 会更强调"暴露 USDT 探针 + 提供 SQL 表查询接口"，而不是设计完整的事件订阅框架**。SQL Server xEvents 和 Oracle 10046 已经处于成熟稳定期，不再是创新焦点；新一代 OLAP 引擎（如 ClickHouse、StarRocks、Doris）则倾向走 OpenTelemetry 集成 + 系统表的路线。

## 跨引擎对比矩阵

### 跟踪架构对比汇总

| 维度 | SQL Server xEvents | Oracle 10046 | MySQL P_S | PostgreSQL auto_explain | ClickHouse query_log | DB2 db2trc |
|------|--------------------|--------------|-----------|------------------------|---------------------|------------|
| 引入版本 | 2008 | v6 (~1988) | 5.5 (2010) | 8.4 (2009) | 早期 | 早期 |
| 输出格式 | XEL 二进制 + ring | trace 文本 | SQL 表 | server log | MergeTree 表 | 二进制转储 |
| 过滤位置 | 内核态 predicate | 等级 + 模块/动作 | UPDATE 配置表 | 阈值 | 阈值 + 类型 | mask 表达式 |
| SQL 查询 | DMV (sys.dm_xe_*) | V$ + 解析后 | events_* 表 | -- | system.query_log | MON_GET_* |
| 默认开启 | 是（system_health） | 否 | 是（部分） | 否 | 是 | 否 |
| 开销 | 1-3% | 1-15% | 5-25% | 5-20% | < 1% | 5-30% |
| 持久化 | event_file | trace 文件 | history 环 | server log | MergeTree 持久化 | trace dump |
| 元数据探索 | sys.dm_xe_objects (1500+ 事件) | EVENTS 文档 + level | setup_instruments 表 | -- | system.events | -- |
| 现代替代 | -- (本身就是替代) | Real-Time SQL Monitor | -- | eBPF | -- | MON_GET_* |

### 引擎选型建议

| 场景 | 推荐机制 | 原因 |
|------|---------|------|
| 生产环境长期开启 | SQL Server xEvents `system_health` / ClickHouse query_log / Vertica DC | 默认开 + 低开销 + SQL 可查 |
| 现场深度诊断 | Oracle 10046 level 12 + tkprof | 最完整的事件还原 |
| 快速浏览运行查询 | Oracle Real-Time SQL Monitor / SQL Server XEvents Profiler | 无需配置 |
| 跨服务跟踪 | OpenTelemetry（ClickHouse、Doris、CockroachDB 内置） | 与应用追踪贯通 |
| 内核级关联诊断 | eBPF + USDT（PG、MySQL、ClickHouse） | 关联 SQL + 系统调用 + 网络 |
| 历史趋势分析 | MySQL Performance Schema digest / pg_stat_statements / Snowflake QUERY_HISTORY | 模板化聚合 |
| 合规保留 | 配合审计日志（见 audit-logging.md） | 跟踪侧重诊断、审计侧重合规 |

## 关键设计争议

### 1. 内核态过滤 vs 用户态过滤

xEvents 的 WHERE 谓词是**内核态过滤**——事件触发后立即判断是否丢弃，未命中事件几乎零开销。SQL Trace 走相反路径：事件触发 → 装配 → 推送给 trace provider → provider 过滤。两者性能差距可达 10 倍。Oracle 10046 介于其中：level 决定哪些事件触发，但触发后所有数据都写入文件。

引擎实现建议：**过滤必须在事件装配前**。

### 2. 字段化结构化数据 vs 文本日志

xEvents（XML/JSON 结构化）、ClickHouse（MergeTree 强 schema）、MySQL P_S（关系表）走的是**结构化路线**。Oracle 10046、PG server log、DB2 trace 走的是**文本日志路线**。

文本日志的优势是灵活、人类可读；结构化的优势是 SQL 可查、不需要二次解析工具。现代趋势是结构化压倒文本——但 Oracle 10046 因为历史原因和 tkprof 工具链的成熟，至今仍是文本格式。

### 3. 事件订阅 vs 系统表轮询

| 模型 | 代表 | 优点 | 缺点 |
|------|------|------|------|
| 事件订阅 | xEvents、DB2 Event Monitor | 实时、可中断、低开销 | 框架复杂、跨平台难 |
| 系统表轮询 | MySQL P_S、ClickHouse query_log、Snowflake QUERY_HISTORY | SQL 友好、无需新工具 | 实时性差、轮询开销 |
| 旁路 USDT/eBPF | PG/MySQL eBPF | 零侵入、可编程 | 需操作系统支持、需 root |

三种模型各有适用场景。从 SQL Server 2008 到今天的趋势是**底层事件订阅 + 上层暴露为系统表/视图**——给低延迟和 SQL 友好两种使用方式都留好接口。

### 4. 跟踪粒度的"摩尔定律"

跟踪事件数随版本线性增长：

| SQL Server 版本 | xEvents 数 |
|---------------|-----------|
| 2008 | 254 |
| 2008 R2 | ~ 400 |
| 2012 | ~ 600 |
| 2014 | ~ 800 |
| 2016 | ~ 1100 |
| 2017 | ~ 1300 |
| 2019 | ~ 1450 |
| 2022 | ~ 1500+ |

每个新引擎特性（资源管理、Always On、内存优化表、列存储索引、查询存储、PolyBase、智能查询处理）都附带新的 xEvents。这种"新特性 = 新事件"的设计纪律是 xEvents 长期成功的关键。

### 5. PostgreSQL 为何始终没有原生跟踪？

PG 社区多次讨论但未推进，核心争议：

1. **复杂度**：跟踪框架核心代码量大（参考 SQL Server xEvents 数万行）
2. **替代方案存在**：auto_explain + pg_stat_statements + eBPF 已覆盖 70% 场景
3. **扩展生态**：pg_query_state / pg_show_plans / pgwatch2 等扩展在持续填补
4. **跨平台 USDT**：依赖编译选项与 OS 支持

预计 PG 17+/18+ 仍不会引入原生跟踪——eBPF 方向的"内核态旁路"已被社区视为更现代的答案。

## 对引擎开发者的实现建议

### 1. 事件抽象的最小可行设计

```
struct Event {
    event_id: u32,
    timestamp_ns: u64,
    session_id: u32,
    fields: Vec<(FieldId, Value)>,    // 类型化字段
}

struct EventSession {
    events: Set<EventId>,             // 订阅的事件
    predicate: BooleanExpression,     // 编译后的谓词
    actions: Vec<ActionId>,           // 命中后执行
    target: TargetId,                 // 输出目标
    retention_mode: RetentionMode,
}
```

### 2. 内核态过滤的实现

```
// 错误：装配后过滤
fn fire_event(event: Event) {
    let assembled = assemble_full_event(event);  // 高开销
    if predicate.matches(assembled) {
        target.emit(assembled);
    }
}

// 正确：触发点 → 谓词 → 装配 → 输出
fn fire_event(event_id: EventId, raw_fields: &[Field]) {
    if !session_subscribed(event_id) { return; }     // O(1) 位图
    if !predicate_matches(raw_fields) { return; }    // 早过滤
    let assembled = assemble_with_actions(raw_fields);
    target.emit(assembled);
}
```

### 3. 缓冲区设计

```
关键决策：
1. 多生产者无锁：每个工作线程一个 thread-local buffer
2. 派遣线程：周期性把 thread-local 数据合并到全局环
3. 退路：缓冲满时按 retention_mode 处理（丢失 / 阻塞 / 整批丢弃）
4. 异步 I/O：派遣线程批量写文件，避免阻塞工作线程
```

### 4. 元数据 SQL 表

```sql
-- 必须暴露给用户的元数据
SELECT * FROM sys.events_catalog;       -- 事件目录
SELECT * FROM sys.event_fields;         -- 事件字段
SELECT * FROM sys.event_sessions;       -- 当前会话
SELECT * FROM sys.event_session_state;  -- 会话状态（内存使用、丢失计数）

-- 这是 xEvents 设计中最值得借鉴的细节
-- "用户能用 SQL 探索系统的全部跟踪能力"
```

### 5. USDT 探针纪律

```c
// 在关键路径上插入探针 - 未启用时是 NOP
#include <sys/sdt.h>

void execute_query(Query *q) {
    DTRACE_PROBE2(myengine, query__start, q->id, q->text);
    // ... 实际执行 ...
    DTRACE_PROBE3(myengine, query__done, q->id, elapsed_us, rows);
}

// 命名约定：
//   <engine>:<phase>__<state>
//   postgres:query__start   postgres:query__done
//   postgres:lock__wait__start  postgres:lock__wait__done
```

### 6. 事件命名稳定性

| 原则 | 示例 |
|------|------|
| 事件名一旦发布就不能改 | `sql_statement_completed` 永远叫这个名 |
| 字段可加不可删 | 老字段保留，新字段追加 |
| 版本化新名称 | `query_completed_v2` 用新格式 |
| 文档化每个事件 | 描述、字段语义、引入版本 |

xEvents 在 2008 至 2022 这 14 年间维持了惊人的向后兼容——这是它生态成熟的关键。

### 7. 与 OpenTelemetry 集成

```
现代设计：
1. 引擎事件 → 内部表/缓冲（保留 SQL 友好查询）
2. 同时通过 OTLP 协议导出（保留分布式追踪）
3. trace_id / span_id 在两个通道一致

结果：本地诊断用 SQL 查内部表；分布式诊断走 OTel 收集器。
```

CockroachDB、Doris、TiDB、ClickHouse 都已沿这条路径设计。这是新一代引擎跟踪机制的事实标准。

## 关键发现

1. **SQL 跟踪没有任何标准化**：每个引擎从命名、过滤、缓冲、输出到工具链都完全不同。这是数据库领域标准化程度最低的方向之一。
2. **SQL Server xEvents 是设计标杆**：2008 年推出，至今 16 年仍是 RDBMS 跟踪机制的设计典范。事件 + 谓词 + 动作 + 目标 + 会话的五元组抽象，被无数后来者借鉴。
3. **Oracle 10046 是最古老的活化石**：v6（约 1988）至今仍在使用，tkprof 工具链稳定。但开销高且文本格式落后于结构化潮流，Real-Time SQL Monitoring 是 Oracle 在 11g 给出的现代答案。
4. **MySQL Performance Schema 的妥协路线**：纯 SQL 表配置，对 BI 友好，但配置粒度粗、全开销大。
5. **PostgreSQL 的"反框架"路线**：始终未引入原生跟踪框架，靠 auto_explain + pg_stat_statements + eBPF 拼接。社区把这个"反设计"作为长期路线。
6. **ClickHouse 的"日志即数据"哲学**：query_log + trace_log + opentelemetry_span_log 全部是 MergeTree 表，开销极低 + SQL 友好 + 默认开启。这是新一代 OLAP 引擎的事实标准。
7. **eBPF/USDT 是现代化范式转移**：未来 5 年，引擎自身的跟踪 API 会更强调"暴露探针 + 系统表查询"，而不是设计完整的事件订阅框架。Datadog/Pyroscope/Pixie 等已工业化。
8. **弃用信号清晰**：SQL Server SQL Trace 在 2012 弃用、SQL Profiler GUI 在 2022 进一步弱化、DB2 snapshot monitor 在 9.7 弃用——传统跟踪工具在过去 15 年系统性地让位于现代化机制。
9. **过滤位置决定开销**：xEvents 的内核态 predicate 让"始终运行"成为可能；SQL Trace 的装配后过滤让"必须按需开"成为常态。这是性能差异 5-10 倍的关键。
10. **结构化优于文本**：MergeTree 表、XEL 二进制、Performance Schema 表代表了未来；Oracle 10046 的文本 + tkprof 链路是历史负担。
11. **三类引擎差异化明显**：(a) 老牌 OLTP（Oracle/SQL Server/DB2/MySQL）有完整的事件框架；(b) 云原生 OLAP（Snowflake/BigQuery/Redshift）只暴露查询历史视图；(c) 新一代 OLAP（ClickHouse/Doris/StarRocks）走"日志即数据 + OpenTelemetry"。
12. **Real-Time SQL Monitoring 范式**：Oracle 11g 提出的"自动激活 + V$ 视图查询"模式被 SQL Server `system_health`、ClickHouse query_log 等沿用——**默认始终开 + 低开销 + SQL 可查**已成共识。

## 参考资料

- Microsoft Docs: [Extended Events overview](https://learn.microsoft.com/en-us/sql/relational-databases/extended-events/extended-events)
- Microsoft Docs: [Extended Events deep dive — Bob Ward sessions](https://aka.ms/sqlxe)
- Microsoft Docs: [Quick Sessions for SSMS XEvents Profiler](https://learn.microsoft.com/en-us/sql/relational-databases/extended-events/use-the-ssms-xe-profiler)
- Microsoft Docs: [SQL Trace deprecation announcement (SQL Server 2012)](https://learn.microsoft.com/en-us/sql/database-engine/deprecated-database-engine-features-in-sql-server-2012)
- Oracle Docs: [DBMS_MONITOR Package Reference](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_MONITOR.html)
- Oracle Docs: [Real-Time SQL Monitoring](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/monitoring-database-operations.html)
- Oracle Note 39817.1: [Interpreting Raw SQL_TRACE](https://support.oracle.com/) (10046 详解)
- Cary Millsap, "Optimizing Oracle Performance" (O'Reilly, 2003) — 10046 trace 经典专著
- MySQL Reference Manual: [Performance Schema](https://dev.mysql.com/doc/refman/8.0/en/performance-schema.html)
- PostgreSQL Docs: [auto_explain](https://www.postgresql.org/docs/current/auto-explain.html)
- PostgreSQL Docs: [pg_stat_statements](https://www.postgresql.org/docs/current/pgstatstatements.html)
- PostgreSQL Wiki: [Profiling with perf](https://wiki.postgresql.org/wiki/Profiling_with_perf)
- IBM Docs: [db2trc — Trace command](https://www.ibm.com/docs/en/db2/11.5)
- IBM Docs: [Event Monitor for DB2](https://www.ibm.com/docs/en/db2/11.5)
- ClickHouse Docs: [system.query_log / system.trace_log](https://clickhouse.com/docs/en/operations/system-tables/query_log)
- Brendan Gregg, "BPF Performance Tools" (Addison-Wesley, 2019) — eBPF 范式经典
- bpftrace tutorial: [PostgreSQL probes](https://github.com/iovisor/bpftrace/blob/master/docs/tutorial_one_liners.md)
- Datadog: [Database Monitoring with eBPF](https://www.datadoghq.com/product/database-monitoring/)
- 相关文章：[wait-events.md](./wait-events.md), [audit-logging.md](./audit-logging.md), [slow-query-log.md](./slow-query-log.md)
