# 跟踪标志与调试开关 (Trace Flags and Debug Switches)

凌晨三点接到告警：核心交易系统的某条 SQL 突然走错了执行计划，全表扫描代替了原本完美的索引查找。统计信息没变、表结构没动、参数没改——你只能祭出最后的武器：DBCC TRACEON(9481) 强制使用旧版基数估计器，临时把火扑灭。这就是跟踪标志的真实价值：当文档没说、参数没暴露、行为无法解释时，DBA 必须能"伸手进引擎内部拨一下开关"，而这正是 SQL 标准从未涉及、各家数据库以截然不同方式实现的领域。

## 为什么 DBA 需要拨弄内部开关

任何一个商用数据库内部都有数百到数千个"内部开关"：是否启用某个查询优化规则、是否打印某类执行细节、是否走旧版代码路径、是否绕过某个安全检查……这些开关绝大多数不会作为正式 GUC/系统变量暴露给用户，因为：

1. **稳定性不足**：一些是工程师调试时临时加的钩子，没经过完整测试，正式暴露会带来支持负担。
2. **语义复杂**：开关之间相互依赖、相互影响，标准化为参数后用户使用门槛过高。
3. **临时绕过 (workaround)**：当某个版本出现回归 bug 时，需要快速给客户一个可以临时关闭新行为的开关，发布周期等不及加正式参数。
4. **诊断专用**：仅在故障定位场景使用，正常运行时不应启用。

但这些"内部开关"对 DBA 至关重要。Oracle 的事件 (event) 10046 是 SQL 跟踪的祖师爷，1990 年代起就是性能调优的金钥匙；SQL Server 的 DBCC TRACEON 4199 控制是否启用最新的查询优化器修复；MySQL 5.6 引入的 optimizer_trace 让 DBA 第一次看清优化器的内部决策。本文系统对比 45+ SQL 引擎在跟踪标志与调试开关方面的能力差异。

## 没有 SQL 标准

ISO/IEC 9075 系列标准 (SQL:1992 至 SQL:2023) 从未定义任何"跟踪"、"调试"、"诊断开关"语句或机制。标准只规定了 `GET DIAGNOSTICS` 用于获取上一条语句的执行信息（行数、错误状态等），但这是面向应用的错误处理接口，与数据库内部行为的可观察性和可调控性无关。

原因显而易见：

1. **跟踪是引擎内部实现细节**：哪些代码路径需要打印日志、哪些优化器规则可关闭，本质上是引擎实现的"私事"，标准化没有意义。
2. **每个引擎的内部架构差异巨大**：Oracle 的 oradebug 操作 SGA 内部状态、PostgreSQL 的 log_min_messages 控制日志级别、ClickHouse 的 send_logs_level 流式推送日志到客户端——这些机制的形态完全不同。
3. **稳定性不可承诺**：一旦标准化，引擎就必须长期维护这个跟踪点，但内部代码经常重构，不可能给所有内部钩子做向后兼容承诺。

结果是：**跟踪标志是 SQL 世界最具"厂商专属性"的特性之一**。同样的诊断需求，SQL Server DBA 用 DBCC TRACEON、Oracle DBA 用 ALTER SYSTEM SET EVENTS、PostgreSQL DBA 改 log_min_messages、MySQL DBA 用 optimizer_trace——彼此之间几乎没有可移植性。

## 支持矩阵

### 1. 跟踪机制总览

| 引擎 | 主要机制 | 关键字 / 命令 | 引入版本 |
|------|---------|---------------|----------|
| SQL Server | DBCC TRACEON/TRACEOFF + 启动参数 -T | `DBCC TRACEON (1117, -1)` | 早期 (6.x+) |
| Oracle | EVENTS + oradebug + tkprof | `ALTER SESSION SET EVENTS '10046 trace name context forever, level 12'` | v6 / v7 (1989) |
| PostgreSQL | log_min_messages + debug_print_* GUC | `SET log_min_messages = 'debug5'` | 早期 |
| MySQL | --debug 选项 + optimizer_trace | `SET SESSION optimizer_trace='enabled=on'` | 5.6 (2013) |
| MariaDB | 继承 MySQL + slow_query_log_filter | `SET optimizer_trace='enabled=on'` | 10.0+ |
| SQLite | 编译时 SQLITE_DEBUG + EXPLAIN | `.eqp on` (CLI) | 早期 |
| DB2 | db2trc + EXPLAIN | `db2trc on -m '*.*.*.*.*'` | 早期 |
| Snowflake | ALTER SESSION 调试参数 | `ALTER SESSION SET QUERY_TAG='debug'` | GA (有限) |
| BigQuery | --apilog (bq CLI) + Job 元数据 | bq --apilog | GA |
| Redshift | enable_result_cache_for_session 等 | `SET enable_result_cache_for_session=off` | 早期 |
| DuckDB | PRAGMA enable_profiling + 日志 | `PRAGMA enable_profiling='json'` | 0.3+ |
| ClickHouse | send_logs_level + 系统表 | `SET send_logs_level='trace'` | 早期 |
| Trino | session 属性 + 事件监听 | `SET SESSION query_max_run_time='5m'` | 早期 |
| Presto | session 属性 | `SET SESSION ...` | 早期 |
| Spark SQL | Conf + Listener API | `SET spark.sql.debug.maxToStringFields=100` | 1.0+ |
| Hive | hive.log.* 配置 | `SET hive.root.logger=DEBUG,console` | 早期 |
| Flink SQL | log4j + state.backend.rocksdb.* | `SET pipeline.name='debug'` | 1.10+ |
| Databricks | Spark Conf + Photon 调试 | `SET spark.databricks.io.cache.enabled=true` | GA |
| Teradata | DIAGNOSTIC 语句 | `DIAGNOSTIC HELPSTATS ON FOR SESSION` | V2R5+ |
| Greenplum | gp_debug_* GUC + log_min_messages | `SET gp_debug_linger='5min'` | 继承 PG |
| CockroachDB | crdb_internal + 集群 setting | `SET CLUSTER SETTING sql.trace.session_eventlog.enabled=true` | 1.0+ |
| TiDB | tidb_* 系统变量 + EXPLAIN ANALYZE | `SET tidb_general_log=1` | 早期 |
| OceanBase | OB_TRACE_LOG_HINT + tracing | `SELECT /*+ trace_log */ ...` | 4.0+ |
| YugabyteDB | yb_debug_* GUC | `SET yb_debug_log_internal_restarts=true` | 继承 PG |
| SingleStore | profile + plancache | `PROFILE SELECT ...` | 早期 |
| Vertica | profiling + dbLog | `PROFILE SELECT ...` | 早期 |
| Impala | impalad --logtostderr 等启动参数 | EXPLAIN_LEVEL=2 | 早期 |
| StarRocks | enable_profile + audit log | `SET enable_profile=true` | 1.x+ |
| Doris | enable_profile | `SET is_report_success=true` (旧) | 早期 |
| MonetDB | TRACE 语句 | `TRACE SELECT ...` | 早期 |
| CrateDB | -- | -- | 不支持 |
| TimescaleDB | timescaledb.debug | `SET timescaledb.debug_compression=true` | 继承 PG |
| QuestDB | 日志级别 | log4j 配置 | 早期 |
| Exasol | EXAPlus / EXAOPERATION | -- | 早期 |
| SAP HANA | 跟踪文件 + ALTER SYSTEM ALTER CONFIGURATION | `ALTER SYSTEM ALTER CONFIGURATION ('indexserver.ini', 'system') SET ('trace', 'sql') = 'debug'` | 1.0+ |
| Informix | onstat / onmode | `onmode -I 26000,1` | 早期 |
| Firebird | trace API + tracemgr | fbtracemgr -se -a | 2.5+ |
| H2 | TRACE_LEVEL_FILE / TRACE_LEVEL_SYSTEM_OUT | `SET TRACE_LEVEL_FILE 4` | 早期 |
| HSQLDB | TRACE 选项 (启动参数) | `--trace true` | 早期 |
| Derby | derby.language.logQueryPlan | -Dderby.language.logQueryPlan=true | 早期 |
| Amazon Athena | 工作组日志 + CloudWatch | -- (云服务) | GA |
| Azure Synapse | DBCC TRACEON (兼容 SQL Server) + Azure Monitor | `DBCC TRACEON (...)` | GA |
| Google Spanner | request_options.priority | gRPC 元数据 | GA |
| Materialize | mz_introspection schema | `SET CLUSTER='mz_introspection'` | GA |
| RisingWave | rw_internal | `SET visibility_mode='checkpoint'` | GA |
| InfluxDB (SQL) | -- | -- | 不支持 |
| Databend | profile + system tables | `SET enable_query_log=1` | GA |
| Yellowbrick | sys.log_query + diagnose | -- | GA |
| Firebolt | engine history + SET | `SET log_level='debug'` | GA |

> 统计：约 30 个引擎提供 SQL 级跟踪开关 (DBCC/SET/ALTER SESSION)，约 10 个引擎依赖启动参数或外部命令，约 5 个引擎完全没有内置跟踪能力。

### 2. 会话作用域 vs 全局作用域

