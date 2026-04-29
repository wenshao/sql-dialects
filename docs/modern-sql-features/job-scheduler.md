# 作业调度器 (Job Scheduler)

数据库内置作业调度器（Job Scheduler）让 cron-like 的周期性任务直接运行在数据库内部：定时刷新统计信息、清理历史分区、刷新物化视图、归档冷数据、收集运维指标。它让 DBA 不必在外部布置 crontab、Airflow 或 Kubernetes CronJob，就能完成最常见的"每小时/每天/每周做一次"的运维操作。

但调度器并不是 SQL 的标配——它是被低估的"运维基础设施"，各引擎之间的差异远超表面看起来的样子：Oracle 的 `DBMS_SCHEDULER` 像一个完整的批处理系统，支持 chain、calendar、windows 和资源消费组；MySQL 的 `EVENT` 调度器只是一个最小可用产品；PostgreSQL 干脆没有内建调度器，社区用 `pg_cron` 扩展和 `pg_timetable` 工具补足。本文围绕 45+ 引擎横向对比内置作业调度器的能力、语法和典型设计取舍。

相关阅读：[`triggers.md`](triggers.md) 讨论 DML/DDL 触发器，[`materialized-view-refresh.md`](materialized-view-refresh.md) 讨论物化视图刷新策略——许多调度器场景就是为了驱动 MV 刷新或定期统计采集。

## SQL 标准并未定义作业调度器

ISO/IEC 9075（SQL 标准）从 SQL-92 到最新的 SQL:2023 修订版，**从未定义过 "schedule" 或 "job" 关键字**。标准只关心查询、模式定义、事务和过程化扩展（PSM）；周期性任务被认为是数据库管理的"环境层"，由实现者自由定义。

这导致几个直接的后果：

- **关键字百花齐放**：Oracle 用 `DBMS_SCHEDULER.CREATE_JOB`，SQL Server 用 `sp_add_job`，MySQL 用 `CREATE EVENT`，CockroachDB 用 `CREATE SCHEDULE`，Snowflake 用 `CREATE TASK`。
- **执行单元粒度不同**：Oracle 把每个调度叫 `JOB`，SQL Server 一个 `JOB` 包含多个 `STEP`，pg_cron 是简单的 `(schedule, command)` 二元组。
- **调度表达式不一致**：有的用 cron 表达式，有的用 `EVERY 5 MINUTE` 之类的自然语言，有的提供完整的 calendar DSL。
- **错误处理与日志策略差异巨大**：Oracle 提供完整的 `*_JOB_LOG` / `*_JOB_RUN_DETAILS` 视图；MySQL 几乎没有日志，失败只会进 error log。

接下来我们看看这些差异具体如何表现。

## 支持矩阵（45+ 数据库）

### 矩阵 1：是否提供内建作业调度器

| 引擎 | 内建调度器 | 名称 | 引入版本 |
|------|----------|------|---------|
| PostgreSQL | 否（扩展）| `pg_cron` (Citus) / `pg_timetable` | pg_cron 2015+ |
| MySQL | 是 | `EVENT` Scheduler | 5.1.6 (2008) |
| MariaDB | 是 | `EVENT` Scheduler（MySQL 兼容）| 5.1+ |
| SQLite | 否 | -- | -- |
| Oracle | 是 | `DBMS_SCHEDULER`（10g+），`DBMS_JOB`（早期）| 10g (2003) |
| SQL Server | 是 | SQL Server Agent | 7.0 (1998) |
| DB2 | 是 | `ADMIN_SCHEDULER` / `DB2 Administrative Task Scheduler` | 9.7+ |
| Snowflake | 是 | `TASK` (with `SCHEDULE 'USING CRON ...'`) | 2019 |
| BigQuery | 是 | Scheduled Queries (Data Transfer Service) | GA 2018 |
| Redshift | 是 | Scheduler API + `pg_cron`（RA3）| 2020+ |
| DuckDB | 否 | -- | -- |
| ClickHouse | 否（部分功能内建）| `REFRESHABLE` MV，无通用调度器 | -- |
| Trino | 否 | -- | -- |
| Presto | 否 | -- | -- |
| Spark SQL | 否 | -- | -- |
| Hive | 是 | `CREATE SCHEDULED QUERY` | 4.0+ |
| Flink SQL | 否（流式语义不需要）| -- | -- |
| Databricks | 是 | Workflows / Jobs / Delta Live Tables | GA |
| Teradata | 是 | TASM（Teradata Active System Management）/ Viewpoint Job Scheduler | 早期 |
| Greenplum | 否（继承 PG）| `pg_cron` 可用 | -- |
| CockroachDB | 是 | `CREATE SCHEDULE FOR ...` | 21.x (2021) |
| TiDB | 否 | 无（需外部 cron）| -- |
| OceanBase | 是 | `DBMS_SCHEDULER`（Oracle 模式） | 3.x+ |
| YugabyteDB | 否（继承 PG）| `pg_cron` 可用 | -- |
| SingleStore | 否 | -- | -- |
| Vertica | 是 | Scheduler / `MAKE_AHM_NOW` | 7.x+ |
| Impala | 否 | -- | -- |
| StarRocks | 是（间接）| 异步 MV `REFRESH ASYNC EVERY` | 2.4+ |
| Doris | 是 | `JOB` 语句（`CREATE JOB`）| 2.1+ |
| MonetDB | 否 | -- | -- |
| CrateDB | 否 | -- | -- |
| TimescaleDB | 是 | Background Jobs / `add_job` | 1.x+ |
| QuestDB | 否 | -- | -- |
| Exasol | 是 | `CREATE SCHEDULER` | 7.0+ |
| SAP HANA | 是 | XS Job Scheduler / `XSJOB` | 1.0+ |
| Informix | 是 | `dbcron` Sysadmin Scheduler | 11.5+ |
| Firebird | 否 | -- | -- |
| H2 | 否 | -- | -- |
| HSQLDB | 否 | -- | -- |
| Derby | 否 | -- | -- |
| Amazon Athena | 是 | EventBridge Scheduled Queries | GA |
| Azure Synapse | 是 | Synapse Pipelines（外部）| GA |
| Google Spanner | 否 | 通过 Cloud Scheduler 外部触发 | -- |
| Materialize | 否（持续语义不需要）| -- | -- |
| RisingWave | 否（持续语义不需要）| -- | -- |
| InfluxDB (SQL) | 是 | Tasks（Flux/SQL）| 2.0+ |
| DatabendDB | 是 | `TASK` | 1.2+ |
| Yellowbrick | 否（外部 cron）| -- | -- |
| Firebolt | 否 | -- | -- |

> 统计：约 26 个引擎提供某种形式的内建调度（含扩展和兼容层），约 19 个完全依赖外部调度。OLAP/MPP 引擎中，Snowflake / CockroachDB / Hive / StarRocks / Doris / Databricks 是少数原生支持的。

### 矩阵 2：cron 表达式支持

cron 表达式是 Unix 世界的事实标准（5 字段：分 时 日 月 周）。看看哪些引擎原生接受 cron 字符串：

