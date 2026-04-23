# 查询计划稳定性 (Query Plan Stability and Management)

数据库升级之后最常见的一类线上事故不是功能回归，而是"同样的 SQL 变慢了"。统计信息刷新、优化器参数改动、版本补丁、甚至绑定变量的值变化，都可能让一条原本毫秒级的查询突然走成全表扫描。对大型企业而言，一次计划漂移 (plan regression) 造成的批处理超时、OLTP 超限、服务雪崩，单次损失往往以百万美元计，这是 Oracle、SQL Server、DB2 等老牌引擎长期投入 SQL Plan Management (SPM)、Query Store、OPTGUIDELINE 的根本动机。

## 没有 SQL 标准

SQL 标准只定义查询语言，不涉及执行计划如何生成、如何固化、如何演化。ISO/IEC 9075 没有任何关于 plan baseline、plan freeze、plan evolution 的规定。每个引擎根据自身优化器架构设计了完全独立的一套机制，语法、存储、演化策略差异极大：

- Oracle: `DBMS_SPM` + `SQL_PLAN_BASELINE`
- SQL Server: `sys.query_store_*` DMV + `sp_query_store_force_plan`
- DB2: XML 格式的 Optimization Profile (`OPTGUIDELINE`)
- TiDB / OceanBase / PolarDB: `CREATE BINDING` / `OUTLINE`
- PostgreSQL / MySQL: 无原生 SPM，依赖扩展 (pg_hint_plan, query_rewrite_plugin)
- 云数仓 (Snowflake/BigQuery): 哲学上拒绝 plan management

## 支持矩阵（综合）

### 计划基线与锁定

| 引擎 | 计划基线 | 计划冻结/强制 | 自动捕获 | 手动捕获 | 版本 |
|------|---------|--------------|---------|---------|------|
| PostgreSQL | -- | 扩展 (pg_hint_plan) | -- | 扩展 | -- |
| MySQL | -- | Query Rewrite Plugin (改写式) | -- | Optimizer Hints | 5.7+ |
| MariaDB | -- | -- | -- | Optimizer Hints | 10.0+ |
| SQLite | -- | -- | -- | -- | -- |
| Oracle | SQL Plan Baseline | `FIXED` 基线 | 是 | `DBMS_SPM.LOAD_PLANS_*` | 11gR1 (2007) |
| SQL Server | Query Store | `sp_query_store_force_plan` | 是 | `sp_query_store_force_plan` | 2016+ |
| DB2 | Optimization Profile | `OPTGUIDELINE` XML | -- | `SYSTOOLS.OPT_PROFILE` | 9.1 (2006) |
| Snowflake | -- | -- | -- | -- | 不支持 |
| BigQuery | -- | -- | -- | -- | 不支持 |
| Redshift | -- | -- | -- | -- | 不支持 |
| DuckDB | -- | -- | -- | -- | 不支持 |
| ClickHouse | -- | -- | -- | -- | 不支持 |
| Trino | -- | -- | -- | -- | 不支持 |
| Presto | -- | -- | -- | -- | 不支持 |
| Spark SQL | -- | -- | -- | -- | 不支持 |
| Hive | -- | -- | -- | -- | 不支持 |
| Flink SQL | -- | -- | -- | -- | 不支持 |
| Databricks | -- | -- | -- | -- | 不支持 |
| Teradata | Query Capture DB | `Statement Locking` | 是 | 是 | V2R6+ |
| Greenplum | -- | 继承 PG (pg_hint_plan) | -- | 扩展 | -- |
| CockroachDB | Plan Gists | -- | 是 (采集) | -- | 22.2+ (2022) |
| TiDB | SQL Binding | `CREATE BINDING` | 是 (evolve) | 是 | 4.0 (2020) |
| OceanBase | Outline / SPM | `CREATE OUTLINE` | 是 (4.0+) | 是 | 1.4+ / 4.0+ |
| YugabyteDB | -- | 继承 PG (pg_hint_plan) | -- | 扩展 | -- |
| SingleStore | Plancache | `RECORD_PLANCACHE` | 是 | -- | 7.0+ |
| Vertica | Directed Queries | 是 | -- | 是 | 8.0+ |
| Impala | -- | -- | -- | Query Hints | -- |
| StarRocks | SQL Plan Manager | `CREATE BASELINE` | 3.3+ | 是 | 3.3 (2024) |
| Doris | SQL Binding | `CREATE SQL_BLOCK_RULE` | -- | 是 | 2.0+ |
| MonetDB | -- | -- | -- | -- | 不支持 |
| CrateDB | -- | -- | -- | -- | 不支持 |
| TimescaleDB | -- | 继承 PG | -- | 扩展 | -- |
| QuestDB | -- | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | Hints | 不支持 |
| SAP HANA | Plan Stability | `ALTER SYSTEM CAPTURE` | 是 | 是 | 2.0 SPS 04+ |
| Informix | SQL Directive | `SET OPTIMIZATION` | -- | 是 | 11.70+ |
| Firebird | -- | -- | -- | -- | 不支持 |
| H2 | -- | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | -- | 不支持 |
| Amazon Athena | -- | -- | -- | -- | 不支持 |
| Azure Synapse | Query Store (Dedicated) | `sp_query_store_force_plan` | 是 (Dedicated) | 是 | GA |
| Google Spanner | -- | `STATEMENT_HINT` | -- | Hint | -- |
| Materialize | -- | -- | -- | -- | 不支持 |
| RisingWave | -- | -- | -- | -- | 不支持 |
| InfluxDB (SQL) | -- | -- | -- | -- | 不支持 |
| DatabendDB | -- | -- | -- | -- | 不支持 |
| Yellowbrick | -- | -- | -- | -- | 不支持 |
| Firebolt | -- | -- | -- | -- | 不支持 |

