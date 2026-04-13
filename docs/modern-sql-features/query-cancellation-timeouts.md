# 查询取消与超时控制 (Query Cancellation and Timeouts)

一条失控的查询可以让整个共享数据库陷入瘫痪——CPU 飙满、内存耗尽、连接池堵塞、磁盘 IO 排队，最终拖垮所有正常业务。在多租户、共享集群、面向用户的 OLTP/HTAP/OLAP 系统里，**对单条语句、单个会话、单个事务甚至单字节扫描量设置硬性上限**，已经从"高级特性"变成了生产环境的最低门槛。本文系统对比 49+ 主流数据库在查询取消与超时控制方面的能力差异。

## 为什么超时与取消不可或缺

共享数据库系统中，runaway query（失控查询）是头号稳定性杀手。一个忘了 WHERE 的 `DELETE`、一个笛卡尔积 JOIN、一个写错的递归 CTE、一个被坏统计信息误导的全表扫描，都可能让某个会话独占资源并造成连锁反应。完整的"runaway query 防御体系"通常包含以下几道闸：

1. **语句级硬超时**（statement timeout）：单条 SQL 执行超过 N 秒强制中断
2. **空闲超时**（idle / wait timeout）：会话空闲过久自动断开，回收连接和锁
3. **事务超时**（transaction timeout / idle in transaction）：长事务超过阈值终止，避免 MVCC 膨胀
4. **锁等待超时**（lock wait timeout）：拿锁时间超过阈值放弃，避免雪崩
5. **手动取消**（KILL QUERY / pg_cancel_backend）：DBA 干预，停掉某条语句但保留连接
6. **手动终止**（KILL CONNECTION / pg_terminate_backend）：直接杀掉会话和后端进程
7. **成本预算**（max_rows / maximum_bytes_billed）：限制扫描行数或字节，云数仓常见
8. **CPU 时间限制**（CPU_PER_CALL / resource_limit）：按 CPU 时间而非 wall clock 限制
9. **内存限制**（max_memory_usage）：单查询内存配额
10. **磁盘 spill 限制**：临时磁盘溢出上限
11. **客户端断开取消**（client disconnect cancellation）：客户端 socket 断开后服务端是否自动取消
12. **死锁中止**（deadlock abort）：死锁检测到后自动牺牲一方（详见 `locks-deadlocks.md`）

不同数据库在这 12 个维度上的覆盖差异极大，本文逐项对比。

## 没有 SQL 标准

ISO/IEC 9075 SQL 标准从未定义查询取消或超时机制——这是 100% 的厂商扩展领域。SQL 标准只规定了事务的 ACID 语义和死锁回滚的可能性，但既没有 KILL 语句，也没有 statement timeout 配置项。结果就是：每个数据库的语法、单位、默认值、生效范围（session/global/role/profile）、是否可热修改、是否影响 DDL 等都各不相同。下面的支持矩阵直接进入厂商对比。

## 支持矩阵

### 1. Statement Timeout（单语句超时）

| 引擎 | 配置项 / 语法 | 单位 | 范围 | 备注 |
|------|--------------|------|------|------|
| PostgreSQL | `statement_timeout` | ms | session/global/role | 7.3+，0 = 禁用 |
| MySQL | `MAX_EXECUTION_TIME` hint / `max_execution_time` | ms | session/global/hint | 5.7.4+，仅 SELECT |
| MariaDB | `max_statement_time` | s（小数） | session/global/user | 10.1+，所有语句 |
| SQLite | -- | -- | -- | 无原生；可用 `sqlite3_progress_handler` 应用层中断 |
| Oracle | `RESOURCE_LIMIT` + `CPU_PER_CALL` profile | CPU 厘秒 | profile | 按 CPU 时间，非 wall |
| SQL Server | `query_governor_cost_limit` | 估算成本 | server | 基于估算 cost，非 wall；SET LOCK_TIMEOUT 仅锁等待 |
| DB2 | `QUERYTIMEOUTINTERVAL` 客户端 / `WLM ACTIVITYTOTALTIME` | s | client/WLM | 服务端通过 WLM 阈值 |
| Snowflake | `STATEMENT_TIMEOUT_IN_SECONDS` | s | account/wh/user/session | 默认 172800（2 天） |
| BigQuery | job-level `jobTimeoutMs`（API） | ms | per-job | 无 SQL 配置 |
| Redshift | `statement_timeout` / WLM `query_execution_time` | ms / s | session / WLM | WLM 优先 |
| DuckDB | -- | -- | -- | 无配置；通过 interrupt API 取消 |
| ClickHouse | `max_execution_time` | s | session/profile/query | 周期性检查，非硬实时 |
| Trino | `query.max-run-time` / `query_max_run_time` session | duration | server/session | 默认 100 days |
| Presto | `query.max-run-time` | duration | server | 同 Trino |
| Spark SQL | `spark.sql.broadcastTimeout` 等局部 | -- | -- | 无统一 statement timeout |
| Hive | `hive.query.timeout.seconds` | s | session/global | 0.14+ |
| Flink SQL | `pipeline.task.cancellation-interval` 等 | -- | -- | 流任务无 statement 概念 |
| Databricks | `spark.databricks.execution.timeout` | s | cluster | 继承 Spark |
| Teradata | `MaxParseTreeSegs` / Query Banding + TASM | -- | workload | 通过 TASM 工作负载管理 |
| Greenplum | `statement_timeout` | ms | 同 PG | 继承 PostgreSQL |
| CockroachDB | `statement_timeout` / `sql.defaults.statement_timeout` | ms | session/cluster | 19.2+ |
| TiDB | `max_execution_time` | ms | session/global/hint | 兼容 MySQL |
| OceanBase | `ob_query_timeout` | µs | session/global | 默认 10s |
| YugabyteDB | `statement_timeout` | ms | 同 PG | 继承 PostgreSQL |
| SingleStore | `query_timeout` 资源池 | s | resource pool | 通过资源池配置 |
| Vertica | `RUNTIMECAP` resource pool | duration | pool/user | 资源池属性 |
| Impala | `EXEC_TIME_LIMIT_S` | s | session/pool | 4.0+ |
| StarRocks | `query_timeout` | s | session/global | 默认 300 |
| Doris | `query_timeout` | s | session/global | 默认 300 |
| MonetDB | `call sys.setquerytimeout(n)` | s | session | 通过存储过程 |
| CrateDB | `statement_timeout` | duration | session | 4.6+ |
| TimescaleDB | `statement_timeout` | ms | 同 PG | 继承 PostgreSQL |
| QuestDB | `query.timeout.sec` | s | server | 服务端配置 |
| Exasol | `QUERY_TIMEOUT` | s | session/profile | ALTER SESSION |
| SAP HANA | `statement_timeout` ini / hint | s | system/session | indexserver.ini |
| Informix | `STMT_CACHE_NOLIMIT` 等 / `SET STATEMENT CACHE` | -- | -- | 无统一 statement timeout，靠 OS LIMIT |
| Firebird | `STATEMENT TIMEOUT` | ms | session/connection | 4.0+ |
| H2 | `SET QUERY_TIMEOUT n` | ms | session | 早期 |
| HSQLDB | JDBC `Statement.setQueryTimeout` | s | client | 仅客户端 |
| Derby | JDBC `Statement.setQueryTimeout` | s | client | 仅客户端 |
| Amazon Athena | DML query 30 min hard limit | -- | service | 不可调 |
| Azure Synapse | `QUERY_TIMEOUT` workload group | s | workload | Dedicated SQL pool |
| Google Spanner | request `deadline` (API) | -- | per-request | 无 SQL 配置 |
| Materialize | `statement_timeout` | ms | 同 PG | 继承 PG 协议 |
| RisingWave | `statement_timeout` | ms | session | 继承 PG 协议 |
| InfluxDB (SQL) | query timeout HTTP param | s | request | 通过 HTTP API |
| Databend | `max_execution_time` | s | session/setting | -- |
| Yellowbrick | `statement_timeout` | ms | session | 继承 PG |
| Firebolt | query timeout（账号级） | s | account | 控制台配置 |