| 引擎 | 接受 cron 表达式 | 字段数 | 时区支持 | 备注 |
|------|----------------|-------|---------|------|
| PostgreSQL (pg_cron) | 是 | 5 | 服务器时区或 UTC | 与 Vixie cron 兼容 |
| MySQL | 否 | -- | -- | 仅 `EVERY n UNIT` |
| MariaDB | 否 | -- | -- | 同 MySQL |
| Oracle DBMS_SCHEDULER | 否（独立 calendar 语法）| -- | 是（per-job）| 见下文 |
| SQL Server Agent | 否（GUI/系统过程）| -- | 是 | 通过 `freq_*` 参数 |
| DB2 | 否（用 UNIX cron 字段拆开） | -- | 是 | `add_task` 接受 5 字段 |
| Snowflake | 是 | 5（+秒可选）| 是（必须显式）| `SCHEDULE = 'USING CRON ... <tz>'` |
| BigQuery | 是 | 5 | 是 | UNIX cron + 时区 |
| Redshift | 是（pg_cron）| 5 | 是 | -- |
| Hive Scheduled Query | 是 | 5 | 是 | Quartz 风格（6 或 7 字段也支持）|
| Databricks | 是 | 5 或 7（Quartz）| 是 | -- |
| CockroachDB | 是 | 5 | 是（默认 UTC）| `RECURRING '*/10 * * * *'` |
| OceanBase | 否（继承 Oracle calendar）| -- | 是 | -- |
| TimescaleDB | 否（间隔语法）| -- | -- | `schedule_interval => INTERVAL '1 hour'` |
| StarRocks | 是（部分）| 5 | 是 | -- |
| Doris | 是 | 5 | 是 | -- |
| SAP HANA XSJOB | 是 | 6（含秒） | 是 | -- |
| Informix dbcron | 是 | 5 | 服务器时区 | -- |
| Athena (EventBridge) | 是 | 6（AWS 风格） | 是 | -- |
| InfluxDB | 是 | 5 | 是 | -- |
| DatabendDB | 是 | 5 | 是 | -- |

> 注：**Quartz cron** 与 **Unix cron** 在字段数和保留字上略有差异。Quartz 通常是 6 或 7 字段（秒 / 分 / 时 / 日 / 月 / 周 / 年）。Hive 和 Databricks 这类 Java 生态的引擎倾向用 Quartz 风格。

### 矩阵 3：循环作业 vs 一次性作业

| 引擎 | 循环（Recurring） | 一次性（One-shot）| 条件触发（Event-based）|
|------|-----------------|----------------|---------------------|
| PostgreSQL (pg_cron) | 是 | 否（需变通）| 否 |
| MySQL EVENT | 是（`ON SCHEDULE EVERY`）| 是（`ON SCHEDULE AT`）| 否 |
| Oracle DBMS_SCHEDULER | 是 | 是 | 是（`event_condition`）|
| SQL Server Agent | 是 | 是 | 是（性能告警驱动）|
| DB2 ADMIN_SCHEDULER | 是 | 是 | 否 |
| Snowflake TASK | 是 | 否（cron 触发，但可手动 `EXECUTE TASK`）| 是（`AFTER` 任务依赖）|
| BigQuery Scheduled Queries | 是 | 是（一次性）| 否 |
| CockroachDB | 是 | 否（需变通）| 否 |
| Hive Scheduled Query | 是 | 否 | 否 |
| Databricks Jobs | 是 | 是 | 是（File arrival、Delta updates）|
| TimescaleDB | 是 | 否（手动 `run_job`）| 否 |
| Vertica Scheduler | 是 | 是 | 否 |
| StarRocks 异步 MV | 是 | 否 | 否（partition-driven 部分支持）|
| Doris JOB | 是 | 是（`AT '2026-01-01 00:00:00'`）| 否 |
| Informix dbcron | 是 | 是 | 是（数据变化）|
| SAP HANA XSJOB | 是 | 是 | 否 |
| InfluxDB Tasks | 是 | 否 | 否 |

### 矩阵 4：链式依赖（Job Chains / DAG）

链式依赖是企业级调度器的高阶能力——一个作业完成后才能启动另一个，或者一组作业组成 DAG。

| 引擎 | 链式依赖 | 机制 | 失败处理 |
|------|---------|------|---------|
| Oracle DBMS_SCHEDULER | 是 | `DBMS_SCHEDULER.CREATE_CHAIN` + chain rules | 完整（per-step）|
| SQL Server Agent | 是 | Job 内多 Step + `on_success_action` | per-step |
| DB2 | 否 | -- | -- |
| Snowflake TASK | 是 | `CREATE TASK ... AFTER parent_task` | DAG，per-task |
| Databricks | 是 | Workflows DAG | 完整 |
| Hive | 否 | -- | -- |
| CockroachDB | 否 | 仅独立调度 | -- |
| MySQL EVENT | 否 | 仅独立调度 | -- |
| PostgreSQL pg_cron | 否 | 多个 cron 项无依赖关系 | -- |
| pg_timetable | 是 | 任务链（chain）模型 | per-step retry |
| TimescaleDB | 否 | 仅独立 job | -- |
| Vertica | 否 | -- | -- |
| StarRocks 异步 MV | 是（隐式）| 基于 partition 依赖 | -- |
| Doris JOB | 否 | -- | -- |
| Informix dbcron | 否 | -- | -- |

### 矩阵 5：日历/窗口（Calendar / Window）支持

日历提供"每月最后一个工作日"、"每季度第一天"这类复杂日期表达；窗口让作业仅在特定时间段（如夜间维护窗口）内运行。

| 引擎 | 日历表达 | 维护窗口 | 资源管理集成 |
|------|---------|---------|-------------|
| Oracle DBMS_SCHEDULER | 是（`CREATE_SCHEDULE` 含 `BYMONTH/BYWEEKDAY/BYSETPOS`）| 是（`CREATE_WINDOW`）| 是（资源消费组）|
| SQL Server Agent | 部分（GUI 中可指定"月第几个星期几"）| 否 | 否（需 Resource Governor 单独配） |
| DB2 | 否 | 否 | 否 |
| Snowflake TASK | 部分（CRON 字段已可表达大多数场景）| 否 | 是（`USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE`）|
| Databricks Jobs | 部分（cron）| 否 | 是（cluster policy）|
| MySQL EVENT | 否 | 否 | 否 |
| PostgreSQL pg_cron | 否（cron 表达式之外不支持）| 否 | 否 |
| pg_timetable | 部分 | 部分 | 否 |
| Hive | 否 | 否 | 部分（YARN queue）|
| CockroachDB | 否 | 否 | 否 |
| Vertica | 否 | 部分（Resource Pool 关联）| 是 |
| TimescaleDB | 否 | 否 | 否 |
| OceanBase | 是（继承 Oracle）| 是 | 是 |
| SAP HANA XSJOB | 部分 | 否 | 否 |

> 一句话总结：**Oracle DBMS_SCHEDULER 是日历语法、窗口和资源管理三位一体最完整的实现**。其他引擎大多只提供 cron 这一层。

## Oracle DBMS_SCHEDULER：参考实现的复杂度上限

Oracle 在 10g（2003）引入 `DBMS_SCHEDULER`，正式取代早期的 `DBMS_JOB`。后者在 9i 之前是唯一选择，至今仍向后兼容，但所有新代码都应使用 `DBMS_SCHEDULER`。

### 基本概念

DBMS_SCHEDULER 把"调度"拆成三层正交对象：

```
PROGRAM   = "做什么"   (PL/SQL block / stored procedure / external executable)
SCHEDULE  = "什么时候做" (calendar string / repeat interval)
JOB       = PROGRAM × SCHEDULE × 运行参数
```

这样 `PROGRAM` 和 `SCHEDULE` 都可以独立复用，多个 JOB 共享同一个 SCHEDULE 或 PROGRAM。

### 创建一个简单的循环作业

```sql
-- 最简单形式：内联 PL/SQL 块 + 重复间隔
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'NIGHTLY_STATS_GATHER',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN DBMS_STATS.GATHER_DATABASE_STATS; END;',
        start_date      => SYSTIMESTAMP,
        repeat_interval => 'FREQ=DAILY; BYHOUR=2; BYMINUTE=0',
        enabled         => TRUE,
        comments        => '每天凌晨 2 点收集统计信息'
    );
END;
/
```

`repeat_interval` 用的是 Oracle 自定义的 **calendar string** 语法，而不是 cron。它的核心字段：

| 字段 | 取值 |
|------|------|
| `FREQ` | YEARLY / MONTHLY / WEEKLY / DAILY / HOURLY / MINUTELY / SECONDLY |
| `INTERVAL` | 1, 2, 3, ...（频率倍数）|
| `BYMONTH` | 1..12 |
| `BYMONTHDAY` | 1..31 / -1..-31 |
| `BYWEEKDAY` | MON, TUE, ..., SUN（可加序号 -1MON 表示当月最后一个周一）|
| `BYHOUR` / `BYMINUTE` / `BYSECOND` | 0..23 / 0..59 / 0..59 |
| `BYSETPOS` | 1..366（在多重 BY 限定下选第几个）|
| `INCLUDE`/`EXCLUDE` | 引用其他命名 schedule |