> 统计：约 14 个引擎提供完整的或部分的 plan management 能力；超过 30 个引擎完全不提供或只能靠 Hint 实现"伪稳定"。

### 计划演化 / 回归检测

| 引擎 | 计划演化 (Evolve) | 自动强制 | 回归自动回滚 | 版本 |
|------|-------------------|---------|-------------|------|
| Oracle | `DBMS_SPM.EVOLVE_SQL_PLAN_BASELINE` | 否 (11g), 是 (12c+) | 是 (SPM verify) | 11gR1+ |
| SQL Server | Query Store Auto Tuning | `FORCE_LAST_GOOD_PLAN` | 是 | 2017+ |
| DB2 | Profile 手动替换 | -- | -- | -- |
| TiDB | `Evolve Binding` | 是 | 是 | 4.0+ |
| OceanBase | SPM Evolution | 4.0+ | 4.0+ | 4.0+ |
| SAP HANA | Capture and Replay | 是 | 部分 | 2.0 SPS 04+ |
| StarRocks | Plan Baseline Cache | 是 | -- | 3.3+ |
| 其他 | -- | -- | -- | -- |

### 计划变化可观察性

| 引擎 | 计划历史 | Plan ID / Hash | 回归报告 | 源视图 |
|------|---------|----------------|---------|--------|
| Oracle | `DBA_HIST_SQL_PLAN` + AWR | `PLAN_HASH_VALUE` | 是 (SQL Tuning Advisor) | AWR / ASH |
| SQL Server | `sys.query_store_plan` | `query_plan_hash` | 是 (Query Store Reports) | Query Store |
| DB2 | `MON_GET_PKG_CACHE_STMT` | `STMT_EXEC_ID` | -- | MON |
| PostgreSQL | 扩展 (pg_stat_statements) | `queryid` | 社区扩展 | pg_stat_statements |
| MySQL | `events_statements_summary_by_digest` | `DIGEST` | -- | PS |
| TiDB | `STATEMENTS_SUMMARY` + `Statement Summary` | `DIGEST` + `PLAN_DIGEST` | 是 (evolve) | information_schema |
| CockroachDB | `crdb_internal.statement_statistics` | `plan_gist` | 部分 | crdb_internal |
| OceanBase | `GV$OB_SQL_AUDIT` | `PLAN_HASH` | 是 | sys tenants |
| SAP HANA | `M_SQL_PLAN_CACHE` | `PLAN_ID` | 是 | M_ views |
| Teradata | Query Capture Database (QCD) | `QueryID` | 是 (TASM/TVI) | QCD |
| SingleStore | `PLANCACHE` view | `PLAN_ID` | 部分 | information_schema |
| StarRocks | `_statistics_.baseline_meta` | `plan_id` | -- | information_schema |

## Oracle SQL Plan Management (SPM) 深入

### 架构概览

Oracle 在 11gR1 (2007) 引入 SPM，替代 8i 时代功能有限的 "Stored Outlines"。核心目标是**允许优化器探索新计划，但只有经过验证确认不劣化才生效**。整个机制建立在三个字典表上：

```
SQL Management Base (SMB)
  ├─ SQLPLAN$       -- 每个 SQL 语句的所有已知计划 (baselines)
  ├─ SQLOBJ$        -- 存储每条 SQL 的元数据 (signature, statement)
  └─ SQLLOG$        -- 日志 / 统计
```

每个 baseline 有三个关键状态位：

- `ENABLED` = YES / NO：是否允许被使用
- `ACCEPTED` = YES / NO：是否已通过验证
- `FIXED` = YES / NO：是否强制使用 (不允许被新的 baseline 替代)

优化器工作流：

```
1. 解析 SQL → 生成 cost-based 最优计划 (candidate plan)
2. 检查 SMB 中是否有 SIGNATURE 匹配的 baseline
   ├─ 无 baseline: 按普通 CBO 执行
   └─ 有 baseline:
       ├─ 若 FIXED baseline 存在 → 强制使用它
       ├─ 若 ACCEPTED=YES 的 baseline 包含 candidate → 使用 candidate
       └─ 否则: 用 ACCEPTED=YES 中代价最低的 baseline
                同时把 candidate plan 作为 ACCEPTED=NO 的新条目保存
                (等待 DBA 手动或定时任务 EVOLVE)
```

### 自动捕获 (Automatic Capture)

```sql
-- 会话级开启 (SPM 自动捕获从第 2 次执行该 SQL 开始生效)
ALTER SESSION SET OPTIMIZER_CAPTURE_SQL_PLAN_BASELINES = TRUE;

-- 系统级开启
ALTER SYSTEM SET OPTIMIZER_CAPTURE_SQL_PLAN_BASELINES = TRUE;

-- 使用 baseline (默认 TRUE, 除非显式关闭)
ALTER SYSTEM SET OPTIMIZER_USE_SQL_PLAN_BASELINES = TRUE;

-- 查看已捕获的 baseline
SELECT sql_handle, plan_name, enabled, accepted, fixed, origin, created, last_executed
FROM   dba_sql_plan_baselines
ORDER BY created DESC;
```

Oracle 默认策略：自动捕获只记录至少执行过 2 次的 SQL，避免一次性查询污染 SMB。第一次执行的计划自动成为 ACCEPTED=YES 的初始 baseline。之后如果优化器生成了不同的 candidate plan，只会以 ACCEPTED=NO 存入，等待 EVOLVE。

### 手动捕获