### 2. Session / Idle Timeout（空闲连接超时）

| 引擎 | 配置项 | 默认 | 备注 |
|------|--------|------|------|
| PostgreSQL | `idle_session_timeout` | 0（禁用） | 14+ |
| MySQL | `wait_timeout` / `interactive_timeout` | 28800s | 8 小时 |
| MariaDB | `wait_timeout` / `interactive_timeout` | 28800s | 同 MySQL |
| SQLite | -- | -- | 嵌入式无网络会话 |
| Oracle | `IDLE_TIME` profile（分钟） | UNLIMITED | RESOURCE_LIMIT 必须打开 |
| SQL Server | `remote login timeout` / Resource Governor | -- | 客户端为主 |
| DB2 | `IDLE_TIME` (CLIENT IDLE TIMEOUT) | -- | 9.7+ |
| Snowflake | `CLIENT_SESSION_KEEP_ALIVE` / 4h 默认 | 4h | 不活动 4 小时断开 |
| BigQuery | -- | -- | 无持久会话 |
| Redshift | `idle_session_timeout` | -- | 2020+ |
| DuckDB | -- | -- | 嵌入式 |
| ClickHouse | `idle_connection_timeout` | 3600s | 服务端 |
| Trino | `idle-timeout` (HTTP) | -- | -- |
| Presto | 同 Trino | -- | -- |
| Spark SQL | Thrift Server `hive.server2.idle.session.timeout` | 1d | -- |
| Hive | `hive.server2.idle.session.timeout` | 7d | HiveServer2 |
| Flink SQL | session gateway idle timeout | -- | -- |
| Databricks | cluster auto-termination | 120 min | -- |
| Teradata | `SESSION TIMEOUT` | -- | TDGSS / DBQM |
| Greenplum | `idle_session_timeout` | -- | 6.x+ |
| CockroachDB | `idle_in_session_timeout` | 0 | -- |
| TiDB | `wait_timeout` / `interactive_timeout` | 28800s | 兼容 MySQL |
| OceanBase | `wait_timeout` | 28800s | 兼容 MySQL |
| YugabyteDB | `idle_session_timeout` | -- | 继承 PG |
| SingleStore | `wait_timeout` | -- | 兼容 MySQL |
| Vertica | `IDLESESSIONTIMEOUT` | -- | 用户属性 |
| Impala | `--idle_session_timeout` | 0 | impalad flag |
| StarRocks | `wait_timeout` | 28800s | -- |
| Doris | `wait_timeout` | 28800s | -- |
| MonetDB | -- | -- | -- |
| CrateDB | `idle_in_transaction_session_timeout` | -- | -- |
| TimescaleDB | `idle_session_timeout` | 同 PG | 14+ |
| QuestDB | `pg.idle.connection.timeout` | -- | -- |
| Exasol | `IDLE_TIMEOUT` | -- | 用户属性 |
| SAP HANA | `idle_connection_timeout` | -- | indexserver.ini |
| Informix | `IDLE_USER_TIMEOUT` | -- | onconfig |
| Firebird | -- | -- | -- |
| H2 | -- | -- | -- |
| HSQLDB | -- | -- | -- |
| Derby | -- | -- | -- |
| Amazon Athena | -- | -- | -- |
| Azure Synapse | -- | -- | -- |
| Google Spanner | -- | -- | -- |
| Materialize | `idle_in_transaction_session_timeout` | -- | -- |
| RisingWave | `idle_in_transaction_session_timeout` | -- | -- |
| InfluxDB (SQL) | -- | -- | -- |
| Databend | -- | -- | -- |
| Yellowbrick | `idle_session_timeout` | -- | 继承 PG |
| Firebolt | -- | -- | -- |

### 3. Transaction Timeout（事务/事务空闲超时）

