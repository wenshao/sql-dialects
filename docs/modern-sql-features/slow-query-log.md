# 慢查询日志与性能监控 (Slow Query Log and Performance Monitoring)

凌晨三点，DBA 被告警叫醒：核心交易系统 P99 延迟从 50 毫秒飙升到 8 秒。打开慢查询日志的那一刻，决定了故障定位是 5 分钟还是 5 小时——慢查询日志是 OLTP 调优最古老、却也是最不可替代的诊断工具。

## 为什么慢查询日志至关重要

OLTP 系统的性能问题几乎都遵循 80/20 分布：少数 SQL 模板贡献了绝大多数的资源消耗。慢查询日志的核心价值就是把这些"长尾"实时捕获下来，让 DBA 不必依赖事后复现：

1. **被动捕获**：开发者常常无法预测哪些查询会变慢——参数倾斜、统计信息过期、计划突变都会让原本毫秒级的查询变成秒级灾难。慢查询日志在故障发生时就把现场固定下来。
2. **趋势分析**：把日志归一化（digest）后聚合，可以看到"模板级"的 P50/P95/P99 变化，比单次执行的孤立日志更有价值。
3. **变更回归**：业务发布、索引调整、版本升级后，对比慢查询模板的进出，可以快速发现回退。
4. **容量规划**：CPU/IO 排名前 N 的 SQL 模板决定了下一次硬件采购的方向。
5. **审计取证**：和审计日志互补，慢查询日志保留了"实际执行了什么"以及"为什么慢"。

正因如此，几乎所有 OLTP 数据库都在很早期就引入了某种形式的慢查询日志：MySQL 在 3.23（2001）就有 `slow_query_log`，PostgreSQL 在 7.x 就有 `log_min_duration_statement`，Oracle 的 AWR/ASH 在 10g（2003）一并发布，SQL Server 早期靠 SQL Trace 和 Profiler，2016 年后被 Query Store 取代。

> 注意：本主题完全是厂商扩展，**SQL 标准没有任何关于性能监控/慢查询日志的规定**。所有语法、视图、配置项都是各厂商独立设计的，互不兼容。本文的对比因此完全围绕"能力维度"而非"标准符合度"。

## 支持矩阵

### 1. 慢查询日志开关与基础形态

下表列出主流 45+ 引擎的"慢查询日志"原生能力。这里区分两类：**文件日志**（写到磁盘文件，通常需要外部工具解析）和**视图/系统表**（持久化到数据库内部表，可用 SQL 直接查询）。

| 引擎 | 文件日志 | 系统视图/表 | 默认开启 | 历史 |
|------|---------|-------------|---------|------|
| PostgreSQL | `log_min_duration_statement` → server log | `pg_stat_statements` 扩展 | 否 | 7.x / 8.4 |
| MySQL | `slow_query_log` (file) / `slow_log` (table) | `performance_schema.events_statements_*` | 否 / 是(PS) | 3.23 (2001) / 5.5 |
| MariaDB | `slow_query_log` | `performance_schema` + `slow_log` 表 | 否 | 继承 MySQL |
| SQLite | -- | -- | -- | 不支持 |
| Oracle | -- | AWR + ASH + `V$SQL` / `DBA_HIST_*` | 是(AWR) | 10g+ |
| SQL Server | Extended Events / Profiler trace | Query Store + DMV | 视版本 | 2016+ (QS) |
| DB2 | event monitor (file/pipe) | `MON_GET_*` 表函数 | 是(MON) | 9.7+ |
| Snowflake | -- | `QUERY_HISTORY` 视图 | 是 | GA |
| BigQuery | -- | `INFORMATION_SCHEMA.JOBS_*` | 是 | GA |
| Redshift | -- | `STL_QUERY` / `SVL_QUERY_REPORT` / `SYS_QUERY_HISTORY` | 是 | GA |
| DuckDB | -- | -- (PRAGMA `enable_profiling`) | 否 | -- |
| ClickHouse | -- | `system.query_log` | **是** | 早期 |
| Trino | event listener (插件) | -- | 否 | -- |
| Presto | event listener (插件) | -- | 否 | -- |
| Spark SQL | event log (JSON files) | History Server | 否 | -- |
| Hive | hive log4j | `hive.querylog.location` | 否 | -- |
| Flink SQL | task manager log | -- | -- | -- |
| Databricks | event log + Query History UI | `system.query.history` | 是 | GA |
| Teradata | -- | DBQL (`DBC.DBQLogTbl`) | 视表 | 早期 |
| Greenplum | `log_min_duration_statement` | `gp_toolkit` + 继承 PG | 否 | 继承 PG |
| CockroachDB | `sql.log.slow_query.latency_threshold` | `crdb_internal.statement_statistics` | 否 / 是(stats) | 19.2+ |
| TiDB | tidb-slow.log | `INFORMATION_SCHEMA.SLOW_QUERY` + Statements Summary | 是 | 1.0+ |
| OceanBase | observer.log + sql_audit | `GV$OB_SQL_AUDIT` | 是 | 早期 |
| YugabyteDB | `log_min_duration_statement` | `pg_stat_statements` | 否 | 继承 PG |
| SingleStore | -- | `INFORMATION_SCHEMA.MV_QUERIES` | 是 | 7.x+ |
| Vertica | -- | `QUERY_REQUESTS` / `EXECUTION_ENGINE_PROFILES` | 是 | 早期 |
| Impala | impalad log | `query_log_size` 内存环 + Web UI | 是 | 早期 |
| StarRocks | fe.audit.log | `information_schema.loads` 等 | 是(audit) | 1.x+ |
| Doris | fe.audit.log | `__internal_schema.audit_log` | 是(audit) | 早期 |
| MonetDB | merovingian.log | -- | -- | -- |
| CrateDB | -- | `sys.jobs_log` | 是(有限) | 早期 |
| TimescaleDB | 继承 PG | 继承 PG + `timescaledb_information` | 否 | 继承 PG |
| QuestDB | server log | -- | -- | -- |
| Exasol | -- | `EXA_DBA_PROFILE_*` / `EXA_USER_AUDIT_SQL` | 否 | 早期 |
| SAP HANA | -- | `M_EXPENSIVE_STATEMENTS` / `M_SQL_PLAN_CACHE` | 是(PC) | 早期 |
| Informix | online.log + sqexplain | `sysmaster:sysscan` 等 | 否 | 早期 |
| Firebird | firebird.log + trace API | `MON$STATEMENTS` | 否 | 2.5+ |
| H2 | trace file | -- | 否 | -- |
| HSQLDB | -- | -- | -- | 不支持 |
| Derby | derby.log | -- | -- | 不支持 |
| Amazon Athena | CloudWatch Logs | `INFORMATION_SCHEMA.QUERY_HISTORY`(预览) | 是(CW) | GA |
| Azure Synapse | -- | `sys.dm_pdw_exec_requests` | 是 | GA |
| Google Spanner | -- | `SPANNER_SYS.QUERY_STATS_TOP_*` | 是 | GA |
| Materialize | -- | `mz_internal.mz_recent_activity_log` | 是 | GA |
| RisingWave | -- | `rw_catalog.rw_query_log`(有限) | -- | 早期 |
| InfluxDB (SQL) | -- | -- | -- | 不支持 |
| Databend | -- | `system.query_log` | 是 | GA |
| Yellowbrick | -- | `sys.log_query` | 是 | GA |
| Firebolt | -- | `information_schema.query_history` | 是 | GA |

