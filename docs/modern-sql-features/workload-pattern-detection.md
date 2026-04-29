# 工作负载模式检测 (Workload Pattern Detection)

凌晨四点，告警系统提示集群 CPU 利用率从平时的 30% 飙升到 95%，核心应用响应时间从 50 毫秒升至 5 秒。打开运维平台的那一刻，DBA 最先要回答的问题是："现在到底是哪些 SQL 在烧 CPU？比基线慢了多少？这个模式以前是否出现过？"——工作负载模式检测 (Workload Pattern Detection) 就是把这些问题从"靠经验猜"变成"按数据答"的核心能力。

## 为什么需要工作负载模式检测

慢查询日志解决了"哪条 SQL 跑得慢"，查询指纹解决了"同一模板有多少次执行"，但生产现场的真问题往往更复杂：

1. **Top SQL 识别**：在每秒数万条 SQL 的 OLTP 系统中，95% 的资源消耗集中在不到 100 个 SQL 模板。把这些"重投资"模板按 CPU/IO/逻辑读排名，是任何调优工作的起点。
2. **回归检测**：上线后某个模板的 P99 从 50ms 涨到 500ms，是流量上涨、统计信息过期、还是计划突变？没有基线对比，DBA 无法在 5 分钟内定位。
3. **基线对比**：上周同一时段的负载分布是怎样的？同期对比可以快速识别"周期性"和"突发性"问题。
4. **异常检测**：某个原本每天执行 100 次的查询，突然在 10 分钟内被执行 10 万次——这往往是应用 bug 或攻击的信号。
5. **容量规划**：未来 3 个月的资源缺口在哪？哪些模板将首先成为瓶颈？需要长期 (天/周/月) 维度的工作负载画像。
6. **变更影响评估**：新版本上线后，有哪些 SQL 模板进入或退出 Top N？哪些计划发生变化？哪些是性能改善、哪些是退化？

工作负载模式检测的演进路径大致经历了三个时代：

- **手动 SQL_TRACE 时代 (1990s)**：Oracle 的 SQL_TRACE 7.x、TKPROF；SQL Server 的 SQL Trace；MySQL 的 mysqldumpslow——DBA 手动开启 trace、解析文件、统计 Top N
- **AWR/Query Store 时代 (2003-2017)**：Oracle 10g (2003) 的 AWR 自动每小时快照，DBA 可以直接对比任意两个快照；SQL Server 2016 的 Query Store 内置在数据库引擎；MySQL 5.6 (2013) 的 performance_schema 支持
- **ML 异常检测时代 (2018+)**：AWS Performance Insights (2018) 引入按维度自动钻取；DevOps Guru (2020) 用机器学习自动发现异常；Azure Query Performance Insight 内置阈值告警；Aurora ML 模型识别隐式回归

> 说明：本主题完全是厂商扩展，**SQL 标准 (ISO/IEC 9075) 没有任何关于工作负载分析、Top SQL、基线快照的规定**。所有视图、表函数、配置项都是各厂商独立设计的；甚至同一厂商不同版本的命名也常有变化 (Oracle 7 V$SESSION → 10g AWR → 12c CDB_HIST_*)。

## 没有 SQL 标准

工作负载模式检测属于运维诊断范畴，SQL 标准既不规定监控视图，也不约束采样、聚合、告警语义。原因有三：

1. **标准聚焦语义而非性能**：ISO/IEC 9075 定义的是"执行了什么"而非"执行得怎么样"
2. **物理实现差异巨大**：行存 vs 列存、单机 vs 分布式、托管 vs 自管的运维模型完全不同
3. **厂商商业利益**：Oracle Diagnostic Pack 是付费授权，AWR/ASH 是其核心卖点；标准化反而损害商业利益

由此带来的现实是：

- 同样的"Top SQL 视图"在 Oracle 叫 `V$SQLAREA`，在 MySQL 叫 `events_statements_summary_by_digest`，在 PG 叫 `pg_stat_statements`，在 Snowflake 叫 `QUERY_HISTORY`；列名、单位、聚合方式都不同
- AWR 报告这种"快照对比"形态被多厂商参考但没有统一格式 (Oracle awrrpt.sql、PG awr_pgsql、TiDB Dashboard 各自不兼容)
- 异常检测算法 (季节性分解、孤立森林、动态阈值) 主流上仅在云厂商产品中提供，自建数据库基本依赖外部 APM (Datadog, New Relic, Prometheus + Grafana)
- 跨引擎迁移工作负载分析栈几乎需要完全重做

## 支持矩阵 (45+ 引擎)

### 1. 原生 Top SQL 视图

下表列出主流引擎是否提供"按资源消耗排序的 SQL 列表"原生视图。