| 引擎 | 配置项 | 备注 |
|------|--------|------|
| PostgreSQL | `idle_in_transaction_session_timeout` | 9.6+，针对 idle in tx |
| MySQL | `innodb_rollback_on_timeout` + `innodb_lock_wait_timeout` | 无单独事务总超时 |
| MariaDB | 同 MySQL | -- |
| SQLite | `BEGIN`/`busy_timeout` | -- |
| Oracle | `MAX_IDLE_BLOCKER_TIME` / `MAX_IDLE_TIME` | 12c+ |
| SQL Server | `XACT_ABORT` 是行为开关，非超时 | 通过 LOCK_TIMEOUT 间接 |
| DB2 | `MAX_IDLE_TIME` workload | -- |
| Snowflake | `TRANSACTION_ABORT_ON_ERROR` 行为；事务由 statement timeout 自然约束 | 无独立 tx timeout |
| BigQuery | 多语句事务 6h 限制 | 服务硬限制 |
| Redshift | `idle_in_transaction_session_timeout` | -- |
| DuckDB | -- | -- |
| ClickHouse | -- | 无传统事务 |
| Trino | `idle-timeout` | -- |
| Presto | 同 Trino | -- |
| Spark SQL | -- | -- |
| Hive | -- | -- |
| Flink SQL | -- | -- |
| Databricks | -- | -- |
| Teradata | TASM 控制 | -- |
| Greenplum | `idle_in_transaction_session_timeout` | 继承 PG |
| CockroachDB | `idle_in_transaction_session_timeout` | -- |
| TiDB | `tidb_idle_transaction_timeout`（24h 默认） | -- |
| OceanBase | `ob_trx_idle_timeout` / `ob_trx_timeout` | µs |
| YugabyteDB | `idle_in_transaction_session_timeout` | 继承 PG |
| SingleStore | -- | -- |
| Vertica | `IDLESESSIONTIMEOUT` 间接 | -- |
| Impala | -- | 无传统事务 |
| StarRocks | -- | -- |
| Doris | -- | -- |
| MonetDB | -- | -- |
| CrateDB | `idle_in_transaction_session_timeout` | -- |
| TimescaleDB | `idle_in_transaction_session_timeout` | 继承 PG |
| QuestDB | -- | -- |
| Exasol | -- | -- |
| SAP HANA | `idle_cursor_lifetime` 等 | -- |
| Informix | `LTXEHWM` long transaction high water mark | -- |
| Firebird | -- | -- |
| H2 | -- | -- |
| HSQLDB | -- | -- |
| Derby | -- | -- |
| Amazon Athena | -- | -- |
| Azure Synapse | -- | -- |
| Google Spanner | 单读写事务 10s idle / 总 1h | 服务硬限制 |
| Materialize | `idle_in_transaction_session_timeout` | -- |
| RisingWave | -- | -- |
| InfluxDB (SQL) | -- | -- |
| Databend | -- | -- |
| Yellowbrick | `idle_in_transaction_session_timeout` | 继承 PG |
| Firebolt | -- | -- |

### 4. Lock Wait Timeout（锁等待超时）

| 引擎 | 配置项 | 默认 | 备注 |
|------|--------|------|------|
| PostgreSQL | `lock_timeout` | 0（禁用） | 9.3+ |
| MySQL (InnoDB) | `innodb_lock_wait_timeout` | 50s | -- |
| MariaDB | `innodb_lock_wait_timeout` | 50s | -- |
| SQLite | `busy_timeout` | 0 | PRAGMA |
| Oracle | `DDL_LOCK_TIMEOUT` / `WAIT n` 子句 | 0/no wait | 行级靠 SELECT FOR UPDATE WAIT |
| SQL Server | `SET LOCK_TIMEOUT` | -1（无限） | ms |
| DB2 | `LOCKTIMEOUT` 数据库参数 | -1 | s |
| Snowflake | `LOCK_TIMEOUT` | 43200s | 12h |
| BigQuery | -- | -- | DML 自带排队 |
| Redshift | `statement_timeout` | -- | 无独立 lock_timeout |
| DuckDB | -- | -- | -- |
| ClickHouse | `lock_acquire_timeout` | 120s | -- |
| Trino | -- | -- | -- |
| Presto | -- | -- | -- |
| Spark SQL | -- | -- | -- |
| Hive | `hive.lock.numretries` × wait | -- | ZooKeeper |
| Flink SQL | -- | -- | -- |
| Databricks | -- | -- | Delta 乐观并发 |
| Teradata | -- | TASM | -- |
| Greenplum | `lock_timeout` | 继承 PG | -- |
| CockroachDB | `lock_timeout` (22.2+) | -- | -- |
| TiDB | `innodb_lock_wait_timeout` | 50s | 兼容 MySQL |
| OceanBase | `ob_trx_lock_timeout` | -- | µs |
| YugabyteDB | `lock_timeout` | -- | 继承 PG |
| SingleStore | `lock_wait_timeout` | -- | -- |
| Vertica | `LockTimeout` | 5min | -- |
| Impala | -- | -- | -- |
| StarRocks | -- | -- | -- |
| Doris | -- | -- | -- |
| MonetDB | -- | -- | -- |
| CrateDB | -- | -- | -- |
| TimescaleDB | `lock_timeout` | 继承 PG | -- |
| QuestDB | -- | -- | -- |
| Exasol | `QUERY_TIMEOUT` 间接 | -- | -- |
| SAP HANA | `lock_wait_timeout` | -- | indexserver.ini |
| Informix | `SET LOCK MODE TO WAIT n` | -- | -- |
| Firebird | `SET TRANSACTION ... WAIT n` | -- | -- |
| H2 | `SET LOCK_TIMEOUT n` | 1000 ms | -- |
| HSQLDB | -- | -- | -- |
| Derby | `derby.locks.waitTimeout` | 60s | -- |
| Amazon Athena | -- | -- | -- |
| Azure Synapse | `LOCK_TIMEOUT` | -- | T-SQL |
| Google Spanner | -- | -- | 强一致性内部处理 |
| Materialize | -- | -- | -- |
| RisingWave | -- | -- | -- |
| InfluxDB (SQL) | -- | -- | -- |
| Databend | -- | -- | -- |
| Yellowbrick | `lock_timeout` | 继承 PG | -- |
| Firebolt | -- | -- | -- |