| 引擎 | 会话级开关 | 全局级开关 | 全局立即生效 | 全局需重启 |
|------|----------|----------|-----------|----------|
| SQL Server | `DBCC TRACEON(N)` | `DBCC TRACEON(N, -1)` | 是 | 启动参数 -T |
| Oracle | `ALTER SESSION SET EVENTS '...'` | `ALTER SYSTEM SET EVENTS '...'` | 是 (`SCOPE=MEMORY`) | `SCOPE=SPFILE` |
| PostgreSQL | `SET log_min_messages='debug5'` | `ALTER SYSTEM SET log_min_messages='debug5'` | reload (大多数) | 部分需 restart |
| MySQL | `SET SESSION optimizer_trace=...` | `SET GLOBAL optimizer_trace=...` | 是 (新会话) | innodb_* 部分需重启 |
| MariaDB | `SET SESSION optimizer_trace=...` | `SET GLOBAL optimizer_trace=...` | 是 (新会话) | 部分需重启 |
| DB2 | db2trc on (实例级) | db2trc on (实例级) | 是 | -- |
| Snowflake | `ALTER SESSION SET ...` | `ALTER ACCOUNT SET ...` | 是 | -- |
| Redshift | `SET param=...` | `ALTER USER ... SET ...` (持久) | 是 | -- |
| ClickHouse | `SET send_logs_level=...` | profile 文件 | 是 | -- |
| Trino | `SET SESSION key=value` | catalog/jvm.config | 是 | 是 |
| Spark SQL | `SET spark.sql.x=y` | spark-defaults.conf | 是 | -- |
| Teradata | `DIAGNOSTIC ... FOR SESSION` | `DIAGNOSTIC ... FOR SYSTEM` | 是 | -- |
| Greenplum | `SET gp_debug_linger='5min'` | `ALTER SYSTEM SET ...` | reload | 部分需 restart |
| CockroachDB | `SET ...` | `SET CLUSTER SETTING ...` | 是 | -- |
| TiDB | `SET tidb_general_log=1` | `SET GLOBAL tidb_general_log=1` | 是 (新会话) | -- |
| SAP HANA | `ALTER SYSTEM ... LAYER='SESSION'` | `ALTER SYSTEM ... LAYER='SYSTEM'` | 是 | -- |
| H2 | `SET TRACE_LEVEL_FILE 4` (会话隐式继承) | jdbc URL 参数 | 是 | -- |

### 3. 文档化 vs 未文档化 (Documented vs Undocumented)

| 引擎 | 官方文档化跟踪标志 | 未文档化但社区已知 | 未文档化的支持立场 |
|------|------------------|-----------------|------------------|
| SQL Server | 约 20-30 个常用 TF (1117/1118/4199/9481 等) | 数百个 (TF 8649/8666/2371 等) | 部分情况官方支持 |
| Oracle | 部分 events (10046/10053) | 数千个 events | 仅在 MyOracleSupport 提供，不公开 |
| PostgreSQL | log_min_messages / debug_print_plan | -- (大多通过源码可见) | GUC 系统对所有用户可见 |
| MySQL | --debug + optimizer_trace | DBUG 标签 (源码 dbug.c) | optimizer_trace 文档化，--debug 半文档 |
| DB2 | db2trc 部分级别文档化 | 数百个 trace mask | 大部分需 IBM 支持指导 |
| Oracle | _ 开头隐藏参数 | 数千个 (`_disable_logging` 等) | 严禁生产环境使用 |
| Snowflake | 公开参数有限 | 部分内部参数 | 需 Snowflake 支持启用 |
| ClickHouse | send_logs_level 等 | system.* 表 | 全部可用 |
| Greenplum | gp_log_* 部分 GUC | gp_debug_linger 等 | 工程师指导使用 |

> 关键观察：**SQL Server、Oracle、DB2 这类传统商用数据库有大量未文档化的跟踪标志**，往往只有原厂支持工程师才知道完整列表。开源数据库 (PG/MySQL/CH) 通常将所有调试开关设计为正式 GUC/参数，不存在"隐藏开关"的概念。

### 4. 重启后的持久性

| 引擎 | 会话级跟踪重启后 | 全局级跟踪重启后 | 持久化方法 |
|------|----------------|----------------|----------|
| SQL Server | 失效 | 失效 (除非用 -T 启动参数) | mssqlserver.exe -T9481 启动参数 |
| Oracle | 失效 | 取决于 SCOPE | `SCOPE=SPFILE` 持久；`SCOPE=MEMORY` 不持久 |
| PostgreSQL | 失效 | 由 ALTER SYSTEM 写入 postgresql.auto.conf | postgresql.conf 或 postgresql.auto.conf |
| MySQL | 失效 | SET PERSIST 写入 mysqld-auto.cnf | my.cnf 或 SET PERSIST (8.0+) |
| MariaDB | 失效 | my.cnf | my.cnf |
| DB2 | 失效 (db2trc 是实例级) | 失效 | db2set 注册表变量 |
| Snowflake | 失效 | account 级永久 (除非显式 UNSET) | ALTER ACCOUNT SET ... |
| ClickHouse | 失效 | profile 文件 | users.xml profile |
| Trino | 失效 | catalog properties 文件 | catalog/*.properties |
| CockroachDB | 失效 | CLUSTER SETTING 持久存储 | 集群表 system.settings |
| TiDB | 失效 | GLOBAL 写入 mysql.tidb 表 | GLOBAL 自动持久 |
| SAP HANA | 失效 (SESSION 层) | SYSTEM 层持久到 .ini | indexserver.ini |
| H2 | 失效 | jdbc URL 持久 | jdbc:h2:mem:test;TRACE_LEVEL_FILE=4 |

### 5. 云数据库的支持情况

| 云数据库 | 是否支持跟踪标志 | 限制 | 备注 |
|---------|--------------|------|------|
| Aurora MySQL | 受限 | 只允许部分参数 | DB Parameter Group 控制 |
| Aurora PostgreSQL | 受限 | 不允许部分 GUC | DB Parameter Group |
| RDS for SQL Server | 部分 TF 允许 | 通过 Parameter Group + custom DB Engine Version | TF 1117/1118/3604 等可设 |
| RDS for Oracle | 受限 | 不允许 oradebug, ALTER SYSTEM SET EVENTS 受限 | 需通过 Oracle 包装包 |
| Cloud SQL (MySQL/PG) | 受限 | 仅 flags 白名单 | --enable-cloud-sql-proxy-flags |
| Cloud SQL for SQL Server | 部分 | TF 通过 console flags | 受限白名单 |
| Azure SQL Database | 不支持 DBCC TRACEON | 替代品: ALTER DATABASE SCOPED CONFIGURATION | 部分 TF 行为通过 DSCS 配置 |
| Azure Database for MySQL | 受限 | server parameter | 控制台白名单 |
| Snowflake | 有限 | account / session 级 | 不暴露内部 trace |
| BigQuery | 否 | 无内部 trace 暴露 | 仅查询信息 (Job stats) |
| Redshift | 受限 | 仅文档化的 GUC | parameter group |
| Athena | 否 | -- | -- |
| Databricks | 部分 | Spark Conf 部分允许 | -- |
| Aurora DSQL | 否 | 极简 | -- |
| Spanner | 否 | 仅 RPC priority | request options |
| AlloyDB | 受限 | 仅 PG GUC 白名单 | -- |

云数据库整体趋势：**禁用底层 trace 标志，提供高层可观测性 (slow query, query insights, performance schema)**。原因：

1. **多租户隔离**：低层 trace 可能泄露其他租户信息或影响其他租户性能
2. **云厂商需要稳定 SLA**：让用户随意启用 trace 可能引发未预期的故障
3. **替代方案完善**：云厂商提供了 Performance Insights、Query Insights、Cloud Logging 等高层工具

## 各引擎详解

### SQL Server: DBCC TRACEON / TRACEOFF + 启动参数 -T

SQL Server 的跟踪标志 (Trace Flag, TF) 体系是商用数据库中最完整、文档化最好、社区研究最深的。从 SQL Server 6.x 开始就有 DBCC TRACEON 命令，至今 (2026) 已积累 200+ 个文档化或半文档化的 TF。

```sql
-- 启用会话级跟踪标志 (仅当前连接生效)
DBCC TRACEON (3604);  -- 将跟踪输出从错误日志重定向到客户端

-- 启用全局跟踪标志 (-1 表示全局，所有会话生效)
DBCC TRACEON (1117, -1);

-- 关闭跟踪标志
DBCC TRACEOFF (1117, -1);

-- 查看当前活动的跟踪标志
DBCC TRACESTATUS;
DBCC TRACESTATUS(-1);  -- 查看全局
DBCC TRACESTATUS(1117, 1118);  -- 查询特定 TF

-- 查看跟踪输出 (需先开 3604)
DBCC TRACEON (3604, 9481);
SELECT * FROM big_table WHERE id = 100;  -- 优化器输出可见
```

**启动参数 -T (重启持久)**：

```bash
# Windows (服务配置)
sqlservr.exe -T1117 -T1118 -T4199

# 或在 SQL Server Configuration Manager 中:
# 服务属性 → 启动参数 → 添加 "-T1117"
```

**SQL Server 高频跟踪标志详解**：

| TF | 类别 | 作用 | 默认 (2016+) |
|----|------|------|------------|
| 1117 | tempdb | 当一个数据文件满时所有文件一起增长 (避免单文件偏大) | 2016+ 默认行为 |
| 1118 | tempdb | tempdb 全部使用统一区分配 (避免 SGAM 争用) | 2016+ 默认行为 |
| 1224 | 锁 | 禁用基于锁数量的锁升级 (但仍按内存压力升级) | 关闭 |
| 1118 (用户表) | 行存储 | 禁用混合区分配 (适用于所有表) | 关闭 |
| 2371 | 统计信息 | 触发统计信息更新的阈值动态调整 (大表更敏感) | 2016+ 默认行为 |
| 3023 | 备份 | 改变 BACKUP 默认 CHECKSUM 行为 | 关闭 |
| 3226 | 备份 | 抑制错误日志中的成功备份记录 | 关闭 |
| 3604 | 输出 | 将 DBCC 输出从错误日志重定向到客户端 | 关闭 |
| 3605 | 输出 | 将 DBCC 输出写入错误日志 | 关闭 |
| 4199 | 优化器 | 启用查询优化器修复程序 (后续 CU 中的 fix) | 关闭 (需显式启用) |
| 7412 | 性能 | 启用轻量级查询执行统计信息基础结构 | 2016+ 默认行为 |
| 8048 | 内存 | 将 NUMA 节点分区扩展到对象级别 (减少 spinlock 争用) | 关闭 |
| 8602 | 优化器 | 禁用提示 OPTION (FORCE ORDER) | 关闭 |
| 8649 | 并行 | 强制并行计划 (DOP=1 也并行) | 未文档化 |
| 8666 | 优化器 | 输出更详细的查询计划 XML 调试信息 | 未文档化 |
| 9481 | 优化器 | 强制使用 SQL Server 2012 及之前的 CE (基数估计器) | 关闭 (默认用新 CE) |
| 9485 | 优化器 | 禁用 SELECT 权限检查 (用于内存内 OLTP 调试) | 未文档化 |
| 9495 | 复制 | 禁用复制内存清理 | 未文档化 |
| 9806 | 备份 | 禁用快照备份的元数据标头读取 | 未文档化 |

**TF 1117/1118 的演进**：

```sql
-- SQL Server 2014 及更早: 必须显式启用
DBCC TRACEON (1117, 1118, -1);

-- SQL Server 2016+: 这些行为成为 tempdb 的默认配置
-- 通过 sys.databases 中的列暴露，无需 TF
SELECT name, is_mixed_page_allocation_on, is_autogrow_all_files
FROM sys.databases WHERE name = 'tempdb';

-- 2016+ 也可通过 ALTER DATABASE 单独配置
ALTER DATABASE tempdb MODIFY FILEGROUP [PRIMARY] AUTOGROW_ALL_FILES;
ALTER DATABASE tempdb SET MIXED_PAGE_ALLOCATION OFF;
```

**TF 4199 的复杂性**：

```sql
-- TF 4199 启用所有"由 CU 引入的查询优化器修复"
-- 默认关闭以保持升级时计划稳定性
DBCC TRACEON (4199, -1);

-- SQL Server 2016 SP1+ 引入数据库级配置 (替代 TF 4199):
ALTER DATABASE SCOPED CONFIGURATION SET QUERY_OPTIMIZER_HOTFIXES = ON;

-- 兼容级别 130 + DSCS 等价于 TF 4199 的早期版本效果
ALTER DATABASE MyDB SET COMPATIBILITY_LEVEL = 160;
```

**TF 9481 (旧版基数估计器)**：

```sql
-- SQL Server 2014 引入新 CE (Cardinality Estimator)
-- 部分查询性能可能因新 CE 回归
-- 解决方案 1: 数据库级回退到旧 CE
ALTER DATABASE MyDB SET COMPATIBILITY_LEVEL = 110;  -- 2012 行为

-- 解决方案 2: 兼容级别保持 130+, 但用 TF 9481 强制旧 CE
DBCC TRACEON (9481, -1);

-- 解决方案 3: 单查询级 hint (推荐, 影响最小)
SELECT * FROM big_table
WHERE order_date > '2024-01-01'
OPTION (USE HINT('FORCE_LEGACY_CARDINALITY_ESTIMATION'));
```

### Oracle: EVENTS + oradebug

Oracle 的诊断体系比 SQL Server 更深邃但也更危险。Oracle 不叫 trace flag，叫 **event** (事件)，编号通常是 5 位数字 (10000-65000)。

```sql
-- 会话级启用事件 10046 (SQL trace)
ALTER SESSION SET EVENTS '10046 trace name context forever, level 12';

-- 关闭事件
ALTER SESSION SET EVENTS '10046 trace name context off';

-- 系统级启用 (所有会话)
ALTER SYSTEM SET EVENTS '10046 trace name context forever, level 12';

-- 多个事件同时启用
ALTER SESSION SET EVENTS '10046 trace name context forever, level 12 :
                          10053 trace name context forever, level 1';
```

**Oracle Event 10046: SQL Trace 的祖师爷**：

10046 是 Oracle DBA 的"金钥匙"，自 Oracle v7 (1992) 就存在，至今仍是诊断 SQL 性能问题的首选工具。

| Level | 含义 |
|-------|------|
| 1 | 启用基础 SQL trace (等同于 SQL_TRACE = TRUE) |
| 4 | Level 1 + 绑定变量值 |
| 8 | Level 1 + 等待事件 |
| 12 | Level 1 + 绑定变量 + 等待事件 (最常用，"全息" trace) |
| 16 | 12c+ 包含 STAT 行级别统计 |

```sql
-- 经典工作流程
-- 1. 启用 trace
ALTER SESSION SET EVENTS '10046 trace name context forever, level 12';

-- 2. 找到 trace 文件位置
SELECT VALUE FROM v$diag_info WHERE NAME = 'Default Trace File';
-- 输出类似: /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_ora_12345.trc

-- 3. 执行需要诊断的 SQL
SELECT /* my_problem_query */ * FROM orders WHERE customer_id = 12345;