| 引擎 | 原生视图/表 | 排序维度 | 持久化 | 引入版本 |
|------|------------|---------|--------|---------|
| Oracle | `V$SQLAREA` / `DBA_HIST_SQLSTAT` | elapsed/cpu/buffer_gets/disk_reads | AWR 持久化 | 9i+ / 10g (2003) |
| SQL Server | `sys.dm_exec_query_stats` + Query Store `sys.query_store_runtime_stats` | total_worker_time/elapsed/logical_reads | Query Store 持久化 | 2008 / 2016 |
| MySQL | `performance_schema.events_statements_summary_by_digest` + `sys.statement_analysis` | sum_timer_wait/sum_rows_examined | 内存 | 5.6 (2013) |
| MariaDB | 同 MySQL + `pmm` 插件 | 同 MySQL | 内存 | 10.x+ |
| PostgreSQL | `pg_stat_statements` 扩展 + `pg_stat_kcache` | total_exec_time/total_plan_time | 内存 (重启丢失) | 8.4 (2009) |
| SQLite | -- | -- | -- | 不支持 |
| DB2 LUW | `MON_GET_PKG_CACHE_STMT` + `EVMON_FORMAT_UE_TO_TABLES` | TOTAL_CPU_TIME/TOTAL_ACT_TIME | event monitor | 9.7+ (2010) |
| Snowflake | `INFORMATION_SCHEMA.QUERY_HISTORY` + `ACCOUNT_USAGE.QUERY_HISTORY` | EXECUTION_TIME/COMPILATION_TIME | 365 天 (Account Usage) | GA |
| BigQuery | `INFORMATION_SCHEMA.JOBS_BY_PROJECT` + Query Insights | total_slot_ms/total_bytes_processed | 180 天 | GA / 2022 (Insights) |
| Redshift | `SYS_QUERY_HISTORY` + `STL_QUERY` + Advisor | elapsed/queue_time | 2-7 天 (本机)/ 365 天 (Audit) | GA |
| ClickHouse | `system.query_log` + `system.query_thread_log` | query_duration_ms/memory_usage | 默认 7 天 | 早期 |
| Trino | event listener 插件 + JMX | -- | -- | 早期 |
| Presto | event listener (Webhook) | -- | -- | 早期 |
| Spark SQL | Spark History Server (event log) | duration/inputBytes | -- | 1.x+ |
| Hive | `hive.querylog.location` + Tez UI | -- | -- | -- |
| Flink SQL | Flink Web UI / Metrics | -- | metrics 持久化 | 1.x+ |
| Databricks | `system.query.history` + Query Profile UI | duration_ms/total_task_duration_ms | 持久化 | GA |
| Teradata | DBQL `DBC.DBQLogTbl` + ResUsage | TotalCPUTime/TotalIOCount | DBQL 持久化 | V2R5+ |
| Greenplum | `pg_stat_statements` + `gp_toolkit.gp_stats_*` | 同 PG | 内存 + 扩展 | 6.0+ |
| CockroachDB | `crdb_internal.statement_statistics` + Insights | service_lat_avg/contention_time | 持久化 | 21.1+ / 22.2 (Insights) |
| TiDB | `INFORMATION_SCHEMA.STATEMENTS_SUMMARY` + Top SQL Dashboard | sum_latency/exec_count | 内存 + 持久化 | 4.0+ / 5.4 (Top SQL, 2022) |
| OceanBase | `GV$OB_SQL_AUDIT` + `DBA_HIST_*` | elapsed_time/execute_time | 内存 + 落盘 | 3.x+ |
| YugabyteDB | `pg_stat_statements` + YSQL Stats | 同 PG | 内存 | 2.6+ |
| SingleStore | `INFORMATION_SCHEMA.MV_QUERIES` + `MV_ACTIVITIES` | execution_time/cpu_time_ms | 持久化 | 7.x+ |
| Vertica | `QUERY_PROFILES` + `EXECUTION_ENGINE_PROFILES` | request_duration_ms/memory_acquired | DC 持久化 | 早期 |
| Impala | impalad PROFILE + `IMPALA_QUERY_LOG` | totalTime/cpuTime | 内存环 + Web UI | 早期 |
| StarRocks | `_statistics_.audit_log` + Query Profile | query_time/scan_bytes | audit 持久化 | 1.x+ |
| Doris | `__internal_schema.audit_log` + Profile | query_time | audit 持久化 | 早期 |
| MonetDB | `sys.queue` + 日志 | -- | -- | -- |
| CrateDB | `sys.jobs_log` | duration | 内存 | 早期 |
| TimescaleDB | 继承 PG + `timescaledb_information.job_stats` | 同 PG | 同 PG | 继承 PG |
| QuestDB | server log | -- | -- | -- |
| Exasol | `EXA_DBA_PROFILE_*` + `EXA_USER_AUDIT_SQL` | duration/temp_db_ram | 30 天 | 早期 |
| SAP HANA | `M_EXPENSIVE_STATEMENTS` + `M_SQL_PLAN_CACHE` | total_execution_time/total_lock_wait_time | 持久化 | 早期 |
| Informix | `sysmaster:sysscan` / `syssqltrace` | 默认按 elapsed 排序 | trace buffer | 11.50+ |
| Firebird | trace API + `MON$STATEMENTS` | -- | -- | 2.5+ |
| H2 | trace file | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | 不支持 |
| Derby | derby.log | -- | -- | 不支持 |
| Amazon Athena | `INFORMATION_SCHEMA.QUERY_HISTORY` (Workgroup, 预览) | elapsed/data_scanned | CloudWatch | GA / 2024 (预览) |
| Azure Synapse | `sys.dm_pdw_exec_requests` + Query Performance Insight | total_elapsed_time | Azure Monitor | GA |
| Azure SQL Database | Query Performance Insight + Query Store | cpu_time/duration | Query Store 持久化 | 2018 |
| Aurora MySQL/PostgreSQL | RDS Performance Insights + DevOps Guru | DBLoad / wait events | 7-731 天 | 2018 (PI) / 2020 (DevOps Guru) |
| Google Spanner | `SPANNER_SYS.QUERY_STATS_TOP_*` | elapsed_time/cpu_seconds | 30 天 (按粒度) | GA |
| Materialize | `mz_internal.mz_recent_activity_log` + `mz_compute_dependencies` | -- | 持久化视图 | GA |
| RisingWave | `rw_catalog.rw_query_log` (有限) | -- | -- | -- |
| InfluxDB (SQL/IOx) | -- | -- | -- | 不支持 |
| Databend | `system.query_log` | duration_ms | 持久化 | GA |
| Yellowbrick | `sys.log_query` | run_time | 自带追踪 | GA |
| Firebolt | `INFORMATION_SCHEMA.QUERY_HISTORY` | duration_us | 14 天 | GA |

> 统计：约 41 个引擎提供某种形式的 Top SQL 视图，云原生数仓和托管服务普遍提供更长的持久化保留 (90-365 天)，自管引擎多为内存或短期持久化 (7-30 天)。

### 2. 基线 / 回归检测

"基线"指对历史时段的工作负载特征进行汇总并保存，"回归检测"指对当前与基线进行对比、识别异常变化。

| 引擎 | 基线/快照机制 | 回归检测能力 | 自动化级别 |
|------|--------------|------------|----------|
| Oracle | AWR snapshot (默认 1 小时) + Baseline (`DBMS_WORKLOAD_REPOSITORY.CREATE_BASELINE`) | ADDM 报告自动对比 | 高 (ADDM 自动诊断) |
| SQL Server | Query Store (Plan + Runtime stats) | Query Store regressed_queries 报告 | 中 (Auto Plan Correction since 2017) |
| MySQL | -- (需外部 PMM/Datadog) | 仅 sys.statement_analysis 排名 | 低 (无内置基线) |
| PostgreSQL | `pg_stat_statements_reset()` + 手动备份 | 需外部工具 (pgwatch2, pgBadger) | 低 |
| DB2 LUW | `EVMON_FORMAT_UE_TO_TABLES` 历史表 | optim_query_workload 包 | 中 |
| Snowflake | Account Usage `QUERY_HISTORY` (365 天) | Resource Monitor + 手动比较 | 中 |
| BigQuery | Query Insights (Slot consumption baseline) | INFORMATION_SCHEMA.JOBS_TIMELINE | 中 |
| Redshift | Advisor (自动建议) + STL_QUERY 历史 | Auto WLM + Concurrency Scaling | 中 |
| ClickHouse | system.query_log 持久化 + ttl | 仅手动对比 | 低 |
| Trino | -- | 需外部 (Datadog, Grafana) | 低 |
| Spark SQL | History Server 持久化 event log | -- | 低 |
| Databricks | system.query.history (持久化) + Lakehouse Monitoring | 自动 lineage + alert | 中 |
| Teradata | DBQL 历史 + Workload Designer | DBQL Trend Analysis | 中 |
| CockroachDB | crdb_internal.statement_statistics + Insights tab | Insights (Slow + Schema) | 中 (22.2+) |
| TiDB | Statement Summary History + Top SQL Dashboard | Top SQL 对比 + Continuous Profiling | 中 (5.4+) |
| OceanBase | `DBA_HIST_*` (兼容 Oracle AWR 形态) | 类 ADDM (有限) | 中 |
| Aurora (RDS) | Performance Insights (7-731 天) + DevOps Guru | DevOps Guru ML 自动检测异常 | 高 (ML) |
| Azure SQL DB | Query Performance Insight + Automatic Tuning | Auto Index + Auto Plan Correction | 高 |
| Vertica | DC 历史 + Workload Analyzer | Workload Analyzer 建议 | 中 |
| SAP HANA | M_SQL_PLAN_CACHE 累计 + Capture/Replay | Capture/Replay 回归测试 | 中 |
| Exasol | EXA_USER_AUDIT_SQL (审计) | 仅手动 | 低 |
| Spanner | Query Stats (30 天) | -- | 低 |
| 其他 | -- | 多依赖外部 APM | 低 |

> 关键洞察：**真正自动化的回归检测仅在云托管 / 商业数据库中存在** (Oracle ADDM, SQL Server Auto Plan Correction, Aurora DevOps Guru, Azure SQL Automatic Tuning)。开源/自管系统普遍依赖外部 APM 栈。

### 3. 异常告警