```sql
-- 方式 1: 从当前 cursor cache 批量加载
DECLARE
    l_loaded PLS_INTEGER;
BEGIN
    l_loaded := DBMS_SPM.LOAD_PLANS_FROM_CURSOR_CACHE(
        sql_id => 'abc123xyz9876'
    );
    DBMS_OUTPUT.PUT_LINE('Loaded: ' || l_loaded);
END;
/

-- 方式 2: 从 AWR 历史加载 (覆盖故障窗口之前的好计划)
DECLARE
    l_loaded PLS_INTEGER;
BEGIN
    l_loaded := DBMS_SPM.LOAD_PLANS_FROM_AWR(
        begin_snap => 12345,
        end_snap   => 12400,
        basic_filter => q'[sql_id = 'abc123xyz9876']'
    );
END;
/

-- 方式 3: 从一个 SQL Tuning Set (STS) 加载
DECLARE
    l_loaded PLS_INTEGER;
BEGIN
    l_loaded := DBMS_SPM.LOAD_PLANS_FROM_SQLSET(
        sqlset_name => 'my_production_sts',
        basic_filter => 'elapsed_time > 1000000'
    );
END;
/
```

### 计划演化 (Evolution) - SPM 的灵魂

Evolution 是 SPM 区别于简单 "plan lock" 的核心：允许新 candidate plan 被证明更优后自动接受：

```sql
-- 11gR2 手动演化
DECLARE
    l_report CLOB;
BEGIN
    l_report := DBMS_SPM.EVOLVE_SQL_PLAN_BASELINE(
        sql_handle => 'SQL_abc123',
        plan_name  => 'SQL_PLAN_xyz',
        verify     => 'YES',    -- 验证新计划性能
        commit     => 'YES'     -- 确认接受
    );
END;
/

-- 12c+ 自动演化任务 (SPM_EVOLVE_ADVISOR_TASK)
BEGIN
    DBMS_SPM.SET_EVOLVE_TASK_PARAMETER(
        task_name => 'SYS_AUTO_SPM_EVOLVE_TASK',
        parameter => 'ACCEPT_PLANS',
        value     => 'TRUE'
    );
END;
/

-- 启动 evolve 任务 (通常由自动维护窗口触发)
DECLARE
    l_task_name VARCHAR2(30) := 'my_evolve_task';
    l_name      VARCHAR2(30);
BEGIN
    l_name := DBMS_SPM.CREATE_EVOLVE_TASK(
        sql_handle => 'SQL_abc123'
    );
    DBMS_SPM.EXECUTE_EVOLVE_TASK(task_name => l_name);
    DBMS_OUTPUT.PUT_LINE(DBMS_SPM.REPORT_EVOLVE_TASK(task_name => l_name));
END;
/
```

Evolve 的验证规则：

```
对同一个 SQL，依次执行 (在真实数据上):
  1. 当前 ACCEPTED baseline 的计划 → 记录 buffer gets, elapsed time
  2. 候选 (ACCEPTED=NO) 计划 → 记录同样的指标
  3. 如果候选计划的 buffer gets / elapsed time 显著低于当前 baseline
     (Oracle 内置阈值 ~10x factor)
     → 将候选置为 ACCEPTED=YES
  4. 否则保持 ACCEPTED=NO, 不使用
```

### FIXED baseline - 紧急止损

```sql
-- 当知道某计划最稳定时，把它标记为 FIXED，阻止后续 evolve
BEGIN
    DBMS_SPM.ALTER_SQL_PLAN_BASELINE(
        sql_handle      => 'SQL_abc123',
        plan_name       => 'SQL_PLAN_the_good_one',
        attribute_name  => 'fixed',
        attribute_value => 'YES'
    );
END;
/
```

FIXED baseline 的存在会让优化器跳过对新 candidate 的验证 - 这是紧急止损的最后手段。

### Adaptive Query Plans (12c) vs SPM

这两者经常被混淆，但解决的是完全不同的问题：

| 特性 | Adaptive Query Plans | SQL Plan Management |
|------|---------------------|---------------------|
| 触发时机 | 执行过程中 | 查询优化阶段 |
| 切换粒度 | 单次执行内切换 (如 NL → HJ) | 不同执行间复用固化计划 |
| 生效持久性 | 本次执行 | 跨 session / 跨重启 |
| 数据源 | 运行时统计 | 历史计划库 (SMB) |
| 适用问题 | 优化时估错行数 | 版本升级 / 统计漂移引发的回归 |

### Adaptive Cursor Sharing (11g)

ACS 解决的是"绑定变量倾斜"问题：同一 SQL 不同绑定值应该有不同计划。与 SPM 正交 - SPM 作用于一条 SQL 的所有执行，ACS 作用于同一 SQL 的不同 bind 值。

## SQL Server Query Store 深入

### 架构

SQL Server 2016 引入 Query Store，每个数据库独立开启：

```sql
-- 开启
ALTER DATABASE mydb SET QUERY_STORE = ON (
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 90),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 60,
    MAX_STORAGE_SIZE_MB = 1000,
    QUERY_CAPTURE_MODE = AUTO,           -- AUTO | ALL | NONE | CUSTOM
    SIZE_BASED_CLEANUP_MODE = AUTO,
    MAX_PLANS_PER_QUERY = 200
);
```

存储结构 (全部存入数据库本身的 internal 表):

```
Query Store
  ├─ sys.query_store_query_text    -- 原始 SQL 文本
  ├─ sys.query_store_query          -- 查询元数据 (批次/上下文)
  ├─ sys.query_store_plan           -- XML 格式的执行计划
  ├─ sys.query_store_runtime_stats  -- 每计划执行统计 (CPU/duration/reads)
  ├─ sys.query_store_wait_stats     -- 等待事件统计 (2017+)
  └─ sys.query_store_runtime_stats_interval -- 时间切片
```