### 5. Query Cancellation（手动取消，保留连接）

| 引擎 | 取消语法 | 粒度 |
|------|---------|------|
| PostgreSQL | `pg_cancel_backend(pid)` | 后端进程 |
| MySQL | `KILL QUERY thread_id` | 线程 |
| MariaDB | `KILL QUERY thread_id` | 线程 |
| SQLite | `sqlite3_interrupt(db)` | C API |
| Oracle | `ALTER SYSTEM CANCEL SQL 'sid,serial#'` | 19c+ |
| SQL Server | `KILL spid` | 会话级（无 cancel-only） |
| DB2 | `CANCEL DATABASE` / `db2 force application` | 应用 |
| Snowflake | `SYSTEM$CANCEL_QUERY('query_id')` | 单 query |
| BigQuery | `jobs.cancel` REST / `bq cancel` | 作业 |
| Redshift | `CANCEL pid` | 后端 |
| DuckDB | C API `duckdb_interrupt` | -- |
| ClickHouse | `KILL QUERY WHERE query_id = ...` | 单 query |
| Trino | REST `/v1/query/{queryId}` DELETE | 单 query |
| Presto | 同 Trino | -- |
| Spark SQL | `SparkContext.cancelJobGroup` | job group |
| Hive | `KILL QUERY '<query_id>'` | 2.2+ |
| Flink SQL | `STOP JOB '<jobId>'` | 流作业 |
| Databricks | UI / REST `runs/cancel` | -- |
| Teradata | `ABORT SESSION` (PMON) | 会话 |
| Greenplum | `pg_cancel_backend` | 同 PG |
| CockroachDB | `CANCEL QUERY 'query_id'` | 单 query |
| TiDB | `KILL TIDB QUERY connection_id` | -- |
| OceanBase | `KILL QUERY id` | -- |
| YugabyteDB | `pg_cancel_backend` | 同 PG |
| SingleStore | `KILL QUERY connection_id` | -- |
| Vertica | `INTERRUPT_STATEMENT(session_id, statement_id)` | -- |
| Impala | `:shell` cancel / Web UI | -- |
| StarRocks | `KILL QUERY connection_id` | -- |
| Doris | `KILL QUERY connection_id` | -- |
| MonetDB | `sys.shutdown` 仅整库 | 受限 |
| CrateDB | `KILL '<job_id>'` | -- |
| TimescaleDB | `pg_cancel_backend` | 同 PG |
| QuestDB | `CANCEL QUERY query_id` | -- |
| Exasol | `KILL STATEMENT IN SESSION n` | -- |
| SAP HANA | `ALTER SYSTEM CANCEL SESSION 'cn'` | -- |
| Informix | `onmode -z sid` | OS 命令 |
| Firebird | `DELETE FROM MON$STATEMENTS WHERE MON$STATEMENT_ID = ?` | 监控表 |
| H2 | JDBC `Statement.cancel()` | 客户端 |
| HSQLDB | JDBC `Statement.cancel()` | 客户端 |
| Derby | JDBC `Statement.cancel()` | 客户端 |
| Amazon Athena | `StopQueryExecution` API | -- |
| Azure Synapse | `KILL 'request_id'` | -- |
| Google Spanner | gRPC cancel context | -- |
| Materialize | `pg_cancel_backend` | 兼容 PG |
| RisingWave | `pg_cancel_backend` | 兼容 PG |
| InfluxDB (SQL) | -- | -- |
| Databend | `KILL QUERY query_id` | -- |
| Yellowbrick | `pg_cancel_backend` | 兼容 PG |
| Firebolt | UI / REST | -- |

### 6. Query Termination（杀掉连接/会话）

| 引擎 | 终止语法 |
|------|---------|
| PostgreSQL | `pg_terminate_backend(pid)` |
| MySQL | `KILL CONNECTION thread_id` (= `KILL thread_id`) |
| MariaDB | `KILL CONNECTION thread_id` |
| SQLite | -- |
| Oracle | `ALTER SYSTEM KILL SESSION 'sid,serial#' [IMMEDIATE]` |
| SQL Server | `KILL spid [WITH STATUSONLY]` |
| DB2 | `FORCE APPLICATION (handle)` |
| Snowflake | `SYSTEM$ABORT_SESSION('session_id')` |
| BigQuery | `jobs.cancel`（作业即会话） |
| Redshift | `pg_terminate_backend(pid)` |
| DuckDB | -- |
| ClickHouse | `KILL QUERY ... SYNC` + 重启连接 |
| Trino | -- 无独立会话杀死，cancel = 中断 |
| Presto | 同 Trino |
| Spark SQL | `SparkContext.cancelStage` / Thrift Server kill |
| Hive | -- |
| Flink SQL | -- |
| Databricks | cluster restart / kill driver |
| Teradata | `LOGOFF` via PMON |
| Greenplum | `pg_terminate_backend` |
| CockroachDB | `CANCEL SESSION 'session_id'` |
| TiDB | `KILL TIDB connection_id` |
| OceanBase | `KILL connection_id` |
| YugabyteDB | `pg_terminate_backend` |
| SingleStore | `KILL CONNECTION id` |
| Vertica | `CLOSE_SESSION('session_id')` |
| Impala | Web UI / `KILL SESSION` |
| StarRocks | `KILL connection_id` |
| Doris | `KILL connection_id` |
| MonetDB | -- |
| CrateDB | -- |
| TimescaleDB | `pg_terminate_backend` |
| QuestDB | -- |
| Exasol | `KILL SESSION n` |
| SAP HANA | `ALTER SYSTEM DISCONNECT SESSION 'cn'` |
| Informix | `onmode -z sid` |
| Firebird | `DELETE FROM MON$ATTACHMENTS WHERE MON$ATTACHMENT_ID = ?` |
| H2 | -- |
| HSQLDB | -- |
| Derby | -- |
| Amazon Athena | -- |
| Azure Synapse | `KILL 'session_id'` |
| Google Spanner | -- |
| Materialize | `pg_terminate_backend` |
| RisingWave | `pg_terminate_backend` |
| InfluxDB (SQL) | -- |
| Databend | `KILL CONNECTION conn_id` |
| Yellowbrick | `pg_terminate_backend` |
| Firebolt | -- |

