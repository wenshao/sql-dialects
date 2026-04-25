# 等待事件监控 (Wait Event Monitoring)

当一个查询慢得让人抓狂时，最关键的问题不是"它在做什么"，而是"它在等什么"。等待事件 (Wait Event) 是数据库性能诊断的第一性原理：CPU 时间是少数，等待时间才是大多数——锁、I/O、网络、内部信号量——而能直接告诉 DBA "数据库正在为这个查询等待什么资源" 的能力，是分辨现代数据库系统成熟度的核心指标。

## 没有 SQL 标准

ISO/IEC 9075 SQL 标准**不涉及**等待事件、性能视图或运行时诊断。每个引擎都是各自演化：

- Oracle 在 Oracle 7 (1992) 引入 V$SESSION_WAIT，是等待事件诊断的鼻祖
- SQL Server 在 2005 引入 sys.dm_os_wait_stats，2016 加入会话级 DMV
- MySQL 在 5.6 (2013) 加入 performance_schema 的 events_waits 系列表
- PostgreSQL 在 9.6 (2016) 终于加上 pg_stat_activity.wait_event 字段
- 各 OLAP/云数仓采用混合模型 (查询级耗时拆解 + 系统事件计数器)

由于没有标准，列名、视图名、事件分类、采样方式各不相同，跨引擎的诊断方法论存在巨大差异。

## 支持矩阵 (45+ 引擎)

### 原生等待事件追踪能力

| 引擎 | 原生支持 | 视图/表 | 颗粒度 | 历史保留 | 引入版本 |
|------|---------|--------|--------|---------|---------|
| Oracle | 是 | V$SESSION_WAIT / V$SESSION_EVENT / V$SYSTEM_EVENT | 会话/系统 | ASH (内存) + AWR (持久化) | 7.x (1992) |
| SQL Server | 是 | sys.dm_os_wait_stats / sys.dm_exec_session_wait_stats | 实例/会话 | Query Store (持久化) | 2005 (实例) / 2016 (会话) |
| MySQL | 是 | performance_schema.events_waits_* | 线程/全局 | history / history_long | 5.6 (2013) |
| MariaDB | 是 | performance_schema.events_waits_* | 线程/全局 | history / history_long | 10.0 (继承 MySQL) |
| PostgreSQL | 部分 | pg_stat_activity.wait_event | 当前快照 | 需扩展 (pg_wait_sampling) | 9.6 (2016) |
| DB2 (LUW) | 是 | MON_GET_REQUEST_WAITS / MON_GET_*_TIME | 会话/请求 | 实时累计 | 9.7+ (2010) |
| SQLite | 否 | -- | -- | -- | 不支持 |
| Snowflake | 是 | QUERY_HISTORY (queue/compile/exec time) | 查询级 | 365 天 | GA |
| BigQuery | 是 | jobs.JOB_TIMING / jobs_by_project | 任务级 | 180 天 (默认) | GA |
| Redshift | 是 | STL_WLM_QUERY / SVL_QUERY_REPORT | 查询/步骤 | 2-5 天 | GA |
| ClickHouse | 是 | system.processes / system.events / system.metric_log | 查询/全局 | metric_log 持久化 | 早期 |
| CockroachDB | 是 | crdb_internal.cluster_queries / cluster_locks | 集群级 | 实时 | 21.1+ |
| TiDB | 是 | INFORMATION_SCHEMA.PROCESSLIST / TIDB_HOT_REGIONS | 集群级 | 实时 + Top SQL | 4.0+ |
| OceanBase | 是 | GV$ACTIVE_SESSION_HISTORY (兼容 Oracle ASH) | 会话级 | 内存 + 落盘 | 3.x+ |
| YugabyteDB | 部分 | pg_stat_activity (继承 PG) | 当前快照 | 继承 PG | 2.6+ |
| Greenplum | 部分 | pg_stat_activity (继承 PG) | 当前快照 | gp_workfile_usage 等 | 6.x+ |
| Trino | 是 | system.runtime.queries / system.runtime.tasks | 查询/任务 | 内存 (可配置) | 早期 |
| Presto | 是 | system.runtime.queries | 查询级 | 内存 | 早期 |
| Spark SQL | 是 | Spark UI / SHS (History Server) | Stage/Task | event log 持久化 | 1.x+ |
| Hive | 部分 | YARN ResourceManager / Tez UI | 任务级 | event log | -- |
| Flink SQL | 是 | Flink Web UI / Metrics | 算子级 | metrics 持久化 | 1.x+ |
| Databricks | 是 | Spark UI + System Tables (system.query.history) | Stage/Query | 持久化 | GA |
| SingleStore | 是 | INFORMATION_SCHEMA.MV_PROCESSLIST / PROFILE | 查询/算子 | 实时 + plan persist | 7.x+ |
| Vertica | 是 | DC_REQUESTS_ISSUED / DATA_COLLECTOR | 会话/查询 | 自带 DC (Data Collector) | 7.x+ |
| Teradata | 是 | DBC.DBQLogTbl / DBQL ResUsageSpma | 查询级 | DBQL 持久化 | V2R5+ |
| Sybase ASE | 是 | sysprocesses / monProcessActivity | 进程级 | MDA (Monitor Tables) | 12.5.0.3+ |
| SAP HANA | 是 | M_SERVICE_THREADS / M_EXPENSIVE_STATEMENTS | 线程/语句 | 自带追踪 | 1.x+ |
| Informix | 是 | onstat -g sql / onstat -g ses | 会话/SQL | 实时 | -- |
| Firebird | 部分 | MON$ATTACHMENTS / MON$STATEMENTS | 当前快照 | 实时 | 2.5+ |
| Impala | 是 | impala-shell PROFILE / Web UI | 查询级 | profile 持久化 | -- |
| Doris | 是 | INFORMATION_SCHEMA.PROCESSLIST + Profile | 查询级 | 可配置 | -- |
| StarRocks | 是 | INFORMATION_SCHEMA.PROCESSLIST + QueryDetail | 查询级 | profile 落盘 | 2.x+ |
| TimescaleDB | 部分 | pg_stat_activity (继承 PG) + 自有视图 | 继承 PG | -- | -- |
| Citus | 部分 | pg_stat_activity + citus_* views | 节点级 | 继承 PG | -- |
| H2 | 否 | -- | -- | -- | 不支持 |
| HSQLDB | 否 | -- | -- | -- | 不支持 |
| Derby | 否 | -- | -- | -- | 不支持 |
| Amazon Athena | 部分 | CloudTrail + Athena Query Stats | 查询级 | CloudWatch | GA |
| Azure Synapse | 是 | sys.dm_pdw_request_steps / sys.dm_exec_sessions | 步骤/会话 | DWU 监控 | GA |
| Google Spanner | 是 | SPANNER_SYS.LOCK_STATS / TXN_STATS | 集群级 | 30 天 | GA |
| MonetDB | 部分 | sys.queue() / sys.sessions() | 查询级 | 实时快照 | -- |
| QuestDB | 部分 | tables() / query_activity | 查询级 | 实时 | -- |
| CrateDB | 是 | sys.jobs / sys.jobs_log / sys.operations | 查询/算子 | 可配置 | 3.x+ |
| Materialize | 是 | mz_internal.mz_active_peeks / mz_compute_dependencies | 持久化视图 | 实时 | GA |
| RisingWave | 部分 | rw_catalog.rw_actor_states 等 | Actor 级 | 实时 | -- |
| Yellowbrick | 是 | sys.query / sys.session | 查询/会话 | 自带追踪 | GA |
| DuckDB | 部分 | duckdb_processes / pragma_database_size 等 | 进程级 | 内存 | -- |
| Firebolt | 部分 | INFORMATION_SCHEMA.QUERY_HISTORY | 查询级 | 14 天 | GA |
| DatabendDB | 是 | system.processes / system.metrics | 进程级 | 实时 | GA |
| Exasol | 是 | EXA_SQL_LAST_DAY / EXA_DBA_AUDIT_SQL | 查询级 | 30 天审计 | -- |
| InfluxDB (SQL) | 否 | -- | -- | -- | 流处理模型 |

> 统计: 大约 36 个引擎提供某种形式的等待/耗时追踪，约 9 个完全没有此能力或仅依赖外部监控系统。

### 异步采样 vs 同步追踪

| 模型 | 代表引擎 | 工作原理 | 开销 | 数据完整性 |
|------|---------|---------|------|-----------|
| 同步累计 | Oracle V$SESSION_EVENT, SQL Server sys.dm_os_wait_stats, MySQL events_waits_summary, DB2 MON_GET_*_TIME | 每次等待开始/结束都记账 | 较高 (微秒级开销 × 每次等待) | 完整、精确 |
| 异步采样 | Oracle ASH (1Hz), pg_wait_sampling (10Hz 默认), TiDB Top SQL | 定时器/采样器周期性快照 active session | 极低 (每秒固定次数采样) | 概率统计、长事件偏置 |
| 触发式记录 | Oracle 10046 trace, MySQL slow query log | 仅在阈值触发时记录 | 阈值外为零 | 仅命中阈值的事件 |
| 查询级粗粒度 | Snowflake QUERY_HISTORY, BigQuery JOB_TIMING | 仅记录查询的关键阶段时间 | 极低 | 粗粒度，无内部等待细节 |
| 流式日志 | Vertica DC_REQUESTS_ISSUED, ClickHouse query_log | 异步写入持久化日志表 | 中等 | 完整但延迟落盘 |

### 系统视图命名约定对比