### 强制计划 (Force Plan)

```sql
-- 找出某个 SQL 的所有计划
SELECT q.query_id, p.plan_id, p.is_forced_plan,
       rs.avg_duration, rs.count_executions,
       CAST(p.query_plan AS XML) AS plan_xml
FROM   sys.query_store_query q
JOIN   sys.query_store_plan  p  ON p.query_id = q.query_id
JOIN   sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
WHERE  q.query_text_id IN (
    SELECT query_text_id FROM sys.query_store_query_text
    WHERE  query_sql_text LIKE '%Orders%ShipDate%'
);

-- 强制一个计划
EXEC sp_query_store_force_plan @query_id = 42, @plan_id = 73;

-- 取消强制
EXEC sp_query_store_unforce_plan @query_id = 42, @plan_id = 73;

-- 删除特定计划 (下次执行重新编译)
EXEC sp_query_store_remove_plan @plan_id = 73;

-- 清空整个 Query Store
ALTER DATABASE mydb SET QUERY_STORE CLEAR;
```

强制后，每次执行都会尝试使用该 plan_id 的计划形状。如果由于对象丢失或提示失效导致强制失败，查询仍然会运行 (使用优化器新生成的计划) 并在 `sys.query_store_plan.force_failure_count` 中累加。

### 回归检测 + 自动调优 (2017+)

SQL Server 2017 在 Query Store 基础上引入 Automatic Tuning：

```sql
ALTER DATABASE mydb SET AUTOMATIC_TUNING (
    FORCE_LAST_GOOD_PLAN = ON
);
```

触发条件 (Microsoft 内置启发式):

```
连续两个时间间隔 (默认 60 分钟):
  新计划的 CPU 时间 > 旧计划 CPU 时间 * (1 + threshold)
  AND 执行次数 >= 最低阈值
  AND 新计划导致的回归代价 > 5 秒 CPU

触发后:
  1. DMV sys.dm_db_tuning_recommendations 生成推荐
  2. 如果 FORCE_LAST_GOOD_PLAN = ON:
     → 自动执行 sp_query_store_force_plan 强制回到旧计划
  3. 引擎持续监控强制后的性能
  4. 如果强制计划反而恶化 → 自动取消强制
```

查看推荐：

```sql
SELECT reason, score, state, details
FROM   sys.dm_db_tuning_recommendations;
```

### Query Store Hints (2022+)

SQL Server 2022 引入不改 SQL 文本的 Hint 注入：

```sql
-- 为特定 query_id 永久注入 RECOMPILE 提示
EXEC sys.sp_query_store_set_hints
    @query_id = 42,
    @query_hints = N'OPTION(RECOMPILE, MAXDOP 1)';

-- 移除
EXEC sys.sp_query_store_clear_hints @query_id = 42;
```

这补齐了 Oracle SPM 的一个短板 - 不通过改代码就能把提示附加到线上 SQL。

## TiDB SQL Plan Management 深入

### 基线绑定

TiDB 从 4.0 (2020) 开始提供 MySQL 兼容的 SPM，语法围绕 `BINDING` 展开：

```sql
-- 创建绑定: 给 SELECT * FROM t WHERE id > 100 绑定一个索引提示的版本
CREATE GLOBAL BINDING FOR
    SELECT * FROM t WHERE id > 100
USING
    SELECT /*+ USE_INDEX(t, idx_id) */ * FROM t WHERE id > 100;

-- SESSION 级
CREATE SESSION BINDING FOR ... USING ...;

-- 列出所有绑定
SHOW GLOBAL BINDINGS;
SHOW SESSION BINDINGS;

-- 删除
DROP GLOBAL BINDING FOR SELECT * FROM t WHERE id > 100;
```

SQL 文本会被归一化 (参数化) 存入 `mysql.bind_info` 系统表，之后对同一指纹的查询自动应用。

### 自动捕获

```sql
-- 开启自动捕获 (默认关)
SET GLOBAL tidb_capture_plan_baselines = ON;
-- 开启后，TiDB 会定期扫描 Statement Summary 表
-- 对执行 ≥ 2 次的 SQL 自动创建绑定
```

### 基线演化 (Evolve)

```sql
-- 开启演化
SET GLOBAL tidb_evolve_plan_baselines = ON;

-- 允许的演化时间窗口 (避开业务高峰)
SET GLOBAL tidb_evolve_plan_task_start_time = '00:00 +0000';
SET GLOBAL tidb_evolve_plan_task_end_time   = '06:00 +0000';

-- 最大可验证的候选计划数
SET GLOBAL tidb_evolve_plan_task_max_time = 600;  -- 秒
```

Evolve 过程：TiDB 对每个已绑定的 SQL 在空闲时段使用当前数据验证候选计划，若代价显著低于现有绑定则自动替换，替换前保存旧绑定以便回滚。

### Status 字段

```
CREATE BINDING ... USING ...
  └─ status:
      ├─ using      -- 当前生效
      ├─ disabled   -- 已禁用
      ├─ deleted    -- 已删除 (软删)
      └─ pending verify -- 等待 evolve 验证
```

### 查询诊断

```sql
-- Plan Digest (v4.0+) 可以不改 SQL 替换计划
-- 先查 statements_summary 找到坏 plan:
SELECT digest, plan_digest, exec_count, avg_latency
FROM   information_schema.statements_summary
WHERE  schema_name = 'mydb'
ORDER  BY avg_latency DESC
LIMIT  10;

-- 用 PLAN REPLAYER 导出现场
PLAN REPLAYER DUMP EXPLAIN SELECT * FROM t WHERE id > 100;
```

## OceanBase Outline / SPM

OceanBase 的 plan management 有两代：