> 统计：约 42 个引擎提供某种形式的慢/全量查询历史；其中约 22 个支持文件日志，约 38 个提供 SQL 可查询的系统视图。**云原生数据仓库几乎全部不提供文件日志**——只暴露视图，避免暴露底层文件系统。

### 2. 阈值配置（long_query_time / min_duration_statement）

| 引擎 | 配置项 | 默认值 | 单位 | 动态生效 |
|------|--------|--------|------|---------|
| PostgreSQL | `log_min_duration_statement` | -1 (关闭) | 毫秒 | SIGHUP |
| MySQL | `long_query_time` | 10 | 秒 (浮点) | 是 (会话/全局) |
| MariaDB | `long_query_time` | 10 | 秒 | 是 |
| Oracle | AWR 自动按 elapsed_time 排名 | top SQL | -- | DBMS_WORKLOAD_REPOSITORY |
| SQL Server (QS) | `QUERY_CAPTURE_MODE = AUTO/ALL/CUSTOM` | AUTO | -- | ALTER DATABASE |
| DB2 | `mon_act_metrics` + WLM 阈值 | -- | -- | DB2 配置 |
| Snowflake | -- (无阈值，全部记录) | 14 天 | -- | -- |
| BigQuery | -- (全部记录) | 180 天 | -- | -- |
| Redshift | `WLM query_execution_time` (审计) | -- | 秒 | 参数组 |
| ClickHouse | `log_queries_min_query_duration_ms` | 0 | 毫秒 | 是 |
| TiDB | `tidb_slow_log_threshold` | 300 | 毫秒 | SET GLOBAL |
| OceanBase | `trace_log_slow_query_watermark` | 100 | 毫秒 | 是 |
| CockroachDB | `sql.log.slow_query.latency_threshold` | 0 (关闭) | 毫秒/秒 | SET CLUSTER SETTING |
| Vertica | `EXECUTION_ENGINE_PROFILES` 始终 | -- | -- | -- |
| StarRocks | `audit_log_modules = slow_query` + `qe_slow_log_ms` | 5000 | 毫秒 | 是 |
| Doris | `qe_slow_log_ms` | 5000 | 毫秒 | 是 |
| SAP HANA | `expensive_statements_threshold` | 1000000 | 微秒 | 是 |
| YugabyteDB | `log_min_duration_statement` | -1 | 毫秒 | 继承 PG |
| Greenplum | `log_min_duration_statement` | -1 | 毫秒 | 继承 PG |
| TimescaleDB | 继承 PG | -1 | 毫秒 | -- |
| Databricks | -- (Query History 全部) | -- | -- | -- |
| Databend | `log.query.on = true` | 全部 | -- | 配置文件 |
| Yellowbrick | `slow_query_log_threshold` | -- | 毫秒 | 是 |

> PostgreSQL 把 `log_min_duration_statement` 设为 0 表示**记录所有 SQL**，设为 -1 表示关闭——这与 ClickHouse 的 0=记录所有相反，是常见的运维陷阱。

### 3. 采样率与限流

慢查询日志的一个长期痛点：在高 QPS 系统下，一旦阈值设得过低，日志体积爆炸、磁盘 IO 反过来拖慢实例。各厂商的解决方案：

| 引擎 | 采样能力 | 配置项 |
|------|---------|--------|
| PostgreSQL | `log_statement_sample_rate` (15+) | 0.0 ~ 1.0 |
| PostgreSQL | `log_min_duration_sample` (13+) | 单独阈值 + 采样率 |
| PostgreSQL | `log_transaction_sample_rate` | 事务级采样 |
| MySQL | `log_slow_rate_limit` (Percona/Aurora 扩展) | 1/N |
| MariaDB | `log_slow_rate_limit` | 1/N |
| Oracle | AWR `INTERVAL` + `TOPNSQL` | 默认每小时一个快照 |
| SQL Server (QS) | `QUERY_CAPTURE_MODE = CUSTOM` + 阈值 | 执行次数/CPU 阈值 |
| ClickHouse | `log_queries_probability` | 0.0 ~ 1.0 |
| TiDB | -- (按阈值过滤，无采样) | -- |
| CockroachDB | `sql.metrics.statement_details.threshold` | 直方图采样 |
| Datadog/APM (外挂) | 任意 | 通常 1% ~ 10% |

> PostgreSQL 13 起的 `log_min_duration_sample + log_statement_sample_rate` 组合是目前**最优雅的设计**：阈值之上全记录，阈值之下采样，避免全量带来的日志洪水。

### 4. 查询归一化（Digest / Fingerprint）

只看单条慢查询是不够的，**模板级**聚合才是真正的金矿。归一化把字面量替换成占位符（如 `?` 或 `$1`），让 `WHERE id=1` 和 `WHERE id=2` 算同一个模板。