| 引擎 | 内置异常检测 | 告警通道 | ML 模型 |
|------|------------|---------|--------|
| Oracle | ADDM Findings + EM Cloud Control alerts | Enterprise Manager / OEM | 静态阈值 + 启发式 |
| SQL Server | Query Store regression detection + Extended Events | SQL Agent / Azure Monitor | 启发式 (回归百分比) |
| MySQL | -- (无内置) | -- | 无 |
| PostgreSQL | -- (无内置) | 需外部 | 无 |
| Aurora MySQL/PG | DevOps Guru ML Insights | SNS + Lambda | ML (异常评分) |
| Azure SQL DB | Performance Recommendations + Anomaly Detection | Azure Monitor | ML (内部) |
| Snowflake | Resource Monitor + Account Usage alerts | Email / SNS / Webhook | 静态阈值 |
| BigQuery | Cloud Monitoring + Recommender | Cloud Pub/Sub | 启发式 |
| Redshift | Advisor 建议 | CloudWatch | 启发式 |
| Datadog Database Monitoring | 跨引擎 ML 异常 | Slack/PagerDuty/Email | ML |
| Aurora DevOps Guru | DBLoad spike, anomalous wait events | SNS | ML (Random Cut Forest) |
| TiDB | Top SQL + 慢查询自动告警 | Webhook + AlertManager | 静态阈值 |
| CockroachDB | Insights (slow, contention, plan changes) | Webhook | 启发式 |
| OceanBase | OCP 告警 | OCP / Webhook | 静态阈值 |
| ClickHouse Cloud | 内置 metrics 告警 | Email / Slack | 静态阈值 |
| Databricks | Lakehouse Monitoring | Webhook / Email | ML (Schema/data drift) |
| 自管 PG/MySQL | -- | 依赖 Prometheus + Alertmanager | 静态/可定制 |

### 4. AWR 风格快照

"AWR 风格快照"指：周期性 (固定间隔，通常 1 小时) 把当前的工作负载视图聚合到持久化历史表，DBA 可以对比任意两个时段的差异。

| 引擎 | 快照机制 | 默认间隔 | 持久化 | 报告生成 |
|------|---------|---------|--------|---------|
| Oracle | AWR (`DBMS_WORKLOAD_REPOSITORY`) | 60 分钟 | 8 天 (默认) | `awrrpt.sql` / OEM |
| SQL Server | Query Store + Performance Dashboard | 持续累计 | INTERVAL_LENGTH_MINUTES 配置 | Performance Dashboard |
| MySQL | -- (无内置) | -- | -- | 需 PMM/外部 |
| PostgreSQL | `pg_profile` 扩展 (类 AWR) / pgwatch2 | 30 分钟 (扩展) | 配置 | 扩展生成 |
| DB2 LUW | `db2top` + Event Monitor | -- | -- | -- |
| Snowflake | ACCOUNT_USAGE | 持续累计 | 365 天 | 自定义查询 |
| Redshift | STL_QUERY + Advisor | 持续累计 | 7 天 (本机) | Advisor 报告 |
| Teradata | DBQL Summary | 10 分钟 (默认) | 配置 | Viewpoint |
| OceanBase | `DBA_HIST_*` | 60 分钟 | 30 天 | 类 AWR 报告 |
| Aurora (RDS) | Performance Insights | 1 秒采样 | 7-731 天 | PI 控制台 |
| TiDB | Statement Summary History + Continuous Profiling | 30 分钟 (默认) | 90 天 | TiDB Dashboard |
| ClickHouse | system.query_log + metric_log | 持续累计 | TTL 配置 | -- |
| SAP HANA | Plan Cache snapshots | 持续累计 | 配置 | -- |
| Exasol | EXA_DBA_PROFILE_RUNNING | 实时 | 30 天 | -- |
| Vertica | DC (Data Collector) | 实时 | 配置 (默认 8 天) | Workload Analyzer |
| pg_profile (PG 扩展) | 类 AWR | 30 分钟 | 配置 | HTML 报告 |
| pgBadger | 离线日志聚合 | 按日 | 配置 | HTML 报告 |
| pgwatch2 | InfluxDB 采集 | 60 秒 | 配置 | Grafana |

> 注：纯开源 PG 没有内置 AWR 等价物，但 `pg_profile` (Postgres Pro 主导)、`pgBadger` (CLI 日志解析)、`pgwatch2` (Cybertec) 等社区工具填补了这一空缺。

### 5. 云 APM 集成

| 引擎/服务 | 内置 APM 集成 | 第三方 APM | API 形态 |
|----------|--------------|----------|---------|
| Aurora (RDS) | Performance Insights / DevOps Guru | Datadog DBM, New Relic | CloudWatch + PI API |
| Azure SQL DB | Query Performance Insight | Datadog, AppDynamics | Azure Monitor |
| Snowflake | Trail / Account Usage | Datadog, Monte Carlo | Account Usage views |
| BigQuery | Query Insights + Cloud Monitoring | Datadog | INFORMATION_SCHEMA |
| Cloud SQL (PG/MySQL) | Cloud Monitoring + Insights | Datadog | INFORMATION_SCHEMA + API |
| Spanner | Query Insights | Datadog | SPANNER_SYS |
| TiDB Cloud | TiDB Dashboard + Top SQL | Datadog (实验) | -- |
| CockroachDB Cloud | DB Console + Insights | Datadog | API |
| MongoDB Atlas (跨界对比) | Performance Advisor + Query Profiler | Datadog | Atlas API |
| Databricks | Lakehouse Monitoring + System Tables | Datadog | system.* tables |
| Self-managed | -- | Datadog DBM, Percona PMM, SolarWinds DPA | JDBC + scrape |

> Datadog Database Monitoring (DBM) 已成为跨引擎工作负载诊断的事实标准之一，覆盖 PostgreSQL/MySQL/SQL Server/Oracle/MongoDB；其工作原理是通过 SQL 查询 (而非 wire-protocol 嗅探) 获取统计视图，对引擎本身侵入很小。

## Oracle AWR：自动负载存储库深度剖析

Oracle 的 AWR (Automatic Workload Repository) 是工作负载分析领域的事实标准——后续几乎所有"快照对比"模型都参考了它。

### 概念架构

```
                +----------------------+
                |  内存中 v$ 视图       |
                |  (V$SQLAREA, V$SQL,  |
                |   V$SESSION_EVENT)   |
                +----------+-----------+
                           |
                           | MMON 后台进程
                           | 每小时一次快照
                           v
                +----------------------+
                |  SYSAUX 表空间        |
                |  (DBA_HIST_*)        |
                +----------+-----------+
                           |
                           | 默认保留 8 天
                           v
                +----------------------+
                |  awrrpt.sql 报告      |
                |  + ADDM 自动诊断      |
                +----------------------+
```

关键点：

1. **MMON (Memory Monitor) 后台进程**：每 60 分钟 (默认) 把内存视图聚合到 `DBA_HIST_*` 表
2. **采样基础是 ASH (Active Session History)**：每 1 秒采样所有 active session 状态
3. **默认保留 8 天**：可通过 `DBMS_WORKLOAD_REPOSITORY.MODIFY_SNAPSHOT_SETTINGS(retention => 30*24*60)` 调整为 30 天
4. **快照编号自增**：snap_id 单调递增，DBA 通过指定 begin_snap, end_snap 生成报告

### Diagnostic Pack License

AWR 是 Oracle Database Enterprise Edition 的功能，但**默认许可不包括 AWR**，需要单独购买 **Diagnostic Pack** 选件 (约每 CPU 每年数千美元，价格按 Oracle 协议谈判)。