-- 4. 关闭 trace
ALTER SESSION SET EVENTS '10046 trace name context off';

-- 5. 用 tkprof 格式化 trace 文件
-- shell> tkprof orcl_ora_12345.trc output.txt explain=user/pwd sys=no
-- output.txt 包含每条 SQL 的执行计划、IO 统计、CPU 时间、绑定变量
```

**Oracle Event 10053: CBO Trace (优化器决策日志)**：

10053 输出 CBO (Cost-Based Optimizer) 的全部决策过程：每个候选计划的代价、统计信息使用、转换规则触发情况。

```sql
-- 启用 CBO trace (注意: 仅对硬解析生效)
ALTER SESSION SET EVENTS '10053 trace name context forever, level 1';

-- 触发硬解析
ALTER SYSTEM FLUSH SHARED_POOL;
SELECT * FROM big_table WHERE col_a = 100 AND col_b = 200;

-- 关闭
ALTER SESSION SET EVENTS '10053 trace name context off';

-- trace 文件中可看到:
-- - 表统计信息 (NDV, density)
-- - 候选 access path 及其代价
-- - JOIN ORDER 枚举 (n! 个排列)
-- - 转换规则应用 (subquery unnesting, view merging)
-- - 最终选择的计划及其代价
```

**oradebug: SGA 内部状态操作**：

```sql
-- 进入 oradebug (sysdba)
sqlplus / as sysdba
SQL> ORADEBUG SETMYPID;        -- 附加到当前会话
SQL> ORADEBUG SETOSPID 12345;  -- 附加到指定 OS 进程

-- 启用事件
SQL> ORADEBUG EVENT 10046 TRACE NAME CONTEXT FOREVER, LEVEL 12;

-- 获取 trace 文件路径
SQL> ORADEBUG TRACEFILE_NAME;

-- 转储进程内部状态
SQL> ORADEBUG DUMP HEAPDUMP 5;       -- 堆内存转储
SQL> ORADEBUG DUMP PROCESSSTATE 10;  -- 进程状态
SQL> ORADEBUG DUMP SYSTEMSTATE 10;   -- 全系统状态
SQL> ORADEBUG DUMP ERRORSTACK 3;     -- 错误堆栈

-- 危险操作 (生产慎用):
SQL> ORADEBUG POKE address length value;  -- 直接写内存
SQL> ORADEBUG CALL function arg1 arg2;    -- 调用内部函数
```

**Oracle 隐藏参数 (_ 开头)**：

```sql
-- 查看所有隐藏参数 (sys 用户)
SELECT a.ksppinm  AS name,
       b.ksppstvl AS value,
       a.ksppdesc AS description
FROM   x$ksppi  a,
       x$ksppcv b
WHERE  a.indx = b.indx
  AND  a.ksppinm LIKE '\_%' ESCAPE '\'
ORDER BY a.ksppinm;

-- 常见隐藏参数:
-- _allow_resetlogs_corruption: RESETLOGS 时允许块损坏 (灾难恢复)
-- _disable_logging: 关闭 redo (极度危险，仅测试用)
-- _optimizer_use_feedback: 12c+ 自动调优反馈
-- _gc_files_to_lock: RAC 全局缓存锁定文件控制
-- _sql_compatibility: SQL 兼容性级别

-- 修改 (sysdba, 严禁生产):
ALTER SYSTEM SET "_optimizer_use_feedback" = FALSE SCOPE=SPFILE;
```

> Oracle 隐藏参数文档完全保密在 MyOracleSupport (My Oracle Support) 内部，对外只有 Tanel Poder、Maris Elsins 等顶级 DBA 通过逆向研究公开了部分。生产环境严禁随意修改，必须 Oracle Support 书面授权。

### PostgreSQL: log_min_messages + debug_print_*

PostgreSQL 没有"trace flag"概念，所有调试开关都是正式 GUC (Grand Unified Configuration) 参数。

```sql
-- 设置日志级别 (会话级)
SET log_min_messages = 'debug5';

-- 全局 (需 superuser)
ALTER SYSTEM SET log_min_messages = 'debug5';
SELECT pg_reload_conf();