calendar 字符串的真正威力在于"每月最后一个工作日"这类组合：

```sql
DBMS_SCHEDULER.CREATE_SCHEDULE(
    schedule_name   => 'LAST_BUSINESS_DAY_OF_MONTH',
    repeat_interval =>
        'FREQ=MONTHLY; BYMONTHDAY=-1,-2,-3; BYDAY=MON,TUE,WED,THU,FRI; BYSETPOS=-1',
    comments => '每月最后一个工作日 23:30 运行'
);
```

含义：取每月的最后三天 → 过滤掉非工作日 → 取剩下集合的最后一个。Oracle 的 `BYSETPOS` 是 cron 完全做不到的能力。

### 程序对象（Program）

```sql
-- 创建一个可复用的 PROGRAM
DBMS_SCHEDULER.CREATE_PROGRAM(
    program_name        => 'CLEANUP_OLD_AUDIT',
    program_type        => 'STORED_PROCEDURE',
    program_action      => 'audit_pkg.purge_older_than',
    number_of_arguments => 1,
    enabled             => FALSE
);

DBMS_SCHEDULER.DEFINE_PROGRAM_ARGUMENT(
    program_name      => 'CLEANUP_OLD_AUDIT',
    argument_position => 1,
    argument_name     => 'days',
    argument_type     => 'NUMBER',
    default_value     => 90
);

DBMS_SCHEDULER.ENABLE('CLEANUP_OLD_AUDIT');

-- 用 SCHEDULE + PROGRAM 组合创建 JOB
DBMS_SCHEDULER.CREATE_JOB(
    job_name      => 'AUDIT_NIGHTLY',
    program_name  => 'CLEANUP_OLD_AUDIT',
    schedule_name => 'LAST_BUSINESS_DAY_OF_MONTH',
    enabled       => TRUE
);
```

### Chain：作业链

链是 DBMS_SCHEDULER 真正区别于其他调度器的能力。一个 chain 由若干 step + 若干 rule 组成：

```sql
-- 创建链对象
DBMS_SCHEDULER.CREATE_CHAIN(chain_name => 'ETL_NIGHTLY');

-- 加入步骤（每个 step 关联一个 PROGRAM）
DBMS_SCHEDULER.DEFINE_CHAIN_STEP('ETL_NIGHTLY', 'STEP_EXTRACT',  'PRG_EXTRACT');
DBMS_SCHEDULER.DEFINE_CHAIN_STEP('ETL_NIGHTLY', 'STEP_TRANSFORM','PRG_TRANSFORM');
DBMS_SCHEDULER.DEFINE_CHAIN_STEP('ETL_NIGHTLY', 'STEP_LOAD',     'PRG_LOAD');
DBMS_SCHEDULER.DEFINE_CHAIN_STEP('ETL_NIGHTLY', 'STEP_NOTIFY',   'PRG_NOTIFY');

-- 加入规则（DAG 边 + 终止条件）
DBMS_SCHEDULER.DEFINE_CHAIN_RULE('ETL_NIGHTLY',
    condition => 'TRUE',
    action    => 'START STEP_EXTRACT');

DBMS_SCHEDULER.DEFINE_CHAIN_RULE('ETL_NIGHTLY',
    condition => 'STEP_EXTRACT SUCCEEDED',
    action    => 'START STEP_TRANSFORM');

DBMS_SCHEDULER.DEFINE_CHAIN_RULE('ETL_NIGHTLY',
    condition => 'STEP_TRANSFORM SUCCEEDED',
    action    => 'START STEP_LOAD');

DBMS_SCHEDULER.DEFINE_CHAIN_RULE('ETL_NIGHTLY',
    condition => 'STEP_LOAD COMPLETED',
    action    => 'START STEP_NOTIFY');

DBMS_SCHEDULER.DEFINE_CHAIN_RULE('ETL_NIGHTLY',
    condition => 'STEP_NOTIFY COMPLETED',
    action    => 'END');

DBMS_SCHEDULER.ENABLE('ETL_NIGHTLY');

-- 用 JOB 触发 chain
DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'JOB_ETL_NIGHTLY',
    job_type        => 'CHAIN',
    job_action      => 'ETL_NIGHTLY',
    repeat_interval => 'FREQ=DAILY; BYHOUR=1',
    enabled         => TRUE
);
```

链的失败处理可以非常细粒度：每个 step 有 `SUCCEEDED`、`FAILED`、`COMPLETED`、`STOPPED` 四种终态，`COMPLETED` 是 SUCCEEDED 或 FAILED 的并集。可以基于这些状态分支跳转：

```sql
DBMS_SCHEDULER.DEFINE_CHAIN_RULE('ETL_NIGHTLY',
    condition => 'STEP_EXTRACT FAILED',
    action    => 'START STEP_NOTIFY_FAILURE');
```

### Window：维护窗口

Window 是一段被命名的时间段，作业可以指定"仅在窗口打开时运行"。例如夜间维护窗口：

```sql
DBMS_SCHEDULER.CREATE_WINDOW(
    window_name     => 'NIGHT_WINDOW',
    resource_plan   => 'BATCH_PLAN',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=DAILY; BYHOUR=22',
    duration        => INTERVAL '8' HOUR,
    window_priority => 'LOW'
);

DBMS_SCHEDULER.CREATE_JOB(
    job_name      => 'BIG_REINDEX',
    job_type      => 'PLSQL_BLOCK',
    job_action    => 'BEGIN dbms_stats.gather_table_stats(USER, ''ORDERS''); END;',
    schedule_name => 'NIGHT_WINDOW',
    enabled       => TRUE
);
```

窗口可以关联资源计划（resource plan），打开时自动激活——这意味着夜间任务可以独占 80% CPU，白天 OLTP 时段只能用 5%。这种"调度 × 资源管理"耦合在其他引擎几乎没有等价物。

### 元数据视图

```sql
-- 所有作业
SELECT job_name, state, last_start_date, next_run_date FROM dba_scheduler_jobs;

-- 运行历史
SELECT job_name, status, error#, run_duration
FROM dba_scheduler_job_run_details
WHERE log_date > SYSDATE - 1
ORDER BY log_date DESC;

-- 链状态
SELECT * FROM dba_scheduler_running_chains;
```

这些视图比所有其他引擎加起来都丰富，是 Oracle 调度器作为"工业级"标杆的关键证据。

## SQL Server Agent：最早的工业级调度器

SQL Server Agent 自 SQL Server 7.0（1998）起就提供，比 Oracle DBMS_SCHEDULER 早 5 年。它是一个**独立 Windows 服务**（msdb 数据库存储元数据），与数据库引擎进程分离。

### 模型层次

```
JOB         一个作业（顶层容器）
  CATEGORY  类别（仅分类用）
  STEP[]    步骤序列（按 step_id 顺序）
    SUBSYSTEM  子系统：T-SQL / PowerShell / SSIS / CmdExec / ...
    ON_SUCCESS_ACTION  成功后跳到第几步 / 终止 / 失败
    ON_FAILURE_ACTION  失败后跳到第几步 / 终止 / 失败
    RETRY_ATTEMPTS / RETRY_INTERVAL
  SCHEDULE[] 多个 schedule 可绑定到同一 job
  ALERT[]    告警触发的关联
  NOTIFICATION[] 操作员（operator）通知
```

### 创建作业的样板代码