**Outline (1.4+)** - 基于 SQL 文本指纹的 Hint 注入：

```sql
-- 创建 Outline
CREATE OUTLINE outline_fix_orders ON
    SELECT * FROM orders WHERE user_id = ? AND status = ?
USING HINT /*+ INDEX(orders idx_user_status) */;

-- 查看
SELECT * FROM oceanbase.DBA_OB_OUTLINES;
```

**SPM (4.0+)** - 类 Oracle 的完整基线体系：

```sql
-- 开启自动捕获
ALTER SYSTEM SET optimizer_capture_sql_plan_baselines = TRUE;
ALTER SYSTEM SET optimizer_use_sql_plan_baselines    = TRUE;

-- 手动接受一个历史计划
CALL DBMS_SPM.ACCEPT_SQL_PLAN_BASELINE(
    sql_handle => 'SQL_abc123',
    plan_hash  => 987654321
);
```

## DB2 Optimization Profile (OPTGUIDELINE)

DB2 9.1 (2006) 提供 XML 格式的 Optimization Profile，比 SPM 更早但可观察性更低：

```sql
-- Profile 本身是 XML，绑定方式有两种:

-- 方式 1: 会话级
SET CURRENT OPTIMIZATION PROFILE = 'MYSCHEMA.MY_PROFILE';

-- 方式 2: 写入 SYSTOOLS.OPT_PROFILE 后 FLUSH CACHE
INSERT INTO SYSTOOLS.OPT_PROFILE VALUES (
    'MYSCHEMA', 'MY_PROFILE',
    BLOB('<?xml version="1.0" encoding="UTF-8"?>
          <OPTPROFILE VERSION="9.1.0.0">
            <STMTPROFILE ID="force_index">
              <STMTKEY SCHEMA="MYSCHEMA">
                <![CDATA[SELECT * FROM ORDERS WHERE STATUS=?]]>
              </STMTKEY>
              <OPTGUIDELINES>
                <IXSCAN TABLE="ORDERS" INDEX="IDX_STATUS"/>
              </OPTGUIDELINES>
            </STMTPROFILE>
          </OPTPROFILE>')
);

CALL SYSPROC.SYSINSTALLOBJECTS('OPT_PROFILE', 'C', '', '');
FLUSH PACKAGE CACHE DYNAMIC;
```

OPTGUIDELINE 的特点：

- 支持的指导类型丰富：`IXSCAN`, `TBSCAN`, `NLJOIN`, `HSJOIN`, `MSJOIN`, `ACCESS`, `JOIN`
- 基于 STMTKEY 精确匹配，大小写敏感
- 没有"演化"概念，profile 是静态的
- 对 DBA 要求较高：需要读 `db2exfmt` 输出手写 XML

## SAP HANA Plan Stability

SAP HANA 2.0 SPS 04+ 提供 Capture and Replay 机制：

```sql
-- 开启捕获
ALTER SYSTEM SET ('indexserver.ini', 'SYSTEM')
    ('sql', 'plan_stability_capture') = 'ON';

-- 列出捕获的计划
SELECT * FROM M_SQL_PLAN_STABILITY;

-- 强制一个计划
CALL SYS.EXPORT_SQL_PLAN_STABILITY('<plan_id>', 'EXPORT_TABLE');
```

HANA 把整个 plan 对象序列化 (而非 hash)，Replay 时反序列化并应用，理论上在不同版本之间也能还原，但实测 plan 结构在大版本间会漂移。

## Teradata Query Capture Database

Teradata 很早就有完整的 plan 管理：

```sql
-- 创建 Query Capture DB
CREATE QUERY LOG ON ALL WITH SQL, OBJECTS, STEPINFO;

-- 锁定某 SQL 的计划 (Target Level Emulation + QCF)
COLLECT DEMOGRAPHICS INDEX ON orders;

-- Directed Queries (对等 Oracle SPM)
LOCKING ROW FOR ACCESS
SELECT ... FROM orders WHERE ...;
-- 配合 TASM Throttles + Query Bands 实现运行时保护
```

## CockroachDB Plan Gists

CockroachDB 22.2 (2022) 提供 Plan Gists - 一种**轻量化、压缩的计划指纹**，主要用于可观察性，而非强制：

```sql
-- 查看 plan gist (紧凑表示)
EXPLAIN (GIST) SELECT * FROM users WHERE email = 'a@b.com';

-- 解码 gist 还原结构
SELECT crdb_internal.decode_plan_gist('AgH...');

-- 在 crdb_internal.statement_statistics 里对比 gist 漂移
SELECT plan_gist, count(*), max(service_lat_avg)
FROM crdb_internal.statement_statistics
WHERE fingerprint_id = '0x...'
GROUP BY plan_gist;
```

CockroachDB 明确声明：**不提供强制计划**。官方立场是让优化器在每次统计信息刷新后重新选择，Gist 仅用于诊断。

## StarRocks SQL Plan Manager

StarRocks 3.3 (2024) 引入 SQL Plan Manager，借鉴 Oracle SPM + TiDB Binding：

```sql
-- 创建基线
CREATE BASELINE
USING SELECT /*+ SET_VAR(cbo_use_nth_exec_plan = 2) */
       * FROM lineitem WHERE l_shipdate > '1995-01-01';

-- 列出
SHOW BASELINE;

-- 删除
DROP BASELINE <id>;
```

## PostgreSQL 的选择：拒绝 plan management

PostgreSQL 社区长期讨论但从未合并原生 SPM。官方立场大致可以概括为：

> 优化器是"生产线"，让它自由工作；如果某条 SQL 固化了一个过时的计划，那才是真的灾难。统计信息 + vacuum + cost 参数已经提供了足够的调节手段。