| 引擎 | 当前活动会话 | 历史等待累计 | 实时事件流 | 持久化历史 |
|------|------------|------------|-----------|----------|
| Oracle | V$SESSION (含 EVENT 列) | V$SESSION_EVENT, V$SYSTEM_EVENT | V$ACTIVE_SESSION_HISTORY (内存) | DBA_HIST_ACTIVE_SESS_HISTORY (AWR) |
| SQL Server | sys.dm_exec_requests | sys.dm_os_wait_stats, sys.dm_exec_session_wait_stats | sys.dm_exec_query_profiles | Query Store (sys.query_store_*) |
| MySQL | performance_schema.threads | events_waits_summary_global_by_event_name | events_waits_current | events_waits_history_long |
| PostgreSQL | pg_stat_activity (wait_event) | -- (需 pg_wait_sampling) | -- | pg_stat_statements (无等待维度) |
| DB2 | MON_GET_CONNECTION | MON_GET_REQUEST_WAITS, MON_GET_AGENT | -- | EVENT MONITOR FOR STATISTICS |
| ClickHouse | system.processes | system.events, system.metrics | system.metric_log, system.query_log | metric_log (默认 7 天) |
| Snowflake | -- | QUERY_HISTORY (聚合视图) | -- | INFORMATION_SCHEMA.QUERY_HISTORY (14 天) / SNOWFLAKE.ACCOUNT_USAGE (365 天) |
| BigQuery | INFORMATION_SCHEMA.JOBS_BY_USER | INFORMATION_SCHEMA.JOBS | -- | jobs (180 天) |
| CockroachDB | crdb_internal.cluster_queries | crdb_internal.cluster_statement_statistics | crdb_internal.node_runtime_info | -- |
| TiDB | INFORMATION_SCHEMA.PROCESSLIST | INFORMATION_SCHEMA.STATEMENTS_SUMMARY | -- | INFORMATION_SCHEMA.SLOW_QUERY |
| Trino | system.runtime.queries | system.runtime.queries (state=FINISHED) | -- | event listener (外部) |

### 事件分类体系对比

| 引擎 | 顶层分类数 | 类别名称 | 特别值得关注的子类 |
|------|----------|---------|------------------|
| Oracle | 12 个 wait class | Idle, Network, User I/O, System I/O, Concurrency, Application, Commit, Configuration, Administrative, Scheduler, Cluster, Other | "User I/O" 占大多数 OLTP 系统 |
| PostgreSQL | 8 个 wait_event_type | Activity, BufferPin, Client, Extension, IO, IPC, Lock, LWLock, Timeout | Lock vs LWLock 容易混淆 |
| SQL Server | 不分类 (~1000+ 类型) | 平铺事件名 | PAGEIOLATCH_*, PAGELATCH_*, LCK_M_*, CXPACKET, ASYNC_NETWORK_IO |
| MySQL | 4 大类 | wait/io/*, wait/lock/*, wait/synch/*, wait/idle | wait/io/file/innodb/*, wait/synch/mutex/innodb/* |
| DB2 | -- | Lock wait time, Log disk wait, Buffer pool data physical read time, Network send/receive time | "Total wait time" 总览 |
| ClickHouse | -- | system.events 包含 ~500 个事件 | NetworkSendElapsedMicroseconds, DiskReadElapsedMicroseconds |

### SQL 级可见性

| 引擎 | 当前 SQL 与等待关联 | SQL 历史与等待关联 | 历史 Top SQL by Wait |
|------|-------------------|------------------|--------------------|
| Oracle | V$SESSION.EVENT + V$SESSION.SQL_ID | ASH 关联 V$SQL | DBA_HIST_ACTIVE_SESS_HISTORY join DBA_HIST_SQLTEXT |
| SQL Server | sys.dm_exec_session_wait_stats + sys.dm_exec_requests | Query Store wait categories (2017+) | sys.query_store_wait_stats |
| MySQL | events_statements_current join events_waits_current (相同 thread_id) | events_statements_history_long join events_waits_history_long | events_statements_summary_by_digest (无 wait 维度) |
| PostgreSQL | pg_stat_activity (query + wait_event) | pg_stat_statements (无 wait) | 需 pg_wait_sampling join pg_stat_statements |
| DB2 | MON_GET_ACTIVITY (含 wait time 与 SQL) | MON_GET_PKG_CACHE_STMT | -- |
| ClickHouse | system.processes (含 query_id + ProfileEvents) | system.query_log (含 ProfileEvents map) | -- (需手工 GROUP BY ProfileEvents) |

### 会话级 vs 语句级归因

| 引擎 | 会话级累计 | 语句级累计 | 当前等待 |
|------|----------|----------|---------|
| Oracle | V$SESSION_EVENT (按 SID) | V$SQL.WAIT_TIME, V$SESSION.SQL_EXEC_ID 关联 | V$SESSION.EVENT |
| SQL Server | sys.dm_exec_session_wait_stats (since 2016) | sys.query_store_wait_stats (since 2017) | sys.dm_exec_requests.wait_type |
| MySQL | events_waits_summary_by_thread_by_event_name | events_waits_summary_by_user_by_event_name (无 statement 级) | events_waits_current |
| PostgreSQL | -- (无) | -- (无) | pg_stat_activity.wait_event |
| DB2 | MON_GET_AGENT | MON_GET_PKG_CACHE_STMT | -- |

### 历史保留与持久化

| 引擎 | 内存中保留 | 持久化到表/磁盘 | 默认保留期 |
|------|----------|---------------|----------|
| Oracle ASH | V$ACTIVE_SESSION_HISTORY (~1 小时) | DBA_HIST_ACTIVE_SESS_HISTORY (AWR 快照, 1/10 抽样) | AWR 默认 8 天 |
| Oracle wait stats | V$SYSTEM_EVENT 累计 | DBA_HIST_SYSTEM_EVENT (AWR) | AWR 默认 8 天 |
| SQL Server Query Store | -- | sys.query_store_* | OPERATION_MODE 配置, 默认 30 天 |
| MySQL P_S | events_waits_history (10 行/线程), events_waits_history_long (10000 行/全局) | -- (需用户主动持久化) | 内存 |
| PostgreSQL | pg_stat_activity 仅当前 | pg_wait_sampling 持久化样本 | 取决于扩展配置 |
| ClickHouse metric_log | system.metric_log | 持久化到磁盘 | 默认 7 天 |
| Snowflake | INFORMATION_SCHEMA.QUERY_HISTORY (14 天) | SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY | 365 天 |
| BigQuery | -- | INFORMATION_SCHEMA.JOBS_* | 180 天 |
| Redshift | STL_QUERY (2-5 天) | -- | 滚动覆盖 |

## 各引擎深入：监控视图与查询模式

### Oracle: V$SESSION_WAIT / V$SESSION_EVENT / ASH / AWR

Oracle 是等待事件诊断的发明者，1992 年的 Oracle 7 引入 V$SESSION_WAIT，2005 年的 Oracle 10g 引入 ASH (Active Session History) 和 AWR (Automatic Workload Repository)，至今仍是最完整的等待事件体系。

```sql
-- 1) 当前会话正在等待什么
SELECT sid,
       serial#,
       username,
       sql_id,
       event,                 -- 等待事件名
       wait_class,            -- 12 个分类之一
       wait_time,             -- 0 表示正在等待，>0 表示最后一次等待时长 (cs)
       seconds_in_wait,
       state                  -- WAITING / WAITED KNOWN TIME 等
  FROM v$session
 WHERE status = 'ACTIVE'
   AND username IS NOT NULL
   AND wait_class != 'Idle'
 ORDER BY seconds_in_wait DESC;

-- 2) 实例启动以来的累计等待事件 (按等待时间排序)
SELECT event,
       wait_class,
       total_waits,
       total_timeouts,
       time_waited / 100      AS time_waited_seconds,        -- 输出单位是 cs
       average_wait / 100     AS avg_wait_seconds
  FROM v$system_event
 WHERE wait_class != 'Idle'
 ORDER BY time_waited DESC
 FETCH FIRST 20 ROWS ONLY;

-- 3) 按 wait_class 汇总 (Oracle Wait Class 是诊断的入口)
SELECT wait_class,
       SUM(total_waits)               AS waits,
       SUM(time_waited) / 100         AS time_waited_seconds
  FROM v$system_event
 GROUP BY wait_class
 ORDER BY 3 DESC;

-- 4) 单个会话从登录开始的累计等待
SELECT sid,
       event,
       total_waits,
       time_waited / 100  AS seconds_waited
  FROM v$session_event
 WHERE sid = 1234
 ORDER BY time_waited DESC;
```

#### Oracle Wait Classes (12 类)

```text
Idle           : 会话空闲 (SQL*Net message from client, etc.)
Network        : 网络相关 (SQL*Net more data to client)
User I/O       : 用户进程读取数据块 (db file sequential read, db file scattered read)
System I/O    : 后台进程 I/O (log file parallel write, control file sequential read)
Concurrency    : 并发争用 (latch: cache buffers chains, library cache lock)
Application    : 应用层等待 (enq: TX - row lock contention)
Commit         : 提交相关 (log file sync)
Configuration  : 配置相关 (free buffer waits, log file switch)
Administrative : 管理操作 (rebuild, online ops)
Scheduler      : Resource Manager 调度
Cluster        : RAC 集群通信 (gc cr block 2-way, gc current block 2-way)
Other          : 难以分类的事件
```

> 经验法则：OLTP 系统中 Idle 不计入诊断；User I/O + Concurrency + Commit 是 90% 问题的源头；Cluster 仅 RAC 环境出现。

#### ASH (Active Session History) — 1 Hz 采样

```sql
-- ASH 每秒对所有 active session 拍快照，写入 SGA 中的循环缓冲区 (~1 小时容量)
-- 然后 MMON 后台进程每 10 秒抽样 1/10 写入 AWR 持久化 (DBA_HIST_ACTIVE_SESS_HISTORY)

-- 5) 过去 5 分钟里最常见的等待事件 (TOP-N by sample count)
SELECT event,
       wait_class,
       COUNT(*) AS samples,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct
  FROM v$active_session_history
 WHERE sample_time > SYSDATE - INTERVAL '5' MINUTE
   AND wait_class != 'Idle'
 GROUP BY event, wait_class
 ORDER BY samples DESC
 FETCH FIRST 10 ROWS ONLY;

-- 6) 过去 1 小时按 SQL_ID 聚合的总等待时间 (DB time)
-- 因为 ASH 是 1 秒采样, 一次出现 = 约 1 秒 active time
SELECT sql_id,
       COUNT(*) AS active_seconds,
       SUM(CASE WHEN session_state = 'ON CPU'  THEN 1 ELSE 0 END) AS cpu_seconds,
       SUM(CASE WHEN session_state = 'WAITING' THEN 1 ELSE 0 END) AS wait_seconds
  FROM v$active_session_history
 WHERE sample_time > SYSDATE - INTERVAL '1' HOUR
 GROUP BY sql_id
 ORDER BY active_seconds DESC
 FETCH FIRST 10 ROWS ONLY;

-- 7) AWR 历史: 跨多日的等待事件趋势
SELECT TRUNC(sample_time, 'HH') AS hour,
       wait_class,
       COUNT(*) * 10 AS approx_active_seconds   -- 1/10 采样, 每个样本代表 10 秒
  FROM dba_hist_active_sess_history
 WHERE sample_time > SYSDATE - INTERVAL '7' DAY
 GROUP BY TRUNC(sample_time, 'HH'), wait_class
 ORDER BY hour, wait_class;
```

> 重要许可注意：ASH/AWR 属于 Oracle Diagnostic Pack，需要单独许可证 (Enterprise Edition + Diagnostic Pack option)。在没有许可的环境下查询这些视图等同于违约。Statspack 是免费替代品 (社区维护)。

### SQL Server: sys.dm_os_wait_stats / sys.dm_exec_session_wait_stats / Query Store

SQL Server 2005 引入实例级 sys.dm_os_wait_stats，但直到 2016 才补齐会话级 sys.dm_exec_session_wait_stats，2017 引入 Query Store wait categories。

```sql
-- 1) 实例启动以来 Top 20 wait types
SELECT TOP 20
       wait_type,
       waiting_tasks_count,
       wait_time_ms,
       max_wait_time_ms,
       signal_wait_time_ms,         -- 等待 CPU 的时间 (CPU pressure 指标)
       wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms
  FROM sys.dm_os_wait_stats
 WHERE wait_type NOT IN (
    -- 排除已知的 idle / 后台 / benign waits (Paul Randal 列表)
    'CLR_AUTO_EVENT', 'CLR_MANUAL_EVENT', 'CLR_SEMAPHORE',
    'BROKER_TASK_STOP', 'BROKER_RECEIVE_WAITFOR',
    'CHECKPOINT_QUEUE', 'DBMIRROR_EVENTS_QUEUE',
    'DIRTY_PAGE_POLL', 'DISPATCHER_QUEUE_SEMAPHORE',
    'FT_IFTS_SCHEDULER_IDLE_WAIT', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
    'LAZYWRITER_SLEEP', 'LOGMGR_QUEUE',
    'OLEDB', 'PWAIT_ALL_COMPONENTS_INITIALIZED',
    'REQUEST_FOR_DEADLOCK_SEARCH', 'RESOURCE_QUEUE',
    'SLEEP_*', 'SP_SERVER_DIAGNOSTICS_SLEEP',
    'SQLTRACE_BUFFER_FLUSH', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
    'WAITFOR', 'XE_DISPATCHER_WAIT', 'XE_TIMER_EVENT'
 )
 ORDER BY wait_time_ms DESC;

-- 2) 当前正在等待的请求
SELECT r.session_id,
       r.status,
       r.wait_type,
       r.wait_time AS wait_time_ms,
       r.last_wait_type,
       r.blocking_session_id,
       SUBSTRING(t.text, r.statement_start_offset/2 + 1,
           ((CASE r.statement_end_offset
                 WHEN -1 THEN DATALENGTH(t.text)
                 ELSE r.statement_end_offset
              END - r.statement_start_offset)/2) + 1) AS current_statement
  FROM sys.dm_exec_requests r
 CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
 WHERE r.session_id > 50         -- 排除系统会话
   AND r.wait_type IS NOT NULL;

-- 3) 会话级累计 wait stats (since 2016)
SELECT session_id,
       wait_type,
       waiting_tasks_count,
       wait_time_ms
  FROM sys.dm_exec_session_wait_stats
 WHERE session_id = 75
 ORDER BY wait_time_ms DESC;

-- 4) Query Store wait stats (since 2017) — 持久化的 SQL+wait 关联
SELECT TOP 20
       qsq.query_id,
       qsqt.query_sql_text,
       wait_category_desc,
       SUM(total_query_wait_time_ms) AS total_wait_ms,
       SUM(execution_count) AS exec_count
  FROM sys.query_store_wait_stats qsws
  JOIN sys.query_store_plan      qsp  ON qsws.plan_id = qsp.plan_id
  JOIN sys.query_store_query     qsq  ON qsp.query_id = qsq.query_id
  JOIN sys.query_store_query_text qsqt ON qsq.query_text_id = qsqt.query_text_id
 GROUP BY qsq.query_id, qsqt.query_sql_text, wait_category_desc
 ORDER BY total_wait_ms DESC;
```

#### SQL Server Wait Stats Top-N 模式

```sql
-- Paul Randal 经典查询: 计算每个 wait type 占总等待时间的百分比
WITH waits AS (
  SELECT wait_type,
         wait_time_ms / 1000.0 AS wait_seconds,
         (wait_time_ms - signal_wait_time_ms) / 1000.0 AS resource_seconds,
         signal_wait_time_ms / 1000.0 AS signal_seconds,
         waiting_tasks_count AS wait_count,
         100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS pct
    FROM sys.dm_os_wait_stats
   WHERE wait_type NOT IN (/* benign waits 列表，同上 */ '')
     AND wait_time_ms > 0
)
SELECT wait_type,
       wait_seconds,
       resource_seconds,
       signal_seconds,
       wait_count,
       CAST(pct AS DECIMAL(5,2)) AS pct,
       SUM(pct) OVER (ORDER BY pct DESC ROWS UNBOUNDED PRECEDING) AS running_pct
  FROM waits
 WHERE pct > 0.5
 ORDER BY pct DESC;