| 引擎 | 归一化机制 | 表示形式 |
|------|-----------|---------|
| PostgreSQL | `pg_stat_statements` 计算 `queryid` | 64 位 hash + 标准化文本 |
| MySQL | Performance Schema `DIGEST` / `DIGEST_TEXT` | MD5 hash + 标准化 |
| Oracle | `SQL_ID` (固定哈希) | 13 字符 base32 hash |
| SQL Server | `query_hash` + `query_plan_hash` | 8 字节二进制 |
| SQL Server (QS) | `query_id` (持久化) | bigint |
| DB2 | `STMTID` + `EXECUTABLE_ID` | bigint |
| Snowflake | `QUERY_PARAMETERIZED_HASH` | hash |
| BigQuery | `query_info.query_hashes.normalized_literals` | hash |
| Redshift | `query_hash` (SYS_QUERY_HISTORY) | hash |
| ClickHouse | `normalized_query_hash` | UInt64 |
| TiDB | `Digest` 列 | 64 字符 hex |
| OceanBase | `SQL_ID` | hash |
| CockroachDB | `fingerprint_id` | hash |
| Vertica | `DC_REQUESTS_ISSUED.REQUEST_ID` + 文本 | 视图 |
| StarRocks | -- (字符串聚合) | -- |
| SAP HANA | `STATEMENT_HASH` | hash |

> 几乎所有现代 OLAP/HTAP 都内置了 query digest——这与 10 年前需要靠 `pt-query-digest` 等外部工具的状况已经完全不同。**digest 是慢查询日志能升级为"模板分析"的关键基础设施**。

### 5. 执行计划捕获

| 引擎 | 计划捕获方式 | 是否随慢日志输出 |
|------|------------|----------------|
| PostgreSQL | `auto_explain` 模块 | 是（独立 GUC） |
| MySQL | -- | 否（需要事后 EXPLAIN） |
| Oracle | AWR baselines + SQL Plan Management | 是 |
| SQL Server | Query Store 自动捕获 | 是（query_plan XML） |
| DB2 | `explain_mode = EXPLAIN` | 是 |
| Snowflake | `EXPLAIN_JSON` 列 | 是 |
| BigQuery | `query_info.statementType` + 阶段树 | 是 |
| Redshift | `STL_EXPLAIN` 关联 | 是 |
| ClickHouse | `query_log.ProfileEvents` | 部分（事件而非树） |
| TiDB | slow log 中 `Plan_digest` + 完整计划 | 是 |
| OceanBase | `GV$OB_PLAN_CACHE_PLAN_EXPLAIN` | 是 |
| CockroachDB | `crdb_internal.node_statement_statistics` | 是（计划样本） |
| Vertica | `QUERY_PLAN_PROFILES` | 是 |
| StarRocks | `__internal_schema.query_history` | 是 |
| SAP HANA | `M_SQL_PLAN_CACHE` + plan trace | 是 |

> PostgreSQL 的 `auto_explain` 是少数与慢查询日志解耦的设计——你可以单独打开 `auto_explain.log_min_duration` 让计划写入 server log，而 `pg_stat_statements` 只负责统计。这种"正交"哲学在调优时反而最灵活。

### 6. 日志目的地（File / Table / Syslog / Trace）

| 引擎 | 文件 | 表 | syslog | trace event | OpenTelemetry/外推 |
|------|------|-----|--------|-------------|----|
| PostgreSQL | 是 | -- (扩展) | 是 | -- | 通过 `log_destination` |
| MySQL | 是 | `mysql.slow_log` 表 | -- | Performance Schema | 是（PS Consumer） |
| MariaDB | 是 | `mysql.slow_log` | -- | PS | 是 |
| Oracle | -- | AWR 表 | -- | SQL Trace (10046) | 是 |
| SQL Server | -- | Query Store 表 | -- | Extended Events (.xel) | 是 |
| DB2 | event 文件 | `MON_GET_*` | -- | event monitor | -- |
| ClickHouse | -- | `system.query_log` | -- | Trace logs | 是 (OTLP exporter) |
| TiDB | tidb-slow.log | `INFORMATION_SCHEMA.SLOW_QUERY` | -- | -- | 是 (Prometheus) |
| CockroachDB | 是 (cockroach-sql-slow) | `crdb_internal.statement_statistics` | -- | -- | 是 |
| OceanBase | observer.log | `GV$OB_SQL_AUDIT` | -- | -- | 是 |
| Snowflake | -- | `ACCOUNT_USAGE.QUERY_HISTORY` | -- | -- | 通过 Reader API |

> MySQL 是少数同时支持"文件 + 表 + Performance Schema"三种目的地的引擎：`log_output = FILE,TABLE` 可以双写。表形式查询方便但写入开销更大；高 QPS 生产环境通常仍用文件 + 异步采集。

### 7. 未执行语句的捕获（解析/绑定阶段失败）

慢查询日志容易遗漏的一类问题：**SQL 还没执行到执行阶段就失败**（语法错误、绑定变量类型不匹配、权限拒绝），却消耗了大量解析时间。

| 引擎 | 解析失败记录 | 绑定/准备失败 | 配置项 |
|------|--------|--------|--------|
| PostgreSQL | `log_statement = 'all'` | 是（同上） | + `log_parser_stats` |
| MySQL | general_log | -- | `general_log = ON` |
| Oracle | error stack trace | 是 | `EVENT='10046 trace'` |
| SQL Server | XEvents `error_reported` | 是 | XE 会话 |
| TiDB | `tidb_slow_log` 包含解析时间 | 是 | -- |
| OceanBase | sql_audit | 是 | -- |
| ClickHouse | `system.query_log` 中 `type='ExceptionBeforeStart'` | 是 | `log_queries=1` |
| CockroachDB | `sql.log.slow_query.experimental_full_table_scans.enabled` | 部分 | 多个开关 |

> ClickHouse 的设计相对独特：`system.query_log` 把每条查询的生命周期分成 `QueryStart`、`QueryFinish`、`ExceptionBeforeStart`、`ExceptionWhileProcessing` 四种事件类型，**任何阶段失败都会产生一行**。这对于诊断"语句根本没跑起来"的问题非常友好。

### 8. 关键厂商锚点能力