### 7. Cost-Based Abort（成本/字节/行数预算）

| 引擎 | 配置项 | 单位 | 备注 |
|------|--------|------|------|
| PostgreSQL | -- | -- | 无原生（需扩展） |
| MySQL | -- | -- | -- |
| MariaDB | -- | -- | -- |
| Oracle | `RESOURCE_LIMIT` + `LOGICAL_READS_PER_CALL` | 块数 | profile |
| SQL Server | `query_governor_cost_limit` | 估算秒 | 基于 estimated cost，常常失效 |
| DB2 | `WLM ESTIMATEDSQLCOST` 阈值 | timerons | -- |
| Snowflake | `STATEMENT_QUEUED_TIMEOUT_IN_SECONDS` 队列 | s | -- |
| BigQuery | `maximum_bytes_billed` | bytes | 成本上限非时间 |
| Redshift | WLM `query_max_memory` / RA3 abort actions | -- | -- |
| ClickHouse | `max_rows_to_read` / `max_bytes_to_read` / `max_result_rows` | 行/字节 | -- |
| Trino | `query.max-scan-physical-bytes` / `query_max_scan_physical_bytes` | bytes | -- |
| Presto | 同 Trino | -- | -- |
| Spark SQL | -- | -- | -- |
| Hive | `hive.limit.query.max.table.partition` 等 | -- | 部分 |
| Databricks | -- | -- | -- |
| Teradata | TASM `MaxRows` / `MaxAMPCPUTime` | -- | -- |
| Greenplum | `gp_max_csv_line_length` 等局部 | -- | -- |
| CockroachDB | -- | -- | -- |
| TiDB | `tidb_mem_quota_query` (内存为主) | bytes | -- |
| OceanBase | `ob_query_timeout` 为主 | -- | -- |
| YugabyteDB | -- | -- | -- |
| SingleStore | resource pool `query_timeout` | -- | -- |
| Vertica | `MAXMEMORYSIZE` / pool | -- | -- |
| Impala | `MEM_LIMIT` / `SCAN_BYTES_LIMIT` | bytes | -- |
| StarRocks | `query_mem_limit` | bytes | -- |
| Doris | `exec_mem_limit` | bytes | -- |
| MonetDB | -- | -- | -- |
| CrateDB | `statement_max_length` | -- | -- |
| Exasol | -- | -- | -- |
| SAP HANA | `STATEMENT MEMORY LIMIT` | GB | -- |
| Athena | `DataScannedInBytes` workgroup limit | bytes | -- |
| Azure Synapse | workload group `request_max_resource_grant_percent` | -- | -- |
| Spanner | -- | -- | -- |
| Materialize | -- | -- | -- |
| RisingWave | -- | -- | -- |
| Databend | `max_result_rows` | -- | -- |
| Yellowbrick | -- | -- | -- |
| Firebolt | -- | -- | -- |

### 8. CPU 时间限制

| 引擎 | 配置项 | 备注 |
|------|--------|------|
| Oracle | `CPU_PER_CALL` / `CPU_PER_SESSION` profile | 厘秒，需 RESOURCE_LIMIT=TRUE |
| DB2 | `WLM CPUTIME` | -- |
| Teradata | TASM `MaxAMPCPUTime` | -- |
| ClickHouse | -- | wall clock 为主 |
| 其他多数引擎 | -- | 通常以 wall clock 而非 CPU 时间为单位 |

### 9. 内存限制（单查询）

| 引擎 | 配置项 |
|------|--------|
| PostgreSQL | `work_mem`（每 sort/hash 节点）|
| Oracle | `PGA_AGGREGATE_LIMIT` 实例 |
| SQL Server | Resource Governor `REQUEST_MAX_MEMORY_GRANT_PERCENT` |
| ClickHouse | `max_memory_usage` |
| Snowflake | -- 由 warehouse size 决定 |
| BigQuery | -- 服务自适应 |
| Redshift | WLM `query_max_memory` |
| Trino | `query.max-memory-per-node` / `query_max_memory` |
| Spark SQL | `spark.executor.memory` |
| Vertica | resource pool `MAXMEMORYSIZE` |
| Impala | `MEM_LIMIT` |
| StarRocks | `query_mem_limit` |
| Doris | `exec_mem_limit` |
| TiDB | `tidb_mem_quota_query` |
| OceanBase | `ob_sql_work_area_percentage` |
| SAP HANA | `STATEMENT MEMORY LIMIT` |

### 10. 磁盘 spill 限制

| 引擎 | 配置项 | 备注 |
|------|--------|------|
| PostgreSQL | `temp_file_limit` | per-session bytes |
| Trino | `query.max-spill-per-node` / `query.max-total-memory-per-node` | -- |
| Spark SQL | `spark.shuffle.spill.numElementsForceSpillThreshold` | -- |
| Snowflake | -- spill 自动到本地 SSD/远端 | -- |
| Redshift | `query_max_disk_use` (action) | -- |
| Impala | `SCRATCH_LIMIT` | -- |
| ClickHouse | `max_bytes_before_external_group_by` 等 | -- |

### 11. 客户端断开自动取消

| 引擎 | 行为 |
|------|------|
| PostgreSQL | `client_connection_check_interval`（14+）触发取消，否则继续执行 |
| MySQL | 默认继续执行直到结束（除非用 KILL） |
| Oracle | DCD `SQLNET.EXPIRE_TIME` 检测死连接 |
| SQL Server | 客户端断开通常会终止请求 |
| Snowflake | 客户端断开后 Snowflake 仍执行至完成（或 timeout） |
| BigQuery | 客户端断开不影响后台 job 执行 |
| Trino | 客户端断开不一定取消，需要显式 cancel |
| ClickHouse | `cancel_http_readonly_queries_on_client_close` 控制 |
| BigQuery / Snowflake | 异步作业模型，断开≠取消 |