实践中 PostgreSQL 用户靠以下手段实现类 SPM 效果：

```sql
-- 方案 1: pg_hint_plan 扩展 (Fujitsu 开源)
LOAD 'pg_hint_plan';
/*+ IndexScan(orders idx_status) */
SELECT * FROM orders WHERE status = 'NEW';

-- 可以把 hint 存入 hint_plan.hints 表，实现持久化
INSERT INTO hint_plan.hints(norm_query_string, application_name, hints)
VALUES (
    'SELECT * FROM orders WHERE status = ?',
    '',
    'IndexScan(orders idx_status)'
);

-- 方案 2: 锁死 GUC 参数 (集群全局)
ALTER SYSTEM SET enable_seqscan = OFF;
ALTER SYSTEM SET random_page_cost = 1.1;

-- 方案 3: 物化视图 / 表重写
```

## MySQL 的选择：Hint + Query Rewrite

MySQL 8.0 提供丰富的 Optimizer Hints，但不持久化到系统表：

```sql
-- 会话级 Hint (不持久)
SELECT /*+ INDEX(t idx1) */ * FROM t WHERE x > 10;

-- Query Rewrite Plugin (5.7+): 改写 SQL 文本，间接固定计划
INSERT INTO query_rewrite.rewrite_rules (pattern, replacement)
VALUES (
    'SELECT * FROM t WHERE x > ?',
    'SELECT /*+ USE_INDEX(t, idx1) */ * FROM t WHERE x > ?'
);
CALL query_rewrite.flush_rewrite_rules();

-- 需要安装 Rewriter plugin:
INSTALL PLUGIN rewriter SONAME 'rewriter.so';
```

这是典型的"改写式 plan lock" - 不直接冻结计划，而是把 SQL 变成带 hint 的版本。

## 云数仓为什么拒绝 plan management

Snowflake, BigQuery, Redshift (Serverless), Databricks SQL 都不提供任何形式的 plan management。官方理由可以归纳为：

### 1. 计算层无状态

```
Snowflake: Warehouses 可以秒级弹性启停，每个 query 可能落在不同节点
BigQuery:  Slots 动态分配，查询到达后即时规划
-> 基线存储在哪里？固化的 plan 对新节点有效吗？
```

### 2. 统计信息持续变化

```
列存数仓: micro-partition / block 级统计
           写入频繁 → 统计刷新频繁 → plan 应该持续演化
固化一个旧 plan 等于把引擎锁在过去。
```

### 3. 自适应执行是终极方案

```
Snowflake Adaptive execution
BigQuery Dynamic execution
Databricks AQE (Spark AQE)
-> 它们做的事情相当于每次查询都"动态 evolve"
-> 因此不需要离线 evolve 机制
```

### 4. 多租户的 blast radius

```
如果一个租户固化了糟糕计划，可能恶化整个集群的调度决策。
云厂商倾向于"永远给你当前最优 plan" + 自适应重排。
```

代价是：**偶尔会遇到回归但你什么也做不了**。这也是一些用户从 Snowflake 迁回 Oracle / SQL Server 的典型理由。

## 各引擎 Plan ID / Hash 算法

计划可观测性依赖 Plan ID。各引擎实现路线：

| 引擎 | 标识 | 算法 | 稳定性 |
|------|------|------|--------|
| Oracle | `PLAN_HASH_VALUE` | 32-bit hash of plan tree | 跨节点稳定，跨版本可能变化 |
| Oracle | `FULL_PLAN_HASH_VALUE` (12c+) | 64-bit | 更稳定 |
| Oracle | `SQL_PLAN_HASH_VALUE_2` (19c+) | 忽略 child operator 差异 | 更抽象 |
| SQL Server | `query_plan_hash` | MD5 of showplan XML | 对统计信息敏感 |
| SQL Server | `query_hash` | MD5 of normalized SQL | 语义一致 |
| PostgreSQL | `queryid` (pg_stat_statements) | 64-bit hash of AST | 不含 plan |
| MySQL | `DIGEST` | SHA-256 of normalized SQL | 不含 plan |
| TiDB | `PLAN_DIGEST` | hash of operator tree | 含 plan |
| OceanBase | `PLAN_HASH` | hash of plan tree | 含 plan |
| CockroachDB | `plan_gist` | base64 编码的压缩 tree | 含 plan, 可解码 |
| SAP HANA | `PLAN_ID` | 64-bit generated | 引擎内部唯一 |
| SingleStore | `PLAN_ID` | 自增 ID | 每个 plancache 唯一 |

Oracle 历史上修过 `PLAN_HASH_VALUE` 多次 (9i → 10g → 12c → 19c)，每次都引入了新的更稳定的 hash 字段。经验：**只用 hash 比较 plan 跨版本不可靠**，需要结合 plan outline 或完整 operator tree。

## 典型回归场景

### 绑定变量窥视引发的剧变

```
-- 首次执行 (窥视到稀有值)
EXECUTE myquery USING 'INACTIVE';   -- status='INACTIVE' 占 1%
  → 优化器: 用 idx_status + lookup
  → 计划 A 缓存

-- 后续执行 (实际大量是 active)
EXECUTE myquery USING 'ACTIVE';     -- status='ACTIVE' 占 99%
  → 仍然用计划 A: 99% 的行走索引回表 → 慢 100 倍
```

解决方案：

- Oracle: ACS (Adaptive Cursor Sharing) 自动识别倾斜 bind
- SQL Server: OPTION (RECOMPILE) 或 `FORCESEEK` hint
- TiDB: `SELECT /*+ IGNORE_PLAN_CACHE() */` 或 `tidb_plan_cache_invalidation_on_fresh_stats`