- **PostgreSQL `log_min_duration_statement`**：8.x 起的 GUC，单位毫秒，-1 关闭，0 全开。配合 `log_min_duration_sample` (13+) 和 `log_statement_sample_rate` (15+)。
- **MySQL `long_query_time`**：3.23 (2001) 引入的 `slow_query_log`，5.1 引入 `log_queries_not_using_indexes`，5.5 引入 Performance Schema。`long_query_time` 支持 **微秒粒度浮点**。
- **`performance_schema.events_statements_summary_by_digest`**：MySQL 5.6 起按 digest 聚合，含 `COUNT_STAR`、`SUM_TIMER_WAIT`、`SUM_ROWS_EXAMINED` 等。
- **SQL Server Query Store**：2016 起内置；2017 引入 wait stats；2022 引入 Query Store hints。捕获模式 `AUTO/ALL/CUSTOM/NONE`。
- **Oracle AWR**：10g 起，默认每小时快照；保留 8 天。`DBA_HIST_SQLSTAT` 是慢 SQL 的核心历史视图。
- **Oracle ASH**：`V$ACTIVE_SESSION_HISTORY` 每秒采样一次活跃会话状态；`DBA_HIST_ACTIVE_SESS_HISTORY` 是 ASH 的 1/10 采样持久化。

## 各引擎深入

### PostgreSQL

PostgreSQL 没有"慢查询日志"这个一体化概念，而是把功能切成几个**正交的模块**：

```sql
-- 1) server log: 文本行
ALTER SYSTEM SET log_min_duration_statement = 200;   -- 单位 ms，0=全部，-1=关闭
ALTER SYSTEM SET log_min_duration_sample    = 50;     -- 50ms 以上开始采样
ALTER SYSTEM SET log_statement_sample_rate  = 0.01;   -- 50~200ms 区间采 1%
ALTER SYSTEM SET log_transaction_sample_rate = 0;
SELECT pg_reload_conf();
```

- 200ms 以上全部记录
- 50~200ms 之间按 1% 采样
- 50ms 以下不记录

```sql
-- 2) auto_explain: 计划随日志输出
LOAD 'auto_explain';
SET auto_explain.log_min_duration = '200ms';
SET auto_explain.log_analyze       = on;
SET auto_explain.log_buffers       = on;
SET auto_explain.log_format        = 'json';
SET auto_explain.log_nested_statements = on;
```

```sql
-- 3) pg_stat_statements: 模板级聚合
CREATE EXTENSION pg_stat_statements;

SELECT queryid,
       calls,
       total_exec_time,
       mean_exec_time,
       rows,
       100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0)
           AS hit_pct,
       query
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 20;
```

`pg_stat_statements` 自 PostgreSQL **8.4 (2009)** 起作为可加载扩展存在，存储在共享内存的固定大小桶中（`pg_stat_statements.max` 默认 5000）。归一化算法：把字面量与 `IN (...)` 列表替换成占位符，但保留结构，再用 SipHash 计算 `queryid`。

**注意陷阱**：`pg_stat_statements` 不持久化——重启后归零；要长期跟踪必须定期 `INSERT INTO history SELECT * FROM pg_stat_statements` 或者使用 `pg_stat_statements_reset()` 后差值采集。商业生态中的 PgWatch、pganalyze、pgbadger 等都基于此扩展。

### MySQL

MySQL 同时维护两套机制：**slow_query_log**（文件 / 表）和 **Performance Schema**（系统视图）。两者目标不同：前者面向 DBA 抓现场，后者面向监控系统采集模板级指标。

```sql
-- 1) slow query log
SET GLOBAL slow_query_log = ON;
SET GLOBAL slow_query_log_file = '/var/log/mysql/mysql-slow.log';
SET GLOBAL long_query_time = 0.5;                 -- 500ms，浮点
SET GLOBAL log_queries_not_using_indexes = ON;    -- 5.1+
SET GLOBAL log_slow_admin_statements = ON;
SET GLOBAL log_slow_replica_statements = ON;
SET GLOBAL log_output = 'FILE,TABLE';             -- 双写
```

```sql
-- 2) 表形式的慢日志
SELECT start_time, query_time, lock_time, rows_sent, rows_examined,
       LEFT(sql_text, 80) AS sql_text
FROM mysql.slow_log
ORDER BY query_time DESC
LIMIT 20;
```

```sql
-- 3) Performance Schema digest 聚合
SELECT DIGEST,
       DIGEST_TEXT,
       COUNT_STAR,
       ROUND(AVG_TIMER_WAIT/1e9, 2) AS avg_us,
       SUM_ROWS_EXAMINED,
       SUM_NO_INDEX_USED,
       FIRST_SEEN,
       LAST_SEEN
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 20;
```

`events_statements_summary_by_digest` 自 5.6 起按 digest 聚合，每条 SQL 的字面量被替换成 `?`，但保留运算符与函数调用结构。MySQL 8.0 又引入了 `events_statements_histogram_by_digest`，给出每个模板的延迟直方图——这对于发现"99 分位异常"比单纯的均值更有用。

`pt-query-digest`（Percona Toolkit）是 MySQL 生态中事实标准的慢日志解析器，把文件日志按模板归一化并输出 P50/P95/P99。Aurora MySQL 和 PolarDB 在云端提供了类似的"性能洞察"控制台。

### Oracle

Oracle 的方式与所有其他厂商都不同：**没有"慢查询日志"概念**，而是用 AWR/ASH 定期采样的方式覆盖全部 SQL 性能监控。

```sql
-- 1) AWR 历史 SQL 统计
SELECT sql_id,
       executions_delta,
       elapsed_time_delta / 1e6 AS elapsed_sec,
       cpu_time_delta    / 1e6 AS cpu_sec,
       buffer_gets_delta,
       disk_reads_delta,
       rows_processed_delta
FROM dba_hist_sqlstat
WHERE snap_id BETWEEN 12000 AND 12005
ORDER BY elapsed_time_delta DESC
FETCH FIRST 20 ROWS ONLY;

-- 2) ASH 实时活跃会话
SELECT TO_CHAR(sample_time, 'HH24:MI:SS') t,
       session_state, event, sql_id, sql_plan_hash_value, blocking_session
FROM v$active_session_history
WHERE sample_time > SYSDATE - INTERVAL '10' MINUTE;

-- 3) 生成 AWR 报告
SELECT * FROM TABLE(dbms_workload_repository.awr_report_text(
    l_dbid     => (SELECT dbid FROM v$database),
    l_inst_num => 1,
    l_bid      => 12000,
    l_eid      => 12005));
```