-- 日志级别 (从详细到简略):
-- debug5, debug4, debug3, debug2, debug1, log, notice, warning, error, fatal, panic
SHOW log_min_messages;
```

**PostgreSQL 调试相关 GUC 大全**：

| 参数 | 作用 | 默认 |
|------|------|------|
| log_min_messages | 服务器日志最低级别 | warning |
| client_min_messages | 客户端消息最低级别 | notice |
| log_min_error_statement | 引发指定级别错误的语句也记录 | error |
| log_min_duration_statement | 慢查询日志阈值 (ms) | -1 (关闭) |
| log_statement | 'none' / 'ddl' / 'mod' / 'all' | none |
| log_duration | 记录每条语句执行时间 | off |
| log_lock_waits | 记录锁等待 | off |
| log_temp_files | 记录大于指定大小的临时文件 | -1 |
| log_checkpoints | 记录 checkpoint 信息 | off |
| log_connections | 记录连接 | off |
| log_disconnections | 记录断开 | off |
| debug_print_parse | 输出 parse tree | off |
| debug_print_rewritten | 输出 rewritten parse tree | off |
| debug_print_plan | 输出执行计划 | off |
| debug_pretty_print | 美化 debug_print_* 输出 | on |
| trace_notify | 跟踪 LISTEN/NOTIFY | off |
| trace_sort | 跟踪排序操作 | off |
| trace_locks | 跟踪锁操作 (需编译时开 LOCK_DEBUG) | off |
| trace_lwlocks | 跟踪轻量级锁 (需编译时开) | off |
| trace_userlocks | 跟踪用户锁 (需编译时开) | off |
| log_planner_stats | 计划器统计信息 | off |
| log_executor_stats | 执行器统计信息 | off |
| log_statement_stats | 整体语句统计 | off |
| jit_debugging_support | JIT 调试器支持 (LLVM) | off |

```sql
-- 经典调试组合
SET client_min_messages = 'debug1';
SET debug_print_plan = on;
SET debug_pretty_print = on;
EXPLAIN ANALYZE SELECT * FROM big_table WHERE id = 100;

-- 输出 parse tree (深入分析查询解析)
SET debug_print_parse = on;
SELECT * FROM users WHERE name LIKE 'A%';
```

### MySQL: --debug + optimizer_trace

MySQL 的调试机制分两类：

1. **DBUG library** (dbug.c)：编译时启用的内部跟踪框架，只有 debug 编译版本可用
2. **optimizer_trace**：5.6 (2013) 引入的 SQL 级优化器跟踪，所有版本可用

**optimizer_trace (5.6+ 文档化的优化器跟踪)**：

```sql
-- 启用 optimizer trace (会话级)
SET SESSION optimizer_trace='enabled=on';
SET SESSION optimizer_trace_max_mem_size=1000000;  -- 1MB

-- 执行需要分析的 SQL
SELECT * FROM orders o
JOIN customers c ON o.customer_id = c.id
WHERE c.country = 'US' AND o.order_date > '2024-01-01';

-- 查看 trace 输出 (JSON 格式)
SELECT * FROM information_schema.OPTIMIZER_TRACE\G

-- 关闭
SET SESSION optimizer_trace='enabled=off';
```

**optimizer_trace 输出包含**：

- 每个表的访问方法 (access path) 选择过程
- JOIN 顺序的全部排列代价
- range optimizer 的范围分析
- ICP (Index Condition Pushdown) 推送决策
- MRR (Multi-Range Read) 优化决定
- 半连接 (semi-join) 转换决策
- 子查询展开 (subquery materialization vs IN-to-EXISTS)

```sql
-- 多步 trace 控制
SET SESSION optimizer_trace_offset=-1;       -- 最后一条
SET SESSION optimizer_trace_limit=5;         -- 保留最后 5 条
SET SESSION end_markers_in_json=on;          -- JSON 中加注释
SET SESSION optimizer_trace_features='greedy_search=on,
    range_optimizer=on, dynamic_range=on, repeated_subselect=on';
```

**--debug 选项 (DBUG library)**：

```bash
# 启动 mysqld 时启用 (需 debug 编译版本)
mysqld --debug=d:t:i:o,/tmp/mysqld.trace

# 格式: <flags>:<options>
# d  - 启用 DBUG_<level> 输出
# t  - 跟踪函数 enter/exit
# i  - 函数缩进
# o,file - 输出到文件
# F  - 文件名
# L  - 行号
# l  - 进程 ID
# p,key1,key2 - 仅跟踪指定 keyword (如 "p,sql,opt")

# 在线启用 (会话级)
SET SESSION debug='d:t:O,/tmp/session.trace';
SET SESSION debug='-d:t';  -- 禁用 (减号前缀)
```

**MySQL 系统变量 (跟踪相关)**：

```sql
-- 通用查询日志 (记录所有 SQL)
SET GLOBAL general_log = 'ON';
SET GLOBAL general_log_file = '/var/log/mysql/general.log';

-- 慢查询日志
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 1.0;  -- 秒
SET GLOBAL log_queries_not_using_indexes = 'ON';

-- Performance Schema (高级)
UPDATE performance_schema.setup_consumers
SET ENABLED = 'YES'
WHERE NAME LIKE '%statement%';

-- InnoDB monitor (定期输出 InnoDB 内部状态)
SET GLOBAL innodb_status_output = 'ON';
SET GLOBAL innodb_status_output_locks = 'ON';
-- 输出可在 ERROR LOG 中看到，每 ~15 秒一次
```

### DB2: db2trc + EXPLAIN

DB2 的 `db2trc` 是命令行工具，提供与 Oracle event 和 SQL Server TF 类似的内部跟踪能力。

```bash
# 启用所有跟踪
db2trc on -m '*.*.*.*.*'

# 仅跟踪 SQL compiler
db2trc on -m '*.*.SQO.*.*'

# 启用并指定缓冲区大小
db2trc on -l 64M

# 转储到文件
db2trc dump trace.dmp

# 格式化 (字符可读)
db2trc fmt trace.dmp trace.fmt

# 流程化 (按时间顺序)
db2trc flw trace.dmp trace.flw

# 关闭
db2trc off
```

**db2trc mask 格式**：`<rec_type>.<event>.<product>.<component>.<function>`

| 位置 | 含义 | 例 |
|------|------|------|
| rec_type | 记录类型 | dat (数据), err (错误), * (全部) |
| event | 事件 | entry, exit, retcode, * |
| product | 产品组件 | DB2, OSSE, RDS, * |
| component | 子组件 | SQO (SQL Optimizer), SQL, BPS (buffer pool), * |
| function | 函数 | sqlnoSetup, * |

**SQL 级跟踪**：

```sql
-- 设置注册表变量 (实例级)
db2set DB2COMM=TCPIP
db2set DB2_FMP_COMM_HEAPSZ=8192

-- 在线参数变更 (动态)
UPDATE DBM CFG USING DIAGLEVEL 4;  -- 详细诊断日志
UPDATE DB CFG FOR mydb USING LOGRETAIN ON;

-- EXPLAIN 跟踪
DELETE FROM EXPLAIN_INSTANCE;
SET CURRENT EXPLAIN MODE EXPLAIN;  -- 仅 EXPLAIN, 不执行
SELECT * FROM big_table WHERE col = 100;
SET CURRENT EXPLAIN MODE NO;

-- 查看 explain 结果
db2exfmt -d mydb -1 -o explain.out
```

### Trino / Presto: Session Properties

Trino 没有传统的"trace flag"概念，但提供了大量 session properties 用于调试和性能调优。

```sql
-- 查看所有 session properties
SHOW SESSION;

-- 特定 catalog 的属性
SHOW SESSION LIKE 'hive.%';

-- 设置 session property (仅当前 session)
SET SESSION query_max_run_time = '1h';
SET SESSION query_max_memory_per_node = '4GB';

-- 重置
RESET SESSION query_max_run_time;
```

**Trino 调试相关 session properties**：

| 属性 | 作用 |
|------|------|
| query_max_run_time | 单查询最长运行时间 |
| query_max_memory | 单查询全集群内存上限 |
| query_max_memory_per_node | 单节点内存上限 |
| join_distribution_type | PARTITIONED / BROADCAST / AUTOMATIC |
| join_reordering_strategy | NONE / ELIMINATE_CROSS_JOINS / AUTOMATIC |
| optimizer.enable_intermediate_aggregations | 中间聚合优化 |
| optimizer.dictionary_aggregation | 字典聚合优化 |
| optimize_metadata_queries | 元数据查询优化 (仅 COUNT/MIN/MAX) |
| use_preferred_write_partitioning | 写入分区策略 |
| prefer_partial_aggregation | 偏好部分聚合 |
| dynamic_filtering_enabled | 启用动态过滤 |
| spill_enabled | 内存不足时溢写到磁盘 |

**Trino 事件监听器 (EventListener SPI)**：

```java
// trino-server/etc/event-listener.properties
event-listener.name=my-event-listener
event-listener.host=localhost
event-listener.port=8080

// 自定义实现 io.trino.spi.eventlistener.EventListener
public class MyEventListener implements EventListener {
    @Override
    public void queryCreated(QueryCreatedEvent event) { ... }

    @Override
    public void queryCompleted(QueryCompletedEvent event) { ... }

    @Override
    public void splitCompleted(SplitCompletedEvent event) { ... }
}
```

### Snowflake: ALTER SESSION 调试参数 (有限)

Snowflake 作为云原生数据库，故意不暴露太多内部跟踪能力。少数可调参数：

```sql
-- 设置 query tag (用于在 QUERY_HISTORY 中过滤)
ALTER SESSION SET QUERY_TAG = 'debug_session_001';