```sql
USE msdb;
GO

-- 1. 创建 JOB
EXEC sp_add_job
    @job_name = N'Nightly Index Maintenance',
    @description = N'重建碎片大于 30% 的索引';

-- 2. 加入 STEP
EXEC sp_add_jobstep
    @job_name   = N'Nightly Index Maintenance',
    @step_name  = N'Rebuild Indexes',
    @subsystem  = N'TSQL',
    @command    = N'EXEC dbo.usp_RebuildFragmentedIndexes',
    @database_name = N'OnlineStore',
    @on_success_action = 1,  -- Quit with success
    @on_fail_action    = 2;  -- Quit with failure

-- 3. 创建 SCHEDULE
EXEC sp_add_schedule
    @schedule_name = N'NightlyAt2AM',
    @freq_type     = 4,        -- daily
    @freq_interval = 1,         -- every 1 day
    @active_start_time = 020000;-- 02:00:00

-- 4. 关联
EXEC sp_attach_schedule
    @job_name      = N'Nightly Index Maintenance',
    @schedule_name = N'NightlyAt2AM';

-- 5. 注册到 server
EXEC sp_add_jobserver @job_name = N'Nightly Index Maintenance';
```

### 调度类型（freq_type）

SQL Server Agent 不接受 cron 字符串，而是用一组数值常量描述频率：

| freq_type | 含义 |
|-----------|------|
| 1 | 一次（One-time）|
| 4 | 每日（每 N 天）|
| 8 | 每周（指定 weekday 位掩码）|
| 16 | 每月（指定日）|
| 32 | 每月相对（"第二个周二"）|
| 64 | 启动 SQL Server Agent 时 |
| 128 | CPU 空闲时 |

### Step 内的流程控制

每个 STEP 都可以独立设定"成功 / 失败 → 下一步" 行为，这天然就是一个 chain：

```
Step 1: Extract (subsystem TSQL)
  on_success_action = 3  (next step)
  on_fail_action    = 6  (jump to step 6: Notify Failure)
Step 2: Transform
  on_success = 3
  on_fail    = 6
Step 3: Load
  on_success = 1  (Quit success)
  on_fail    = 6
Step 6: Notify Failure
  on_success = 2  (Quit failure)
```

虽然不像 Oracle chain 那样可以多向条件分支，但线性 + 跳转已经能覆盖绝大多数 ETL 流程。

### 与 Linux SQL Server 的兼容性

SQL Server 2017+ 在 Linux 上也可用，**SQL Server Agent on Linux 在 2018 年以预览方式提供，2019 GA**。它不是 Windows 服务，而是 sqlservr 进程内的子组件。日志位置和外部任务（CmdExec subsystem）有差异。

## pg_cron：PostgreSQL 生态的事实标准

PostgreSQL 核心从未引入调度器（多次社区讨论被否决，理由是"应该用 OS 级 cron 或外部工具"）。Citus Data 公司在 2015 年开源了 `pg_cron` 扩展，成为事实标准——AWS RDS、Azure Database for PostgreSQL、Google Cloud SQL 全部内置。

### 安装与基本用法

```sql
-- 必须由超级用户在 postgresql.conf 启用
-- shared_preload_libraries = 'pg_cron'
-- cron.database_name = 'postgres'

CREATE EXTENSION pg_cron;

-- 调度作业（cron 表达式 + SQL 命令）
SELECT cron.schedule(
    'vacuum-nightly',
    '0 3 * * *',
    $$VACUUM (ANALYZE) public.large_table$$
);

-- 列出所有作业
SELECT * FROM cron.job;

-- 取消
SELECT cron.unschedule('vacuum-nightly');

-- 在指定数据库执行
SELECT cron.schedule_in_database(
    'analytics-refresh',
    '*/15 * * * *',
    $$REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.dau$$,
    'analytics_db'
);
```

### 架构设计：单一 worker + libpq

pg_cron 的设计极简：

```
后台进程（一个 background worker）
   |
   |  每分钟轮询 cron.job 表
   |
   v
计算到期任务
   |
   v
对每个到期作业，通过 libpq 连接到目标数据库执行 SQL
   |
   v
执行结果写入 cron.job_run_details
```

关键架构属性：

1. **单 worker 串行扫描**：cron worker 自己每分钟唤醒一次，轮询 `cron.job`。**worker 不直接执行 SQL**——它通过 libpq 创建一个新会话连接到目标数据库（即使在同一个集群内），然后异步触发命令。这意味着 N 个作业并发跑会消耗 N 个 backend 连接。
2. **跨数据库需要 libpq 而非 background worker dispatch**：因为 PG 的 background worker 必须固定连接到一个数据库，无法跨数据库发命令；用 libpq 反而绕开了这个限制。
3. **不存在跨节点协调**：在主备复制场景里，pg_cron 默认只在主库（主导写入的实例）运行；备库一般会被禁用。读副本上不应该启用 pg_cron。
4. **没有失败重试**：失败就是失败，写日志。需要重试得在 SQL 里自己实现（或用 pg_timetable）。
5. **超时与并发控制**：可通过 `cron.max_running_jobs` 限制同时运行作业数。

### 日志与故障排查

```sql
-- 最近运行历史
SELECT jobid, runid, status, return_message, start_time, end_time
FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 50;

-- 长期运行的作业
SELECT * FROM cron.job_run_details
WHERE status = 'running' AND start_time < now() - interval '1 hour';
```

### 在云托管 PG 中的差异

- **AWS RDS**：默认未启用，需要在参数组打开 `shared_preload_libraries`，并设置 `cron.database_name`。`rds_superuser` 角色可执行 `cron.schedule`。
- **Azure Database for PostgreSQL Flexible Server**：通过 server parameter `azure.extensions` 启用 pg_cron。
- **Google Cloud SQL**：通过 flag `cloudsql.enable_pg_cron` 启用，需要重启实例。
- **Crunchy Bridge / Aiven**：默认启用，无需额外配置。

### pg_cron 的局限与 pg_timetable 的补足

pg_cron 不支持：

- 子分钟粒度（最小 1 分钟）
- 任务依赖（chain）
- 任务参数化
- 失败重试
- 任务超时

为此 Cybertec 维护的 `pg_timetable` 提供了上述能力：它是一个独立的 Go 进程而非扩展，连接到 PG 后从 `timetable.chain` 表读取链定义。chain 内的多个 task 可以串行/并行执行，支持参数、超时、重试、autocleanup。

```sql
-- pg_timetable: 创建链
INSERT INTO timetable.chain
    (chain_name, run_at, max_instances, live, self_destruct)
VALUES
    ('etl_nightly', '0 1 * * *', 1, TRUE, FALSE);

-- 加入步骤（命令、参数、依赖）
INSERT INTO timetable.task
    (chain_id, task_order, kind, command, ignore_error)
VALUES
    (..., 1, 'SQL', 'CALL etl.extract($1)', FALSE),
    (..., 2, 'SQL', 'CALL etl.transform()', FALSE),
    (..., 3, 'PROGRAM', '/usr/bin/aws s3 cp ... s3://...', TRUE);
```

## MySQL EVENT Scheduler：最小可用产品

MySQL 在 5.1.6（2008）引入 `EVENT` 调度器。它一直是 MySQL 内置调度的唯一选择，但功能远不及 Oracle 或 SQL Server。

### 启用与基本语法

```sql
-- EVENT 调度器默认关闭，必须显式启用
SET GLOBAL event_scheduler = ON;

-- 周期性事件
CREATE EVENT clean_audit_logs
ON SCHEDULE
    EVERY 1 DAY
    STARTS '2026-04-30 02:00:00'
DO
    DELETE FROM audit_log WHERE created_at < NOW() - INTERVAL 90 DAY;

-- 一次性事件
CREATE EVENT one_time_migration
ON SCHEDULE AT '2026-05-01 03:00:00'
DO
    CALL run_migration();

-- 完整选项
CREATE DEFINER = 'root'@'localhost' EVENT my_event
ON SCHEDULE
    EVERY 1 HOUR
    STARTS CURRENT_TIMESTAMP
    ENDS CURRENT_TIMESTAMP + INTERVAL 30 DAY
ON COMPLETION PRESERVE          -- 结束日期到达后保留事件
ENABLE
COMMENT 'hourly stats refresh'
DO BEGIN
    -- 多语句体
    CALL refresh_stats();
    CALL log_run('hourly');
END;
```

### 调度间隔表达式