### 版本升级后优化器变化

```
Oracle 19c → 23ai: 新 adaptive 特性默认开启可能选不同 plan
SQL Server 2019: Intelligent Query Processing 引入 batch mode for rowstore
MySQL 8.0: cost model 重构，某些 order_by 变慢
```

止损：

- Oracle: `OPTIMIZER_FEATURES_ENABLE = '19.1.0'` 锁定优化器行为
- SQL Server: `ALTER DATABASE ... SET COMPATIBILITY_LEVEL = 150` 锁住 CE 版本
- 配合 SPM / Query Store 固化关键 SQL 的 baseline

### 统计信息刷新

```
Oracle: DBMS_STATS.GATHER_TABLE_STATS 后 shared_pool 失效
        → 下次执行重新生成 plan → 可能选不同 index
MySQL: ANALYZE TABLE 改变 rec_per_key → join order 变化
TiDB: auto_analyze 后 plan cache invalidate
```

## 关键发现

### 1. Plan management 的 30 年演进

```
1990s: Oracle Stored Outlines (8i)
       原理: 把优化提示存为 outline hints
       问题: 无法随统计信息演化, 需手动维护

2006:  DB2 Optimization Profile (v9)
       原理: XML + OPTGUIDELINE
       问题: 仅强制, 无演化

2007:  Oracle SPM (11gR1) ← 里程碑
       创新: ACCEPTED/ENABLED/FIXED 三态 + EVOLVE 验证
       影响: 成为后续引擎 SPM 的模板

2016:  SQL Server Query Store ← 另一里程碑
       创新: 默认 ON, DMV 友好, 整合到 SSMS UI
       易用性远超 Oracle SPM

2017:  SQL Server Automatic Tuning (FORCE_LAST_GOOD_PLAN)
       首个真正"自动回滚"的商用实现

2020:  TiDB SPM / OceanBase SPM (4.0)
       国产分布式数据库跟进, MySQL 兼容语法

2022:  CockroachDB Plan Gists
       新思路: 轻量化观察 > 强制锁定

2024:  StarRocks Plan Manager (3.3)
       MPP 数仓开始回归 plan management
```

### 2. 四种哲学阵营

| 阵营 | 代表 | 立场 |
|------|------|------|
| 完整 SPM | Oracle, SQL Server, DB2, TiDB, OceanBase | 必须提供基线 + 演化 + 回归检测 |
| Hint 为王 | MySQL, PostgreSQL (pg_hint_plan), Spanner | 不直接管理 plan, 只提供 hint 机制 |
| 自适应派 | Snowflake, BigQuery, Databricks AQE | 拒绝固化, 信任运行时反馈 |
| 观察派 | CockroachDB | 提供丰富 observability, 不提供强制 |

### 3. 自动 vs 手动

```
Oracle SPM: 需 DBA 熟悉 DBMS_SPM, 学习曲线陡
SQL Server Query Store: SSMS UI + DMV 易上手
TiDB: SQL 语法简单 (CREATE BINDING), 但 evolve 需要调参
DB2 OPTGUIDELINE: XML 手写, 最难维护
```

### 4. 观察性决定价值

没有 plan ID / hash 的 plan management 几乎不可用。Oracle `PLAN_HASH_VALUE`, SQL Server `query_plan_hash`, TiDB `PLAN_DIGEST` 是 plan management 能被运营的基石。CockroachDB 用 Plan Gist 重新设计了这一层：同一个字段既是指纹又可解码，是工程上更优雅的做法。

### 5. 云数仓的缺口是真实的

无 plan management 的云数仓：

- 查询回归时**没有任何抓手**
- 工单提到 "yesterday it was fast" 基本只能等厂商分析
- 关键批处理应避免放在"纯 Serverless" 产品上

Snowflake 2024 开始提供 `QUERY_HISTORY` 的 execution profile 对比，算是向可观察性靠拢，但仍未提供强制能力。

### 6. 未来趋势

```
1. AI 驱动的 plan 选择:
   - Oracle 23ai: AI 辅助 evolve
   - Databricks: Photon 的 ML cost model
2. Serverless 下的 plan 缓存粒度:
   - 从 session → tenant → warehouse → ephemeral
3. Plan hint 注入不改 SQL:
   - SQL Server 2022 query_store_set_hints
   - 预期 Oracle 后续版本跟进
4. 分布式自适应执行:
   - Spark AQE, TiDB Runtime Filter, CockroachDB Streamer
   - 方向: 让每次执行都"动态 evolve", 减少对离线 SPM 的依赖
```

## 对引擎开发者的实现建议

### 1. Plan Identity

```
1. 提供至少两层标识:
   - Statement fingerprint (SQL hash): 跨 plan 变化稳定
   - Plan identity (plan hash / gist): 精确指向单一执行计划
2. plan hash 应在 operator tree 级别计算, 忽略 cost
3. 提供解码能力 (像 CockroachDB gist → explain)
4. 记录 plan 的来源 (AUTO / MANUAL / FORCED / EVOLVED)
```

### 2. 存储结构

```
CREATE TABLE spm_baseline (
    sql_handle      VARCHAR(64) NOT NULL,       -- SQL 指纹
    plan_id         VARCHAR(64) NOT NULL,       -- 计划指纹
    sql_text        TEXT NOT NULL,
    plan_outline    TEXT NOT NULL,              -- 可恢复的 hint 集合
    status          VARCHAR(16) NOT NULL,       -- ENABLED/ACCEPTED/FIXED
    origin          VARCHAR(16) NOT NULL,       -- AUTO/MANUAL/EVOLVED
    created_at      TIMESTAMP,
    last_used_at    TIMESTAMP,
    exec_count      BIGINT,
    avg_elapsed_us  BIGINT,
    PRIMARY KEY (sql_handle, plan_id)
);
```