-- 输出示例:
--  wait_type           | wait_seconds | resource_seconds | signal_seconds | pct  | running_pct
--  PAGEIOLATCH_SH      | 18234.5      | 18100.2          | 134.3          | 35.2 | 35.2
--  CXPACKET            | 12500.1      | 12480.0          | 20.1           | 24.1 | 59.3
--  WRITELOG            | 5800.3       | 5790.1           | 10.2           | 11.2 | 70.5
--  ASYNC_NETWORK_IO    | 3200.5       | 3180.0           | 20.5           | 6.2  | 76.7
--  LCK_M_X             | 2100.8       | 2095.0           | 5.8            | 4.0  | 80.7
```

#### 常见 Wait Type 速查

```text
PAGEIOLATCH_*    : 物理 I/O 读取数据页 → 内存不足 / 慢 I/O
PAGELATCH_*      : 内存中页面争用 → 通常是 tempdb 分配热点 (SGAM/PFS contention)
WRITELOG         : 事务日志写等待 → 日志磁盘慢 / 提交过频
LCK_M_*          : 行锁/页锁/表锁等待 → 应用并发设计问题
CXPACKET         : 并行查询协调 → 不一定坏，可能 MAXDOP 设置不当
CXCONSUMER       : 并行消费者等生产者 → 同上
ASYNC_NETWORK_IO : 客户端读取结果集慢 → 应用瓶颈
SOS_SCHEDULER_YIELD : CPU 压力 → 并发线程过多
RESOURCE_SEMAPHORE : 内存授予等待 → 内存不足
THREADPOOL       : 工作线程耗尽 → 连接数过多
```

### MySQL: performance_schema events_waits

MySQL 5.6 (2013) 引入 performance_schema 的 events_waits_* 系列表，提供线程级、全局级、按事件名汇总等多种维度。

```sql
-- 1) 启用 wait instrumentation (默认部分启用)
UPDATE performance_schema.setup_instruments
   SET ENABLED = 'YES', TIMED = 'YES'
 WHERE NAME LIKE 'wait/%';

UPDATE performance_schema.setup_consumers
   SET ENABLED = 'YES'
 WHERE NAME IN ('events_waits_current',
                'events_waits_history',
                'events_waits_history_long');

-- 2) 全局累计：按事件名汇总的 Top wait events
SELECT event_name,
       count_star,
       sum_timer_wait / 1e12  AS sum_seconds,        -- 单位是皮秒
       avg_timer_wait / 1e9   AS avg_microseconds,
       max_timer_wait / 1e9   AS max_microseconds
  FROM performance_schema.events_waits_summary_global_by_event_name
 WHERE event_name NOT LIKE 'idle%'
   AND event_name NOT LIKE 'wait/synch/cond/%'   -- 排除空闲信号量
   AND count_star > 0
 ORDER BY sum_timer_wait DESC
 LIMIT 20;