MySQL 不接受 cron 表达式，只接受 `INTERVAL` 风格的关键字：

```
EVERY <value> { YEAR | QUARTER | MONTH | WEEK | DAY
              | HOUR | MINUTE | SECOND
              | YEAR_MONTH | DAY_HOUR | DAY_MINUTE
              | DAY_SECOND | HOUR_MINUTE | HOUR_SECOND
              | MINUTE_SECOND }
```

要表达"每天凌晨 2 点"必须用 `STARTS '... 02:00:00' EVERY 1 DAY`，而不能用 `0 2 * * *`。

### 维护与查询

```sql
-- 列出所有事件
SELECT event_name, status, last_executed, definer, event_definition
FROM information_schema.events
WHERE event_schema = DATABASE();

-- 暂停 / 启用 / 删除
ALTER EVENT clean_audit_logs DISABLE;
ALTER EVENT clean_audit_logs ENABLE;
DROP EVENT clean_audit_logs;
```

### 已知局限

- **没有失败重试**：异常进 error log，事件不会自动重跑。
- **没有 chain**：多个事件之间无依赖关系。
- **没有运行日志表**：要看历史只能解析 error log 或在事件体里手动写日志表。
- **副本上的行为**：默认事件在副本上设置为 `SLAVESIDE_DISABLED`，避免双重执行。需要时通过 `SET GLOBAL event_scheduler = ON` 在副本启用，并显式 `ALTER EVENT ENABLE`。
- **一台机器上只有一个事件调度器线程**：高并发到期事件会串行化。
- **被弃用的疑虑**：MySQL 团队近年没有在 EVENT 上做大改进；许多大型部署改用外部 cron + scheduled SQL 文件。

MariaDB 完全继承这套语法，并增加了一个小改进：在 ALTER EVENT 中可以重命名（`RENAME TO new_name`）。

## Snowflake TASK：CRON × 数据仓库

Snowflake 在 2019 年推出 `TASK` 对象。它是 Snowflake 的"调度即对象"——TASK 既是元数据又是执行单元。

### 基本语法

```sql
-- 周期性 task
CREATE TASK daily_aggregation
    WAREHOUSE = etl_wh
    SCHEDULE = 'USING CRON 0 2 * * * America/Los_Angeles'
    COMMENT = 'rebuild daily aggregates'
AS
    INSERT INTO daily_agg
    SELECT date_trunc('day', ts), region, count(*)
    FROM events
    WHERE date_trunc('day', ts) = date_trunc('day', dateadd(day, -1, current_date))
    GROUP BY 1, 2;

-- 启用（默认创建后是 SUSPENDED）
ALTER TASK daily_aggregation RESUME;

-- 间隔语法（cron 之外的简化）
CREATE TASK refresh_session_summary
    WAREHOUSE = etl_wh
    SCHEDULE = '5 MINUTE'
AS
    CALL refresh_session_summary_proc();
```

CRON 字段是标准 5 字段（分 时 日 月 周），**时区是必填的**——这是 Snowflake 与其他引擎的一大差异。`USING CRON 0 2 * * * UTC` 与 `... America/New_York` 完全是两个含义，避免了夏令时切换时的歧义。

### Task 依赖（DAG）

Snowflake 的 task DAG 不是用 chain 显式定义，而是用 `AFTER` 关键字让一个 task 在另一个完成时触发：

```sql
CREATE TASK extract_task
    WAREHOUSE = etl_wh
    SCHEDULE = 'USING CRON 0 1 * * * UTC'
AS
    CALL extract_proc();

CREATE TASK transform_task
    WAREHOUSE = etl_wh
    AFTER extract_task            -- 只在 extract 成功后触发
AS
    CALL transform_proc();

CREATE TASK load_task
    WAREHOUSE = etl_wh
    AFTER transform_task
AS
    CALL load_proc();

-- 启用整个 DAG（必须从 root task 反向，先 enable 子节点）
ALTER TASK load_task RESUME;
ALTER TASK transform_task RESUME;
ALTER TASK extract_task RESUME;   -- root task 最后 enable
```

DAG 限制：

- **单 root**：每个 DAG 只能有一个根（顶层 schedule 触发）。
- **每个 task 仅一个 parent**：不允许多个 parent，要 join 必须用条件触发或额外的协调 task（最近版本通过 `FINALIZE` task 类型增加了汇合点）。
- **最多 1000 个 task / DAG**。
- **15 秒延迟**：DAG 内子 task 在父 task 完成后约 15 秒被调度——不是即时的。

### 条件触发：WHEN 子句

```sql
CREATE TASK conditional_refresh
    WAREHOUSE = etl_wh
    SCHEDULE = '15 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('orders_stream')   -- 仅当 stream 有数据时执行
AS
    MERGE INTO orders_target
    USING orders_stream s ON ...;
```

`WHEN` 与 stream 配合是 Snowflake 实现"近实时增量"的常见模式：每 15 分钟唤醒一次，但只有真正有新数据时才消耗 warehouse credits。

### Serverless TASK

```sql
CREATE TASK my_task
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SCHEDULE = '5 MINUTE'
AS
    CALL my_proc();
```

省略 `WAREHOUSE` 改用 `USER_TASK_MANAGED_*` 参数后，task 在 Snowflake 托管的"按使用计费"计算池上运行——非常适合不规律的小任务，不必为它单独保留一个 warehouse。

### 元数据视图

```sql
-- 历史运行
SELECT name, state, error_code, error_message, scheduled_time, completed_time
FROM TABLE(information_schema.task_history(
    task_name => 'daily_aggregation',
    scheduled_time_range_start => dateadd(day, -1, current_timestamp)
));

-- DAG 视图
SELECT * FROM TABLE(information_schema.task_dependents('daily_aggregation'));
```

## CockroachDB CREATE SCHEDULE

CockroachDB 在 21.x 系列引入 `CREATE SCHEDULE`，主要面向定时备份（BACKUP），后扩展到通用 SQL 调度。

```sql
-- 定时备份
CREATE SCHEDULE daily_backup
    FOR BACKUP INTO 's3://my-bucket/backups?AUTH=specified&AWS_ACCESS_KEY_ID=...'
    RECURRING '@daily'
    FULL BACKUP ALWAYS
    WITH SCHEDULE OPTIONS first_run = 'now';

-- 列表与控制
SHOW SCHEDULES;
PAUSE SCHEDULE 64;
RESUME SCHEDULE 64;
DROP SCHEDULE 64;
```

`RECURRING` 接受标准 5 字段 cron 表达式，也接受 `@daily` / `@weekly` / `@hourly` 等 nickname。`first_run = 'now'` 表示创建后立即执行第一次，否则等到下个 cron 时点。

CockroachDB 的 `CREATE SCHEDULE FOR <stmt>` 在 22.x 后可调度 BACKUP、IMPORT、CHANGEFEED，**通用 SQL 调度（任意语句）目前是企业版功能**，社区版仅限上述几种。

## Hive Scheduled Queries

Hive 4.0 引入 `CREATE SCHEDULED QUERY`，依赖 Hive Metastore 持久化、HiveServer2 触发：

```sql
CREATE SCHEDULED QUERY daily_agg
    EVERY 1 DAYS AS
    INSERT OVERWRITE TABLE daily_agg
    SELECT dt, region, COUNT(*) FROM events GROUP BY dt, region;

-- 用 cron
CREATE SCHEDULED QUERY hourly_load
    CRON '0 0 * * * ?' AS
    INSERT INTO ...;

-- 管理
ALTER SCHEDULED QUERY hourly_load DISABLE;
ALTER SCHEDULED QUERY hourly_load EVERY 30 MINUTES;
DROP SCHEDULED QUERY hourly_load;

-- 查询历史
SELECT * FROM information_schema.scheduled_executions
WHERE scheduled_query_name = 'hourly_load';
```

Hive 的调度相对简单，不支持 chain，但对于"每日 ETL 定时跑一条 SQL"这种主流批处理场景已够用。

## DB2 ADMIN_SCHEDULER