- **AWR**（Automatic Workload Repository，10g+）：默认每小时一次快照，保留 8 天，存储在 `SYSAUX` 表空间。`DBA_HIST_SQLSTAT` 是慢 SQL 历史视图。
- **ASH**（Active Session History）：每秒对 `V$SESSION` 采样一次活跃会话；`V$ACTIVE_SESSION_HISTORY` 保存最近 30 分钟，`DBA_HIST_ACTIVE_SESS_HISTORY` 持久化 ASH 的 1/10 采样。
- **AWR 报告**：HTML/文本格式，DBA 最常用的诊断工具，`@?/rdbms/admin/awrrpt.sql`。
- 注意：AWR/ASH 的使用需要 **Diagnostic & Tuning Pack 许可证**——在严格的 license 审计场景下，部分客户会改用免费的 Statspack（9i 起）。

### SQL Server (Query Store + Extended Events)

```sql
-- 1) 启用 Query Store
ALTER DATABASE MyDB SET QUERY_STORE = ON
(
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 60,
    MAX_STORAGE_SIZE_MB = 1024,
    QUERY_CAPTURE_MODE = AUTO,
    SIZE_BASED_CLEANUP_MODE = AUTO
);

-- 2) Top 资源消耗查询
SELECT TOP 20
    qt.query_sql_text,
    qs.query_id,
    rs.avg_duration / 1000.0 AS avg_ms,
    rs.count_executions,
    rs.avg_logical_io_reads,
    p.query_plan
FROM sys.query_store_query_text qt
JOIN sys.query_store_query        q  ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan         p  ON q.query_id        = p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id        = rs.plan_id
ORDER BY rs.avg_duration DESC;
```

Query Store 自 **SQL Server 2016** 起内置，2022 版本进一步引入 Query Store hints（不修改原 SQL 即可强制使用某个 plan）。在 Query Store 之前，DBA 依赖 SQL Trace、Profiler 和 Extended Events，但这些都不持久化、不归一化、对生产开销大。Query Store 本质上是**把 Oracle AWR 的核心思想搬到 SQL Server**。

Extended Events 仍然是补充：用来抓取 Query Store 不覆盖的事件（锁等待、错误、登录失败等）。`system_health` XE 会话默认开启。

### DB2

```sql
-- MON_GET_PKG_CACHE_STMT: 包缓存中的语句统计
SELECT EXECUTABLE_ID,
       NUM_EXECUTIONS,
       TOTAL_CPU_TIME / NUM_EXECUTIONS AS avg_cpu,
       TOTAL_ACT_TIME / NUM_EXECUTIONS AS avg_act,
       SUBSTR(STMT_TEXT, 1, 100) AS stmt
FROM TABLE(MON_GET_PKG_CACHE_STMT(NULL, NULL, NULL, -2)) AS t
ORDER BY TOTAL_CPU_TIME DESC
FETCH FIRST 20 ROWS ONLY;
```

DB2 9.7+ 引入 `MON_GET_*` 系列表函数，取代旧的快照监视器（snapshot monitor）。所有运行时统计都在内存中维护，重启后归零；要长期保留需要 WLM 事件监控写到磁盘。

### Snowflake

Snowflake 完全不让用户配置任何"慢查询日志"——所有查询都默认进入 `QUERY_HISTORY`，保留 14 天（INFORMATION_SCHEMA）或 365 天（ACCOUNT_USAGE）。

```sql
SELECT query_id,
       user_name,
       warehouse_name,
       execution_status,
       total_elapsed_time / 1000 AS elapsed_sec,
       compilation_time   / 1000 AS compile_sec,
       queued_overload_time / 1000 AS queue_sec,
       bytes_scanned,
       partitions_scanned,
       partitions_total,
       query_parameterized_hash
FROM snowflake.account_usage.query_history
WHERE start_time > DATEADD(hour, -1, CURRENT_TIMESTAMP())
  AND total_elapsed_time > 5000
ORDER BY total_elapsed_time DESC
LIMIT 50;
```

`QUERY_PARAMETERIZED_HASH` 自 2023 起加入，让模板级聚合不需要外部归一化。`SNOWFLAKE.ACCOUNT_USAGE` schema 有 ~12 小时的延迟，`INFORMATION_SCHEMA` 是实时的但只有 14 天。

### BigQuery

```sql
SELECT job_id,
       creation_time,
       user_email,
       statement_type,
       TIMESTAMP_DIFF(end_time, start_time, MILLISECOND) AS duration_ms,
       total_slot_ms,
       total_bytes_processed,
       total_bytes_billed,
       query_info.query_hashes.normalized_literals AS template_hash
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND state = 'DONE'
  AND statement_type = 'SELECT'
ORDER BY duration_ms DESC
LIMIT 50;
```

BigQuery 的 `INFORMATION_SCHEMA.JOBS_BY_*` 视图是按区域而非按数据集组织的；`query_info.query_hashes.normalized_literals` 是 2023 引入的官方 fingerprint，把字面量替换后再哈希。默认保留 180 天，无需用户配置阈值。

### Redshift

```sql
-- 老版本: STL/SVL 系统表
SELECT query, userid, starttime, endtime,
       DATEDIFF(ms, starttime, endtime) AS duration_ms,
       SUBSTRING(querytxt, 1, 100) AS qt
FROM stl_query
WHERE starttime > GETDATE() - INTERVAL '1 hour'
ORDER BY duration_ms DESC
LIMIT 20;

-- 新版本 (2023+): SYS 视图
SELECT query_id, user_id, query_type, status,
       elapsed_time / 1000000 AS elapsed_sec,
       execution_time / 1000000 AS exec_sec,
       queue_time / 1000000 AS queue_sec,
       query_text
FROM sys_query_history
WHERE start_time > GETDATE() - INTERVAL '1 hour'
ORDER BY elapsed_time DESC
LIMIT 20;
```

Redshift 长期使用 STL（系统日志，7 天保留）、STV（系统瞬态）、SVL/SVV（系统视图）三套体系。2023 起逐步用 `SYS_*` 视图统一。`SVL_QUERY_REPORT` 给出每个步骤的细粒度统计，是诊断单条慢查询执行计划的关键。

### ClickHouse

ClickHouse 是少数把慢日志做成"系统表 + 始终开启"的引擎：

```sql
-- system.query_log 默认开启，按天分区
SELECT event_time,
       query_duration_ms,
       read_rows,
       memory_usage,
       normalized_query_hash,
       query
FROM system.query_log
WHERE event_date = today()
  AND type = 'QueryFinish'
  AND query_duration_ms > 1000
ORDER BY query_duration_ms DESC
LIMIT 50;
```