```sql
-- 查看是否启用 (Oracle 12c+)
SELECT name, detected_usages, currently_used
FROM DBA_FEATURE_USAGE_STATISTICS
WHERE name LIKE '%AWR%' OR name LIKE 'Diagnostic Pack';

-- CONTROL_MANAGEMENT_PACK_ACCESS 控制是否允许使用诊断包
ALTER SYSTEM SET CONTROL_MANAGEMENT_PACK_ACCESS = 'DIAGNOSTIC+TUNING' SCOPE=BOTH;
-- 取值: NONE, DIAGNOSTIC, DIAGNOSTIC+TUNING
```

> 提醒：在没有 Diagnostic Pack 授权的环境查询 `DBA_HIST_*` 视图会被 Oracle 视为合规违约。Standard Edition 中 AWR 不可用，Statspack 是其免费替代品 (功能子集)。

### 关键视图与字段

```sql
-- 所有快照
SELECT snap_id, begin_interval_time, end_interval_time
FROM DBA_HIST_SNAPSHOT
ORDER BY snap_id DESC FETCH FIRST 24 ROWS ONLY;

-- Top SQL by elapsed_time (历史)
SELECT s.snap_id,
       SUBSTR(t.sql_text, 1, 60) AS sql_preview,
       s.elapsed_time_delta / 1e6 AS elapsed_sec,
       s.cpu_time_delta / 1e6 AS cpu_sec,
       s.executions_delta AS exec_count,
       s.buffer_gets_delta AS buffer_gets
FROM DBA_HIST_SQLSTAT s
JOIN DBA_HIST_SQLTEXT t ON s.sql_id = t.sql_id
WHERE s.snap_id = (SELECT MAX(snap_id) FROM DBA_HIST_SNAPSHOT)
ORDER BY s.elapsed_time_delta DESC
FETCH FIRST 20 ROWS ONLY;

-- Top events by waited time (历史快照)
SELECT event_name, total_waits_delta, time_waited_micro_delta / 1e6 AS waited_sec
FROM DBA_HIST_SYSTEM_EVENT
WHERE snap_id = ?
ORDER BY waited_sec DESC FETCH FIRST 15 ROWS ONLY;
```

### 生成 AWR 报告

```sql
-- 交互式报告 (推荐: SQL*Plus)
@?/rdbms/admin/awrrpt.sql

-- 编程式生成 (快照 ID 已知)
SELECT output FROM TABLE(
    DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_HTML(
        l_dbid    => (SELECT dbid FROM v$database),
        l_inst_num => 1,
        l_bid      => 12345,    -- begin snap_id
        l_eid      => 12348     -- end snap_id
    )
);

-- 跨实例 (RAC) 报告
@?/rdbms/admin/awrgrpt.sql

-- ASH 报告 (单 session 详情)
@?/rdbms/admin/ashrpt.sql
```

### 创建命名基线

```sql
-- 把"业务高峰" (2026-04-29 10:00 ~ 11:00) 的快照保存为命名基线
BEGIN
    DBMS_WORKLOAD_REPOSITORY.CREATE_BASELINE(
        start_snap_id => 12345,
        end_snap_id   => 12348,
        baseline_name => 'PEAK_HOUR_BASELINE',
        expiration    => NULL  -- 永不过期
    );
END;
/

-- 列出所有基线
SELECT baseline_name, start_snap_id, end_snap_id, expiration
FROM DBA_HIST_BASELINE;

-- 比较当前与基线 (Diff Periods)
SELECT output FROM TABLE(
    DBMS_WORKLOAD_REPOSITORY.AWR_DIFF_REPORT_HTML(
        dbid1       => (SELECT dbid FROM v$database),
        inst_num1   => 1,
        bid1        => 12345,
        eid1        => 12348,
        dbid2       => (SELECT dbid FROM v$database),
        inst_num2   => 1,
        bid2        => 67890,
        eid2        => 67893
    )
);
```

### ADDM (Automatic Database Diagnostic Monitor)

ADDM 是基于 AWR 数据的自动诊断引擎：

```sql
-- 查看 ADDM 任务
SELECT task_name, advisor_name, created
FROM DBA_ADVISOR_TASKS
WHERE advisor_name = 'ADDM'
ORDER BY created DESC FETCH FIRST 10 ROWS ONLY;

-- 查看最新发现 (Top Findings)
SELECT type, name, message, impact_pct
FROM DBA_ADVISOR_FINDINGS
WHERE task_name = 'ADDM:1234567_8901_8902'
ORDER BY impact_pct DESC;

-- 推荐的具体动作
SELECT type, message, command
FROM DBA_ADVISOR_RECOMMENDATIONS
WHERE task_name = 'ADDM:1234567_8901_8902';
```

ADDM 的"DB Time"模型是其灵魂：把整个实例的时间消耗按"等待事件 → 资源 → SQL"维度分解，找出 Top 影响因子。这一思路被 SQL Server Query Store、AWS Performance Insights 等多个产品继承。

### AWR 的局限性

1. **粒度受限**：1 小时快照对 5 分钟级别的突发事件几乎无效
2. **采样偏置**：ASH 1 秒采样会漏掉短事件 (<1s)，长事件被多次记录形成偏置
3. **存储成本**：DBA_HIST_* 在繁忙系统每天可写入 GB 级数据，SYSAUX 容易爆满
4. **License 风险**：未购买 Diagnostic Pack 却查询 DBA_HIST_* 会被认定合规违约
5. **跨实例对比难**：DBA_HIST_* 仅本实例数据，跨数据库对比需要 ADDM Cross Database (12c+)

## SQL Server Query Store + Automatic Plan Correction

SQL Server 2016 引入的 Query Store 是"内置在数据库引擎"的工作负载存储库，2017 加入 Automatic Plan Correction，是对 Oracle AWR/SPM 的精简化复制。

### 启用与配置

```sql
-- 启用 Query Store
ALTER DATABASE production SET QUERY_STORE = ON
    (OPERATION_MODE = READ_WRITE,
     CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
     DATA_FLUSH_INTERVAL_SECONDS = 900,
     INTERVAL_LENGTH_MINUTES = 60,
     MAX_STORAGE_SIZE_MB = 1024,
     QUERY_CAPTURE_MODE = AUTO,        -- AUTO/ALL/CUSTOM/NONE
     SIZE_BASED_CLEANUP_MODE = AUTO);

-- 查看当前配置
SELECT actual_state_desc, current_storage_size_mb,
       max_storage_size_mb, query_capture_mode_desc,
       interval_length_minutes
FROM sys.database_query_store_options;
```

### Top SQL 查询

```sql
-- Top 10 by total CPU time (most recent 24 hours)
SELECT TOP 10
    qsq.query_id,
    qst.query_sql_text,
    qsrs.count_executions,
    qsrs.avg_cpu_time / 1000 AS avg_cpu_ms,
    qsrs.avg_duration / 1000 AS avg_duration_ms,
    qsrs.avg_logical_io_reads,
    qsrs.last_execution_time
FROM sys.query_store_query qsq
JOIN sys.query_store_query_text qst ON qsq.query_text_id = qst.query_text_id
JOIN sys.query_store_plan qsp ON qsq.query_id = qsp.query_id
JOIN sys.query_store_runtime_stats qsrs ON qsp.plan_id = qsrs.plan_id
JOIN sys.query_store_runtime_stats_interval qsrsi
     ON qsrs.runtime_stats_interval_id = qsrsi.runtime_stats_interval_id
WHERE qsrsi.start_time >= DATEADD(HOUR, -24, SYSUTCDATETIME())
ORDER BY qsrs.avg_cpu_time * qsrs.count_executions DESC;
```