DB2 提供 `DB2 Administrative Task Scheduler`（DBATS），通过 SYSTOOLS schema 中的 `ADMIN_TASK_ADD` 等过程操作：

```sql
CALL SYSPROC.ADMIN_TASK_ADD(
    'cleanup_old_audit',     -- name
    NULL,                    -- begin_timestamp
    NULL,                    -- end_timestamp
    NULL,                    -- max_invocations
    '0 3 * * *',             -- UNIX cron string
    'mySchema',              -- procedure schema
    'PURGE_AUDIT',           -- procedure name
    NULL,                    -- procedure_input (CLOB)
    NULL,                    -- options
    'Daily audit cleanup'
);

-- 查询作业
SELECT * FROM SYSTOOLS.ADMIN_TASK_LIST;
SELECT * FROM SYSTOOLS.ADMIN_TASK_STATUS WHERE NAME = 'cleanup_old_audit';

-- 删除
CALL SYSPROC.ADMIN_TASK_REMOVE('cleanup_old_audit', NULL);
```

DBATS 不支持 chain 和参数化，但接受标准 UNIX cron，比 MySQL EVENT 灵活得多。

## SAP HANA XS Job Scheduler

HANA 的调度器与 XS（eXtended Services）应用框架绑定。一个 `xsjob` 由 `.xsjob` 配置文件 + 后端 server-side JavaScript（XSJS）或 SQLScript 过程组成。

```json
// foo.xsjob 文件
{
    "description": "Daily aggregation",
    "action": "myapp.proc::run_daily",
    "schedules": [
        {
            "description": "Every day 2 AM",
            "xscron": "* * * * 2 0 0",
            "parameter": { "mode": "full" }
        }
    ]
}
```

`xscron` 是 7 字段（年 月 日 周 时 分 秒）扩展，比标准 cron 多了"周"和"秒"。HANA 2.0 之后引入 XSA（Cloud Foundry-style）后更推荐 SAP Cloud Application Programming Model 的 cron job，但旧接口仍兼容。

## TimescaleDB Background Jobs

TimescaleDB（PG 扩展）提供独立的 `add_job` API：

```sql
-- 定义任务函数
CREATE OR REPLACE PROCEDURE compress_old_chunks(job_id INTEGER, config JSONB)
LANGUAGE PLPGSQL AS $$
BEGIN
    PERFORM compress_chunk(c)
    FROM show_chunks('metrics', older_than => INTERVAL '7 days') c;
END;
$$;

-- 添加 job（按间隔运行，无 cron）
SELECT add_job(
    'compress_old_chunks',
    schedule_interval => INTERVAL '1 day',
    initial_start     => '2026-04-30 02:00:00+00'::timestamptz,
    config            => '{"max_chunks": 100}'::jsonb
);

-- 查看
SELECT job_id, application_name, schedule_interval, next_start, scheduled
FROM timescaledb_information.jobs;

-- 历史
SELECT * FROM timescaledb_information.job_stats;
```

TimescaleDB 不接受 cron 表达式，只接受 `INTERVAL`。优势是与 hypertable / continuous aggregate 深度集成：`add_continuous_aggregate_policy()`、`add_retention_policy()`、`add_compression_policy()` 都是 background job 的封装。

## StarRocks 与 Doris：异步物化视图驱动的调度

StarRocks 异步物化视图自带"按周期刷新"语法，与调度器边界模糊：

```sql
-- StarRocks 异步 MV
CREATE MATERIALIZED VIEW mv_orders_daily
REFRESH ASYNC
START('2026-04-30 00:00:00') EVERY (INTERVAL 1 HOUR)
AS
SELECT date_trunc('day', ordered_at) AS day, region, sum(amount)
FROM orders GROUP BY 1, 2;
```

Doris 在 2.1+ 支持独立的 `JOB` 语句：

```sql
CREATE JOB my_purge
    ON SCHEDULE
        AT '2026-04-30 02:00:00'                   -- 一次性
        -- 或 EVERY 1 DAY
        -- 或 ON SCHEDULE STARTS '... ' EVERY 1 HOUR
DO BEGIN
    DELETE FROM events WHERE event_date < CURDATE() - INTERVAL 30 DAY;
END;

SHOW JOBS;
```

Doris 的 JOB 语法明显借鉴 MySQL EVENT，对 MySQL 用户来说迁移成本低。

## Vertica Scheduler

Vertica 提供 `STORED PROCEDURE` + `Scheduler`，主要服务于 Kafka 数据加载（Vertica 的招牌场景之一）：

```sql
-- 创建 scheduler 实例
SELECT KAFKA_UTIL_SCHEDULER('--add', 'kafka_sched', '--frame-duration=00:00:10');

-- 关联 streaming source
SELECT KAFKA_CONFIG_SCHEDULER('kafka_sched', '--add-source=...', ...);

-- 启用
SELECT KAFKA_UTIL_SCHEDULER('--start', 'kafka_sched');
```

通用作业调度需要外部工具（如 `dbadmin` 用户的 crontab）。

## Informix dbcron / Sysadmin Scheduler

Informix 11.5+ 提供基于 Sysadmin 数据库的调度器，类似 cron 风格：

```sql
DATABASE sysadmin;

INSERT INTO ph_task (
    tk_name, tk_description, tk_type,
    tk_group, tk_execute,
    tk_start_time, tk_stop_time,
    tk_frequency
) VALUES (
    'NightlyVacuum', 'Compact storage', 'TASK',
    'STORAGE', 'EXECUTE FUNCTION compact_all_tables()',
    DATETIME (02:00:00) HOUR TO SECOND, NULL,
    '1 00:00:00'        -- 每 1 天
);
```

不接受 cron 字符串，但接受 `INTERVAL`、起止时间、按月按周相对位置等灵活表达。

## Databricks Workflows

Databricks 已经超越"调度器"范畴，是工作流编排器：

```python
# JSON 描述 (Workflows API / Terraform)
{
  "name": "daily_etl",
  "schedule": {
    "quartz_cron_expression": "0 0 2 * * ?",
    "timezone_id": "UTC"
  },
  "tasks": [
    {"task_key": "extract", "notebook_task": {...}},
    {"task_key": "transform", "depends_on": [{"task_key": "extract"}], ...},
    {"task_key": "load", "depends_on": [{"task_key": "transform"}], ...}
  ]
}
```

支持：

- 7 字段 Quartz cron
- 任务依赖 DAG
- File-arrival 触发
- Delta change 触发
- Continuous mode（持续重启）
- Repair runs（仅重跑失败的子任务）

完全是企业级编排器水平。

## InfluxDB Tasks 与 BigQuery Scheduled Queries

```flux
// InfluxDB 2.x Flux Task
option task = {name: "downsample_5m", every: 5m}

from(bucket: "metrics")
    |> range(start: -task.every)
    |> aggregateWindow(every: 1m, fn: mean)
    |> to(bucket: "metrics_5m")
```

```sql
-- BigQuery 通过 console / bq CLI 注册
bq mk --transfer_config \
   --display_name='daily_dashboard_refresh' \
   --schedule='every 24 hours' \
   --params='{"query":"INSERT INTO ds.daily_t SELECT ... FROM ds.events ..."}' \
   --target_dataset=ds \
   --data_source=scheduled_query
```

BigQuery Scheduled Queries 对接 BigQuery Data Transfer Service，调度时间用自然语言（"every 24 hours"）或 cron。失败可通过 Cloud Pub/Sub 通知。

## DatabendDB TASK

新生代云数仓 Databend 在 1.2+ 推出 TASK，明显借鉴了 Snowflake：

```sql
CREATE TASK my_task
    WAREHOUSE = 'small'
    SCHEDULE = '5 MINUTE'
AS
    INSERT INTO target SELECT * FROM staging WHERE processed = false;

ALTER TASK my_task RESUME;
```

支持 cron 表达式、AFTER 依赖、WHEN 条件——基本是 Snowflake TASK 的开源 SQL 版子集。

## 关键设计取舍

### 1. 是否提供内建调度器：哲学差异