### 12. 死锁中止（详见 `locks-deadlocks.md`）

几乎所有支持事务的数据库都有死锁检测器，发现循环等待后会回滚一个或多个事务（通常是"代价最小"的那个）。例如 PostgreSQL 的 `deadlock_timeout`（默认 1s），MySQL InnoDB 的死锁检测器（默认开启），SQL Server deadlock priority 等。本表略，详见专门文章。

## 各引擎详解

### PostgreSQL：超时 GUC 全家桶 + 函数式取消

PostgreSQL 把超时全部做成可热修改的 GUC（grand unified configuration）参数，覆盖 statement / lock / idle 三大维度，并提供两个 SQL 函数完成取消和终止。

```sql
-- 1) 单语句超时（毫秒）：可在 postgresql.conf / 角色 / 数据库 / session 任意层
SET statement_timeout = '30s';
ALTER ROLE etl SET statement_timeout = '2h';
ALTER DATABASE analytics SET statement_timeout = '10min';

-- 2) 锁等待超时（9.3+）
SET lock_timeout = '5s';

-- 3) 事务空闲超时（9.6+）：BEGIN 后空转过久自动 ROLLBACK 并断开
SET idle_in_transaction_session_timeout = '10min';

-- 4) 会话空闲超时（14+）：连接空闲过久断开
SET idle_session_timeout = '1h';

-- 5) 客户端断开检测（14+）：每 N 秒检测，断开后自动取消
SET client_connection_check_interval = '10s';

-- 取消正在运行的查询（保留连接）
SELECT pg_cancel_backend(12345);

-- 强制终止后端（连接也断）
SELECT pg_terminate_backend(12345);
```

`statement_timeout` 自 7.3（2002 年）就已存在，是工业级 RDBMS 中最早提供的 SQL 级硬超时之一。`idle_in_transaction_session_timeout` 在 9.6（2016）引入，专门治理 ORM/应用代码忘了 commit 的"幽灵长事务"，对避免 vacuum 滞后和 wraparound 至关重要。`lock_timeout` 在 9.3（2013）引入，解决了之前只能整体 statement_timeout 一刀切的痛点——例如执行 DDL 时只想等锁 5 秒，但语句本身想跑半小时。

### MySQL：HINT 级超时 + KILL 双形态