### 回归查询识别

Query Store 内置 "Regressed Queries" 报告，识别**计划发生变化导致性能退化**的 SQL：

```sql
-- 找出多个计划且最新计划比历史计划慢 > 50% 的查询
WITH plan_stats AS (
    SELECT qsq.query_id,
           qsp.plan_id,
           AVG(qsrs.avg_cpu_time) AS avg_cpu,
           MAX(qsrs.last_execution_time) AS last_exec
    FROM sys.query_store_query qsq
    JOIN sys.query_store_plan qsp ON qsq.query_id = qsp.query_id
    JOIN sys.query_store_runtime_stats qsrs ON qsp.plan_id = qsrs.plan_id
    GROUP BY qsq.query_id, qsp.plan_id
),
ranked AS (
    SELECT query_id, plan_id, avg_cpu, last_exec,
           ROW_NUMBER() OVER (PARTITION BY query_id ORDER BY last_exec DESC) AS rn
    FROM plan_stats
)
SELECT a.query_id, a.plan_id AS new_plan, a.avg_cpu AS new_avg_cpu,
       b.plan_id AS old_plan, b.avg_cpu AS old_avg_cpu,
       (a.avg_cpu * 1.0 / NULLIF(b.avg_cpu, 0)) AS regression_ratio
FROM ranked a
JOIN ranked b ON a.query_id = b.query_id AND b.rn = a.rn + 1
WHERE a.rn = 1 AND a.avg_cpu > b.avg_cpu * 1.5;
```

### Force Plan / Automatic Plan Correction

```sql
-- 手动强制使用某个计划
EXEC sp_query_store_force_plan @query_id = 42, @plan_id = 100;

-- 取消强制
EXEC sp_query_store_unforce_plan @query_id = 42, @plan_id = 100;

-- 启用 Automatic Plan Correction (SQL Server 2017+)
ALTER DATABASE production
SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON);
-- 启用后，Query Store 检测到计划回归 (CPU 增加 > 10%) 会自动 force 上一个 "good plan"
```

Automatic Plan Correction 的判定逻辑：

```
1. 检测计划变化：query_id 出现新的 plan_id
2. 比较新旧计划：新计划在最近 N 次执行中的 avg_cpu_time 是否 > 旧计划 1.1x ?
3. 如果是，标记为 "regression"
4. 在 sys.dm_db_tuning_recommendations 中给出建议
5. 如果 FORCE_LAST_GOOD_PLAN = ON，自动 force 旧计划
6. 持续监控 forced plan，如果性能仍然不好，取消 force 让优化器重新选择
```

### 与 Oracle SQL Plan Management 的对比

| 特性 | SQL Server Query Store + APC | Oracle SPM |
|------|------------------------------|-----------|
| 计划存储位置 | 数据库内部 (Query Store) | SYSAUX (Plan Baselines) |
| 自动捕获 | QUERY_CAPTURE_MODE = AUTO | DBMS_SPM 手动或 SPA |
| 自动应用 | FORCE_LAST_GOOD_PLAN = ON | 手动 evolve baseline |
| 历史保留 | INTERVAL_LENGTH_MINUTES + STORAGE_SIZE | 无固定限制 |
| 引入版本 | 2016 / 2017 (APC) | 11g (2007) |
| License | 标准/企业均可 | EE + Tuning Pack |

## MySQL Performance Schema + sys schema

MySQL 5.6 (2013) 引入 performance_schema，5.7 (2015) 加入 sys schema 提供更友好的视图。

### Top SQL 查询

```sql
-- Top 10 by total latency (sys schema)
SELECT digest_text, exec_count, total_latency,
       avg_latency, lock_latency, rows_sent, rows_examined,
       first_seen, last_seen
FROM sys.statement_analysis
ORDER BY total_latency DESC
LIMIT 10;

-- 等价的 raw performance_schema 查询
SELECT DIGEST_TEXT,
       COUNT_STAR AS exec_count,
       SUM_TIMER_WAIT / 1e12 AS total_sec,
       AVG_TIMER_WAIT / 1e9 AS avg_ms,
       SUM_ROWS_EXAMINED, SUM_ROWS_SENT,
       FIRST_SEEN, LAST_SEEN
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 10;
```

### 全表扫描 / 高代价查询

```sql
-- 全表扫描的 Top 查询
SELECT * FROM sys.statements_with_full_table_scans
ORDER BY rows_examined DESC LIMIT 10;

-- 临时表 / 文件排序
SELECT * FROM sys.statements_with_temp_tables ORDER BY tmp_disk_tables DESC LIMIT 10;
SELECT * FROM sys.statements_with_sorting    ORDER BY rows_sorted DESC      LIMIT 10;

-- 高错误率
SELECT * FROM sys.statements_with_errors_or_warnings LIMIT 20;
```

### 周期性重置 (基线)

MySQL 没有内置基线机制，常见做法：

```sql
-- 1. 定期 dump performance_schema 到归档表
CREATE TABLE archive.statement_snapshot_20260429 AS
SELECT NOW() AS snapshot_time, *
FROM performance_schema.events_statements_summary_by_digest;

-- 2. 重置统计 (准备下一个采集窗口)
TRUNCATE performance_schema.events_statements_summary_by_digest;

-- 3. 对比两个快照
SELECT a.digest_text,
       a.count_star - b.count_star AS exec_delta,
       (a.sum_timer_wait - b.sum_timer_wait) / 1e9 AS latency_delta_ms
FROM archive.statement_snapshot_20260429 a
JOIN archive.statement_snapshot_20260428 b
     ON a.digest = b.digest
ORDER BY latency_delta_ms DESC LIMIT 20;
```

实际生产中通常使用 **PMM (Percona Monitoring and Management)** 或 **Datadog DBM** 自动完成这些采集。

## PostgreSQL pg_stat_statements + pg_stat_kcache + auto_explain

PG 的工作负载分析依赖三件套扩展：

### pg_stat_statements (8.4 since 2009)

```sql
-- 安装
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
-- postgresql.conf:
--   shared_preload_libraries = 'pg_stat_statements'
--   pg_stat_statements.max = 10000
--   pg_stat_statements.track = all
--   pg_stat_statements.track_planning = on   -- PG 13+

-- Top by total time
SELECT queryid, calls, total_exec_time, mean_exec_time,
       rows, shared_blks_read, shared_blks_hit,
       LEFT(query, 80) AS query_preview
FROM pg_stat_statements
ORDER BY total_exec_time DESC LIMIT 20;

-- Top by IO
SELECT queryid, calls,
       shared_blks_read + shared_blks_dirtied + shared_blks_written AS total_blks,
       LEFT(query, 80) AS query_preview
FROM pg_stat_statements
ORDER BY total_blks DESC LIMIT 20;
```

### pg_stat_kcache (扩展)

补充 OS 级别的真实 IO/CPU (从 /proc/self/io 和 getrusage):

```sql
CREATE EXTENSION pg_stat_kcache;

-- Top by real CPU
SELECT k.queryid, s.calls,
       k.user_time + k.system_time AS total_cpu_sec,
       k.reads, k.writes,
       LEFT(s.query, 80) AS query_preview
FROM pg_stat_kcache k
JOIN pg_stat_statements s ON s.queryid = k.queryid
ORDER BY total_cpu_sec DESC LIMIT 20;
```