PostgreSQL 核心多次拒绝把调度器纳入主线，理由是 "OS 已经有 cron"。这种设计被指责为"开机即用体验差"，但也保持了核心精简，避免了把 background worker 行为标准化的负担——结果就是 pg_cron / pg_timetable / Patroni hook / OS crontab 多种方案并存，每种部署都得选。

Oracle 的相反哲学：把数据库做成"运行时操作系统"。DBMS_SCHEDULER 不仅有 cron，还有 calendar、chain、window、resource plan 联动——把企业批处理直接吞进 RDBMS 内部。代价是学习曲线陡，PL/SQL 强绑定。

云数仓（Snowflake / BigQuery / Databricks）选择中间路径：提供 cron + 简单 DAG，深入功能交给云供应商的工作流服务（Snowflake Tasks → Streams 配套；BigQuery Scheduled Queries → Cloud Composer/Workflows）。

### 2. cron 表达式是否标配

cron 表达式简单、行业熟悉。但它的弱点也明显：

- 不能表达"每月最后一天"（需要技巧 `0 0 28-31 * * test $(date -d tomorrow +\%d) -eq 1`）。
- 不能表达"每月第二个周二"（标准 5 字段做不到，Quartz 7 字段加 `#` 才能）。
- 不能跨时区表达"夏令时之后调整"。

Oracle 抛弃 cron 改用自家 calendar string 是有道理的——它确实能干 cron 干不了的事。但代价是多了一种 DSL 要学。

主流取舍是**接受 cron 字符串作为最低公分母**，但允许扩展（Snowflake 的时区必填、Databricks 的 Quartz 7 字段、Hive 的混合）。

### 3. 调度器进程：内嵌 vs 独立

| 模型 | 代表 | 优点 | 缺点 |
|------|------|------|------|
| 独立服务进程 | SQL Server Agent (msdb)、pg_timetable | 与 DB 故障隔离 | 多一个进程要部署/监控 |
| 数据库内 background worker | pg_cron、TimescaleDB | 部署简单 | DB 重启影响 schedule |
| PL/SQL 内嵌 + 多线程 | Oracle DBMS_SCHEDULER (job slave processes) | 完整集成 | 资源耗用与 DB 共享 |
| 客户端库定时任务（如 cron + psql 脚本）| 通用 | 极简 | 状态分散，难治理 |

### 4. 高可用与多副本协调

最棘手的问题：调度器在主备 / 多 leader / 分片集群里要不要"不重不漏"？

- **MySQL EVENT**：副本上自动 disable，主切换需要手动启用（`SLAVESIDE_DISABLED` 状态需要 `ALTER EVENT ENABLE` 才会激活）。
- **pg_cron**：默认只在主库运行；备库被推到读流量时事件不会跑（连接到 hot standby 的 cron 即使表上有作业，也无法写日志，事实上无效）。failover 后新 primary 启动 cron worker 接管。
- **Oracle DBMS_SCHEDULER**：在 Data Guard 切换中由角色（primary/standby）决定是否调度。
- **Snowflake TASK**：完全云托管，多区域可用性由 Snowflake 负责。
- **CockroachDB**：作为分布式 SQL，scheduler 元数据本身分布式存储，任意节点接管运行（基于 lease holder）。

### 5. 失败、重试与告警

| 引擎 | 失败重试 | 告警通道 |
|------|---------|---------|
| Oracle | 是（job 级 retry_count + retry_delay）| 内建邮件、Enterprise Manager |
| SQL Server Agent | 是（step 级）| Operator 邮件 / pager / Net Send（已废弃） |
| pg_cron | 否（只记录失败）| 自行实现 |
| pg_timetable | 是（task 级 retry_count）| 自行实现 |
| MySQL EVENT | 否 | 仅 error log |
| Snowflake TASK | 否（默认；可在 SQL 内实现 retry） | EMAIL via integrations |
| Databricks Jobs | 是（max_retries / retry_on_timeout）| 邮件 / Slack / PagerDuty |
| TimescaleDB | 是（max_retries）| 通过 hook |
| Hive | 否 | 监控历史表 |
| CockroachDB | 部分（基于 schedule 状态） | 监控视图 |

### 6. 调度精度与最小间隔

| 引擎 | 最小间隔 | 备注 |
|------|---------|------|
| Oracle DBMS_SCHEDULER | 1 秒 | calendar 支持 SECONDLY |
| SQL Server Agent | 10 秒 | sub-day frequency |
| MySQL EVENT | 1 秒 | INTERVAL SECOND |
| pg_cron | 1 分钟 | cron 限制 |
| pg_timetable | 1 秒 | -- |
| Snowflake TASK | 1 分钟（cron）/ 1 秒（间隔语法的最小是 1 分钟）| -- |
| CockroachDB | 1 分钟 | cron |
| TimescaleDB | 1 微秒（INTERVAL）| 实际取决于 background worker 调度延迟 |
| Hive | 1 分钟 | -- |
| Databricks Jobs | 1 分钟 | continuous mode 是另一个语义 |

亚分钟调度应当避免——它通常意味着应该用流处理（Flink / Materialize / RisingWave）而不是反复触发批任务。

## 实战场景与最佳实践

### 场景 1：定时刷新统计信息

```sql
-- Oracle: gather table stats nightly
DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'STATS_NIGHTLY',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN DBMS_STATS.GATHER_SCHEMA_STATS(USER); END;',
    repeat_interval => 'FREQ=DAILY; BYHOUR=2',
    enabled         => TRUE
);

-- PostgreSQL pg_cron
SELECT cron.schedule('analyze-nightly', '0 2 * * *', 'ANALYZE VERBOSE');

-- SQL Server Agent (one-step T-SQL job)
EXEC sp_add_jobstep
    @job_name = 'NightlyStats',
    @step_name = 'sp_updatestats',
    @subsystem = N'TSQL',
    @command   = N'EXEC sp_updatestats';
```

### 场景 2：周期清理历史数据

```sql
-- MySQL EVENT
CREATE EVENT purge_old_audit
ON SCHEDULE EVERY 1 DAY STARTS '2026-04-30 03:00:00'
DO
    DELETE FROM audit_log WHERE created_at < NOW() - INTERVAL 90 DAY LIMIT 100000;

-- Snowflake TASK
CREATE TASK purge_old_events
    WAREHOUSE = ops_wh
    SCHEDULE = 'USING CRON 0 4 * * * UTC'
AS
    DELETE FROM events WHERE event_time < dateadd(day, -180, current_timestamp);
```

`LIMIT 100000` 在 MySQL 是必须的——一次性 DELETE 几亿行会撑爆 undo log，分批删除是惯用做法。

### 场景 3：物化视图刷新

```sql
-- PostgreSQL + pg_cron + REFRESH CONCURRENTLY
SELECT cron.schedule(
    'refresh-mv-dau',
    '*/5 * * * *',
    $$REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.dau$$
);

-- StarRocks 异步 MV（调度内置在 MV 定义中）
CREATE MATERIALIZED VIEW mv_dau
REFRESH ASYNC EVERY (INTERVAL 5 MINUTE)
AS SELECT date(login_at) d, count(distinct user_id) FROM logins GROUP BY 1;

-- Oracle MV with NEXT
CREATE MATERIALIZED VIEW mv_orders_daily
REFRESH FORCE
START WITH SYSDATE NEXT SYSDATE + 1/24
AS SELECT date_trunc('hour', ordered_at) h, sum(amount) FROM orders GROUP BY 1;
```

### 场景 4：备份调度

```sql
-- CockroachDB
CREATE SCHEDULE backup_daily
    FOR BACKUP INTO 's3://backups/clusterX' WITH revision_history
    RECURRING '@daily'
    FULL BACKUP '@weekly';

-- SQL Server Agent (call BACKUP DATABASE)
EXEC sp_add_jobstep
    @job_name = 'BackupAdventureWorks',
    @step_name = 'Full Backup',
    @subsystem = N'TSQL',
    @command   = N'BACKUP DATABASE [AdventureWorks] TO DISK = N''D:\Backups\AW.bak''';
```