-- 启用复杂查询的查询审计
ALTER SESSION SET TRACE_LEVEL = 'ALWAYS';  -- 仅 sproc 内 SYSTEM$LOG 函数有效

-- 查询历史 + 元数据
SELECT query_id, query_text, execution_status, error_code, error_message,
       total_elapsed_time, bytes_scanned, rows_produced
FROM table(information_schema.query_history())
WHERE query_tag = 'debug_session_001'
ORDER BY start_time DESC;

-- EXPLAIN
EXPLAIN USING JSON SELECT * FROM big_table WHERE col = 100;
EXPLAIN USING TEXT SELECT * FROM big_table WHERE col = 100;

-- Query Profile (Web UI 提供详细 trace, SQL 不直接可用)
-- 需在 Web UI Snowsight 中点击查询查看可视化 profile
```

**Snowflake account 级调试参数**：

```sql
-- account 级的某些参数仅 ACCOUNTADMIN 可改
-- 需联系 Snowflake Support 启用部分内部参数
ALTER ACCOUNT SET STATEMENT_TIMEOUT_IN_SECONDS = 7200;
ALTER ACCOUNT SET QUERY_TAG = 'global-monitoring';

-- 查看所有可见参数
SHOW PARAMETERS IN ACCOUNT;
SHOW PARAMETERS IN SESSION;
```

### ClickHouse: SET send_logs_level

ClickHouse 提供独特的"流式日志推送"机制：执行查询时把日志直接通过协议返回给客户端。

```sql
-- 启用日志推送 (会话级)
SET send_logs_level = 'trace';
-- 级别: 'fatal', 'critical', 'error', 'warning', 'notice', 'information', 'debug', 'trace', 'test'

SELECT count() FROM big_table WHERE col = 100;
-- 客户端 (clickhouse-client) 会同时收到查询结果和日志输出
-- 例如:
--   <Information> ContextAccess (default): Granted: SELECT(col) ON test.big_table
--   <Trace> InterpreterSelectQuery: FetchColumns -> Complete
--   <Debug> MergeTreeBaseSelectProcessor: Reading approx. 1000000 rows
--   <Trace> InterpreterSelectQuery: The query is executed in 0.123 sec
```

**ClickHouse 系统日志表**：

```sql
-- 查询日志 (默认开启)
SELECT query_id, query, type, event_time,
       query_duration_ms, read_rows, written_rows, exception
FROM system.query_log
WHERE event_date >= today()
ORDER BY event_time DESC
LIMIT 10;

-- 查询线程日志 (默认关闭)
SET log_queries = 1;
SET log_query_threads = 1;
SELECT * FROM system.query_thread_log WHERE event_date = today();

-- 文本日志 (服务器日志)
SELECT * FROM system.text_log WHERE event_date = today() AND level = 'Trace';

-- profile 事件 (内部计数器)
SELECT event, value FROM system.events WHERE value > 0 ORDER BY value DESC;

-- 查询过程中的 metric
SELECT * FROM system.metric_log WHERE event_date = today() ORDER BY event_time DESC LIMIT 1;
```

### MariaDB: 继承 MySQL + 扩展

MariaDB 继承了 MySQL 的全部跟踪机制，同时在自身添加了几个独有的：

```sql
-- 优化器 trace (与 MySQL 兼容)
SET SESSION optimizer_trace = 'enabled=on';
SELECT * FROM information_schema.OPTIMIZER_TRACE;

-- MariaDB 特有: 慢查询日志过滤器
SET GLOBAL slow_query_log_filter = 'admin,filesort';

-- ANALYZE FORMAT=JSON (MariaDB 独有, 实际执行 + JSON 计划)
ANALYZE FORMAT=JSON SELECT * FROM big_table WHERE col = 100;

-- SHOW EXPLAIN FOR <thread_id> (查看其他会话当前查询计划)
SHOW EXPLAIN FOR 12345;
```

### CockroachDB: SET CLUSTER SETTING

CockroachDB 是云原生分布式数据库，所有"trace flag"都设计成正式的 cluster settings。

```sql
-- 列出所有 cluster settings (需 admin)
SELECT * FROM crdb_internal.cluster_settings;

-- 启用 SQL trace
SET CLUSTER SETTING sql.trace.session_eventlog.enabled = true;
SET CLUSTER SETTING sql.trace.txn.enable_threshold = '1s';
SET CLUSTER SETTING sql.trace.stmt.enable_threshold = '500ms';

-- 启用 jaeger / zipkin 分布式 trace
SET CLUSTER SETTING trace.zipkin.collector = 'localhost:9411';
SET CLUSTER SETTING trace.jaeger.agent = 'localhost:6831';

-- 单查询 trace
SET tracing = on;
SELECT * FROM big_table WHERE id = 100;
SET tracing = off;
SHOW TRACE FOR SESSION;

-- 显示已记录的 trace
SELECT * FROM crdb_internal.session_trace;
```

### TiDB: tidb_* 系统变量

TiDB 兼容 MySQL 协议，但内部添加了大量 `tidb_` 前缀的调试变量。

```sql
-- 启用通用查询日志
SET GLOBAL tidb_general_log = 1;

-- 慢查询阈值
SET GLOBAL tidb_slow_query_file = '/var/log/tidb/slow.log';

-- 启用统计信息收集 trace
SET tidb_enable_collect_execution_info = 1;

-- 查询级 trace
TRACE SELECT * FROM big_table WHERE id = 100;
TRACE FORMAT='json' SELECT * FROM big_table WHERE id = 100;
TRACE PLAN SELECT * FROM big_table WHERE id = 100;

-- EXPLAIN ANALYZE (实际执行 + 详细统计)
EXPLAIN ANALYZE SELECT * FROM big_table WHERE id = 100;

-- TiDB 内部表 (类似 PG 的 pg_stat_*)
SELECT * FROM information_schema.cluster_statements_summary
WHERE digest_text LIKE '%big_table%' ORDER BY exec_count DESC;

SELECT * FROM information_schema.tidb_trx;       -- 当前事务
SELECT * FROM information_schema.cluster_slow_query;  -- 慢查询
```

### OceanBase: trace_log hint

OceanBase 兼容 Oracle 模式时支持 ALTER SYSTEM SET EVENTS，但本身有独有的 trace_log hint 机制。

```sql
-- hint 形式启用 trace (推荐, 单语句生效)
SELECT /*+ trace_log */ * FROM big_table WHERE id = 100;

-- 系统变量
SET ob_enable_trace_log = 1;
SET ob_enable_show_trace = 1;

-- SHOW TRACE 获取最近一次的 trace
SHOW TRACE;
SELECT * FROM oceanbase.gv$ob_sql_audit
WHERE query_sql LIKE '%big_table%' ORDER BY request_time DESC LIMIT 10;

-- Oracle 模式: 兼容 ALTER SYSTEM SET EVENTS
-- 注意: 仅部分 event 实现, 不是全部 Oracle event 都支持
ALTER SYSTEM SET EVENTS '10046 trace name context forever, level 12';
```

### DuckDB: PRAGMA enable_profiling

DuckDB 作为嵌入式分析数据库，调试机制简洁直接。

```sql
-- 启用查询 profiling
PRAGMA enable_profiling = 'json';   -- 或 'text', 'query_tree', 'no_output'
PRAGMA profile_output = '/tmp/profile.json';

SELECT count() FROM big_table;
-- 执行后 /tmp/profile.json 包含详细的算子级统计

-- 关闭
PRAGMA disable_profiling;

-- EXPLAIN ANALYZE
EXPLAIN ANALYZE SELECT * FROM big_table WHERE col = 100;

-- 设置日志详细度
PRAGMA enable_progress_bar;       -- 进度条
PRAGMA log_query_path = '/tmp/queries.log';  -- 记录所有 SQL
```

### Spark SQL: Spark Conf

```sql
-- 设置 Spark conf (会话)
SET spark.sql.adaptive.enabled = true;
SET spark.sql.cbo.enabled = true;
SET spark.sql.statistics.histogram.enabled = true;
SET spark.sql.debug.maxToStringFields = 100;

-- 在 Databricks SQL 中
SET spark.databricks.io.cache.enabled = true;
SET spark.databricks.delta.optimizeWrite.enabled = true;

-- EXPLAIN 多种格式
EXPLAIN SELECT * FROM big_table WHERE col = 100;
EXPLAIN EXTENDED SELECT * FROM big_table WHERE col = 100;
EXPLAIN COST SELECT * FROM big_table WHERE col = 100;
EXPLAIN CODEGEN SELECT * FROM big_table WHERE col = 100;
EXPLAIN FORMATTED SELECT * FROM big_table WHERE col = 100;
```

## SQL Server 高频跟踪标志详细参考

### 内存与 tempdb 相关 (1117/1118/1224)

```sql
-- TF 1117: tempdb 文件统一增长
-- 问题: 默认情况下，多个数据文件中的某一个先满, 它单独增长, 导致文件大小不均衡, 进而 SGAM 争用
-- 启用后: 所有文件同时按相同百分比增长, 保持文件大小一致
DBCC TRACEON (1117, -1);

-- 验证 (2016+ 不需要 TF, 通过列查看):
SELECT name, is_autogrow_all_files
FROM sys.databases WHERE name = 'tempdb';