```xml
<!-- config.xml 调整 -->
<query_log>
    <database>system</database>
    <table>query_log</table>
    <partition_by>toYYYYMM(event_date)</partition_by>
    <flush_interval_milliseconds>7500</flush_interval_milliseconds>
    <max_size_rows>1048576</max_size_rows>
</query_log>
```

`system.query_log` 是一张普通的 `MergeTree` 表，可以 JOIN、聚合、TTL 自动清理。`normalized_query_hash` 自 21.x 起内置。生产建议：把 `query_log` 配置一个长 TTL（如 30 天）+ 远程复制到独立分析实例，不要污染业务集群。

### Teradata DBQL

```sql
-- DBC.DBQLogTbl: 查询日志主表
BEGIN QUERY LOGGING WITH SQL ON ALL;       -- 启用所有用户
BEGIN QUERY LOGGING WITH OBJECTS ON ALL;
BEGIN QUERY LOGGING WITH STEPINFO ON ALL;

SELECT QueryID, UserName,
       (FirstStepTime - StartTime) HOUR(4) TO SECOND AS parse_time,
       (FirstRespTime - StartTime) HOUR(4) TO SECOND AS total_time,
       AMPCPUTime, TotalIOCount,
       SubStr(QueryText, 1, 100)
FROM DBC.DBQLogTbl
WHERE LogDate = CURRENT_DATE
  AND TotalIOCount > 100000
ORDER BY AMPCPUTime DESC;
```

DBQL（Database Query Log）是 Teradata 自 V2R5 起的核心审计与性能日志框架。可以按用户、应用、查询类型分别配置，支持 STEPINFO（逐步执行统计）、OBJECTS（涉及对象）、SQL（完整 SQL 文本）等多种粒度。

### TiDB

TiDB 最大的特点是**同时支持 PostgreSQL 风格的视图 + MySQL 兼容的文本日志**：

```sql
SET GLOBAL tidb_slow_log_threshold = 100;       -- ms
SET GLOBAL tidb_enable_stmt_summary = 1;
SET GLOBAL tidb_stmt_summary_refresh_interval = 1800;
SET GLOBAL tidb_stmt_summary_history_size = 24;

-- 1) 文件日志（兼容 pt-query-digest）
-- /var/lib/tidb/log/tidb-slow.log

-- 2) SLOW_QUERY 表（直接 SQL 查询文件）
SELECT Time, Query_time, DB, Plan_digest, LEFT(Query, 80)
FROM information_schema.slow_query
WHERE Time > NOW() - INTERVAL 1 HOUR
ORDER BY Query_time DESC
LIMIT 20;

-- 3) Statements Summary（模板级）
SELECT digest_text,
       exec_count,
       avg_latency,
       max_latency,
       avg_mem,
       sum_cop_task_num
FROM information_schema.statements_summary
ORDER BY sum_latency DESC
LIMIT 20;
```

TiDB 的 `INFORMATION_SCHEMA.SLOW_QUERY` 表实际上是直接 parse 文件，所以即使节点重启也不丢失。`STATEMENTS_SUMMARY_HISTORY` 还保存过去 24 小时的快照，方便做趋势分析。`TIDB_INDEX_USAGE`（v7.5+）则跟踪每个索引被访问的次数，用来发现"无效索引"。

## pg_stat_statements 深入

pg_stat_statements 是 PostgreSQL 性能分析的事实基础设施。理解它的实现细节，能避免许多常见的运维误解：

### 1. 数据结构与归一化

- **共享内存哈希表**：默认 `pg_stat_statements.max = 5000` 个槽位；按 `(userid, dbid, queryid)` 三元组定位。满了之后 LRU 淘汰。
- **queryid 计算**：基于解析后的 query tree（不是文本！）的 SipHash24。这意味着 `SELECT 1` 与 `select 1` 与 `/* hint */ SELECT 1` 拥有相同的 queryid——但只有当 `pg_stat_statements.track_utility = on` 时才统计 DDL。
- **归一化文本**：`pg_stat_statements` 会重写 SQL 把字面量替换成 `$1, $2, ...`（注意：与 prepared statement 占位符同形式）；列表 `IN (1,2,3,4,5)` 在 14+ 起会归并成 `IN ($1)` 而非 `IN ($1,$2,$3,$4,$5)`，避免相同模板因 IN 长度不同被拆成多个 entry。

### 2. 关键列与采集方法

```sql
SELECT queryid, calls, rows,
       total_exec_time, mean_exec_time, stddev_exec_time,
       min_exec_time, max_exec_time,
       shared_blks_hit, shared_blks_read, shared_blks_dirtied, shared_blks_written,
       local_blks_hit, local_blks_read,
       temp_blks_read, temp_blks_written,
       blk_read_time, blk_write_time,         -- 需要 track_io_timing=on
       wal_records, wal_fpi, wal_bytes,        -- 13+
       jit_functions, jit_generation_time,     -- 15+
       toplevel,                                -- 14+
       plans, total_plan_time, mean_plan_time  -- 13+ 区分 plan/exec
FROM pg_stat_statements;
```

13+ 把 `total_time` 拆成 `total_plan_time + total_exec_time`——对于使用动态参数的应用尤为重要，可以单独看到"是否在反复重新规划"。

### 3. 采集与差值

`pg_stat_statements` **不是时序数据库**：每条记录是从重置以来的累积值。监控系统的标准做法是：

```python
# 伪代码
prev = fetch_pg_stat_statements()
sleep(60)
curr = fetch_pg_stat_statements()
for row in curr:
    delta_calls = row.calls - prev.get(row.queryid, 0).calls
    if delta_calls > 0:
        report(queryid=row.queryid,
               calls_per_sec=delta_calls/60,
               avg_ms=(row.total_exec_time - prev_total) / delta_calls)
```

注意 queryid 在重置或重启后会重算（如果 query tree 有微小变化），所以差值要做 NULL 防御。

### 4. 性能开销

`pg_stat_statements` 在 OLTP 场景下的开销通常 < 5%，主要来自共享内存 spinlock 与 SipHash 计算。pgbench 实测在 32 核机器上 100k QPS 下额外开销约 3~7%。生产环境普遍开启。

### 5. 已知限制