### 场景 5：依赖链 ETL

```sql
-- Snowflake DAG
CREATE TASK extract_t SCHEDULE='USING CRON 0 1 * * * UTC' WAREHOUSE=etl AS CALL etl.extract();
CREATE TASK transform_t AFTER extract_t WAREHOUSE=etl AS CALL etl.transform();
CREATE TASK load_t AFTER transform_t WAREHOUSE=etl AS CALL etl.load();
ALTER TASK load_t RESUME;
ALTER TASK transform_t RESUME;
ALTER TASK extract_t RESUME;
```

```sql
-- Oracle CHAIN（参见 Oracle 章节）
```

```sql
-- pg_timetable chain（参见 pg_cron 章节末尾）
```

### 反模式：用调度器做"近实时"流处理

如果一个任务跑得比 cron 间隔还频繁（"每分钟刷新一次"），且每次跑都几乎读全表，那真正想要的不是调度，是流式增量处理。换成 Materialize / RisingWave / ClickHouse REFRESHABLE / Snowflake STREAM + TASK 组合更合适。

### 反模式：在调度器里做长时间事务

调度任务持有大事务对 OLTP 库是灾难——`UPDATE 10M rows` 会撑爆 undo / WAL。最佳实践：

1. 分批（`LIMIT N` + 循环）
2. 每批独立提交
3. 在调度器里把批次大小作为参数

```sql
-- MySQL: chunked delete pattern
CREATE EVENT chunked_purge
ON SCHEDULE EVERY 5 MINUTE
DO BEGIN
    DECLARE rows_affected INT DEFAULT 1;
    WHILE rows_affected > 0 DO
        DELETE FROM audit_log
        WHERE created_at < NOW() - INTERVAL 90 DAY
        ORDER BY id LIMIT 5000;
        SET rows_affected = ROW_COUNT();
        DO SLEEP(0.1);  -- 让 OLTP 喘息
    END WHILE;
END;
```

## 监控与可观测性建议

不论用哪个引擎，**调度作业必须有"运行历史" + "失败告警"**，否则就是定时炸弹。最小要求：

1. 一张永久存储的运行历史表（job_name, status, start_ts, end_ts, error_msg, host）
2. 失败 → 告警通道（邮件 / Slack / PagerDuty）
3. 长期未运行的作业告警（"上次运行 > 期望间隔 × 2"）
4. 关键指标 dashboard：成功率、运行时长 P95、并发度

许多团队的盲点：作业 disable 后没人发现。**应在监控里加"作业 enabled 但长时间未运行"告警**。

## 跨引擎迁移参考

从 Oracle 迁到 PostgreSQL 时调度器迁移路径：

| Oracle 概念 | pg_cron + pg_timetable 对应 |
|------------|---------------------------|
| `DBMS_SCHEDULER.CREATE_JOB` | `cron.schedule()` 或 `timetable.add_job()` |
| `repeat_interval` calendar string | cron 5 字段（功能子集）|
| `CREATE_PROGRAM` | 无直接对应；用存储过程 + cron |
| `CREATE_CHAIN` | `pg_timetable` 的 chain |
| `CREATE_WINDOW` | 无对应；用 cron 表达式表达时间段 |
| `BYSETPOS` 表达式 | 不支持；需 `WHEN` 子句过滤 |
| `*_SCHEDULER_JOB_LOG` | `cron.job_run_details` |

从 MySQL 迁到 Doris：语法相近，几乎可直接搬。

从 SQL Server Agent 迁到 Snowflake：JOB → TASK，STEP 之间的 `on_success_action` → `AFTER` 子句构造 DAG。

## 关键发现

1. **SQL 标准从未定义调度器**，所以 45+ 引擎里出现了 26 套互不兼容的语法。
2. **Oracle DBMS_SCHEDULER 是迄今功能最丰富的实现**，唯一在企业级层面同时提供 calendar / chain / window / resource plan 的方案。
3. **PostgreSQL 核心始终拒绝纳入调度器**，pg_cron（Citus, 2015）成为事实标准，AWS / Azure / GCP 全部内置。
4. **MySQL EVENT 自 5.1.6 起就基本停滞**，缺重试、缺 chain、缺日志，是"最小可用产品"。
5. **SQL Server Agent (1998) 是最早的工业级调度器**，模型至今仍在用。
6. **现代云数仓（Snowflake / BigQuery / Databricks）原生支持 cron-based 调度**，CockroachDB 在 21.x 跟进。
7. **TiDB / DuckDB / ClickHouse / Trino / Spark SQL 等 OLAP 引擎不内建调度**，依赖外部工具（Airflow / Prefect / Dagster）。
8. **chain / DAG 是分水岭**：Oracle / SQL Server / Snowflake / Databricks / pg_timetable 提供，其他大多没有。
9. **时区是高频踩坑点**：建议永远显式指定时区（Snowflake 强制要求）。
10. **调度器不是流处理**：亚分钟刷新 + 全表扫描是反模式，应换成 Materialize / RisingWave / Flink 等持续语义系统。
11. **失败重试 + 告警是必须**，但很多引擎只提供"记录"不提供"重试"，需要在 SQL 中自行实现。
12. **副本 / failover 行为差异巨大**：MySQL EVENT 默认副本 disable，pg_cron 仅主库运行，Oracle 由 Data Guard 角色决定，必须在迁移前确认。

## 参考资料

- Oracle: [DBMS_SCHEDULER Reference](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_SCHEDULER.html)
- Oracle: [Scheduler Concepts](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/scheduler-concepts.html)
- SQL Server: [SQL Server Agent](https://learn.microsoft.com/en-us/sql/ssms/agent/sql-server-agent)
- SQL Server: [sp_add_job (Transact-SQL)](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-add-job-transact-sql)
- PostgreSQL pg_cron: [GitHub citusdata/pg_cron](https://github.com/citusdata/pg_cron)
- pg_timetable: [GitHub cybertec-postgresql/pg_timetable](https://github.com/cybertec-postgresql/pg_timetable)
- MySQL: [Event Scheduler](https://dev.mysql.com/doc/refman/8.0/en/events.html)
- MariaDB: [Events](https://mariadb.com/kb/en/events/)
- DB2: [Administrative Task Scheduler](https://www.ibm.com/docs/en/db2/11.5?topic=routines-administrative-task-scheduler)
- SAP HANA: [XS Job Scheduler](https://help.sap.com/docs/SAP_HANA_PLATFORM/4505d0bdaf4948449b7f7379d24d0f0d/35e6ec03ff924c0baff067f5acb78ed8.html)
- CockroachDB: [CREATE SCHEDULE FOR BACKUP](https://www.cockroachlabs.com/docs/stable/create-schedule-for-backup)
- Snowflake: [Tasks](https://docs.snowflake.com/en/user-guide/tasks-intro)
- Snowflake: [CREATE TASK](https://docs.snowflake.com/en/sql-reference/sql/create-task)
- BigQuery: [Scheduled Queries](https://cloud.google.com/bigquery/docs/scheduling-queries)
- Hive: [Scheduled Queries (HIVE-21884)](https://cwiki.apache.org/confluence/display/Hive/Scheduled+Queries)
- TimescaleDB: [User-defined actions](https://docs.timescale.com/use-timescale/latest/user-defined-actions/)
- Databricks: [Jobs / Workflows](https://docs.databricks.com/en/workflows/jobs/index.html)
- StarRocks: [Asynchronous materialized views](https://docs.starrocks.io/docs/using_starrocks/Materialized_view/)
- Apache Doris: [JOB](https://doris.apache.org/docs/sql-manual/sql-statements/Data-Definition-Statements/Create/CREATE-JOB)
- Citus: [Scheduling jobs in Postgres with pg_cron](https://www.citusdata.com/blog/2016/09/09/pgcron-run-periodic-jobs-in-postgres/) (2016)
- Snowflake Engineering Blog: [Tasks: Triggering Periodic Workflow Execution](https://www.snowflake.com/blog/) (2019)