### 3. Evolve 验证算法

```
核心思路: A/B 对比当前 baseline 与候选 plan 的 cost
算法:
  1. 采样窗口: 选 N 次候选 plan 的执行 (通常 N=10)
  2. 对比指标: elapsed_time, buffer_gets, rows_returned
  3. 判定规则:
     if candidate.mean < baseline.mean * (1 - improvement_threshold)
        AND candidate.p95 < baseline.p95 * (1 - improvement_threshold)
     then accept candidate
  4. 防止回归:
     保留 baseline 至少 30 天, 如果 accepted plan 出现异常可回退
  5. 窗口:
     仅在低负载时段做 evolve (避开业务高峰)
```

### 4. Plan Freeze 的实现点

```
1. 优化入口拦截:
   parse(sql) → normalize → lookup SMB → if baseline: use_outline()
2. Hint 反序列化:
   从 plan_outline 还原所有 JOIN / ACCESS / ORDER 指令
3. 失败兜底:
   如果 baseline 无法被应用 (如表删除), fallback 到 CBO 且记录 failure_count
4. 事务一致性:
   SMB 修改必须可见于下一次 parse, 通常需要 cache invalidation 信号
```

### 5. 回归检测最小实现

```
1. 维护每个 plan_id 的滚动统计 (最近 K 次执行)
2. 触发阈值:
   new_plan.p95 > old_plan.p95 * 2
   AND new_plan.exec_count >= MIN_EXECS
   AND new_plan.total_elapsed > MIN_TIME
3. 告警: 产生 tuning recommendation
4. 自动动作: 如果开启 auto-force, 执行 force_plan(old_plan_id)
```

### 6. Observability 面板的必备指标

```
- 每个 SQL 的 plan 历史: 时间轴视图
- Top regressed queries: 按恶化程度排序
- Plan forced queries: 当前强制列表
- Force failure count: 强制失败次数 (帮助发现失效 baseline)
- Plan evolution timeline: 最近 N 天的 evolve 记录
```

## 总结对比

### 核心能力总览

| 能力 | Oracle | SQL Server | DB2 | TiDB | OceanBase | HANA | Snowflake |
|------|--------|------------|-----|------|-----------|------|-----------|
| 自动捕获 | 是 | 是 | -- | 是 | 是 | 是 | -- |
| 手动捕获 | 是 | 是 | 是 | 是 | 是 | 是 | -- |
| 计划强制 | FIXED | force_plan | OPTGUIDELINE | BINDING | OUTLINE | Stability | -- |
| 演化验证 | 是 | 是 (Auto Tuning) | -- | 是 | 是 | 部分 | -- |
| 自动回滚 | -- | 是 | -- | 是 | 是 | 部分 | -- |
| Plan Hash | 是 | 是 | 部分 | 是 | 是 | 是 | -- |
| 回归报告 | 是 | 是 | 部分 | 是 | 是 | 是 | -- |
| 不改 SQL 注入 Hint | -- | 2022+ | 是 | 是 | 是 | -- | -- |
| UI 支持 | OEM | SSMS | Data Studio | Dashboard | OCP | Studio | -- |

### 引擎选型建议

| 场景 | 推荐方案 |
|------|---------|
| 核心交易系统，零容忍回归 | Oracle SPM + FIXED baseline |
| SaaS 多租户 OLTP | SQL Server Query Store + Auto Tuning |
| 分布式 OLTP (HTAP) | TiDB SPM + Evolve |
| 国产化分布式 | OceanBase SPM (4.0+) |
| PostgreSQL 生态 | pg_hint_plan + 锁 GUC 参数 |
| MySQL 生态 | Query Rewrite Plugin + 版本锁定 |
| 云数仓 + 严格 SLA | 避免纯 Serverless, 选 Snowflake 独立 Warehouse + 监控 |
| 新架构设计参考 | CockroachDB Plan Gist + 自适应执行 |

## 参考资料

- Oracle Database Documentation: [SQL Plan Management](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/sql-plan-management.html)
- Oracle White Paper: [SQL Plan Management with Oracle Database](https://www.oracle.com/technetwork/database/bi-datawarehousing/twp-sql-plan-mgmt-11g-133099.pdf)
- Microsoft Learn: [Monitor performance using the Query Store](https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
- Microsoft Learn: [Automatic tuning](https://learn.microsoft.com/en-us/sql/relational-databases/automatic-tuning/automatic-tuning)
- IBM Db2: [Optimization Profiles](https://www.ibm.com/docs/en/db2/11.5?topic=optimizer-creating-optimization-profile)
- TiDB Documentation: [SQL Plan Management (SPM)](https://docs.pingcap.com/tidb/stable/sql-plan-management)
- OceanBase Documentation: [SQL Plan Management](https://en.oceanbase.com/docs/common-oceanbase-database-10000000001697183)
- CockroachDB Documentation: [Plan Gists](https://www.cockroachlabs.com/docs/stable/plan-gists)
- SAP HANA SQLScript Reference: [Plan Stability](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- Microsoft: [Query Store Hints (SQL Server 2022)](https://learn.microsoft.com/en-us/sql/relational-databases/performance/query-store-hints)
- PostgreSQL wiki: [pg_hint_plan](https://github.com/ossc-db/pg_hint_plan)
- MySQL Reference Manual: [Rewriter Query Rewrite Plugin](https://dev.mysql.com/doc/refman/8.0/en/rewriter-query-rewrite-plugin.html)
- StarRocks Documentation: [SQL Plan Manager](https://docs.starrocks.io/docs/administration/management/sql-plan-manager/)