- 不持久化（重启清零，需要外部归档）
- 没有 P95/P99（只有均值/方差/min/max）
- 没有执行计划（要配合 `auto_explain`）
- 没有按时间窗口的趋势（要外部差值）
- 不区分会话（无法定位"哪个 app/host"）

商业生态如 pganalyze、pgwatch2、percona-pmm、Datadog DBM、Aiven 的 pg_stat_monitor（对 pgss 增强：加 P99、桶时间、客户端 IP）都是基于这些限制衍生出来的。

## Query Digest / 归一化跨厂商对比

| 维度 | PostgreSQL | MySQL | Oracle | SQL Server | ClickHouse | TiDB | Snowflake |
|------|-----------|-------|--------|------------|------------|------|-----------|
| 归一化输入 | parse tree | tokens | parse tree | parse tree | parse tree | parse tree | parse tree |
| Hash 算法 | SipHash24 | MD5 | 自有 | MurmurHash3 变种 | SipHash | xxHash | 内部 |
| ID 长度 | 8 字节 | 32 字符 | 13 字符 base32 | 8 字节 | 8 字节 | 32 字符 hex | 内部 hash |
| IN 列表归并 | 14+ 起合并 | 否 | 否 | 否 | 是 | 部分 | 是 |
| 大小写敏感 | 否 | 否 | 否 | 否 | 否 | 否 | 否 |
| 注释保留 | 否 | 否 | 否 | 否 | 否 | 否 | 否 |
| Hint 作为 ID 一部分 | 否 | 否 | 是 (outline) | 否 | 否 | 否 | 否 |
| 跨实例稳定 | 否（依赖 OID） | 是 | 是 | 否 | 是 | 是 | 是 |
| 模板文本可恢复 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |

> **跨实例稳定性**是个大坑：PostgreSQL 的 queryid 依赖 catalog OID，迁移到新实例后同一条 SQL 的 queryid 会变；这就是为什么 pganalyze 等工具需要额外维护一个"逻辑指纹"。Oracle 的 SQL_ID 则是纯文本派生，跨实例稳定。

## 关键发现

### 1. SQL 标准在性能监控领域完全缺席

慢查询日志是数据库管理中最古老、最普遍的需求之一，但 SQL 标准从未涉足。这导致每家厂商都自己设计了一套词汇表（`slow_log` / `query_store` / `query_history` / `query_log` / `dbqlogtbl` / `mon_get_*` / `awr` / `ash` / `dba_hist_*` / `events_statements_summary_by_digest` ...），互不兼容。即使是同一个底层概念（"按归一化模板聚合统计"），各厂商的表名、列名、单位（毫秒/微秒/纳秒/秒）都不同。

### 2. "文件 vs 表"的分裂逐渐倾向"表"

老一代引擎（MySQL 3.23、PostgreSQL 8.x、Oracle 9i）默认提供文件日志；新一代云数据仓库（Snowflake、BigQuery、Redshift、Databricks）**完全不提供文件日志**——只通过系统视图暴露。原因：

- 云原生没有"shell 登录主机"的概念
- 对象存储日志成本高且查询慢
- 视图天然支持 SQL 过滤、聚合、Join
- 多租户隔离更容易

但表形式有一个老问题：**写入慢日志本身的代价**——MySQL `log_output = TABLE` 在高 QPS 下会成为瓶颈，因此生产中通常仍然是 FILE。云数据仓库通过"异步落盘 + 后台聚合"避开了这个问题。

### 3. 阈值之上全记录 + 阈值之下采样：PostgreSQL 13+ 模式胜出

PostgreSQL 13 引入的 `log_min_duration_sample + log_statement_sample_rate` 双阈值采样模式是当前最优雅的设计：

- 200ms 以上（明显有问题的）100% 记录
- 50~200ms（可能有问题的）按 1% 采样
- 50ms 以下（正常的）完全不记录

这避免了"全记录撑爆磁盘"和"阈值过高漏掉小问题"的两难。MySQL 至今没有原生采样支持，需要依赖 Percona 的 `log_slow_rate_limit` 补丁。

### 4. Digest / Fingerprint 已成标配

10 年前 `pt-query-digest` 是事实标准的外挂工具；今天 PostgreSQL（pgss）、MySQL（PS）、Oracle（SQL_ID）、SQL Server（Query Store）、Snowflake（QUERY_PARAMETERIZED_HASH）、BigQuery（query_hashes.normalized_literals）、ClickHouse（normalized_query_hash）、TiDB（Digest）几乎全部内置。这是慢日志从"原始日志"升级为"模板分析"的关键。

但**算法和粒度不统一**：MySQL 的 IN 列表不归并（导致同一模板的不同 IN 长度被拆成多条）、PostgreSQL 14 才修复、Oracle 默认不归并 hint。跨厂商迁移工具（Liquibase、Flyway、原生云迁移服务）通常不携带 digest 历史，迁移后的"基线"必须重建。

### 5. 三大厂商的性能监控哲学差异

- **MySQL**：DBA 主动配置 + 多套并行（slow_log + general_log + Performance Schema + sys schema）。哲学：开箱不开，DBA 按需开启。
- **PostgreSQL**：扩展模块化 + 正交。哲学：把每个能力做成独立 GUC/扩展，让运维自由组合（log_min_duration_statement + auto_explain + pg_stat_statements + pg_stat_kcache + pg_qualstats）。
- **Oracle**：自动持续采样（AWR 1 小时快照 + ASH 每秒快照） + 报告驱动。哲学：DBA 不需要配置，平台自动捕获，问题发生后翻报告。

云数据仓库（Snowflake/BigQuery/Databricks）继承的是 Oracle 哲学：完全不配置，全部记录，按时间查询。差异是它们用对象存储而不是 `SYSAUX` 表空间。

### 6. 计划捕获仍然是"慢查询日志的盲区"

绝大多数引擎的慢查询日志只记录"最终延迟 + 文本 SQL"，**不包含执行计划**——而执行计划往往才是回答"为什么慢"的关键。三种解决方案：

1. **PostgreSQL `auto_explain`**：与日志解耦，独立模块，可以单独打开
2. **SQL Server Query Store**：内置，每个 query_id 关联多个 plan_id，自动捕获 plan 切换
3. **Oracle SQL Plan Baselines**：AWR 内嵌，能跨快照对比 plan 演进

MySQL 至今没有内置的"慢日志带计划"能力——必须事后 EXPLAIN，但参数早已变化。这是 MySQL 性能诊断的长期短板。