MySQL 5.7.4（2014）通过 [WL#6936](https://dev.mysql.com/worklog/task/?id=6936) 引入了 `MAX_EXECUTION_TIME` 优化器 hint，**但仅对 SELECT 生效**——无法用 hint 限制 UPDATE/DELETE/DDL。这个限制源于 MySQL 优化器架构：超时检查嵌在执行器的 row-by-row 调度循环里，对写操作和 DDL 路径覆盖不完整。

```sql
-- 1) hint 形式（仅 SELECT）：5.7.4+
SELECT /*+ MAX_EXECUTION_TIME(2000) */ * FROM huge_table WHERE ...;

-- 2) session 变量（仅 SELECT 受影响）
SET SESSION max_execution_time = 2000;  -- 毫秒

-- 3) 全局默认
SET GLOBAL max_execution_time = 30000;

-- 4) 锁等待
SET innodb_lock_wait_timeout = 5;

-- 5) 空闲超时
SET wait_timeout = 600;
SET interactive_timeout = 600;

-- 取消查询但保留连接
KILL QUERY 12345;

-- 杀掉整个连接
KILL CONNECTION 12345;
KILL 12345;  -- 等价于 KILL CONNECTION
```

注意 MySQL 的 `KILL QUERY` 与 `KILL [CONNECTION]` 是两条独立的命令：前者只中断当前正在执行的语句，连接和会话变量保留；后者整个 thread 关闭，连接断开。这与 PostgreSQL 的 `pg_cancel_backend` vs `pg_terminate_backend` 在语义上一一对应。

### Oracle：基于 PROFILE 的 CPU 与逻辑读限制

Oracle 不通过 GUC 而通过 **user profile** 机制设置资源限制，必须先开 `RESOURCE_LIMIT=TRUE`：

```sql
ALTER SYSTEM SET RESOURCE_LIMIT = TRUE;

CREATE PROFILE bi_user LIMIT
  CPU_PER_CALL          6000        -- 60 秒 CPU 时间（厘秒）
  CPU_PER_SESSION       UNLIMITED
  LOGICAL_READS_PER_CALL 1000000
  IDLE_TIME             30          -- 分钟
  CONNECT_TIME          240;

ALTER USER reporting PROFILE bi_user;

-- 19c+ 提供 SQL 级 CANCEL（之前只能 KILL SESSION）
ALTER SYSTEM CANCEL SQL 'sid, serial#';

-- 老牌的杀会话
ALTER SYSTEM KILL SESSION '123,456' IMMEDIATE;

-- 行级锁等待
SELECT * FROM t FOR UPDATE WAIT 5;       -- 等 5 秒后报 ORA-30006
SELECT * FROM t FOR UPDATE NOWAIT;       -- 不等待
```

Oracle 的 `CPU_PER_CALL` 是真正按 CPU 时间计费（不是 wall clock），所以等待 IO 或锁的时间不计入。这与 PostgreSQL/MySQL 的 wall clock 模型完全不同——长时间等锁的查询在 Oracle 不会被 `CPU_PER_CALL` 终止，需要配合 Resource Manager 的 `MAX_EST_EXEC_TIME` 等其他维度。

### SQL Server：基于估算成本的"伪超时"

SQL Server 没有真正意义上的 wall-clock statement timeout，只有 `query_governor_cost_limit`：

```sql
-- 限制估算 cost 超过 300（秒）的查询直接报错，不允许执行
sp_configure 'query governor cost limit', 300;
RECONFIGURE;

-- 锁等待
SET LOCK_TIMEOUT 5000;  -- ms
SELECT * FROM t;        -- 等不到锁报 1222

-- 杀掉会话
KILL 52;
KILL 52 WITH STATUSONLY;  -- 查看回滚进度
```

`query_governor_cost_limit` 的"成本"来自优化器估算，单位是估计的秒数（在参考机器上），由统计信息、参数嗅探、cardinality estimator 共同决定。**统计信息陈旧时这个值毫无可信度**——这就是工业界经常吐槽 query governor "形同虚设"的根本原因。真正的 wall-clock 超时只能在客户端（ADO.NET `CommandTimeout`、JDBC `Statement.setQueryTimeout`）或通过 Resource Governor 的 `REQUEST_MAX_CPU_TIME_SEC` 实现。

### ClickHouse：周期采样的"软"超时

```sql
SELECT *
FROM huge_events
SETTINGS
  max_execution_time = 60,
  timeout_overflow_mode = 'throw',
  max_rows_to_read = 1000000000,
  max_bytes_to_read = 100000000000,
  max_memory_usage = 10000000000,
  max_result_rows = 1000000;

-- 取消正在运行的查询
KILL QUERY WHERE query_id = 'abc-123' SYNC;

-- 同步等待终止 + 删除
KILL QUERY WHERE user = 'analyst' AND elapsed > 60 SYNC;
```

ClickHouse 的 `max_execution_time` 是**周期检查**（默认每处理一定行数后检查一次），不是硬实时——某个慢算子（比如远端表扫描或外部排序）在两次检查之间花了 5 分钟，依然会跑完才被中断。这是 ClickHouse 高吞吐与超时精度之间的权衡。`timeout_overflow_mode='break'` 可以让超时只截断结果而非报错（很特别的语义）。

### Snowflake：账号级默认 2 天

```sql
-- 默认 172800 秒（48 小时），新 account 必须显式调小
ALTER ACCOUNT SET STATEMENT_TIMEOUT_IN_SECONDS = 3600;
ALTER WAREHOUSE etl SET STATEMENT_TIMEOUT_IN_SECONDS = 7200;
ALTER USER analyst SET STATEMENT_TIMEOUT_IN_SECONDS = 600;
ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = 60;

-- 排队超时（warehouse 满了排队等多久）
ALTER WAREHOUSE etl SET STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = 600;

-- 取消单条查询
SELECT SYSTEM$CANCEL_QUERY('01a2b3c4-...');

-- 取消会话内所有查询
SELECT SYSTEM$CANCEL_ALL_QUERIES(SESSION_ID());

-- 终止整个会话
SELECT SYSTEM$ABORT_SESSION(123456789);
```

**Snowflake 的默认超时是惊人的 172800 秒（2 天）**——这是事故根源最常见的来源之一。一个被卡死的 ETL 在 Snowflake 上能空跑 48 小时烧掉整个 warehouse 信用额度。生产实践应当在 account 层降到几十分钟级别，并按 user/warehouse 进一步细化。

### BigQuery：成本预算而非时间预算

BigQuery 是 serverless 按字节扫描计费的模型，所以提供了独特的 `maximum_bytes_billed` 作为**成本闸**而非时间闸：

```sql
-- 限制本次查询最多扫描 1GB
SELECT *
FROM `proj.ds.events`
WHERE date = '2026-04-13'
OPTIONS(maximum_bytes_billed = 1073741824);
```

```python
# Python client 设置 job 级超时
job_config = bigquery.QueryJobConfig(
    maximum_bytes_billed=10**9,
    job_timeout_ms=60000,
)
client.query(sql, job_config=job_config)
```

```bash
# 取消作业
bq cancel job_id_xxx
```

注意：`maximum_bytes_billed` 是预先估算的扫描字节，超过即拒绝执行（不会先跑一半再终止），所以是一种"成本预算"而不是 wall-clock 超时。多语句脚本中可用 `BEGIN ... EXCEPTION WHEN ERROR THEN ... END` 配合 `ABORT_STATEMENT` 处理超额错误。

### DB2：WLM 工作负载管理 + 客户端 timeout

```sql
-- 数据库级锁等待
UPDATE DB CFG FOR salesdb USING LOCKTIMEOUT 30;

-- 通过 WLM 限制活动总时间
CREATE THRESHOLD slow_kill
  FOR ACTIVITIES ENFORCEMENT DATABASE
  WHEN ACTIVITYTOTALTIME > 5 MINUTES
  STOP EXECUTION;

-- connect_proc：每次连接时执行的存储过程，常用于在登录时设置超时
CREATE PROCEDURE set_session_defaults()
  LANGUAGE SQL
  BEGIN
    SET CURRENT LOCK TIMEOUT = 30;
    -- ... 其他会话默认
  END;
UPDATE DB CFG USING CONNECT_PROC SCHEMA.SET_SESSION_DEFAULTS;

-- 强制终止
FORCE APPLICATION (12345);
```

### Trino：duration 风格全局参数

```properties
# coordinator config.properties
query.max-run-time=2h
query.max-execution-time=1h
query.max-cpu-time=30m
query.max-memory=200GB
query.max-memory-per-node=10GB
query.max-scan-physical-bytes=1TB
```

```sql
-- session 级覆盖
SET SESSION query_max_run_time = '10m';
SET SESSION query_max_scan_physical_bytes = '50GB';
```

```bash
# REST 取消
curl -X DELETE http://coord:8080/v1/query/20260413_120000_00001_x9z3p
```

### CockroachDB：兼容 PG 协议

```sql
SET statement_timeout = '30s';
SET lock_timeout = '5s';                 -- 22.2+
SET idle_in_session_timeout = '10m';
SET idle_in_transaction_session_timeout = '5m';

-- 集群级默认
SET CLUSTER SETTING sql.defaults.statement_timeout = '60s';

-- 取消
CANCEL QUERY '15a8b9c0...';
CANCEL SESSION '15a8b9d1...';

-- 通过虚拟表查找
SELECT query_id, query, age(now(), start) AS dur
FROM crdb_internal.cluster_queries
WHERE age(now(), start) > '30s'::interval;
```

## pg_cancel_backend vs pg_terminate_backend：信号语义的本质差异

PostgreSQL 这两个函数虽然都接受同一个 pid 参数，但底层完全不同：

| 维度 | `pg_cancel_backend(pid)` | `pg_terminate_backend(pid)` |
|------|-------------------------|----------------------------|
| 底层信号 | `SIGINT` | `SIGTERM` |
| 行为 | 中断当前语句，事务回滚到 savepoint 边界 | 整个 backend 进程退出 |
| 连接是否保留 | 是 | 否，client 收到 connection reset |
| 是否需要超级用户 | 同库即可 | 默认需要 pg_signal_backend 角色 |
| 对未阻塞代码的响应 | 在下一个 CHECK_FOR_INTERRUPTS 点响应 | 同样依赖 interrupt 检查点 |
| 典型用途 | 杀掉具体一条慢查询 | 强制踢掉死锁/失控会话 |

关键注意：两者都不是"立即生效"。PostgreSQL 后端进程在执行某些 C 级密集操作（如某些扩展函数、网络等待）时不会响应 interrupt 检查点，这种情况下你会发现 `pg_cancel_backend` 没用，必须 `pg_terminate_backend`，甚至偶尔需要在 OS 层 `kill -9`（这通常会触发整个 cluster 的崩溃恢复，不推荐）。

`pg_terminate_backend` 还有一个 14+ 引入的可选 `timeout` 参数，会在指定毫秒后报告是否成功：

```sql
SELECT pg_terminate_backend(12345, 3000);  -- 等 3 秒确认 backend 真退出
```

## MySQL MAX_EXECUTION_TIME hint 的特殊性：仅 SELECT，且仅顶层

MySQL 5.7.4 的 `MAX_EXECUTION_TIME(N)` 是优化器 hint，但有几条不直觉的规则：

```sql
-- 1) 仅对 SELECT 生效，且仅对顶层 SELECT；放在子查询里被忽略
SELECT /*+ MAX_EXECUTION_TIME(1000) */ COUNT(*) FROM t;  -- OK

-- 2) UPDATE / DELETE / INSERT 都不受 hint 控制
UPDATE /*+ MAX_EXECUTION_TIME(1000) */ t SET x = 1;       -- hint 被忽略

-- 3) 存储函数和触发器中的 SELECT 不受影响

-- 4) session 变量 max_execution_time 同样只影响只读 SELECT
SET SESSION max_execution_time = 1000;
UPDATE t SET x = x + 1;  -- 不会被中断

-- 5) 单位是毫秒，但只在执行器调度点检查
```

如果需要限制写操作，必须配合 `KILL QUERY` 由外部 watchdog 完成，或在 ProxySQL/MaxScale 这类中间件层挂规则。MariaDB 的 `max_statement_time`（10.1+，单位是秒，可以是小数）在这点上做得更彻底——它对所有语句类型都生效。

## 关键发现

1. **没有 SQL 标准**：超时与取消是 100% 厂商扩展，每个引擎自定义配置项、单位、生效层级。
2. **PostgreSQL 系最完整**：PG 的 statement / lock / idle / idle_in_tx / client_check 五件套是行业最齐全的，并被 Greenplum / TimescaleDB / YugabyteDB / CockroachDB / Materialize / RisingWave / Yellowbrick 等"PG 协议派"全部继承。
3. **MySQL 的 hint 是半成品**：`MAX_EXECUTION_TIME` 仅 SELECT 生效是工业界长期吐槽点；要全语句类型超时只能选 MariaDB 的 `max_statement_time` 或 TiDB 的 `max_execution_time`。
4. **SQL Server 的 query_governor 几乎没人真的用**：基于估算成本的"超时"在统计信息陈旧时完全失真，绝大多数 SQL Server 生产环境靠客户端 `CommandTimeout` 来兜底。
5. **Snowflake 默认 2 天极其危险**：172800 秒的默认 `STATEMENT_TIMEOUT_IN_SECONDS` 让事故 blast radius 巨大，新 account 上线第一件事应该是把它降到几十分钟。
6. **BigQuery 是字节预算而非时间预算**：`maximum_bytes_billed` 是 serverless 按量计费模型下的独特安全网，配置时要区分"预算闸"（pre-execution reject）和"超时闸"（mid-execution abort）。
7. **CPU 时间 vs Wall Clock 是另一条分水岭**：Oracle / DB2 / Teradata 提供基于 CPU 时间的限制（公平性更好，等锁不计入），其他大多数引擎都是 wall clock（实现简单但等待长锁也算时间）。
8. **ClickHouse / Trino 的 cost-based 限额是 OLAP 特色**：`max_rows_to_read` / `max_bytes_to_read` / `max-scan-physical-bytes` 把"扫描预算"和"时间预算"解耦，能更精准命中扫描型 runaway。
9. **取消 vs 终止的双形态几乎是普世模式**：PG 的 `pg_cancel_backend` / `pg_terminate_backend`、MySQL 的 `KILL QUERY` / `KILL CONNECTION`、CockroachDB 的 `CANCEL QUERY` / `CANCEL SESSION`、Snowflake 的 `CANCEL_QUERY` / `ABORT_SESSION`——大型数据库都把"中断当前语句"和"杀掉整个会话"做成两条独立路径。
10. **客户端断开≠服务端取消**：Snowflake、BigQuery、Trino、PostgreSQL（< 14）默认情况下，客户端断开后服务端继续跑到底；只有 PG 14+ 的 `client_connection_check_interval` 和 ClickHouse 的 `cancel_http_readonly_queries_on_client_close` 等少数选项能改变这个默认行为。生产应用如果依赖"用户关闭浏览器=查询停止"，必须显式做这件事。
11. **嵌入式数据库依赖客户端**：SQLite、DuckDB、H2、HSQLDB、Derby 没有服务端进程，超时/取消必须通过 C API（`sqlite3_interrupt`、`duckdb_interrupt`）或 JDBC `Statement.cancel()` / `setQueryTimeout` 在调用方实现。
12. **死锁中止是唯一普遍存在的"自动取消"**：所有支持事务的引擎都自带死锁检测（详见 `locks-deadlocks.md`），但其它形式的自动取消（statement / lock / idle）默认大多是关闭的，需要 DBA 主动配置——这正是大量生产事故的根因。