-- TF 1118: 强制使用 uniform extents (8 个连续页全分配给同一对象)
-- 问题: 默认 mixed extents (1-8 页混合分配) 导致 SGAM (Shared Global Allocation Map) 争用
-- 启用后: 所有新对象使用 uniform extents, 减少 SGAM 写入
DBCC TRACEON (1118, -1);

-- 2016+ 默认行为, 可通过列查看:
SELECT name, is_mixed_page_allocation_on FROM sys.databases;

-- TF 1224: 禁用基于锁数量的锁升级
-- 默认: 当一个会话持有 5000+ 行锁时升级为表锁
-- TF 1224: 仅在内存压力时升级 (避免行锁过多导致升级)
DBCC TRACEON (1224, -1);
```

### 查询优化器相关 (4199/9481/9476)

```sql
-- TF 4199: 启用所有 CU 引入的优化器修复
-- 默认: 关闭 (保持升级时计划稳定性)
-- 启用: 获得最新 hotfix
DBCC TRACEON (4199, -1);

-- 数据库级替代品 (推荐):
ALTER DATABASE SCOPED CONFIGURATION SET QUERY_OPTIMIZER_HOTFIXES = ON;

-- 单查询 hint (最精准):
SELECT * FROM big_table WHERE id = 100
OPTION (USE HINT('ENABLE_QUERY_OPTIMIZER_HOTFIXES'));

-- TF 9481: 强制使用 SQL Server 2012 及之前的 CE
-- 用途: SQL Server 2014 引入新 CE 后部分查询性能回归, 用此 TF 临时回退
DBCC TRACEON (9481, -1);

-- 数据库级替代:
ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = ON;

-- TF 9476: 禁用一些 CE 的 simple containment 假设
DBCC TRACEON (9476, -1);

-- TF 2453: 关闭 hekaton 表的统计信息自动更新
-- TF 8649: 强制并行执行 (即使 DOP=1 也并行, 用于诊断 OR 查询的并行度)
-- TF 8666: 输出更详细的查询计划 XML (调试用)
DBCC TRACEON (8666, -1);
```

### 锁与并发相关 (1204/1222/1211/1224)

```sql
-- TF 1204: 死锁信息记录到错误日志 (旧格式, 不推荐)
DBCC TRACEON (1204, -1);

-- TF 1222: 死锁信息记录为 XML 格式 (推荐, 便于工具分析)
DBCC TRACEON (1222, -1);

-- TF 1211: 完全禁用锁升级
-- 警告: 极度危险, 可能导致内存耗尽
DBCC TRACEON (1211, -1);

-- TF 1224 vs 1211 区别:
-- 1224: 禁用基于数量的升级, 仍按内存压力升级 (推荐)
-- 1211: 完全禁用升级 (危险, 内存可能耗尽)
```

### 备份与恢复相关 (3023/3226/3014)

```sql
-- TF 3023: BACKUP 默认启用 CHECKSUM (校验数据完整性)
DBCC TRACEON (3023, -1);

-- 替代品 (推荐, 数据库级配置):
EXEC sp_configure 'backup checksum default', 1;
RECONFIGURE;

-- TF 3226: 抑制成功备份的错误日志记录 (减少日志噪音)
DBCC TRACEON (3226, -1);

-- TF 3014: 详细的备份/恢复进度信息
DBCC TRACEON (3014, -1);
```

### 输出重定向 (3604/3605)

```sql
-- TF 3604: DBCC 输出重定向到客户端 (大多数 DBCC 调试命令必需)
DBCC TRACEON (3604);    -- 不需要 -1, 会话级即可

-- 例: 查看页内容
DBCC TRACEON (3604);
DBCC PAGE ('MyDB', 1, 100, 3);  -- 文件号 1, 页号 100, 详细级别 3

-- TF 3605: DBCC 输出到错误日志
DBCC TRACEON (3605);
```

## Oracle Event 10046: SQL Trace 的完整工作流

```sql
-- ========================================
-- 完整的 10046 trace 调优流程
-- ========================================

-- 1. 启用 trace (推荐 level 12)
ALTER SESSION SET EVENTS '10046 trace name context forever, level 12';

-- (可选) 设置 trace 文件标识符, 便于查找
ALTER SESSION SET TRACEFILE_IDENTIFIER = 'my_problem_query';

-- 2. 查找当前 session 的 trace 文件路径
SELECT VALUE FROM v$diag_info WHERE NAME = 'Default Trace File';
-- 输出: /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_ora_12345_my_problem_query.trc

-- 3. 执行需要诊断的 SQL
SELECT /*+ MY_QUERY */
       o.order_id, c.customer_name, p.product_name
FROM   orders   o
JOIN   customers c ON o.customer_id = c.customer_id
JOIN   products  p ON o.product_id  = p.product_id
WHERE  c.country = 'US'
   AND o.order_date > DATE '2024-01-01';

-- 4. 关闭 trace
ALTER SESSION SET EVENTS '10046 trace name context off';

-- 5. 退出 sqlplus, 然后用 tkprof 格式化 trace 文件
-- shell> tkprof orcl_ora_12345_my_problem_query.trc \
--               output.txt \
--               explain=hr/hr_password \
--               sys=no \
--               sort=exeela,fchela
-- output.txt 输出例:
-- ********************************************************************************
-- SQL ID: aabcdef12345 Plan Hash: 1234567890
-- SELECT /*+ MY_QUERY */ ...
--
-- call     count       cpu    elapsed       disk      query    current        rows
-- ------- ------  -------- ---------- ---------- ---------- ----------  ----------
-- Parse        1      0.00       0.00          0          0          0           0
-- Execute      1      0.00       0.00          0          0          0           0
-- Fetch        1      0.05       0.50      12345     123456          0       10000
-- ------- ------  -------- ---------- ---------- ---------- ----------  ----------
-- total        3      0.05       0.50      12345     123456          0       10000
--
-- Misses in library cache during parse: 1
-- Optimizer mode: ALL_ROWS
-- Parsing user id: 84
--
-- Rows     Row Source Operation
-- -------  ---------------------------------------------------
--   10000  HASH JOIN  (cr=123456 pr=12345 pw=0 time=500000 us)
--    50000   TABLE ACCESS FULL CUSTOMERS (cr=12345 pr=1234 ...)
--  100000   TABLE ACCESS BY INDEX ROWID ORDERS (cr=98765 pr=10000 ...)
--  100000    INDEX RANGE SCAN ORDERS_DATE_IDX (cr=234 ...)
-- ********************************************************************************

-- 等待事件 (level 8/12 包含):
-- Event waited on                      Times Waited   Max. Wait  Total Waited
-- ----------------------------------   ------------   ----------  ------------
-- db file sequential read                       1234        0.05         12.34
-- db file scattered read                         567        0.10          5.67
-- direct path read                               123        0.02          0.50

-- 6. (可选) 启用同时获取等待事件、绑定变量、SQL_ID 的 16 级 trace (12c+)
ALTER SESSION SET EVENTS 'sql_trace level 16';
```

**对其他会话启用 trace (DBA 视角)**：

```sql
-- 找到目标会话
SELECT sid, serial#, username, program, sql_id
FROM v$session WHERE username = 'APP_USER' AND status = 'ACTIVE';

-- 用 DBMS_MONITOR 启用 (推荐, 替代 dbms_system.set_ev)
EXEC DBMS_MONITOR.SESSION_TRACE_ENABLE(
        session_id => 123,
        serial_num => 456,
        waits      => TRUE,
        binds      => TRUE);

-- 等会话执行问题 SQL...

-- 关闭
EXEC DBMS_MONITOR.SESSION_TRACE_DISABLE(
        session_id => 123,
        serial_num => 456);

-- 按 client identifier 跟踪 (适合应用连接池)
EXEC DBMS_MONITOR.CLIENT_ID_TRACE_ENABLE(
        client_id => 'app_user_12345',
        waits     => TRUE,
        binds     => TRUE);
```

## PostgreSQL pg_stat_statements + auto_explain 跟踪

PostgreSQL 没有"trace flag"概念，调试和性能分析依赖两个内置扩展：

### pg_stat_statements (默认未加载)

```sql
-- 1. 配置 (postgresql.conf)
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all  -- 'top' | 'all' | 'none'
pg_stat_statements.max = 10000
pg_stat_statements.track_utility = on  -- 包含 DDL

-- 2. 重启后创建扩展 (每个数据库)
CREATE EXTENSION pg_stat_statements;

-- 3. 查询统计信息
SELECT query,
       calls,
       total_exec_time,
       mean_exec_time,
       rows,
       shared_blks_hit,
       shared_blks_read,
       shared_blks_dirtied,
       temp_blks_read,
       temp_blks_written
FROM pg_stat_statements
WHERE userid = (SELECT oid FROM pg_roles WHERE rolname = 'app_user')
ORDER BY total_exec_time DESC
LIMIT 20;

-- 重置统计信息
SELECT pg_stat_statements_reset();
```

### auto_explain (自动 EXPLAIN 慢查询)

```sql
-- 配置 (可在 session 级或 postgresql.conf)
LOAD 'auto_explain';
SET auto_explain.log_min_duration = '100ms';   -- 慢于 100ms 的语句
SET auto_explain.log_analyze = on;             -- 包含 ANALYZE 输出
SET auto_explain.log_buffers = on;             -- 包含 buffer 统计
SET auto_explain.log_timing = on;              -- 包含 per-node 计时
SET auto_explain.log_triggers = on;            -- 包含触发器
SET auto_explain.log_verbose = on;             -- 包含 schema, alias
SET auto_explain.log_format = 'json';          -- text | xml | json | yaml
SET auto_explain.log_nested_statements = on;   -- 包含 sproc 内部语句