### auto_explain (内置模块)

自动记录慢查询的执行计划：

```ini
# postgresql.conf
shared_preload_libraries = 'auto_explain'
auto_explain.log_min_duration = '500ms'
auto_explain.log_analyze = on
auto_explain.log_buffers = on
auto_explain.log_timing = on
auto_explain.log_verbose = off
auto_explain.log_format = 'json'
auto_explain.sample_rate = 1.0   # 1.0 = 全部记录
```

记录后日志中会出现完整 EXPLAIN ANALYZE 输出，可用 pgBadger 聚合解析。

### pgBadger / pgwatch / pg_profile

| 工具 | 角色 | 数据源 | 输出 |
|------|------|--------|------|
| pgBadger | 离线日志解析 | postgresql.log | HTML 报告 |
| pgwatch2 | 实时监控 | pg_stat_* + InfluxDB | Grafana 仪表盘 |
| pg_profile | 类 AWR 快照 | pg_stat_statements + 自表 | HTML 报告 |
| pgAnalyze | 商业 SaaS | logs + pg_stat_* | Web UI |
| Datadog DBM | 商业 APM | logs + pg_stat_* | Datadog 控制台 |
| pgwatch (PG 14+) | 实时监控 (Cybertec, 重写版) | pg_stat_* + 多种存储 | 仪表盘 |

### pg_profile 类 AWR 报告 (示例)

```sql
CREATE EXTENSION pg_profile;

-- 创建快照 (定期由 cron / pg_cron 调度)
SELECT pg_profile.snapshot();

-- 查看快照列表
SELECT * FROM pg_profile.show_samples();

-- 生成两个快照之间的 HTML 报告
SELECT pg_profile.get_report(start_id => 1234, end_id => 1240);

-- 跨数据库报告
SELECT pg_profile.get_servers_report(start_id => 1234, end_id => 1240);
```

pg_profile 的设计理念是"PG 的 AWR"，但功能仍逊色于 Oracle AWR (没有 ADDM 等价物，没有 baseline 命名机制)。

## AWS RDS Performance Insights + Aurora DevOps Guru ML

AWS Performance Insights (2018) 是托管数据库的"开箱即用工作负载分析"，2020 引入的 DevOps Guru for RDS 则是 ML 异常检测层。

### 概念架构

```
Aurora / RDS 实例
   |
   +-- Performance Insights agent (1秒采样)
   |       |
   |       +-- DBLoad metric (每秒 active session 数)
   |       +-- Top SQL by load
   |       +-- Top wait events
   |       |
   |       +-- 持久化到 PI 数据库 (7-731 天)
   |
   +-- DevOps Guru for RDS (ML 层)
           |
           +-- 检测 anomaly (DBLoad spike, novel wait events)
           +-- 生成 Insight 报告
           +-- 推送 SNS 告警
```

### DBLoad 指标

PI 的核心是 **DBLoad** = 当前 active session 数 (类似 Oracle DB Time)：

```
DBLoad = Σ active_session(t)，t 在某个时间窗口内
       = wait_time + cpu_time
```

DBA 看到 DBLoad 后可以按以下维度钻取：

- **By Wait Event**：哪种等待 (CPU, IO:DataFileRead, Lock:row_lock 等) 主导？
- **By SQL**：哪条 SQL 模板占了 DBLoad 最大份额？
- **By User / Host / Database**：哪个用户/应用造成？

### 编程访问 PI 数据

```python
import boto3

pi_client = boto3.client('pi')

# 获取过去 1 小时的 Top SQL
response = pi_client.describe_dimension_keys(
    ServiceType='RDS',
    Identifier='db-ABCDEFG',
    StartTime=datetime.utcnow() - timedelta(hours=1),
    EndTime=datetime.utcnow(),
    Metric='db.load.avg',
    GroupBy={
        'Group': 'db.sql_tokenized',
        'Dimensions': ['db.sql_tokenized.statement', 'db.sql_tokenized.id'],
        'Limit': 20
    }
)

for key in response['Keys']:
    print(f"DBLoad: {key['Total']:.2f}, SQL: {key['Dimensions']['db.sql_tokenized.statement'][:80]}")
```

### DevOps Guru ML Insights (since 2020)

DevOps Guru for RDS 使用机器学习自动检测异常：

```
ML 算法:
  - Random Cut Forest 异常评分
  - 季节性分解 (STL: Seasonal-Trend-Loess)
  - 多变量相关性分析

输入信号:
  - DBLoad 时间序列
  - 等待事件计数器
  - SQL 执行频率
  - CPU/Memory/IOPS

输出:
  - Insight (相关 metrics 的异常时间窗)
  - Recommendation (具体修复建议)
  - 严重性评级 (LOW / MEDIUM / HIGH)
```

DevOps Guru 的一个典型 Insight 示例：

```
Insight: High database load detected
  Anomalous metrics:
    - DBLoadCPU: spike from 2.0 to 18.0 (9x increase)
    - DBLoadNonCPU: from 0.5 to 5.2 (10x increase, mostly IO:DataFileRead)
    - Lock:row_lock: from 0 to 4.5

  Top contributing SQL:
    - SELECT ... FROM orders o JOIN order_items oi ON ... (load: 12.3)

  Recommendation:
    1. Check missing index on order_items(order_id)
    2. EXPLAIN suggests full scan on order_items (1.2M rows)
    3. Estimated impact: 60% reduction in DBLoad
```

### 与 Oracle AWR 的对比

| 维度 | RDS Performance Insights | Oracle AWR |
|------|--------------------------|-----------|
| 采样频率 | 1 秒 | ASH 1 秒，AWR 快照 60 分钟 |
| 持久化 | 7-731 天 | 默认 8 天 |
| 报告形式 | 控制台 UI + API | awrrpt.sql / OEM |
| 自动诊断 | DevOps Guru ML | ADDM |
| License | 包含在 RDS / Aurora 中 | Diagnostic Pack 单独购买 |
| 跨实例对比 | API 内自由组合 | DBA_HIST_* 跨实例需 Cross Database |

## Aurora DevOps Guru ML

DevOps Guru for RDS 是 AWS 在 2020 年发布的产品，把 ML 异常检测从 SageMaker 那种自定义模型抽象为开箱即用的服务。

### 启用步骤

```bash
# 1. 创建 DevOps Guru 资源覆盖
aws devops-guru update-resource-collection \
    --action ADD \
    --resource-collection-filter '{
      "CloudFormation": {"StackNames": ["my-aurora-cluster-stack"]}
    }'

# 2. 启用 RDS Performance Insights (前提)
aws rds modify-db-instance \
    --db-instance-identifier my-aurora-instance \
    --enable-performance-insights \
    --performance-insights-retention-period 731

# 3. 配置 SNS Topic (告警通道)
aws devops-guru add-notification-channel \
    --config '{
      "Sns": {"TopicArn": "arn:aws:sns:us-east-1:123:devopsguru-alerts"}
    }'
```

### 自动检测的异常类型

```
1. 性能异常:
   - DBLoad spike (相对于历史基线)
   - 异常等待事件 (新出现的 wait event 类别)
   - SQL 执行频率突变

2. 资源异常:
   - CPU/Memory/IOPS 超阈值
   - 存储空间增长异常 (磁盘满预警)
   - 连接数突增

3. Schema/Plan 异常:
   - 缺失索引建议 (基于 EXPLAIN 分析)
   - SQL 改写建议 (低效写法识别)
```