-- 3) 按线程 + 事件名的累计 (定位某个连接的瓶颈)
SELECT t.processlist_id,
       t.processlist_user,
       t.processlist_host,
       e.event_name,
       e.count_star,
       e.sum_timer_wait / 1e12 AS sum_seconds
  FROM performance_schema.events_waits_summary_by_thread_by_event_name e
  JOIN performance_schema.threads t USING (thread_id)
 WHERE t.processlist_id IS NOT NULL
   AND e.sum_timer_wait > 0
 ORDER BY e.sum_timer_wait DESC
 LIMIT 50;

-- 4) 当前正在发生的等待
SELECT thread_id,
       event_name,
       timer_wait / 1e9 AS microseconds,
       object_schema,
       object_name,
       index_name,
       operation
  FROM performance_schema.events_waits_current
 WHERE thread_id IN (SELECT thread_id FROM performance_schema.threads
                      WHERE processlist_id IS NOT NULL);

-- 5) 历史等待事件 (events_waits_history_long 默认 10000 行)
SELECT event_name,
       COUNT(*)               AS occurrences,
       AVG(timer_wait) / 1e9  AS avg_us,
       MAX(timer_wait) / 1e9  AS max_us
  FROM performance_schema.events_waits_history_long
 GROUP BY event_name
 ORDER BY occurrences DESC
 LIMIT 20;

-- 6) sys schema 简化视图 (5.7+)
SELECT * FROM sys.waits_global_by_latency LIMIT 20;
SELECT * FROM sys.waits_by_host_by_latency LIMIT 20;
SELECT * FROM sys.waits_by_user_by_latency LIMIT 20;