-- 全局加载 (postgresql.conf)
shared_preload_libraries = 'auto_explain'
auto_explain.log_min_duration = 1000  -- 1 秒
auto_explain.log_analyze = true

-- 慢查询会自动出现在服务器日志中, 例:
-- LOG:  duration: 123.456 ms  plan:
--   Query Text: SELECT * FROM orders WHERE customer_id = 100;
--   Hash Join  (cost=12.34..567.89 rows=1000 width=200) (actual time=10.5..123.4 rows=950 loops=1)
--     Hash Cond: (o.customer_id = c.id)
--     Buffers: shared hit=1234 read=56
--     ->  Seq Scan on orders o  (cost=...) (actual time=0.5..67.8 rows=10000 loops=1)
--           Buffers: shared hit=1000 read=50
--     ->  Hash  (cost=...) (actual time=8.5..8.5 rows=100 loops=1)
--           ->  Index Scan using customers_pkey on customers c (cost=...) (actual time=...)
```

### pg_stat_activity 实时监控

```sql
-- 查看当前活动会话
SELECT pid, usename, application_name, client_addr,
       state, wait_event_type, wait_event,
       state_change, xact_start, query_start,
       LEFT(query, 100) AS query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start;

-- 查看锁等待
SELECT blocked.pid AS blocked_pid,
       blocked.query AS blocked_query,
       blocking.pid AS blocking_pid,
       blocking.query AS blocking_query,
       blocked.wait_event_type, blocked.wait_event
FROM pg_stat_activity AS blocked
JOIN pg_stat_activity AS blocking
  ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE blocked.wait_event_type IS NOT NULL;

-- 强制取消查询 / 终止连接
SELECT pg_cancel_backend(12345);   -- 取消查询
SELECT pg_terminate_backend(12345); -- 终止连接
```

### log_* GUC 参数详细说明

```sql
-- 慢查询日志
ALTER SYSTEM SET log_min_duration_statement = '100ms';

-- 锁等待日志
ALTER SYSTEM SET log_lock_waits = on;
ALTER SYSTEM SET deadlock_timeout = '1s';   -- 超过此时间触发死锁检查并记录

-- 大临时文件日志
ALTER SYSTEM SET log_temp_files = '10MB';   -- 大于 10MB 的临时文件记录

-- 全 SQL 日志 (生产慎用)
ALTER SYSTEM SET log_statement = 'all';     -- 'none' | 'ddl' | 'mod' | 'all'

-- checkpoint 日志
ALTER SYSTEM SET log_checkpoints = on;

-- 连接日志
ALTER SYSTEM SET log_connections = on;
ALTER SYSTEM SET log_disconnections = on;

-- 加载并应用配置
SELECT pg_reload_conf();
```

## 跟踪开销与生产风险

### 跟踪对生产环境的性能影响

| 引擎 / 机制 | 开销级别 | 影响 |
|------------|---------|------|
| SQL Server DBCC TRACEON (一般) | 低-中 | 大多数 TF 仅改变行为, 不增加日志 |
| SQL Server DBCC TRACEON (3604) | 中 | DBCC 输出占用缓冲 |
| Oracle 10046 level 1 | 中 | SQL trace 写大量数据到 trace 文件 |
| Oracle 10046 level 12 | 高 | 增加绑定+等待事件, trace 文件可达 GB 级 |
| Oracle 10053 | 高 (硬解析时) | CBO 决策日志非常详细 |
| PostgreSQL log_min_messages=debug5 | 极高 | 几乎每个内部操作都记录 |
| PostgreSQL log_statement=all | 高 | 全 SQL 记录 (大流量场景日志爆炸) |
| PostgreSQL auto_explain | 低-中 | 仅慢查询触发, 但 log_analyze 增加执行开销 |
| MySQL --debug | 极高 (debug 编译版本) | 函数级跟踪, 不可在生产用 |
| MySQL optimizer_trace | 中 | 内存占用 (默认 1MB), 仅当前会话影响 |
| MySQL general_log | 高 | 所有 SQL 记录, 高 QPS 系统会瓶颈在 IO |
| ClickHouse send_logs_level=trace | 中 | 客户端协议传输额外数据 |
| Trino EventListener | 取决于实现 | 自定义 listener 可能成为瓶颈 |
| DuckDB enable_profiling | 低 | 嵌入式场景, 仅最后一次查询 |

### 生产环境跟踪最佳实践

1. **优先使用会话级 trace, 避免全局**：减少对其他会话的影响
2. **设置时间窗口**：用 cron / event 自动启用-观察-禁用
3. **设置文件大小上限**：避免 trace 文件填满磁盘
4. **避免 log_statement=all**：高 QPS 系统几分钟就能写满日志盘
5. **优先用专用工具**：Performance Insights / Query Insights / Datadog / Prometheus 等
6. **隔离环境复现**：能在测试环境重现的问题, 不要在生产 trace
7. **保留窗口**：trace 文件应自动归档, 便于后续分析
8. **审计 trace 操作**：DBA 启用 trace 应有审计记录

```sql
-- Oracle: 自动停用的 trace (避免遗忘)
-- 通过 dbms_scheduler 创建一个 5 分钟后自动关闭的任务
BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'TRACE_AUTO_OFF',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN
                          DBMS_MONITOR.SESSION_TRACE_DISABLE(123, 456);
                        END;',
    start_date      => SYSTIMESTAMP + INTERVAL '5' MINUTE,
    enabled         => TRUE);
END;
/
```

## 跨引擎对比：诊断同一类问题

### 场景 1: 找出最慢的 10 条 SQL

```sql
-- SQL Server (sys.dm_exec_query_stats)
SELECT TOP 10
       SUBSTRING(qt.text, qs.statement_start_offset/2+1,
         (CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(qt.text)
            ELSE qs.statement_end_offset
          END - qs.statement_start_offset)/2+1) AS query,
       qs.execution_count,
       qs.total_elapsed_time / qs.execution_count AS avg_elapsed_us,
       qs.total_logical_reads / qs.execution_count AS avg_logical_reads
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.total_elapsed_time DESC;

-- Oracle (v$sql)
SELECT * FROM (
  SELECT sql_id, sql_text, executions,
         elapsed_time/1000000 AS total_elapsed_s,
         elapsed_time/executions/1000 AS avg_elapsed_ms,
         disk_reads/executions AS avg_disk_reads
  FROM v$sql
  WHERE executions > 0
  ORDER BY elapsed_time DESC
) WHERE ROWNUM <= 10;

-- PostgreSQL (pg_stat_statements)
SELECT query, calls, total_exec_time / calls AS avg_ms,
       rows / calls AS avg_rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

-- MySQL (performance_schema)
SELECT digest_text, count_star, avg_timer_wait/1e9 AS avg_ms,
       sum_rows_examined/count_star AS avg_rows_examined
FROM performance_schema.events_statements_summary_by_digest
ORDER BY sum_timer_wait DESC LIMIT 10;

-- ClickHouse (system.query_log)
SELECT query,
       count() AS calls,
       avg(query_duration_ms) AS avg_ms,
       sum(read_rows) / count() AS avg_rows_read
FROM system.query_log
WHERE event_date >= today() - 1 AND type = 'QueryFinish'
GROUP BY query
ORDER BY sum(query_duration_ms) DESC LIMIT 10;
```

### 场景 2: 抓取一条 SQL 的完整执行轨迹

```sql
-- SQL Server: 启用 actual execution plan
SET STATISTICS PROFILE ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SELECT * FROM big_table WHERE col = 100;

-- 或扩展事件
CREATE EVENT SESSION [trace_query] ON SERVER
ADD EVENT sqlserver.sql_statement_completed (
   ACTION (sqlserver.sql_text)
   WHERE (sqlserver.sql_text LIKE '%big_table%'))
ADD TARGET package0.event_file (SET filename='trace_query.xel');

ALTER EVENT SESSION [trace_query] ON SERVER STATE = START;
-- 执行查询...
ALTER EVENT SESSION [trace_query] ON SERVER STATE = STOP;

-- Oracle: 10046 level 12
ALTER SESSION SET EVENTS '10046 trace name context forever, level 12';
SELECT * FROM big_table WHERE col = 100;
ALTER SESSION SET EVENTS '10046 trace name context off';
-- tkprof 格式化

-- PostgreSQL: auto_explain + EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
LOAD 'auto_explain';
SET auto_explain.log_min_duration = 0;
SET auto_explain.log_analyze = on;
SET auto_explain.log_buffers = on;
SELECT * FROM big_table WHERE col = 100;

-- MySQL: optimizer_trace + EXPLAIN ANALYZE
SET optimizer_trace = 'enabled=on';
EXPLAIN ANALYZE SELECT * FROM big_table WHERE col = 100;
SELECT * FROM information_schema.OPTIMIZER_TRACE;

-- ClickHouse: send_logs_level + EXPLAIN
SET send_logs_level = 'trace';
EXPLAIN PLAN actions=1, indexes=1 SELECT * FROM big_table WHERE col = 100;
```

### 场景 3: 找出当前阻塞链

```sql
-- SQL Server (sys.dm_exec_requests + sys.dm_os_waiting_tasks)
SELECT r.session_id AS blocked_sid,
       r.blocking_session_id AS blocking_sid,
       r.wait_type, r.wait_time, r.wait_resource,
       qt.text AS blocked_query
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) qt
WHERE r.blocking_session_id != 0;