### Insight 例子分析

```
Insight: High database load
Severity: HIGH
Started: 2026-04-29T14:23:00Z
Duration: 47 minutes

Contributing factors:
  1. Anomalous DBLoad
     - Baseline: 2.5 average sessions
     - Current: 24.8 average sessions (10x increase)
  2. Wait event: IO:DataFileRead spiked
     - Baseline: 5% of DBLoad
     - Current: 78% of DBLoad
  3. SQL contributing 60% of new load:
     SELECT * FROM orders WHERE customer_id = ?
     - Plan changed: now full scan instead of index seek
     - Likely cause: customer_id_idx fragmented or missing

Recommendations:
  1. Run ANALYZE TABLE orders
  2. Check pg_stat_user_indexes.idx_scan to verify index usage
  3. Consider creating compound index (customer_id, status, created_at)

Estimated impact if applied: -65% DBLoad reduction
```

### 局限性

1. **仅 RDS / Aurora**：自管 EC2 上的 PG/MySQL 不支持
2. **数据保留依赖 PI 配置**：默认 7 天，长期诊断需付费升级到 731 天
3. **ML 误报**：周期性业务 (如月底批处理) 可能被识别为异常，需要标记 baseline 周期
4. **跨实例分析有限**：RDS Insights API 主要按单实例聚合，多实例拓扑分析依赖 Application Insights
5. **价格**：DevOps Guru 按资源 / API 调用计费，大规模启用月费可能数千美元

## TiDB Top SQL (since 5.4, 2022)

TiDB 5.4 (2022) 引入的 Top SQL 是开源数据库中较为成熟的"实时 + 历史"工作负载诊断方案，参考了 Oracle ASH 但简化了实现。

### 架构

```
+-------------------+   +-------------------+   +-------------------+
|     TiDB Server   |   |   TiKV Server     |   |    PD Server      |
|   (gRPC)          |   |   (gRPC)          |   |                   |
|   ResourceTagger  |   |   ResourceTagger  |   |                   |
+---------+---------+   +---------+---------+   +-------------------+
          | 5s 采样              | 5s 采样
          v                       v
+----------------------------------------+
|  NgMonitoring (Prometheus + ClickHouse)|
|  - cpu_usage by sql_digest             |
|  - read_keys by sql_digest             |
+--------------------+-------------------+
                     |
                     v
              +-------------+
              |   TiDB UI   |
              |  Top SQL    |
              +-------------+
```

### 实现关键点

1. **ResourceTag**：每个 RPC 请求携带 `sql_digest` 和 `plan_digest` 标签
2. **CPU 采样**：TiDB/TiKV 进程使用 `pprof` 在固定频率采样调用栈，按 sql_digest 归集
3. **读 KV 采样**：TiKV 上每个 RocksDB 读操作也按 sql_digest 计数
4. **NgMonitoring**：聚合 TiDB/TiKV 的采样数据，存入 ClickHouse
5. **TiDB Dashboard**：从 NgMonitoring 拉取 Top N

### 启用与查询

```sql
-- 启用 Top SQL (需要 NgMonitoring 部署)
SET GLOBAL tidb_enable_top_sql = 1;

-- 查看活跃 SQL
SELECT * FROM INFORMATION_SCHEMA.TIDB_TRX
ORDER BY START_TIME DESC LIMIT 20;

-- 历史 Statement Summary
SELECT digest_text, exec_count,
       sum_latency / 1e9 AS sum_latency_ms,
       avg_latency / 1e6 AS avg_latency_ms,
       max_latency / 1e6 AS max_latency_ms,
       sum_cop_task_num,
       sum_process_keys
FROM INFORMATION_SCHEMA.STATEMENTS_SUMMARY_HISTORY
WHERE summary_begin_time >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
ORDER BY sum_latency DESC LIMIT 20;

-- Top SQL by CPU (最近 30 分钟)
-- TiDB Dashboard 提供图形界面，API 也可访问:
-- GET /api/v1/topology/topsql?start=...&end=...
```

### 与 Oracle ASH 的对比

| 维度 | TiDB Top SQL | Oracle ASH |
|------|--------------|-----------|
| 采样频率 | 1 秒 (CPU pprof) | 1 秒 |
| 维度 | sql_digest, plan_digest | sql_id, session_id, wait_event |
| 持久化 | NgMonitoring (ClickHouse) | DBA_HIST_ACTIVE_SESS_HISTORY |
| 查询接口 | TiDB Dashboard + IS 视图 | V$/DBA_HIST_* |
| 报告生成 | Continuous Profiling 截图 | awrrpt.sql / OEM |
| License | 开源 (Apache 2.0) | EE + Diagnostic Pack |

### Continuous Profiling (TiDB 5.3+)

Top SQL 之外，TiDB 还提供 Continuous Profiling：

```
功能:
  - 每 1 分钟自动 pprof / 火焰图采集
  - 历史保留: 7 天 (默认)
  - 各组件: TiDB / TiKV / PD / TiFlash 全部采集

用途:
  - 故障复盘: 5 分钟前 CPU 100%, 查看那时的火焰图
  - 性能对比: 上线前后火焰图差异
  - 热点定位: 哪个 Go 函数占用最多 CPU
```

## 关键发现

### 1. 工作负载分析的"四象限"

按"实时 vs 历史" × "单查询 vs 系统"四象限：

```
                单查询             系统聚合
              +------------------+------------------+
   实时 (秒)  | 当前活动会话视图  | DBLoad/QPS 仪表盘 |
              | EXPLAIN ANALYZE  | 当前 wait_event   |
              +------------------+------------------+
   历史 (天)  | Query Store 计划 | AWR/Insights 报告 |
              | 慢日志           | 趋势对比          |
              +------------------+------------------+
```

成熟的工作负载分析栈应同时覆盖四象限。Oracle 是覆盖最全的：V$SESSION (实时单)、V$SQLAREA (实时聚)、AWR 详情 (历史单)、AWR 报告 (历史聚)。

### 2. AWR 风格快照的两种模式

**Pull 模式** (Oracle, OceanBase, pg_profile)：固定间隔 (1 小时) 主动从内存视图聚合到历史表。优点是简单稳定，缺点是粒度粗 (1 小时内的突发事件无法精细分析)。

**Push/Stream 模式** (Aurora PI, BigQuery, Snowflake)：按 1 秒级别采样，持续写入流式存储。优点是粒度细，缺点是存储成本高，需要更强的写入压力。

### 3. ML 异常检测的成本与价值权衡

云厂商在 2020-2024 集中推出 ML 异常检测：

| 产品 | ML 算法 | 月费 (估算) |
|------|--------|-----------|
| Aurora DevOps Guru | Random Cut Forest | $每资源每月 ~$2 起 |
| Azure SQL Anomaly Detection | 内部 ML | 包含在 Azure SQL 中 |
| Datadog DBM ML | 内部 ML | $70/host/month + |
| BigQuery Recommender | 启发式 + ML | 免费 |

ML 异常检测在大多数情况下提供"我们也不知道为什么但确实异常了"的提示，对没有专职 DBA 的团队价值很大；但对于经验丰富的 DBA，常常误报多于正报，需要长期调优白名单。

### 4. 开源 vs 商业的鸿沟

工作负载模式检测是**开源数据库与商业数据库差距最大的领域之一**：