-- 7) 文件 I/O 等待汇总
SELECT * FROM sys.io_global_by_file_by_latency LIMIT 20;
SELECT * FROM sys.io_global_by_wait_by_latency LIMIT 10;
```

#### MySQL Wait 分类

```text
wait/io/file/*       : 文件 I/O (innodb_data_file, redo_log_file 等)
wait/io/socket/*     : 网络 socket I/O
wait/io/table/*      : 表级 I/O (handler 操作)
wait/lock/table/*    : 表锁等待
wait/lock/metadata/* : MDL (metadata lock) 等待
wait/synch/mutex/*   : 互斥锁 (innodb buf_pool_mutex 等)
wait/synch/rwlock/*  : 读写锁
wait/synch/cond/*    : 条件变量 (大多是空闲)
wait/synch/sxlock/*  : InnoDB SX 锁 (5.7+)
idle                 : 连接空闲, 不属于真等待
```

### PostgreSQL: pg_stat_activity wait_event + pg_wait_sampling

PostgreSQL 9.6 (2016) 才在 pg_stat_activity 加入 wait_event 与 wait_event_type 字段——比 Oracle 晚 24 年，比 SQL Server 晚 11 年。原生只能看到当前快照，无累计统计，需要 pg_wait_sampling 扩展才能做时间分析。

```sql
-- 1) 当前会话等待状态 (PG 9.6+)
SELECT pid,
       usename,
       state,
       wait_event_type,        -- 8 大类
       wait_event,             -- 具体事件
       query_start,
       NOW() - query_start AS query_duration,
       LEFT(query, 80) AS query
  FROM pg_stat_activity
 WHERE state != 'idle'
   AND wait_event IS NOT NULL
 ORDER BY query_duration DESC;

-- 2) 按 wait_event_type 汇总当前活动会话
SELECT wait_event_type,
       wait_event,
       COUNT(*) AS sessions
  FROM pg_stat_activity
 WHERE state != 'idle'
 GROUP BY wait_event_type, wait_event
 ORDER BY sessions DESC;

-- 3) 锁等待详情 (Lock 类型 wait_event 时使用)
SELECT blocked.pid     AS blocked_pid,
       blocked.usename AS blocked_user,
       blocking.pid    AS blocking_pid,
       blocking.usename AS blocking_user,
       blocked.wait_event_type,
       blocked.wait_event,
       LEFT(blocked.query, 80) AS blocked_query,
       LEFT(blocking.query, 80) AS blocking_query,
       NOW() - blocked.query_start AS blocked_duration
  FROM pg_stat_activity blocked
  JOIN pg_stat_activity blocking
    ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
 WHERE blocked.wait_event_type = 'Lock';
```

#### pg_wait_sampling 扩展 (推荐安装)

```sql
-- 安装 pg_wait_sampling (随附 PG14+ 二进制发行版, 之前需自行编译)
CREATE EXTENSION pg_wait_sampling;

-- 配置采样频率 (默认 10Hz, postgresql.conf)
-- pg_wait_sampling.profile_period = 10        -- 毫秒
-- pg_wait_sampling.history_period = 10        -- 毫秒
-- pg_wait_sampling.profile_pid    = true      -- 按 PID 聚合
-- pg_wait_sampling.profile_queries = true     -- 与 queryid 关联

-- 查询累计 profile (扩展启动以来的样本)
SELECT event_type,
       event,
       COUNT(*)                              AS samples,
       ROUND(COUNT(*) * 0.01, 2)             AS approx_seconds  -- 10Hz → 100ms/sample
  FROM pg_wait_sampling_profile
 GROUP BY event_type, event
 ORDER BY samples DESC
 LIMIT 20;

-- 与 pg_stat_statements 关联 — 找出每条 SQL 的等待分布
SELECT s.query,
       p.event_type,
       p.event,
       SUM(p.count) AS samples
  FROM pg_wait_sampling_profile p
  JOIN pg_stat_statements      s ON p.queryid = s.queryid
 GROUP BY s.query, p.event_type, p.event
 ORDER BY samples DESC
 LIMIT 30;

-- 实时历史 (history 表保留最近 N 个样本)
SELECT * FROM pg_wait_sampling_history
 ORDER BY ts DESC
 LIMIT 100;
```

### DB2 (LUW): MON_GET_REQUEST_WAITS

DB2 9.7 (2010) 引入 MON_GET_* 监控函数族，取代了旧的 SNAPSHOT 接口。MON_GET_REQUEST_WAITS 是新版等待事件视图。

```sql
-- 1) 当前请求的等待时间分解
SELECT request_type,
       COUNT(*)                  AS request_count,
       SUM(total_request_time)   AS total_request_ms,
       SUM(total_wait_time)      AS total_wait_ms,
       SUM(lock_wait_time)       AS lock_wait_ms,
       SUM(log_disk_wait_time)   AS log_disk_wait_ms,
       SUM(pool_read_time)       AS pool_read_ms,
       SUM(pool_write_time)      AS pool_write_ms
  FROM TABLE(MON_GET_REQUEST_WAITS(-1, NULL))
 GROUP BY request_type;

-- 2) 单个连接的等待分解
SELECT application_handle,
       total_request_time,
       total_wait_time,
       lock_wait_time,
       lock_wait_count,
       log_disk_wait_time,
       pool_read_time,
       direct_read_time,
       client_idle_wait_time,
       fcm_recv_wait_time,
       fcm_send_wait_time
  FROM TABLE(MON_GET_CONNECTION(NULL, -2));

-- 3) 包缓存中的语句的等待时间 (历史 SQL 等待归因)
SELECT SUBSTR(stmt_text, 1, 80) AS sql_preview,
       num_executions,
       total_act_time,
       total_act_wait_time,
       lock_wait_time,
       pool_read_time
  FROM TABLE(MON_GET_PKG_CACHE_STMT(NULL, NULL, NULL, -2))
 ORDER BY total_act_wait_time DESC
 FETCH FIRST 20 ROWS ONLY;
```

### ClickHouse: system.processes / system.events / system.metric_log

ClickHouse 不使用传统的 wait event 模型，而是通过 ProfileEvents (累计计数器，~500 个) 提供细粒度 I/O、CPU、网络耗时统计。

```sql
-- 1) 当前正在运行的查询 (类似 pg_stat_activity)
SELECT query_id,
       user,
       elapsed,                          -- 已运行秒数
       read_rows,
       read_bytes,
       memory_usage,
       formatReadableSize(memory_usage) AS mem_human,
       query
  FROM system.processes
 ORDER BY elapsed DESC;

-- 2) 启动以来的事件计数器 (~500 个事件)
SELECT event,
       value,
       description
  FROM system.events
 WHERE value > 0
 ORDER BY value DESC
 LIMIT 30;

-- 3) 关注的等待相关事件
SELECT event,
       value
  FROM system.events
 WHERE event IN (
    'NetworkSendElapsedMicroseconds',
    'NetworkReceiveElapsedMicroseconds',
    'DiskReadElapsedMicroseconds',
    'DiskWriteElapsedMicroseconds',
    'OSIOWaitMicroseconds',
    'OSCPUWaitMicroseconds',
    'OSCPUVirtualTimeMicroseconds',
    'RWLockReadersWaitMilliseconds',
    'RWLockWritersWaitMilliseconds',
    'ContextLock',
    'QueryProfilerSignalOverruns'
 );

-- 4) 历史指标 (system.metric_log 默认 1Hz 采样, 7 天保留)
SELECT toStartOfMinute(event_time) AS minute,
       avg(CurrentMetric_Query)            AS avg_active_queries,
       avg(CurrentMetric_HTTPConnection)   AS avg_http_conns,
       max(ProfileEvent_OSIOWaitMicroseconds) AS io_wait_us
  FROM system.metric_log
 WHERE event_time > now() - INTERVAL 1 HOUR
 GROUP BY minute
 ORDER BY minute;

-- 5) 单个查询的完整 ProfileEvents (system.query_log)
SELECT query_id,
       query_duration_ms,
       ProfileEvents['NetworkReceiveElapsedMicroseconds'] AS net_recv_us,
       ProfileEvents['DiskReadElapsedMicroseconds']        AS disk_read_us,
       ProfileEvents['SelectedRows']                       AS rows_selected,
       ProfileEvents['SelectedBytes']                      AS bytes_selected
  FROM system.query_log
 WHERE event_date = today()
   AND type = 'QueryFinish'
 ORDER BY query_duration_ms DESC
 LIMIT 10;
```

### Snowflake: QUERY_HISTORY 阶段时间

Snowflake 不提供细粒度 wait event，而是把每个查询的耗时拆成几个粗粒度阶段：排队、编译、执行。

```sql
-- 1) 最近的查询历史 (含阶段耗时)
SELECT query_id,
       LEFT(query_text, 60)        AS query_preview,
       warehouse_size,
       total_elapsed_time          AS total_ms,
       compilation_time            AS compile_ms,
       queued_provisioning_time    AS queue_provision_ms,    -- 等待 warehouse 启动
       queued_repair_time          AS queue_repair_ms,
       queued_overload_time        AS queue_overload_ms,     -- 等待并发槽位
       transaction_blocked_time    AS txn_block_ms,           -- 事务阻塞
       execution_time              AS exec_ms,
       bytes_scanned,
       rows_produced
  FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
 WHERE start_time > DATEADD(hour, -1, CURRENT_TIMESTAMP())
 ORDER BY total_elapsed_time DESC
 LIMIT 20;

-- 2) 排队时间占比异常的查询 (可能需要扩容 warehouse)
SELECT warehouse_name,
       COUNT(*)                                                AS queries,
       SUM(queued_overload_time)                               AS total_queue_ms,
       SUM(execution_time)                                     AS total_exec_ms,
       100.0 * SUM(queued_overload_time) /
              NULLIF(SUM(execution_time + queued_overload_time), 0) AS queue_pct
  FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
 WHERE start_time > DATEADD(day, -1, CURRENT_TIMESTAMP())
 GROUP BY warehouse_name
HAVING SUM(queued_overload_time) > 0
 ORDER BY queue_pct DESC;
```

### BigQuery: jobs.JOB_TIMING

BigQuery 通过 INFORMATION_SCHEMA.JOBS 提供查询级耗时拆解，jobTimeline 提供每个阶段的资源使用快照。

```sql
-- 1) 最近 1 天的查询耗时分布
SELECT job_id,
       user_email,
       creation_time,
       start_time,
       end_time,
       TIMESTAMP_DIFF(start_time, creation_time, MILLISECOND) AS queue_ms,
       TIMESTAMP_DIFF(end_time,   start_time,    MILLISECOND) AS exec_ms,
       total_slot_ms,
       total_bytes_processed,
       cache_hit
  FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
 WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
   AND job_type = 'QUERY'
   AND state = 'DONE'
 ORDER BY exec_ms DESC
 LIMIT 20;

-- 2) 慢查询的 stage 级时间分布
SELECT job_id,
       stage.id     AS stage_id,
       stage.name   AS stage_name,
       stage.slot_ms,
       stage.shuffle_output_bytes,
       stage.records_read,
       stage.wait_ratio_avg,         -- 平均等待比例
       stage.wait_ms_avg,
       stage.read_ratio_avg,
       stage.compute_ratio_avg,
       stage.write_ratio_avg
  FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT,
       UNNEST(job_stages) AS stage
 WHERE job_id = 'bquxjob_xxxxxxx'
 ORDER BY stage.id;
```

### CockroachDB: crdb_internal.cluster_queries

CockroachDB 提供 crdb_internal 系列虚表，跨节点聚合所有活动查询的状态。

```sql
-- 1) 当前所有活动查询
SELECT node_id,
       query_id,
       session_id,
       user_name,
       client_address,
       start AS started_at,
       NOW() - start AS duration,
       phase,                           -- 'preparing' / 'executing'
       LEFT(query, 80) AS query
  FROM crdb_internal.cluster_queries
 ORDER BY duration DESC;

-- 2) 当前持有/等待的锁
SELECT *
  FROM crdb_internal.cluster_locks
 WHERE database_name = 'mydb'
   AND lock_strength != 'Intent'
 ORDER BY duration DESC NULLS LAST;

-- 3) 集群语句统计 (历史等价于 pg_stat_statements + 等待维度)
SELECT key,
       statistics->'statistics'->'cnt'              AS executions,
       statistics->'statistics'->'runLat'->>'mean'  AS avg_run_ms,
       statistics->'statistics'->'svcLat'->>'mean'  AS avg_svc_ms,
       statistics->'statistics'->'rowsRead'->>'mean'  AS avg_rows_read,
       statistics->'statistics'->'lockWait'->>'mean'  AS avg_lock_wait_ms,
       statistics->'statistics'->'idleLat'->>'mean'   AS avg_idle_ms
  FROM crdb_internal.cluster_statement_statistics
 ORDER BY (statistics->'statistics'->'svcLat'->>'mean')::FLOAT DESC
 LIMIT 20;
```

### TiDB: PROCESSLIST + Top SQL

TiDB 兼容 MySQL 协议，但内部使用类似 ASH 的 Top SQL 采样机制。

```sql
-- 1) 当前 SQL (类似 MySQL)
SELECT id,
       user,
       host,
       db,
       command,
       time,
       state,
       LEFT(info, 80) AS query
  FROM INFORMATION_SCHEMA.PROCESSLIST
 ORDER BY time DESC;

-- 2) Top SQL by CPU (TiDB 6.0+, 1Hz 采样)
SELECT instance,
       sql_digest,
       cpu_time_ms,
       exec_count,
       sum_latency / 1e6 AS sum_latency_ms
  FROM INFORMATION_SCHEMA.STATEMENTS_SUMMARY
 ORDER BY sum_latency DESC
 LIMIT 20;

-- 3) 慢日志 (落盘到文件 + 视图查询)
SELECT time,
       user,
       db,
       query_time,
       process_time,           -- TiKV coprocessor 计算时间
       wait_time,              -- 在 TiKV 排队等待时间
       backoff_time,           -- TiKV 重试退避时间
       lock_keys_time,
       request_count,
       process_keys,
       LEFT(query, 80) AS query
  FROM INFORMATION_SCHEMA.SLOW_QUERY
 WHERE time > NOW() - INTERVAL 1 HOUR
 ORDER BY query_time DESC
 LIMIT 20;
```

### OceanBase: GV$ACTIVE_SESSION_HISTORY (兼容 Oracle ASH)

OceanBase 完整复刻了 Oracle ASH，连视图名都几乎一致。

```sql
-- 1) 类似 Oracle ASH
SELECT event,
       wait_class,
       COUNT(*) AS samples,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct
  FROM GV$ACTIVE_SESSION_HISTORY
 WHERE sample_time > NOW() - INTERVAL '5' MINUTE
   AND wait_class != 'Idle'
 GROUP BY event, wait_class
 ORDER BY samples DESC
 LIMIT 10;

-- 2) 历史 ASH 持久化 (类似 AWR)
SELECT event_no,
       event,
       wait_class,
       SUM(time_waited) / 1e6 AS time_waited_seconds
  FROM GV$SYSTEM_EVENT
 WHERE wait_class != 'Idle'
 GROUP BY event_no, event, wait_class
 ORDER BY 4 DESC
 LIMIT 20;
```

## PostgreSQL wait_event_type 8 大类深度解析

PostgreSQL 9.6 引入的 wait_event_type 把所有等待事件归到 8 大类，理解每类的含义是诊断 PG 性能问题的基础。

### 1. Lock — 重量级锁等待 (heavyweight locks)

事务级锁，跨进程协调。最常见也最容易理解。

```text
关系锁:
  AccessShareLock        : SELECT 持有
  RowShareLock          : SELECT FOR UPDATE/SHARE 持有
  RowExclusiveLock      : INSERT/UPDATE/DELETE 持有
  ShareUpdateExclusiveLock : VACUUM, ANALYZE, ALTER INDEX 持有
  ShareLock             : CREATE INDEX 持有
  ShareRowExclusiveLock : 罕见
  ExclusiveLock         : 一些罕见 DDL
  AccessExclusiveLock   : DROP TABLE, TRUNCATE, ALTER TABLE 等持有

行级锁:
  transactionid    : 等待另一事务结束 (典型 row-lock 场景)
  tuple            : 行级锁
  extend           : 等待表扩展 (heap 文件扩展)
  speculative      : INSERT ON CONFLICT 等待

诊断方法: pg_blocking_pids() + pg_locks 视图关联
```

### 2. LWLock — 轻量级锁 (lightweight locks)

PG 内部短期共享内存数据结构的保护，比 Lock 短得多 (微秒级)。

```text
buffer_content    : 缓冲区数据保护 (热数据页竞争)
buffer_io         : 缓冲区 I/O 同步
buffer_mapping    : 缓冲区映射表 (shared_buffers 哈希表)
WALWrite          : WAL 写入串行化
WALInsert         : WAL 缓冲区插入
WALSync           : WAL fsync
ProcArrayLock     : 进程数组保护 (高连接数下的瓶颈)
CommitTs          : 提交时间戳
SubtransSLRU     : 子事务 SLRU 缓存
MultiXactOffset  : MultiXact 偏移
LockManager      : 锁管理器内部
PredicateLockManager : SSI 串行化锁管理

如果 LWLock 经常出现, 通常说明 PG 内部结构成为瓶颈
```

### 3. Buffer — 缓冲区操作

```text
BufferPin   : 等待 pin 计数清零 (rare, 通常发生在 VACUUM 与查询竞争)
```

### 4. IO — 磁盘 I/O 等待

```text
DataFileRead, DataFileWrite, DataFileExtend  : 数据文件 I/O
WALRead, WALWrite, WALSync                    : WAL 文件 I/O
WALInitWrite, WALInitSync                     : 新 WAL 段初始化
RelationMapRead, RelationMapWrite             : pg_filenode.map I/O
SLRURead, SLRUWrite, SLRUSync                 : SLRU 缓存 I/O (commit log, multixact 等)
ControlFileRead, ControlFileWrite             : pg_control 文件 I/O
LogicalRewriteSync                            : 逻辑解码相关
TwophaseFileRead, TwophaseFileWrite          : 两阶段提交 I/O
BasebackupRead, BasebackupSync                : 物理备份相关 (PG14+)
```

### 5. IPC — 进程间通信

```text
HashBuildAllocate, HashBuildElectAllocate : 并行 Hash Join 同步
HashBuildHashOuter, HashBuildHashInner     : 同上
ProcArrayGroupUpdate                       : ProcArray 批量更新
XactGroupUpdate                            : 事务状态批量更新
ParallelFinish                             : 并行查询结束同步
ParallelBitmapScan                         : 并行 Bitmap Scan
ParallelCreateIndexScan                    : 并行 CREATE INDEX
ReplicationOriginDrop                      : 逻辑复制
LogicalSyncStateChange, LogicalSyncData    : 逻辑复制同步
SyncRep                                    : 同步复制等待远端确认
MessageQueueInternal, MessageQueueSend     : 后台 worker 消息队列
ProcSignal                                 : 进程信号
SafeSnapshot                               : 串行化事务安全快照
```

### 6. Activity — 服务进程的常态空闲

```text
ArchiverMain, AutoVacuumMain, BgWriterHibernate
CheckpointerMain, LogicalLauncherMain, LogicalApplyMain
WalSenderMain, WalReceiverMain, WalWriterMain
RecoveryWalAll, RecoveryWalStream          : 物理复制
PgStatsMain                                : 统计收集器
SysLoggerMain                              : 系统日志收集

特点: 这些事件大部分时间都在被等待, 不算"等待问题"
诊断时通常应过滤掉 wait_event_type = 'Activity'
```

### 7. Client — 等待客户端

```text
ClientRead         : 等待客户端发送下一个查询 (idle in transaction 也归此)
ClientWrite        : 等待客户端读取结果 (慢客户端 / 大结果集)
LibPQWalReceiverConnect, LibPQWalReceiverReceive : 物理复制连接
SSLOpenServer      : SSL 握手
WalSenderWaitForWAL: 主库等待新 WAL 写入
WalSenderWriteData : 等待发送 WAL 给从库
GSSOpenServer      : GSSAPI 握手

idle in transaction 长时间挂起, 通常是应用未及时 commit/rollback
```

### 8. Timeout — 等待定时事件

```text
BaseBackupThrottle  : 备份限流
PgSleep             : pg_sleep() 函数
RecoveryApplyDelay  : 备库延迟应用
RecoveryRetrieveRetryInterval : 备库重试
VacuumDelay         : VACUUM cost-based delay
```

### Extension — 扩展定义

第三方扩展可以注册自己的 wait_event (如 Citus, TimescaleDB)。

## Oracle ASH (Active Session History) 1Hz 采样深度

ASH 是 Oracle 10g (2003) 引入的革命性诊断机制，借鉴了操作系统的统计采样思想。

### 工作原理

```text
1. MMNL 后台进程每 1 秒扫描 V$SESSION
2. 仅记录 status='ACTIVE' 的会话快照 (含 wait_event, sql_id, p1/p2/p3 等 ~60 字段)
3. 写入 SGA 的循环缓冲区 (V$ACTIVE_SESSION_HISTORY, ~2MB/CPU)
4. MMON 每 10 秒选取 1/10 样本写入 AWR (DBA_HIST_ACTIVE_SESS_HISTORY, 持久化)

采样而非事件 → 开销极低 (<1% CPU)
长事件天然被偏好捕捉 (一个 10 秒等待会被采样 10 次)
短事件可能完全错过 (但短事件本身不是性能问题)
```

### 经典 ASH 查询

```sql
-- TOP-N 等待事件 (按采样数 = 近似 active seconds)
SELECT event,
       wait_class,
       COUNT(*) AS active_sec,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 2) AS pct
  FROM v$active_session_history
 WHERE sample_time > SYSDATE - INTERVAL '10' MINUTE
   AND wait_class != 'Idle'
 GROUP BY event, wait_class
 ORDER BY 3 DESC
 FETCH FIRST 10 ROWS ONLY;

-- TOP SQL by DB Time
SELECT sql_id,
       COUNT(*) AS active_sec,
       SUM(CASE WHEN session_state = 'ON CPU'  THEN 1 END) AS cpu_sec,
       SUM(CASE WHEN session_state = 'WAITING' THEN 1 END) AS wait_sec
  FROM v$active_session_history
 WHERE sample_time > SYSDATE - INTERVAL '1' HOUR
 GROUP BY sql_id
 ORDER BY 2 DESC
 FETCH FIRST 10 ROWS ONLY;

-- 关联 SQL 文本 + Plan
SELECT a.sql_id,
       a.event,
       a.session_state,
       COUNT(*) AS samples,
       MIN(SUBSTR(s.sql_text, 1, 80)) AS sql_preview
  FROM v$active_session_history a,
       v$sqlarea s
 WHERE a.sql_id = s.sql_id
   AND a.sample_time > SYSDATE - INTERVAL '30' MINUTE
   AND a.wait_class != 'Idle'
 GROUP BY a.sql_id, a.event, a.session_state
 ORDER BY samples DESC;

-- 锁阻塞链分析
SELECT blocking_session,
       blocking_session_serial#,
       sql_id,
       event,
       COUNT(*) AS blocked_samples
  FROM v$active_session_history
 WHERE blocking_session IS NOT NULL
   AND sample_time > SYSDATE - INTERVAL '1' HOUR
 GROUP BY blocking_session, blocking_session_serial#, sql_id, event
 ORDER BY blocked_samples DESC;
```

### ASH vs 同步累计的本质区别

```text
同步累计 (V$SYSTEM_EVENT):
  + 完整精确 (每次等待都记账)
  + 总等待时间 = 真实总和
  - 高并发下记账开销显著
  - 无法关联到 SQL_ID (除非用 V$SESSION_EVENT 实时观察)
  - 无法回溯历史时段 (只能看从启动到现在的累计)

采样 (ASH):
  + 极低开销 (1Hz 不论负载)
  + 时间窗口可任意切片 (过去 5 分钟 vs 过去 1 小时)
  + 自然关联 SQL_ID, 用户, 会话等所有维度
  + 长事件天然被多次采样 (重要事件不会丢)
  - 总等待时间是估计值 (采样数 × 1秒)
  - 短事件 (<1秒) 可能完全错过 (但短事件本身不是问题)
```

## SQL Server Top-N Wait Stats 查询模式

### Paul Randal 的著名查询

SQL Server 社区最广为流传的 wait stats 查询，由 Paul Randal (前 SQL Server team member) 整理。

```sql
WITH [Waits] AS (
    SELECT
        [wait_type],
        [wait_time_ms] / 1000.0                                   AS [WaitS],
        ([wait_time_ms] - [signal_wait_time_ms]) / 1000.0         AS [ResourceS],
        [signal_wait_time_ms] / 1000.0                            AS [SignalS],
        [waiting_tasks_count]                                     AS [WaitCount],
        100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER()      AS [Percentage],
        ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC)           AS [RowNum]
    FROM sys.dm_os_wait_stats
    WHERE [wait_type] NOT IN (
        N'BROKER_EVENTHANDLER',         N'BROKER_RECEIVE_WAITFOR',
        N'BROKER_TASK_STOP',             N'BROKER_TO_FLUSH',
        N'BROKER_TRANSMITTER',           N'CHECKPOINT_QUEUE',
        N'CHKPT',                        N'CLR_AUTO_EVENT',
        N'CLR_MANUAL_EVENT',             N'CLR_SEMAPHORE',
        N'DBMIRROR_DBM_EVENT',           N'DBMIRROR_EVENTS_QUEUE',
        N'DBMIRROR_WORKER_QUEUE',        N'DBMIRRORING_CMD',
        N'DIRTY_PAGE_POLL',              N'DISPATCHER_QUEUE_SEMAPHORE',
        N'EXECSYNC',                     N'FSAGENT',
        N'FT_IFTS_SCHEDULER_IDLE_WAIT',  N'FT_IFTSHC_MUTEX',
        N'HADR_CLUSAPI_CALL',            N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
        N'HADR_LOGCAPTURE_WAIT',         N'HADR_NOTIFICATION_DEQUEUE',
        N'HADR_TIMER_TASK',              N'HADR_WORK_QUEUE',
        N'KSOURCE_WAKEUP',               N'LAZYWRITER_SLEEP',
        N'LOGMGR_QUEUE',                 N'MEMORY_ALLOCATION_EXT',
        N'ONDEMAND_TASK_QUEUE',          N'PARALLEL_REDO_DRAIN_WORKER',
        N'PARALLEL_REDO_LOG_CACHE',      N'PARALLEL_REDO_TRAN_LIST',
        N'PARALLEL_REDO_WORKER_SYNC',    N'PARALLEL_REDO_WORKER_WAIT_WORK',
        N'PREEMPTIVE_HADR_LEASE_MECHANISM', N'PREEMPTIVE_SP_SERVER_DIAGNOSTICS',
        N'PREEMPTIVE_OS_LIBRARYOPS',     N'PREEMPTIVE_OS_COMOPS',
        N'PREEMPTIVE_OS_CRYPTOPS',       N'PREEMPTIVE_OS_PIPEOPS',
        N'PREEMPTIVE_OS_AUTHENTICATIONOPS', N'PREEMPTIVE_OS_GENERICOPS',
        N'PREEMPTIVE_OS_VERIFYTRUST',    N'PREEMPTIVE_OS_FILEOPS',
        N'PREEMPTIVE_OS_DEVICEOPS',      N'PREEMPTIVE_OS_QUERYREGISTRY',
        N'PREEMPTIVE_OS_WRITEFILE',      N'PREEMPTIVE_XE_CALLBACKEXECUTE',
        N'PREEMPTIVE_XE_DISPATCHER',     N'PREEMPTIVE_XE_GETTARGETSTATE',
        N'PREEMPTIVE_XE_SESSIONCOMMIT',  N'PREEMPTIVE_XE_TARGETINIT',
        N'PREEMPTIVE_XE_TARGETFINALIZE', N'PWAIT_ALL_COMPONENTS_INITIALIZED',
        N'PWAIT_DIRECTLOGCONSUMER_GETNEXT', N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
        N'QDS_ASYNC_QUEUE',              N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
        N'QDS_SHUTDOWN_QUEUE',           N'REDO_THREAD_PENDING_WORK',
        N'REQUEST_FOR_DEADLOCK_SEARCH',  N'RESOURCE_QUEUE',
        N'SERVER_IDLE_CHECK',            N'SLEEP_BPOOL_FLUSH',
        N'SLEEP_DBSTARTUP',              N'SLEEP_DCOMSTARTUP',
        N'SLEEP_MASTERDBREADY',          N'SLEEP_MASTERMDREADY',
        N'SLEEP_MASTERUPGRADED',         N'SLEEP_MSDBSTARTUP',
        N'SLEEP_SYSTEMTASK',             N'SLEEP_TASK',
        N'SLEEP_TEMPDBSTARTUP',          N'SNI_HTTP_ACCEPT',
        N'SP_SERVER_DIAGNOSTICS_SLEEP',  N'SQLTRACE_BUFFER_FLUSH',
        N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SQLTRACE_WAIT_ENTRIES',
        N'WAIT_FOR_RESULTS',             N'WAITFOR',
        N'WAITFOR_TASKSHUTDOWN',         N'WAIT_XTP_HOST_WAIT',
        N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', N'WAIT_XTP_CKPT_CLOSE',
        N'XE_DISPATCHER_JOIN',           N'XE_DISPATCHER_WAIT',
        N'XE_TIMER_EVENT'
    )
    AND [waiting_tasks_count] > 0
)
SELECT
    MAX([W1].[wait_type])                        AS [WaitType],
    CAST(MAX([W1].[WaitS])      AS DECIMAL(16,2)) AS [Wait_S],
    CAST(MAX([W1].[ResourceS])  AS DECIMAL(16,2)) AS [Resource_S],
    CAST(MAX([W1].[SignalS])    AS DECIMAL(16,2)) AS [Signal_S],
    MAX([W1].[WaitCount])                         AS [WaitCount],
    CAST(MAX([W1].[Percentage]) AS DECIMAL(5,2))  AS [Percentage],
    CAST((MAX([W1].[WaitS])     / MAX([W1].[WaitCount])) AS DECIMAL(16,4)) AS [AvgWait_S],
    CAST((MAX([W1].[ResourceS]) / MAX([W1].[WaitCount])) AS DECIMAL(16,4)) AS [AvgRes_S],
    CAST((MAX([W1].[SignalS])   / MAX([W1].[WaitCount])) AS DECIMAL(16,4)) AS [AvgSig_S]
FROM [Waits] AS [W1]
INNER JOIN [Waits] AS [W2]
    ON [W2].[RowNum] <= [W1].[RowNum]
GROUP BY [W1].[RowNum]
HAVING SUM([W2].[Percentage]) - MAX([W1].[Percentage]) < 95;   -- 累计到 95% 停止
```

### Wait Stats 重置技巧

```sql
-- 清零 wait stats (DBCC, 只影响当前实例)
DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR);

-- 标准做法: 清零 → 等待 N 分钟 → 再次查询 → 计算这段时间的等待
-- 比直接看实例启动以来的累计更有诊断价值

DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR);
WAITFOR DELAY '00:30:00';      -- 等待 30 分钟
-- 然后运行 Paul Randal 查询
```

### Query Store + Wait Stats (2017+)

```sql
-- Query Store 的最大优势: SQL 历史 + 等待事件 持久化关联
-- 即使 SQL Server 重启或 buffer cache 被清空也不丢失

ALTER DATABASE MyDB SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    WAIT_STATS_CAPTURE_MODE = ON,            -- 启用等待统计采集
    DATA_FLUSH_INTERVAL_SECONDS = 900,       -- 15 分钟刷盘
    INTERVAL_LENGTH_MINUTES = 60,            -- 1 小时聚合粒度
    MAX_STORAGE_SIZE_MB = 1000,
    QUERY_CAPTURE_MODE = AUTO
);

-- 找出过去 24 小时哪条 SQL 等待最多, 各等待类别占比
SELECT TOP 20
       qsq.query_id,
       LEFT(qsqt.query_sql_text, 80) AS query_text,
       qsws.wait_category_desc,
       SUM(qsws.total_query_wait_time_ms) AS total_wait_ms,
       SUM(qsws.avg_query_wait_time_ms)   AS avg_wait_ms,
       SUM(qsrs.count_executions)         AS executions
  FROM sys.query_store_wait_stats        qsws
  JOIN sys.query_store_runtime_stats     qsrs ON qsws.runtime_stats_interval_id = qsrs.runtime_stats_interval_id
                                              AND qsws.plan_id = qsrs.plan_id
  JOIN sys.query_store_plan              qsp  ON qsws.plan_id = qsp.plan_id
  JOIN sys.query_store_query             qsq  ON qsp.query_id = qsq.query_id
  JOIN sys.query_store_query_text        qsqt ON qsq.query_text_id = qsqt.query_text_id
  JOIN sys.query_store_runtime_stats_interval qsi ON qsws.runtime_stats_interval_id = qsi.runtime_stats_interval_id
 WHERE qsi.start_time > DATEADD(hour, -24, SYSDATETIMEOFFSET())
 GROUP BY qsq.query_id, qsqt.query_sql_text, qsws.wait_category_desc
 ORDER BY total_wait_ms DESC;
```

#### Query Store Wait Categories (聚合后的高层分类)

```text
CPU                      : SOS_SCHEDULER_YIELD, THREADPOOL
Worker Thread            : THREADPOOL
Lock                     : LCK_M_*
Latch                    : LATCH_*
Buffer Latch             : PAGELATCH_*
Buffer IO                : PAGEIOLATCH_*
Compilation              : RESOURCE_SEMAPHORE_QUERY_COMPILE
SQL CLR                  : CLR_*
Mirroring                : DBMIRROR_*
Transaction              : XACT_*, DTC_*
Idle                     : SLEEP_*
Preemptive               : PREEMPTIVE_*
Service Broker           : BROKER_*
Tran Log IO              : LOGMGR, LOGBUFFER, WRITELOG
Network IO               : ASYNC_NETWORK_IO
Parallelism              : CXPACKET, CXCONSUMER, EXCHANGE
Memory                   : RESOURCE_SEMAPHORE
User Wait                : WAITFOR
Tracing                  : TRACEWRITE
Full Text Search         : FT_*
Other Disk IO            : ASYNC_IO_COMPLETION
Replication              : REPL_*
Log Rate Governor        : POOL_LOG_RATE_GOVERNOR (Azure SQL)
```

## 关键发现 (Key Findings)

### 1. 等待事件诊断的成熟度差异巨大

```text
最成熟 (开箱即用 + 历史 + SQL 关联):
  Oracle (V$SESSION_WAIT 1992 + ASH 2003 + AWR), OceanBase (复刻 Oracle)
  SQL Server (DMV 2005 + 会话级 2016 + Query Store wait 2017)

中等成熟 (有数据但需要扩展或人工聚合):
  MySQL (P_S 5.6+, 自带累计但需主动启用)
  DB2 (MON_GET_REQUEST_WAITS 9.7+)
  ClickHouse (ProfileEvents 模型, 与传统 wait event 概念不同)

入门级 (只有当前快照, 历史靠扩展):
  PostgreSQL (9.6+, wait_event 仅当前快照, 需 pg_wait_sampling 持久化)
  YugabyteDB / Greenplum / Citus (继承 PG)

粗粒度 (只有查询级阶段时间):
  Snowflake (queue/compile/execute time)
  BigQuery (JOB_TIMING + jobTimeline)
  Redshift (STL_QUERY)
  云数仓普遍简化, 内部细节对用户不可见

无原生支持:
  SQLite, H2, HSQLDB, Derby, InfluxDB, MonetDB (部分)
```

### 2. 同步累计 vs 异步采样：两种正交模型

| 维度 | 同步累计 (V$SYSTEM_EVENT, dm_os_wait_stats, P_S) | 异步采样 (ASH, pg_wait_sampling) |
|------|--------------------------------------------|-------------------------------|
| 完整性 | 100% 精确 | 概率性, 长事件偏好 |
| 开销 | 高 (与负载成正比) | 极低 (固定频率) |
| 时间窗口 | 实例启动以来累计 (除非清零) | 任意切片 |
| SQL 关联 | 同步: 较弱; 实时: 强 | 强 (每个样本带 SQL_ID) |
| 短事件 | 全部捕获 | 可能错过 (但通常不重要) |

成熟的诊断系统应同时具备两者：累计提供"长期趋势"，采样提供"具体哪条 SQL 在等什么"。

### 3. wait class 概念的普及度

```text
Oracle: 12 大类 (1992 引入), 是行业标准
PostgreSQL: 8 大类 (2016 引入), 借鉴 Oracle 概念
SQL Server: 平铺 ~1000 个 wait_type, 无内置分类 (Query Store 2017 才有 wait_category)
MySQL: 4 大类前缀分类 (wait/io/, wait/lock/, wait/synch/, wait/idle)

分类的价值:
1. 快速判断瓶颈维度 (I/O / 锁 / 并发 / 网络)
2. 报表聚合 (避免 1000 个事件名挤在一起)
3. 跨版本兼容 (具体事件名常变, 类别相对稳定)
```

### 4. SQL 与等待的关联是分水岭

| 关联强度 | 引擎 | 实现方式 |
|---------|------|---------|
| 强 (历史可查) | Oracle ASH/AWR, SQL Server Query Store, OceanBase | 持久化 SQL_ID + 等待样本/聚合 |
| 中 (实时可查) | MySQL P_S (events_statements + events_waits join), 当前活动 PG, DB2 MON_GET_ACTIVITY | 当前线程的活跃 SQL + 当前等待 |
| 弱 (需扩展) | PostgreSQL + pg_wait_sampling, ClickHouse 手工 ProfileEvents | 第三方/手工方案 |
| 无 | 大多云数仓 (只有查询总耗时, 无内部等待分布) | 黑盒 |

### 5. 历史保留对生产诊断至关重要

"半夜 3 点系统卡了 10 分钟", 第二天 9 点上班才有人看: 没有持久化的等待事件历史, 这种问题永远查不出。

```text
有内置持久化:
  Oracle AWR (默认 8 天, 可调到 365 天)
  SQL Server Query Store (默认 30 天, 可配置)
  ClickHouse system.metric_log + query_log (默认 7 天)
  Snowflake ACCOUNT_USAGE.QUERY_HISTORY (365 天)
  BigQuery INFORMATION_SCHEMA.JOBS (180 天)

需主动持久化:
  PostgreSQL (pg_wait_sampling 配合外部时间序列库)
  MySQL (events_waits_history_long 仅 10000 行内存, 需脚本采集)

无持久化:
  CockroachDB (实时), Materialize (实时)
  → 必须配合外部 Prometheus + 长期存储
```

### 6. 云数仓的"黑盒化"趋势

云数仓 (Snowflake / BigQuery / Redshift / Databricks SQL) 普遍**不暴露内部等待事件**, 只提供高层阶段时间 (queue / compile / execute)。

```text
理由:
1. 多租户隔离 (用户不应看到底层资源争用细节)
2. 简化心智模型 (大多用户不懂 wait event)
3. 引擎演进自由 (内部架构频繁重构, 暴露细节意味着锁定)

代价:
- 复杂性能问题难以诊断 (只能通过加 warehouse 或加 slot 解决)
- 无法做容量规划的精细调优
- 有经验的 Oracle DBA 切换到 Snowflake 后会感到"工具不够用"

折中方案:
- Snowflake QUERY_HISTORY 提供 queued_overload / compilation / execution 时间分解
- BigQuery jobTimeline 提供 stage 级 wait_ratio_avg
- 都比"只有总时间"好一点, 但远不及 Oracle ASH 那样深入
```

### 7. PG 直到 9.6 (2016) 才补齐 wait event：晚了 24 年

```text
Oracle 1992 → SQL Server 2005 → MySQL 2013 → PostgreSQL 2016

即便如此, PG 的 wait event 至今仍只有当前快照, 没有内置累计或历史。
社区扩展 pg_wait_sampling (Postgres Pro 出品) 是事实标准。
PG17 (2024) 也没有把 sampling 纳入核心。

设计哲学差异:
- Oracle/MS: "DBA 必须有完整诊断工具" → 内置持久化
- PG: "保持核心精简, 高级功能用扩展" → 依赖 pg_wait_sampling, pg_stat_statements 等
```

### 8. MySQL 5.6 P_S 的开销不容忽视

```text
performance_schema 默认开启了部分 instrumentation, 但 wait/synch/* 类的 mutex 监控
开销可达 5-15%, 因此 RDS / Aurora 等托管服务默认仅启用部分:
  setup_consumers events_waits_current        : ON
  setup_consumers events_waits_history        : OFF (需手动开启)
  setup_consumers events_waits_history_long   : OFF (需手动开启)

诊断时按需开启:
UPDATE performance_schema.setup_consumers
   SET ENABLED = 'YES'
 WHERE NAME LIKE 'events_waits%';

但要记得查询完关回去, 或者按 instrument 名细粒度控制 (如只开 wait/io/file/*, 不开 wait/synch/mutex/*)
```

### 9. 锁等待与一般等待的诊断方法不同

```text
锁等待 (Lock wait_event_type):
  → 必须用阻塞链分析 (PG: pg_blocking_pids; SQL Server: sys.dm_tran_locks join sys.dm_os_waiting_tasks)
  → 找到 blocker 才能解决 (kill 或等其释放)
  → 与 SQL 调优、索引设计强相关

资源等待 (I/O, CPU, 内存):
  → 用 wait stats 累计 + Top SQL by wait
  → 通常通过容量规划 (加内存 / 加磁盘 / 加 CPU) 或 SQL 调优 (减少扫描) 解决

并发协调等待 (LWLock, latch, CXPACKET):
  → 通常是引擎内部瓶颈
  → 解决方案: 调整 max_connections / shared_buffers / MAXDOP 等参数, 或拆分负载
```

### 10. 引擎开发者的实现建议

```text
1. 累计 + 采样并行:
   累计 (类似 V$SYSTEM_EVENT) 提供精确总和
   采样 (1Hz 类似 ASH) 提供与 SQL/会话的低开销关联
   两者都需要

2. SQL 关联是必备:
   仅有 wait event 名是远远不够的
   必须能回答 "现在 / 5 分钟前 / 1 小时前, 哪条 SQL 在等什么"

3. 持久化窗口:
   内存中至少保留 1 小时的细粒度
   持久化至少 7 天的中粒度 (5 分钟聚合)
   历史归档至少 30 天的粗粒度 (1 小时聚合)

4. 阻塞链原生支持:
   pg_blocking_pids() 类的递归锁追溯函数
   阻塞树可视化 (锁图谱)

5. 分类体系:
   学习 Oracle Wait Class 或 PG wait_event_type
   把成百上千个具体事件归到 ~10 个高层类别

6. 默认就开启 (低开销采样):
   不要让用户在事故发生后才说 "你应该早点开 P_S"
   1Hz 采样 + 持久化 7 天 是合理的默认值
```

## 参考资料

- Oracle: [Active Session History (ASH)](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgdba/active-session-history.html)
- Oracle: [V$SESSION_WAIT](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-SESSION_WAIT.html)
- Oracle: [V$ACTIVE_SESSION_HISTORY](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-ACTIVE_SESSION_HISTORY.html)
- Oracle: [Wait Classes](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/wait-events-statistics.html)
- SQL Server: [sys.dm_os_wait_stats](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-os-wait-stats-transact-sql)
- SQL Server: [sys.dm_exec_session_wait_stats](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-session-wait-stats-transact-sql)
- SQL Server: [sys.query_store_wait_stats](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-wait-stats-transact-sql)
- SQL Server: [Query Store Wait Categories](https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
- Paul Randal: [SQLskills Wait Stats Library](https://www.sqlskills.com/help/waits/)
- MySQL: [Performance Schema Wait Event Tables](https://dev.mysql.com/doc/refman/8.0/en/performance-schema-wait-tables.html)
- MySQL: [sys.waits_global_by_latency](https://dev.mysql.com/doc/refman/8.0/en/sys-waits-global-by-latency.html)
- PostgreSQL: [Wait Events](https://www.postgresql.org/docs/current/monitoring-stats.html#WAIT-EVENT-TABLE)
- PostgreSQL: [pg_stat_activity](https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-ACTIVITY-VIEW)
- pg_wait_sampling: [GitHub repo](https://github.com/postgrespro/pg_wait_sampling)
- DB2: [MON_GET_REQUEST_WAITS](https://www.ibm.com/docs/en/db2/11.5?topic=routines-mon-get-request-waits-table-function)
- ClickHouse: [system.events](https://clickhouse.com/docs/en/operations/system-tables/events)
- ClickHouse: [system.metric_log](https://clickhouse.com/docs/en/operations/system-tables/metric_log)
- Snowflake: [QUERY_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/query_history)
- BigQuery: [INFORMATION_SCHEMA.JOBS](https://cloud.google.com/bigquery/docs/information-schema-jobs)
- CockroachDB: [crdb_internal](https://www.cockroachlabs.com/docs/stable/crdb-internal.html)
- TiDB: [TOP SQL](https://docs.pingcap.com/tidb/stable/top-sql)
- OceanBase: [GV$ACTIVE_SESSION_HISTORY](https://www.oceanbase.com/docs/)