### 7. ClickHouse 的"始终开启"哲学

ClickHouse 是少数把 `system.query_log` 默认设为开启的引擎，并且把它做成普通 `MergeTree` 表——可 JOIN、可聚合、可 TTL 自动清理。这是把"日志"和"查询"统一到同一层的彻底设计：你不需要任何外部工具就能做完整的查询分析。其他引擎把这种能力外包给监控平台（Datadog、Prometheus、pganalyze），ClickHouse 把它内化到核心。

### 8. HTAP/分布式数据库的额外维度

TiDB、CockroachDB、OceanBase、YugabyteDB 等分布式系统的慢查询日志，必须额外回答"哪个节点慢、为什么慢、跨节点协调耗时多少"。TiDB 的 slow log 包含 `Cop_proc_avg`、`Cop_wait_avg`、`Backoff_total`、`Region_count` 等分布式特有指标；CockroachDB 的 `crdb_internal.statement_statistics` 包含 `network_latency`、`contention`、`distinct_nodes`。这些都是单机慢日志没有的概念。

### 9. SQLite 的彻底缺席提醒了边界

SQLite 至今没有任何慢查询日志/性能视图——它的设计哲学（"嵌入式、零运维、单进程"）让性能监控变得不必要：进程级 profiler 已经足够。这提醒我们：慢查询日志不是 SQL 必须的能力，而是**多用户、长生命周期、运维和开发分离**这种部署模型的必然产物。

## 总结对比表

| 能力 | PostgreSQL | MySQL | Oracle | SQL Server | Snowflake | ClickHouse | TiDB | BigQuery |
|------|-----------|-------|--------|------------|-----------|------------|------|----------|
| 慢日志开关 | log_min_duration | slow_query_log | AWR 始终 | Query Store | 始终 | 始终 | 始终 | 始终 |
| 阈值粒度 | 毫秒 | 秒 (浮点) | 自动 | 模式 | 无 | 毫秒 | 毫秒 | 无 |
| 采样率 | 是 (13+) | 否 (Percona) | 否 | 是 (CUSTOM) | 否 | 是 | 否 | 否 |
| Digest 内置 | pgss 扩展 | PS | SQL_ID | query_hash | param_hash | norm_hash | Digest | norm_hash |
| 计划捕获 | auto_explain | 否 | AWR/SPM | 是 | 是 | 部分 | 是 | 是 |
| 持久化 | 重启清零 | 重启清零 | AWR 8天 | QS 30天 | 365天 | TTL 自定义 | 24h+ 文件 | 180天 |
| 文件日志 | 是 | 是 | 否 | 否 | 否 | 否 | 是 | 否 |
| 表/视图 | 扩展 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| 跨节点 | -- | -- | RAC GV$ | 否 | -- | 集群 | 是 | -- |
| API/控制台 | 多个 | sys schema | OEM | SSMS/DBM | UI | UI | Dashboard | Cloud Console |

## 选型建议

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| 高 QPS OLTP 全模板分析 | PostgreSQL pg_stat_statements + log_min_duration_sample | 双层阈值，开销可控 |
| 抓取单条慢 SQL 现场 | MySQL slow_query_log + pt-query-digest | 文件日志，参数完整 |
| 事后追溯历史性能 | Oracle AWR + ASH | 自动持续快照，无需配置 |
| 无需配置的云方案 | Snowflake QUERY_HISTORY / BigQuery JOBS | 始终记录，零运维 |
| 自助式分析（SQL 直接查日志） | ClickHouse system.query_log | 日志即表 |
| 分布式 SQL 排查 | TiDB slow_query + Statements Summary | 节点级细节 |
| 计划演进追踪 | SQL Server Query Store | 自动 plan 历史与切换 |
| 开发/嵌入式 | SQLite (无日志) / DuckDB PRAGMA enable_profiling | 进程级 profiler 即可 |

## 参考资料

- PostgreSQL: [`log_min_duration_statement`](https://www.postgresql.org/docs/current/runtime-config-logging.html)
- PostgreSQL: [`pg_stat_statements`](https://www.postgresql.org/docs/current/pgstatstatements.html)
- PostgreSQL: [`auto_explain`](https://www.postgresql.org/docs/current/auto-explain.html)
- MySQL: [The Slow Query Log](https://dev.mysql.com/doc/refman/8.0/en/slow-query-log.html)
- MySQL: [Performance Schema Statement Digests](https://dev.mysql.com/doc/refman/8.0/en/performance-schema-statement-digests.html)
- Oracle: [Automatic Workload Repository (AWR)](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgdba/gathering-database-statistics.html)
- Oracle: [Active Session History (ASH)](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgdba/active-session-history.html)
- SQL Server: [Monitoring Performance By Using the Query Store](https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
- SQL Server: [Extended Events](https://learn.microsoft.com/en-us/sql/relational-databases/extended-events/extended-events)
- DB2: [`MON_GET_PKG_CACHE_STMT`](https://www.ibm.com/docs/en/db2/11.5?topic=routines-mon-get-pkg-cache-stmt-table-function)
- Snowflake: [`QUERY_HISTORY` View](https://docs.snowflake.com/en/sql-reference/account-usage/query_history)
- BigQuery: [`INFORMATION_SCHEMA.JOBS` views](https://cloud.google.com/bigquery/docs/information-schema-jobs)
- Redshift: [`SYS_QUERY_HISTORY`](https://docs.aws.amazon.com/redshift/latest/dg/SYS_QUERY_HISTORY.html)
- ClickHouse: [`system.query_log`](https://clickhouse.com/docs/en/operations/system-tables/query_log)
- Teradata: [Database Query Log (DBQL)](https://docs.teradata.com/r/Teradata-Database-Administration)
- TiDB: [Identify Slow Queries](https://docs.pingcap.com/tidb/stable/identify-slow-queries)
- TiDB: [Statement Summary Tables](https://docs.pingcap.com/tidb/stable/statement-summary-tables)
- CockroachDB: [SQL Activity Page](https://www.cockroachlabs.com/docs/stable/ui-statements-page)
- OceanBase: [`GV$OB_SQL_AUDIT`](https://en.oceanbase.com/docs/)
- Percona: [`pt-query-digest`](https://docs.percona.com/percona-toolkit/pt-query-digest.html)