- 商业数据库 (Oracle, SQL Server, Aurora) 提供"开箱即用"的 AWR/Query Store/PI 报告
- 开源数据库 (PG, MySQL) 仅提供原始视图，分析栈需要 DBA 自己组装 (pgBadger + pgwatch + pg_profile + Grafana + AlertManager)
- 唯一例外是 ClickHouse (system.query_log + 各种 metric_log) 和 TiDB (Top SQL + Continuous Profiling)，它们在开源生态中提供了相对完整的方案

### 5. 跨引擎可观测性的事实标准

由于没有 SQL 标准，跨引擎工作负载分析依赖几个**事实标准**：

- **OpenTelemetry SQL Auto-instrumentation**：JDBC/驱动层埋点，跨引擎统一 trace
- **Datadog DBM**：商业 SaaS，覆盖 PG/MySQL/SQL Server/Oracle/MongoDB
- **Percona PMM**：开源，覆盖 MySQL/PG/MongoDB
- **Prometheus mysqld_exporter / postgres_exporter**：metric 标准
- **pt-query-digest** (Percona Toolkit)：跨 MySQL/PG/MariaDB 慢日志解析

### 6. License 与合规风险

工作负载分析的功能往往是商业数据库的"加价项"：

- **Oracle Diagnostic Pack**：AWR/ASH/ADDM 必需，单独许可证
- **Oracle Tuning Pack**：SQL Tuning Advisor、SPA 必需，再单独一份
- **SQL Server Query Store**：包含在标准/企业版中，无需额外许可
- **Aurora Performance Insights**：包含在 Aurora 中，但 731 天保留需付费
- **DevOps Guru for RDS**：按资源 / API 调用计费

DBA 在生产环境查询 `DBA_HIST_*` 视图前应确认 Diagnostic Pack 已购买，否则 Oracle 审计可能认定违约 (有过案例)。

### 7. 工作负载基线的"假设"陷阱

任何"基线对比"都依赖一个假设：基线时段是"正常"的。但实际上：

- 业务有日 / 周 / 月 / 季节周期，单一基线无法覆盖
- 大促、月底批处理等"异常时段"如果被采集为基线，会导致后续真实异常被错过
- 引擎升级、硬件更换后基线全部需要重做
- 多租户共享集群，邻居的工作负载会污染基线

实际部署中，基线应至少分"工作日 / 周末"、"白天 / 夜间"、"非 / 月底"几个组合，并允许"标记业务事件"以排除特殊时段。

### 8. AI / LLM 时代的新趋势 (2024+)

2024 年起出现了几个新方向：

- **Snowflake Cortex Analyst**：自然语言查询 + 工作负载诊断
- **AWS Bedrock + DevOps Guru**：把 ML Insight 包装为 LLM 提示
- **GitHub Copilot for SQL**：基于 EXPLAIN 输出建议改写
- **PostgreSQL pgvector + LLM**：自管 PG 也可以集成自定义 LLM 诊断助手
- **TiDB Lightning + LLM**：基于 Top SQL 自动生成索引建议

这些方向尚未成熟，但显示了"工作负载分析 → AI 自动诊断"的演进路径。

### 9. 实施建议

对引擎开发者 / DBA 的建议：

1. **基础三件套优先**：Top SQL 视图、慢查询日志、wait event 视图，三者缺一不可
2. **快照基线先于 ML**：没有快照对比能力时，ML 异常检测失去基础
3. **持久化方案分层**：内存视图 (实时) + 短期持久化 (1-7 天) + 长期归档 (30-365 天)
4. **跨节点聚合**：分布式数据库需要跨节点聚合视图 (TiDB INFORMATION_SCHEMA.CLUSTER_STATEMENTS_SUMMARY)
5. **API 而非视图优先**：现代客户端 (Datadog, Grafana) 通过 API 而非 SQL 视图采集，应提供 RESTful 或 gRPC 接口
6. **License 与合规可见性**：在视图级别明确标记是否需要付费 license

### 10. 演进路径总览

```
  1992          2003          2013          2017          2022          2024
   |             |             |             |             |             |
   v             v             v             v             v             v
+-----+      +-----+      +-----+      +-----+      +-----+      +-----+
| SQL |      | AWR |      | PFS |      | APC |      | ML  |      | LLM |
|TRACE|----->|+ASH |----->|+PSS |----->|+QS  |----->|+DG  |----->|+Cortex|
+-----+      +-----+      +-----+      +-----+      +-----+      +-----+
Oracle 7    Oracle 10g    MySQL 5.6    SQL Svr 2017  Aurora       2024+
              ADDM         pg_stat_     Auto Plan     DevOps
                          statements    Correction    Guru
                          since 8.4
                          (2009)
```

## 参考资料

- Oracle: [AWR (Automatic Workload Repository)](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgdba/automatic-workload-repository.html)
- Oracle: [ADDM (Automatic Database Diagnostic Monitor)](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgdba/automatic-database-diagnostic-monitor.html)
- Oracle: [Diagnostic Pack License](https://www.oracle.com/database/technologies/diagnostic-pack-faq.html)
- SQL Server: [Query Store](https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
- SQL Server: [Automatic Tuning](https://learn.microsoft.com/en-us/sql/relational-databases/automatic-tuning/automatic-tuning)
- MySQL: [Performance Schema](https://dev.mysql.com/doc/refman/8.0/en/performance-schema.html)
- MySQL: [sys Schema](https://dev.mysql.com/doc/refman/8.0/en/sys-schema.html)
- PostgreSQL: [pg_stat_statements](https://www.postgresql.org/docs/current/pgstatstatements.html)
- PostgreSQL: [auto_explain](https://www.postgresql.org/docs/current/auto-explain.html)
- pg_stat_kcache: [Documentation](https://github.com/powa-team/pg_stat_kcache)
- pg_profile: [GitHub](https://github.com/zubkov-andrei/pg_profile)
- pgBadger: [GitHub](https://github.com/darold/pgbadger)
- pgwatch2: [GitHub](https://github.com/cybertec-postgresql/pgwatch2)
- AWS: [RDS Performance Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)
- AWS: [DevOps Guru for RDS](https://docs.aws.amazon.com/devops-guru/latest/userguide/working-with-rds.html)
- Azure: [Query Performance Insight for Azure SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/database/query-performance-insight-use)
- Azure: [Automatic Tuning in Azure SQL](https://learn.microsoft.com/en-us/azure/azure-sql/database/automatic-tuning-overview)
- Snowflake: [Query History](https://docs.snowflake.com/en/sql-reference/account-usage/query_history)
- BigQuery: [Query Insights](https://cloud.google.com/bigquery/docs/query-insights)
- Aurora DevOps Guru: [ML Insights Reference](https://docs.aws.amazon.com/devops-guru/latest/userguide/working-with-insights.html)
- TiDB: [Top SQL](https://docs.pingcap.com/tidb/stable/top-sql)
- TiDB: [Continuous Profiling](https://docs.pingcap.com/tidb/stable/continuous-profiling)
- CockroachDB: [Insights Page](https://www.cockroachlabs.com/docs/stable/ui-insights-page)
- OceanBase: [SQL Audit](https://www.oceanbase.com/docs)
- Datadog: [Database Monitoring](https://docs.datadoghq.com/database_monitoring/)
- Percona: [PMM (Percona Monitoring and Management)](https://docs.percona.com/percona-monitoring-and-management/)
- Vertica: [Workload Analyzer](https://www.vertica.com/docs/latest/HTML/Content/Authoring/AdministratorsGuide/Monitoring/Vertica/UsingWorkloadAnalyzer.htm)
- SAP HANA: [Expensive Statements Trace](https://help.sap.com/docs/SAP_HANA_PLATFORM)