-- Oracle (v$session)
SELECT sid, blocking_session, wait_class, event,
       seconds_in_wait, sql_id
FROM v$session
WHERE blocking_session IS NOT NULL;

-- PostgreSQL (pg_blocking_pids)
SELECT b.pid AS blocked, b.query AS blocked_q,
       a.pid AS blocking, a.query AS blocking_q
FROM pg_stat_activity b
JOIN pg_stat_activity a ON a.pid = ANY(pg_blocking_pids(b.pid));

-- MySQL (performance_schema)
SELECT r.thread_id AS blocked_thread, r.PROCESSLIST_ID AS blocked_pid,
       w.thread_id AS waiting_thread, w.PROCESSLIST_ID AS waiting_pid,
       l.OBJECT_SCHEMA, l.OBJECT_NAME, l.LOCK_TYPE
FROM performance_schema.metadata_locks l
JOIN performance_schema.threads r ON r.thread_id = l.OWNER_THREAD_ID
JOIN performance_schema.threads w ON w.thread_id != r.thread_id
WHERE l.LOCK_STATUS = 'GRANTED' AND l.OBJECT_TYPE = 'TABLE';
```

## 设计争议与风险

### 1. 文档化 vs 隐藏 trace flag

**SQL Server 派 (TF 文档化)**：

- 优点：DBA 可自行学习, 社区可分享 (Brent Ozar、Erik Darling 等专家整理大量 TF 列表)
- 缺点：用户可能滥用未充分理解的 TF, 导致计划回归或数据问题

**Oracle 派 (event 半隐藏)**：

- 优点：避免用户随意启用导致系统问题, MyOracleSupport 可控制访问
- 缺点：DBA 必须依赖原厂支持, 学习曲线陡峭, 社区难以共享经验

**PostgreSQL 派 (无 TF 概念, 全 GUC)**：

- 优点：透明, 所有调试开关都是正式参数, 文档完整
- 缺点：缺少 SQL Server / Oracle 那种"应急 workaround"的灵活性

### 2. 跟踪开销 vs 信息密度

理想的 trace 应该：

- **低开销**：不影响生产性能 < 5%
- **高密度**：捕获足够定位问题的细节
- **可针对**：能限定到特定 session / 查询 / 用户

但这三者是 trade-off。Oracle 10046 level 12 信息密度最高, 但开销大；ClickHouse send_logs_level=trace 信息中等, 开销中等；PostgreSQL auto_explain 仅慢查询, 开销低但需提前设置。

### 3. 全局 trace 的危险性

```sql
-- SQL Server 错误示范 (生产慎用)
DBCC TRACEON (3604, 8666, -1);  -- 全局开启详细查询计划日志
-- 后果: errorlog 几分钟内填满, 可能导致服务不可用

-- 正确做法: 单 session 启用
DBCC TRACEON (3604);  -- 仅当前会话
DBCC TRACEON (8666);
SELECT ...
```

### 4. 云数据库的"诊断真空"

云数据库为了 SLA 稳定性禁用了大多数 trace flag, 这导致 DBA 在云上面对疑难问题时缺少传统的诊断手段。云厂商提供的 Performance Insights / Query Insights 虽然好用, 但深度不及原生 trace。

### 5. 跟踪数据的安全风险

trace 文件可能包含：

- **绑定变量值** (PII / 信用卡 / 密码)
- **完整 SQL** (业务逻辑暴露)
- **执行计划** (数据分布信息泄露)
- **schema 元数据** (表结构暴露)

```sql
-- Oracle 10046 level 12 的 trace 文件包含绑定变量, 例:
-- BINDS #1234:
--  Bind#0 oacdty=01 mxl=32(20) mxlc=00 mal=00 scl=00 pre=00 ...
--   value="user_password_in_plain_text"  -- 危险!

-- 解决方案:
-- 1. trace 文件存储在受限目录 (chmod 700)
-- 2. 使用 level 8 (仅等待事件, 不含绑定)
-- 3. 立即 tkprof 后删除原 trace
-- 4. 应用使用 SUBSTITUTE_BIND_VAR_VALUES 等函数遮蔽
```

## 关键发现

1. **SQL 标准从未涉及跟踪/调试**：除 `GET DIAGNOSTICS` 外, 没有任何标准化语句, 所有引擎自行设计。

2. **三大派系**：
   - **TF 派 (SQL Server / Oracle / DB2)**：用编号 + 命令操控数百个内部开关
   - **GUC 派 (PostgreSQL / Greenplum)**：所有调试开关都是正式参数
   - **session property 派 (Trino / Snowflake)**：用 `SET SESSION` 风格控制

3. **MySQL 是混合派**：optimizer_trace 是 GUC 风格, 但 --debug 是传统 DBUG library 风格 (需 debug 编译)。

4. **Oracle 10046 的统治地位**：自 v7 (1992) 起就是 SQL trace 黄金标准, 至今 33 年仍是 Oracle DBA 必备技能。

5. **SQL Server TF 1117/1118 的演化**：2014 及更早需手动启用, 2016+ 成为 tempdb 默认行为, 体现了"先用 TF 验证, 再固化为默认"的产品演进路径。

6. **TF 4199 的"hotfix 开关"模式**：默认关闭以保持升级时计划稳定性, 用户主动启用获得最新修复——这是商用数据库特有的产品策略。

7. **MySQL optimizer_trace (5.6, 2013) 是 MySQL 第一次公开优化器内部决策**：之前 MySQL DBA 几乎只能"猜"优化器在想什么。

8. **PostgreSQL auto_explain (8.4, 2009)** 提供了"自动捕获慢查询完整 EXPLAIN"的能力, 至今仍是 PG 调优首选工具。

9. **未文档化 trace 是商用数据库的"灰色地带"**：Oracle / SQL Server 都有大量未公开 TF / event, 仅原厂支持知晓, 给 DBA 学习造成壁垒。

10. **云数据库故意限制 trace 能力**：Aurora / RDS / Cloud SQL / Snowflake / BigQuery 都禁用了大量底层 trace, 替代以高层可观察性产品 (Performance Insights / Query Insights / Cloud Monitoring)。

11. **ClickHouse 的"日志推送"独树一帜**：`SET send_logs_level=trace` 把日志通过查询协议直接推到客户端, 适合容器化、Serverless 场景。

12. **CockroachDB / TiDB 的 cluster setting 模型**：作为云原生 NewSQL, 把所有调试开关都设计成集群级 setting, 持久化在系统表, 比传统 GUC 更适合分布式。

13. **跟踪开销不容忽视**：Oracle 10046 level 12 在高 QPS 系统几分钟可产生 GB 级 trace；MySQL general_log = ON 几乎不可能在生产持续启用；PostgreSQL log_min_messages=debug5 几乎拖死服务器。

14. **跟踪输出的安全风险长期被低估**：trace 文件常含绑定变量、明文 SQL、schema 信息, 但很少有审计制度强制保护这些文件。

15. **跨引擎可移植性近乎为零**：同一个诊断目标 (找慢查询、抓阻塞、看优化器决策), 5 个数据库的命令完全不同, 是 SQL 世界标准化最差的角落之一。

## 参考资料

- SQL Server: [Trace Flags](https://learn.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-traceon-trace-flags-transact-sql)
- SQL Server: [DBCC TRACEON](https://learn.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-traceon-transact-sql)
- SQL Server: [ALTER DATABASE SCOPED CONFIGURATION](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-database-scoped-configuration-transact-sql)
- Oracle: [Diagnostic Events](https://docs.oracle.com/en/database/oracle/oracle-database/19/ladbi/diagnostic-events.html)
- Oracle: [DBMS_MONITOR](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_MONITOR.html)
- Oracle: [tkprof](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SQL-Trace-Facility.html)
- Tanel Poder, Maris Elsins: 多篇 oradebug / 隐藏参数研究博客
- PostgreSQL: [Error Reporting and Logging](https://www.postgresql.org/docs/current/runtime-config-logging.html)
- PostgreSQL: [auto_explain](https://www.postgresql.org/docs/current/auto-explain.html)
- PostgreSQL: [pg_stat_statements](https://www.postgresql.org/docs/current/pgstatstatements.html)
- MySQL: [optimizer_trace](https://dev.mysql.com/doc/internals/en/optimizer-tracing.html)
- MySQL: [The DBUG Library](https://dev.mysql.com/doc/dev/mysql-server/latest/PAGE_DBUG.html)
- MySQL: [Performance Schema](https://dev.mysql.com/doc/refman/8.0/en/performance-schema.html)
- MariaDB: [ANALYZE FORMAT=JSON](https://mariadb.com/kb/en/analyze-and-explain-statements/)
- DB2: [db2trc Command](https://www.ibm.com/docs/en/db2/11.5?topic=commands-db2trc-trace)
- Snowflake: [QUERY_HISTORY](https://docs.snowflake.com/en/sql-reference/functions/query_history)
- ClickHouse: [Logging Settings](https://clickhouse.com/docs/en/operations/settings/settings#send_logs_level)
- Trino: [Session Properties](https://trino.io/docs/current/sql/set-session.html)
- CockroachDB: [SHOW TRACE](https://www.cockroachlabs.com/docs/stable/show-trace)
- TiDB: [TRACE Statement](https://docs.pingcap.com/tidb/stable/sql-statement-trace)
- Brent Ozar: [SQL Server Trace Flags](https://www.brentozar.com/blitz/trace-flags/)
- Paul Randal: SQLskills 博客中关于 TF 的多篇深度文章
