# 查询指纹与摘要 (Query Fingerprinting and Digests)

`SELECT * FROM users WHERE id = 1` 和 `SELECT * FROM users WHERE id = 2` 在数据库眼中应该是同一条 SQL——查询指纹（Query Fingerprint / Digest）就是把这个直觉变成可计算、可聚合的 64 位整数。当你想知道"这个集群里到底有哪些 SQL 模板被反复执行"，没有指纹就无从下手。

## 为什么需要指纹

生产数据库每秒可能执行数万条 SQL，但其中真正不同的"模板"通常只有几百到几千条。如果按字面文本聚合：

```sql
SELECT * FROM orders WHERE order_id = 12345;
SELECT * FROM orders WHERE order_id = 67890;
SELECT * FROM orders WHERE order_id = 11111;
-- 在文本层面是 3 条不同的 SQL，但语义上是 1 个模板
```

指纹算法将所有"长得一样、只是字面值不同"的 SQL 归一化为同一个标识符（通常是 64 位 hash 或哈希字符串）。归一化通常包括：

1. **字面值（literals）替换**：数字、字符串、布尔、日期等替换为占位符 `?` 或 `$N`
2. **空白字符（whitespace）压缩**：多个空格/换行/Tab 折叠为单个空格
3. **大小写规范化**：关键字统一为大写或小写
4. **注释剥离**：去除 `--` 单行注释和 `/* */` 块注释（hint 注释除外）
5. **IN 列表折叠**：`IN (1,2,3,4,5)` → `IN (?+)` 或 `IN (...)`
6. **对象名规范化**：`schema.table` 与 `"schema"."table"` 视作相同

归一化后的文本通常称为 **digest text**，对它做哈希得到 **query digest / queryid / query_hash**。

典型用途：

- **Top-N 慢查询识别**：按指纹聚合执行时间，定位真正高负载的模板
- **执行计划缓存（plan cache）键**：避免为每个不同的字面值反复编译
- **限流与熔断**：按指纹做 QPS 限制，针对模板而非具体语句
- **告警与对比**：跨时间窗口对比同一模板的延迟变化
- **审计与合规**：脱敏后日志可对外，保留模板形状但不暴露字面值
- **慢日志聚合**：把数百万行慢日志压缩为几千行模板报告

## 没有 SQL 标准

ISO/IEC 9075（SQL 标准）没有定义查询指纹。这是一个纯粹的实现层概念，每个引擎自行设计，差异极大：

- 是否暴露指纹（部分引擎只内部使用）
- 归一化的颗粒度（IN 列表是否折叠、注释是否保留 hint）
- 哈希函数（FNV-1a / xxHash / MD5 / 自定义 jumble）
- 持久化（运行时统计 vs Query Store 长期保存）
- 是否支持从指纹反查原始 SQL 文本

这种碎片化导致跨引擎迁移可观测性栈（如 APM、SQL Review 工具）非常困难。pt-query-digest 这类外部工具的出现，部分是为了弥补统一指纹的缺失。

## 支持矩阵（45+ 引擎）

### 基础支持：是否暴露查询指纹

| 引擎 | 暴露指纹 | 系统视图/表 | 字段名 | 引入版本 |
|------|---------|-------------|--------|---------|
| PostgreSQL | 是 | `pg_stat_statements` | `queryid` | 9.4 (2014) |
| MySQL | 是 | `events_statements_summary_by_digest` | `DIGEST` / `DIGEST_TEXT` | 5.6 (2013) |
| MariaDB | 是 | `performance_schema.events_statements_summary_by_digest` | `DIGEST` | 10.1+ |
| SQL Server | 是 | `sys.dm_exec_query_stats` | `query_hash`, `query_plan_hash` | 2008 |
| Oracle | 是 | `V$SQLAREA` / `V$SQL` | `SQL_ID`, `FORCE_MATCHING_SIGNATURE` | 10g+ |
| SQLite | 否 | -- | -- | 不支持 |
| DB2 LUW | 是 | `MON_GET_PKG_CACHE_STMT` | `EXECUTABLE_ID` | 9.7+ |
| Snowflake | 是 | `QUERY_HISTORY` | `QUERY_HASH`, `QUERY_PARAMETERIZED_HASH` | GA |
| BigQuery | 部分 | `INFORMATION_SCHEMA.JOBS_BY_*` | `query` (仅原文，无 hash 字段) | GA |
| Redshift | 是 | `STL_QUERY` / `SYS_QUERY_HISTORY` | `query_id`, `query_hash` | 较新版本 |
| ClickHouse | 是 | `system.query_log` | `normalized_query_hash` | 21.3+ |
| Trino | 是 | event listener / `system.runtime.queries` | `query_id` (会话级), 模板需自定义 | GA (会话级 ID) |
| Presto | 同 Trino | -- | -- | -- |
| Spark SQL | 是 | Spark UI / event log | 计划 hash (内部) | 2.0+ |
| Hive | 部分 | HiveServer2 操作日志 | `operationId` (会话级) | -- |
| Flink SQL | 否 | -- | -- | 不支持 |
| Databricks | 部分 | Query History UI | `statement_id` (会话级), 指纹依赖 Unity | DBR 较新 |
| Teradata | 是 | `DBC.DBQLogTbl` (DBQL) | `QueryID` 与 `StatementGroup` | V2R6+ |
| Greenplum | 是 | `pg_stat_statements` (移植自 PG) | `queryid` | 6.0+ |
| CockroachDB | 是 | `crdb_internal.statement_statistics` | `fingerprint_id` | 19.x+ |
| TiDB | 是 | `INFORMATION_SCHEMA.STATEMENTS_SUMMARY` | `digest`, `digest_text` | 4.0+ |
| OceanBase | 是 | `GV$OB_SQL_AUDIT` | `SQL_ID` | 4.x+ |
| YugabyteDB | 是 | `pg_stat_statements` (继承 PG) | `queryid` | 2.x+ |
| SingleStore | 是 | `INFORMATION_SCHEMA.MV_QUERIES` | `query_text` (规范化) | 7.x+ |
| Vertica | 是 | `query_requests` / `query_profiles` | `request_label`, `query_hash` (较新) | 9.x+ |
| Impala | 是 | `impala-shell` 查询历史, lineage log | `query_id` (会话级) | -- |
| StarRocks | 是 | `audit_log` (FE 插件) | `digest` (扩展) | 2.5+ |
| Doris | 是 | `audit_log` 插件 | `digest` | 1.2+ |
| MonetDB | 部分 | `sys.queue` / 日志 | -- | -- |
| CrateDB | 部分 | `sys.jobs_log` | `id` (会话级) | -- |
| TimescaleDB | 是 | 继承 PG `pg_stat_statements` | `queryid` | 继承 PG |
| QuestDB | 否 | -- | -- | 不支持 |
| Exasol | 是 | `EXA_SQL_LAST_DAY` / `EXA_SQL_HOURLY` | `STMT_ID` | -- |
| SAP HANA | 是 | `M_SQL_PLAN_CACHE` | `STATEMENT_HASH` | 2.0+ |
| Informix | 是 | `sysmaster:syssqltrace` | `sql_statement` (规范化) | 11.50+ |
| Firebird | 否 | -- | -- | 不支持 |
| H2 | 否 | -- | -- | 不支持 |
| HSQLDB | 否 | -- | -- | 不支持 |
| Derby | 否 | -- | -- | 不支持 |
| Amazon Athena | 部分 | `INFORMATION_SCHEMA.QUERY_HISTORY` (Workgroup) | `query_id` (会话级) | -- |
| Azure Synapse | 是 | `sys.dm_pdw_exec_requests` | `query_hash` | GA |
| Google Spanner | 是 | `SPANNER_SYS.QUERY_STATS_TOP_*` | `text_fingerprint` | GA |
| Materialize | 部分 | `mz_internal.mz_recent_activity_log` | `id` (会话级) | -- |
| RisingWave | 部分 | `rw_catalog` 日志 | -- | -- |
| InfluxDB (SQL/IOx) | 部分 | 系统日志 | -- | -- |
| Databend | 是 | `system.query_log` | `query_hash` | -- |
| Yellowbrick | 是 | `sys.log_query` | `query_hash` | GA |
| Firebolt | 是 | `information_schema.engine_query_history` | `query_id` (会话级), 模板视图较新 | -- |
| AlloyDB | 是 | 继承 PG `pg_stat_statements` | `queryid` | 继承 PG |
| Aurora PG | 是 | 继承 PG `pg_stat_statements` | `queryid` + Performance Insights | -- |
| Aurora MySQL | 是 | 继承 MySQL `events_statements_summary_by_digest` | `DIGEST` | -- |
| RDS Oracle | 是 | 继承 Oracle `V$SQLAREA` | `SQL_ID` | -- |
| Cosmos DB (SQL API) | 否 | -- | -- | 不支持 |

> 统计（按"暴露稳定可查询的指纹字段"严格统计）：
> - **完整支持**（提供持久化指纹字段如 PG `queryid` / MySQL `DIGEST` / SQL Server `query_hash` / Oracle `SQL_ID` / Snowflake `QUERY_HASH` 等）：约 28 个引擎
> - **会话级 ID 但无跨执行指纹**（如 Trino `query_id` / Hive `operationId` / Athena `query_id`）：约 6 个引擎
> - **不支持或仅日志原文**：约 11 个引擎（包括 SQLite、H2、Firebird、QuestDB、Flink SQL、Cosmos DB 等）

### 归一化算法对比

| 引擎 | 数字字面值 | 字符串字面值 | IN 列表折叠 | 大小写归一 | 空白压缩 | 注释处理 | 对象名 |
|------|-----------|-------------|------------|-----------|---------|---------|--------|
| PostgreSQL | `$1, $2, ...` | `$N` | 9.4-13 不折叠；14+ 自动折叠 | 不归一 | 是 | 剥离 | 不归一（区分 schema） |
| MySQL | `?` | `?` | `IN (...)` 折叠为 `IN (?)` | 是（关键字 UPPER） | 是 | 剥离 | 不归一 |
| SQL Server | 内部参数化 | 内部参数化 | 折叠 | 否 | 是 | 保留部分 | 数据库内有效 |
| Oracle | 由 `CURSOR_SHARING` 控制 | 同左 | 折叠（11g+） | 否 | 是 | 保留 hint | 区分 schema |
| Snowflake | `?` | `?` | 折叠 | 否 | 是 | 剥离 | 区分 schema |
| ClickHouse | `?` | `?` | 不折叠（21.3 起按列表长度折叠） | 否 | 是 | 剥离 | 不归一 |
| TiDB | `?` | `?` | 折叠 | 否 | 是 | 剥离 | 不归一 |
| CockroachDB | `_` | `_` | 折叠 | 否 | 是 | 剥离 | 区分 schema |
| Spanner | `@p1, @p2` | `@pN` | 折叠 | 否 | 是 | 剥离 | 区分 schema |

### 哈希函数与位宽对比

| 引擎 | 哈希函数 | 位宽 | 编码形式 | 跨重启稳定 |
|------|---------|------|---------|-----------|
| PostgreSQL | `hash_any` (可读：基于 Postgres 内部 hash，9.4-10) → 64-bit jumble (10+) | 64 bit | `bigint` (有符号) | 是（同版本同对象） |
| MySQL | SHA-256 | 256 bit | 64 字符 hex 字符串 | 是 |
| SQL Server | 内部哈希算法（未公开） | 64 bit | `binary(8)` | 是（同版本同 server） |
| Oracle | MD5 (12 字符 base32) | -- | `SQL_ID` 13 字符；`FORCE_MATCHING_SIGNATURE` 64-bit number | 是 |
| Snowflake | 自定义 64-bit | 64 bit | hex 字符串 | 是 |
| ClickHouse | `sipHash64` | 64 bit | `UInt64` | 是 |
| TiDB | SHA-256 (取前 16 字符) | -- | hex 字符串 | 是 |
| CockroachDB | FNV-1a | 64 bit | hex 字符串 | 是 |
| Vertica | SHA-1 派生 | -- | hex 字符串 | 是 |
| SAP HANA | 自定义 | 64 bit | hex | 是 |

### 持久化与采集策略

| 引擎 | 内存采集 | 持久化 | Top-N 限制 | 老化策略 |
|------|---------|--------|-----------|---------|
| PostgreSQL | shared memory (`pg_stat_statements.max`) | 文件 (`pg_stat_statements.stat`) | 默认 5000 条 | 满后剔除最不常用 |
| MySQL | Performance Schema 内存 | 否（无持久化） | 全局 `performance_schema_digests_size`（5.7+ 自动调优默认约 10000，5.6 默认 200） | 重启清空 |
| SQL Server | Plan Cache + Query Store | Query Store 写入数据库文件 | Query Store: `MAX_PLANS_PER_QUERY=200`, `MAX_STORAGE_SIZE_MB=100` | 满后停止收集或清理 |
| Oracle | SGA (V$SQLAREA) + AWR | AWR 快照（默认 8 天保留） | `STATISTICS_LEVEL` | AWR 自动清理 |
| Snowflake | Cloud 服务层 | 永久（QUERY_HISTORY 14 天可查，ACCOUNT_USAGE 365 天） | 无显式上限 | 时间窗口 |
| ClickHouse | `query_log` 表（异步刷盘） | 表存储 | 表大小由 TTL 控制 | TTL（默认 30 天） |
| TiDB | TiDB 实例内存 | `STATEMENTS_SUMMARY_HISTORY` | `tidb_stmt_summary_max_stmt_count`（默认 3000） | 时间窗口（默认 30 分钟一桶） |
| CockroachDB | 内存 + 系统表 | `system.statement_statistics` | `sql.metrics.max_mem_stmt_fingerprints`（默认 100k） | 时间窗口聚合 |
| OceanBase | SQL Audit | 历史表 | `ob_sql_audit_percentage` | 内存满后覆盖 |

### Top-N 查询视图与可观测能力

| 引擎 | 内置 Top-N 视图 | 维度 | UI 工具 |
|------|----------------|------|---------|
| PostgreSQL | 自行 ORDER BY | total_exec_time / mean_exec_time / calls | pgBadger / pganalyze |
| MySQL | `events_statements_summary_by_digest` | SUM_TIMER_WAIT / COUNT_STAR | MySQL Enterprise Monitor / sys schema |
| SQL Server | Query Store 报表 | duration / CPU / IO | SSMS Query Store 视图 |
| Oracle | AWR Top SQL | elapsed time / CPU / buffer gets | OEM, AWR 报告 |
| Snowflake | `QUERY_HISTORY` + UI | execution_time | Snowsight 查询历史 |
| ClickHouse | `system.query_log` 自查询 | query_duration_ms | ClickHouse Keeper UI / 第三方 |
| TiDB | `STATEMENTS_SUMMARY` | sum_latency / exec_count | TiDB Dashboard |
| CockroachDB | DB Console | runtime / contention | DB Console |

### 是否支持从指纹反查原始 SQL（重写）

| 引擎 | 是否保留示例 SQL | 是否保留参数 | 备注 |
|------|----------------|-------------|------|
| PostgreSQL | 是（`query` 列保存最近一次的归一化文本） | 否 | 字面值替换为 `$N` |
| MySQL | `DIGEST_TEXT` 是规范化文本，`SQL_TEXT` 在 `events_statements_history` 中保留具体值（短期） | 短期 | 高负载下采样 |
| SQL Server | 通过 `query_hash` JOIN `sys.dm_exec_sql_text` 拿到原文 | 是 | Query Store 保存查询文本 |
| Oracle | `V$SQL.SQL_FULLTEXT` 保留具体字面值 | 是 | 同 SQL_ID 多行（不同字面值） |
| Snowflake | `QUERY_HISTORY.query_text` 保留原文 | 是 | 14 天可查 |
| ClickHouse | `query` 列保留原文，`normalized_query` 列保留模板 | 是 | 双轨保存 |
| TiDB | `digest_text` + `query_sample_text`（一条样本） | 部分 | 不同字面值会覆盖样本 |
| CockroachDB | `metadata.query` JSON 字段 | 是 | 多个样本 |

## PostgreSQL：pg_stat_statements 与 queryid

### 历史与版本演进

| 版本 | 关键变化 |
|------|---------|
| 8.4 (2009) | `pg_stat_statements` 扩展首次发布，按"完全相同的查询文本"聚合 |
| 9.2 (2012) | 引入 `track = 'all'` 选项 |
| 9.4 (2014) | **引入 queryid（基于 parse tree 的 jumble hash）**，从此可按"语义模板"聚合 |
| 9.5 (2016) | I/O 时间统计 |
| 10 (2017) | **`pg_stat_statements.track_utility`、字面值规范化文本（`$1, $2, ...`）开始正式可用** |
| 11 | `dealloc` 计数 |
| 13 | `wal_records` / `wal_bytes` 字段 |
| 14 | `toplevel` 字段、`compute_query_id` 参数（核心引入 query_id 计算）；常量列表自动归一 |
| 15 | `JIT` 统计字段 |
| 16 | `query_id` 出现在 `pg_stat_activity` 中（不再依赖扩展） |
| 17 | 改善 IN 列表折叠 |

### 启用与基本使用

```sql
-- 安装扩展（需 superuser，或安装在 contrib）
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- postgresql.conf 配置（必须重启）
-- shared_preload_libraries = 'pg_stat_statements'
-- pg_stat_statements.max = 10000     -- 最多保留多少条 fingerprint
-- pg_stat_statements.track = all     -- 也跟踪嵌套语句
-- pg_stat_statements.track_utility = on
-- pg_stat_statements.save = on       -- 重启时持久化
-- compute_query_id = on              -- PG 14+ 才有此参数
```

### Top-N 查询样例

```sql
-- 总执行时间排序
SELECT queryid,
       calls,
       total_exec_time,
       mean_exec_time,
       rows,
       100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0) AS hit_pct,
       LEFT(query, 200) AS query_sample
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;

-- 平均时间最长的高频查询
SELECT queryid,
       calls,
       mean_exec_time,
       stddev_exec_time,
       LEFT(query, 200) AS query_sample
FROM pg_stat_statements
WHERE calls > 100
ORDER BY mean_exec_time DESC
LIMIT 20;

-- 仅看某个数据库 / 用户
SELECT queryid, query, calls, mean_exec_time
FROM pg_stat_statements s
JOIN pg_database d ON d.oid = s.dbid
WHERE d.datname = 'production'
ORDER BY total_exec_time DESC
LIMIT 50;
```

### queryid 算法深入：jumble walk

PostgreSQL 的 queryid 是 64-bit hash，计算方式为对查询的 `parse tree` 做"jumble walk"——遍历所有节点，把节点类型、操作符 OID、列引用等关键字段累积进哈希状态，但**跳过常量字面值（Const 节点）**。源码位置 `src/backend/utils/misc/queryjumble.c`（旧版本在 `pg_stat_statements.c` 内）。

```
JumbleNode(node):
    switch (nodeTag(node)):
        case T_Const:
            // 跳过常量值！但记录其类型
            APP_JUMB(constNode->consttype)
            constLocations.push(constNode->location)  // 记录位置用于规范化文本
            return
        case T_Var:
            APP_JUMB(varNode->varno)        // 表序号
            APP_JUMB(varNode->varattno)     // 列序号
        case T_OpExpr:
            APP_JUMB(opNode->opno)          // 运算符 OID
            JumbleList(opNode->args)
        ...
        // 对每种 Node 类型都有专门的字段累积
        // 最终 query_id = hash_any(jumble_state.buffer, length)
```

关键点：

1. **基于 parse tree 而非文本**：`SELECT id FROM t WHERE id = 1` 与 `select id from t where id=2` 得到相同 queryid，因为 parse 后结构一致
2. **OID 敏感**：`varattno`（列序号）参与 hash，所以 `DROP COLUMN` 后同样的查询文本可能 queryid 不同
3. **只在 SELECT/INSERT/UPDATE/DELETE 上稳定**：`CREATE TABLE` 等 utility 语句的 queryid 与文本相关
4. **跨实例可重现**：相同 PG 版本、相同 schema OID 时，相同查询的 queryid 相同
5. **collision rate 可忽略**：64-bit 空间下，对于典型工作负载（< 10^6 模板），碰撞概率 ~ 2.7×10^-8

### 常量规范化文本

PG 10 起，`pg_stat_statements.query` 字段不再原样保存第一次执行的 SQL，而是保存**规范化后的版本**：

```sql
-- 原始执行
SELECT * FROM users WHERE name = 'alice' AND age > 30;

-- pg_stat_statements.query 字段保存的内容
SELECT * FROM users WHERE name = $1 AND age > $2;
```

这通过 `constLocations` 数组记录每个 Const 节点在源文本中的位置，然后在保存前替换为 `$N`。注意：

- 替换后的占位符号是从 1 开始的连续编号
- IN 列表中的常量也会被替换：`IN ($1, $2, $3)`
- PG 14+ 引入的"列表折叠"会进一步把 `IN ($1, $2, $3)` 简化为 `IN ($1)` 当列表长度变化但形状不变时

### 局限与陷阱

```sql
-- 陷阱 1：变长 IN 列表导致大量 fingerprint 膨胀（PG 13 及更早）
SELECT * FROM t WHERE id IN (1,2,3);
SELECT * FROM t WHERE id IN (1,2,3,4);
-- 在 PG 13 这是两个 queryid，PG 14+ 起合并

-- 陷阱 2：同样文本不同 schema 是不同 queryid
-- 这其实是优点，避免误聚合

-- 陷阱 3：DDL 后 queryid 失效
ALTER TABLE users ADD COLUMN gender text;
-- 之后 SELECT * FROM users 的 queryid 改变（varattno 总数变了）

-- 陷阱 4：track = top（默认）只跟踪顶层语句
-- 函数内部的 SQL 默认不计入；track = all 才会
```

## MySQL：events_statements_summary_by_digest

### 历史

| 版本 | 关键变化 |
|------|---------|
| 5.6 (2013) | Performance Schema 引入 `events_statements_summary_by_digest`，使用 MD5 |
| 5.7 (2015) | 改用 SHA-256；`DIGEST_TEXT` 为规范化文本 |
| 8.0 | sys schema 提供更易读的 `statement_analysis` 视图 |
| 8.0.18 | `events_statements_histogram_by_digest`（按延迟分桶） |

### 启用与配置

```sql
-- Performance Schema 默认启用（5.7+）
-- my.cnf
-- performance_schema = ON
-- performance-schema-consumer-events-statements-current = ON
-- performance-schema-consumer-events-statements-history = ON
-- max_digest_length = 1024     -- 规范化文本最长字节数
-- performance_schema_events_statements_history_size = 10
-- performance_schema_digests_size = 10000  -- 全局最多 fingerprint 数

-- sys schema (默认存在)
SELECT * FROM sys.statement_analysis LIMIT 10;
```

### Top-N 查询样例

```sql
-- 按总等待时间排序
SELECT SCHEMA_NAME,
       DIGEST,
       LEFT(DIGEST_TEXT, 200) AS digest_text,
       COUNT_STAR,
       ROUND(SUM_TIMER_WAIT/1e9, 2) AS total_ms,
       ROUND(AVG_TIMER_WAIT/1e6, 2) AS avg_us,
       SUM_ROWS_EXAMINED,
       SUM_ROWS_SENT
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 20;

-- 找出全表扫描的高频 SQL
SELECT DIGEST_TEXT, COUNT_STAR, SUM_NO_INDEX_USED, SUM_NO_GOOD_INDEX_USED
FROM performance_schema.events_statements_summary_by_digest
WHERE SUM_NO_INDEX_USED > 0
ORDER BY COUNT_STAR DESC
LIMIT 20;

-- 找出最近一次执行该 fingerprint 的具体 SQL（含字面值）
SELECT esh.SQL_TEXT
FROM performance_schema.events_statements_history_long esh
WHERE esh.DIGEST = '<digest hex>'
LIMIT 1;
```

### Digest 计算流程

MySQL 的 digest 计算在 SQL Parser 完成时同步进行，源码在 `sql/sql_digest.cc`：

```
DigestComputation(token_stream):
    state = init_sha256()
    for each token in stream:
        switch token.type:
            case NUMBER:
                state.update("?")
                continue
            case STRING_LITERAL:
                state.update("?")
                continue
            case HEX_LITERAL:
                state.update("?")
                continue
            case NULL_LITERAL:
                state.update("?")
                continue
            case IDENTIFIER:
                state.update(token.value)   // 保留对象名
            case KEYWORD:
                state.update(uppercase(token.value))  // 关键字归一为大写
            case WHITESPACE:
                if last != WHITESPACE:
                    state.update(" ")        // 多个空白合并为一个
            case PUNCTUATION:
                if token == '(' AND prev_keyword == 'IN':
                    // 折叠 IN 列表
                    state.update("(...)")
                    skip_until_matching_rparen()
                else:
                    state.update(token.value)
        DIGEST_TEXT += normalized_token

    digest = sha256_finalize(state)
    return (digest, DIGEST_TEXT)
```

`DIGEST_TEXT` 是逐 token 拼接的规范化文本，`DIGEST` 是它的 SHA-256（5.6 早期版本使用 MD5）。

### MySQL digest 实例

```
原始 SQL：
SELECT  *
FROM users
WHERE name = 'alice' AND age IN (20, 25, 30)
   OR /* hint */ status = 1;

DIGEST_TEXT：
SELECT * FROM `users` WHERE `name` = ? AND `age` IN (...) OR `status` = ?

DIGEST (示例)：
1a2b3c4d5e6f7890... (SHA-256, 64 字符 hex)
```

### 局限

```sql
-- 陷阱 1：全局默认值经过 5.7+ 自动调整后约 10000 条 (历史 5.6 默认 200)；非 per-user
SHOW VARIABLES LIKE 'performance_schema_digests_size';
-- 高负载系统应显式调到 10000+ 以避免自动调优给出过小值

-- 陷阱 2：max_digest_length 截断
-- 超过 1024 字节的 SQL 后半部分不会进入 digest 计算
-- 可能导致两个长 SQL 仅前 1024 字节相同就视作同一 digest

-- 陷阱 3：重启后 digest 表清空
-- 需要外部工具（pt-query-digest, MySQL Enterprise Monitor）持久化

-- 陷阱 4：DIGEST_TEXT 中的反引号
-- MySQL 总会给标识符加反引号，与原文不一定一致
```

## SQL Server：query_hash 与 query_plan_hash

### 概念

SQL Server 2008 引入两个 hash：

- **`query_hash`**：基于 SQL 文本（去除字面值），相同模板的 SQL 得到相同的 query_hash
- **`query_plan_hash`**：基于实际执行计划，即使 SQL 模板相同，因不同索引/统计信息选择不同计划时，plan_hash 不同

```sql
-- 通过 query_hash 聚合 Top-N
SELECT TOP 20
    qs.query_hash,
    qs.query_plan_hash,
    SUM(qs.execution_count) AS total_executions,
    SUM(qs.total_worker_time) / 1000 AS total_cpu_ms,
    SUM(qs.total_logical_reads) AS total_logical_reads,
    -- 任意取一个原始 SQL 文本
    MIN(SUBSTRING(st.text,
        qs.statement_start_offset/2 + 1,
        ((CASE qs.statement_end_offset
              WHEN -1 THEN DATALENGTH(st.text)
              ELSE qs.statement_end_offset
          END - qs.statement_start_offset)/2) + 1)) AS sample_query
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
GROUP BY qs.query_hash, qs.query_plan_hash
ORDER BY total_cpu_ms DESC;
```

### Query Store（持久化）

SQL Server 2016 引入 Query Store——把 query_hash + query_plan_hash + 执行统计**持久化到数据库文件**，重启不丢失：

```sql
-- 启用 Query Store
ALTER DATABASE production
    SET QUERY_STORE = ON
    (OPERATION_MODE = READ_WRITE,
     CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
     DATA_FLUSH_INTERVAL_SECONDS = 900,
     INTERVAL_LENGTH_MINUTES = 60,
     MAX_STORAGE_SIZE_MB = 1024,
     QUERY_CAPTURE_MODE = AUTO,
     SIZE_BASED_CLEANUP_MODE = AUTO,
     MAX_PLANS_PER_QUERY = 200);

-- Top-N 报表
SELECT TOP 20
    q.query_id,
    qt.query_sql_text,
    SUM(rs.count_executions) AS total_executions,
    AVG(rs.avg_duration) AS avg_duration_us,
    AVG(rs.avg_cpu_time) AS avg_cpu_us
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
GROUP BY q.query_id, qt.query_sql_text
ORDER BY AVG(rs.avg_duration) DESC;

-- 强制使用某个执行计划（基于 plan_hash）
EXEC sp_query_store_force_plan @query_id = 42, @plan_id = 73;
```

### query_hash 算法细节

SQL Server 的 `query_hash` 算法未公开，但已知特性：

- **64-bit binary**，独立于 plan_hash
- **大小写不敏感**：`SELECT` 与 `select` 同 hash
- **空白不敏感**：换行、Tab 处理一致
- **字面值替换**：数字、字符串都被忽略
- **对象名敏感**：跨数据库相同 SQL 的 query_hash 不同（含 schema 名）
- **NOLOCK / hint 敏感**：`WITH (NOLOCK)` 改变 hash

```sql
-- 实例
SELECT * FROM Sales.Orders WHERE OrderID = 1;
-- query_hash = 0xABCD1234...

SELECT * FROM Sales.Orders WHERE OrderID = 999;
-- query_hash = 0xABCD1234... (相同)

select  *  from   sales.orders   where orderid=1;
-- query_hash = 0xABCD1234... (相同，大小写空白不敏感)

SELECT * FROM Sales.Orders WITH (NOLOCK) WHERE OrderID = 1;
-- query_hash = 0xEEEE5678... (不同，hint 改变 hash)
```

## Oracle：V$SQLAREA、SQL_ID 与 FORCE_MATCHING_SIGNATURE

Oracle 有**两套**指纹机制，容易混淆：

### SQL_ID

- **基于 SQL 文本**（包括字面值）
- 13 字符 base32 字符串（实际是 MD5 取低 64 位编码）
- 字面值不同的 SQL 得到不同的 SQL_ID
- 用于精确定位某次具体执行（绑定变量后才能合并）

```sql
-- 这两条得到不同的 SQL_ID
SELECT * FROM employees WHERE empno = 100;  -- SQL_ID = 'abc...'
SELECT * FROM employees WHERE empno = 200;  -- SQL_ID = 'xyz...'

-- 这两条得到相同的 SQL_ID（绑定变量）
SELECT * FROM employees WHERE empno = :1;   -- SQL_ID = 'def...'
SELECT * FROM employees WHERE empno = :1;   -- SQL_ID = 'def...'
```

### FORCE_MATCHING_SIGNATURE

- **忽略字面值与大小写**，是真正的"模板指纹"
- 64-bit number
- 字面值不同的 SQL 得到相同的 force_matching_signature
- 用于聚合"同一个模板"的所有执行

```sql
-- 这两条 SQL_ID 不同，但 FORCE_MATCHING_SIGNATURE 相同
SELECT * FROM employees WHERE empno = 100;
SELECT * FROM employees WHERE empno = 200;

-- 查询 V$SQLAREA Top-N
SELECT * FROM (
    SELECT FORCE_MATCHING_SIGNATURE,
           SUM(EXECUTIONS) AS exec_count,
           SUM(ELAPSED_TIME)/1000 AS elapsed_ms,
           SUM(CPU_TIME)/1000 AS cpu_ms,
           SUM(BUFFER_GETS) AS buffer_gets,
           MIN(SQL_TEXT) AS sample_text
    FROM V$SQLAREA
    WHERE FORCE_MATCHING_SIGNATURE > 0
    GROUP BY FORCE_MATCHING_SIGNATURE
    ORDER BY elapsed_ms DESC
)
WHERE ROWNUM <= 20;
```

### CURSOR_SHARING 参数

控制是否将字面值"自动绑定变量化"：

| 值 | 行为 |
|----|------|
| `EXACT`（默认） | 字面值不同视为不同 cursor，每次硬解析 |
| `FORCE` | 自动将所有字面值替换为绑定变量，复用 cursor |
| `SIMILAR` | 已废弃，类似 FORCE 但保留某些字面值 |

```sql
-- 设置 CURSOR_SHARING = FORCE 后
ALTER SESSION SET CURSOR_SHARING = FORCE;

SELECT * FROM employees WHERE empno = 100;
-- Oracle 内部转为：SELECT * FROM employees WHERE empno = :"SYS_B_0";
-- 与原本的 SQL_ID 不同，但属于同一个 FORCE_MATCHING_SIGNATURE
```

### AWR Top SQL

```sql
-- 从 AWR 拿历史 Top SQL（需 Diagnostic Pack 许可）
SELECT * FROM (
    SELECT FORCE_MATCHING_SIGNATURE,
           SUM(EXECUTIONS_DELTA) AS execs,
           SUM(ELAPSED_TIME_DELTA)/1e6 AS elapsed_sec,
           MIN(SQL_TEXT) AS sample
    FROM DBA_HIST_SQLSTAT s
    JOIN DBA_HIST_SQLTEXT t USING (SQL_ID)
    WHERE SNAP_ID BETWEEN :begin_snap AND :end_snap
    GROUP BY FORCE_MATCHING_SIGNATURE
    ORDER BY elapsed_sec DESC
)
WHERE ROWNUM <= 20;
```

## Snowflake：QUERY_HASH 与 QUERY_PARAMETERIZED_HASH

Snowflake 在 2022 年引入查询哈希字段，区分两种粒度：

| 字段 | 含义 |
|------|------|
| `QUERY_HASH` | 对完整 SQL 文本（去除空白）的 hash，字面值参与 |
| `QUERY_PARAMETERIZED_HASH` | 对参数化后 SQL 的 hash，等价于"模板指纹" |
| `QUERY_HASH_VERSION` | 算法版本号（未来升级用） |
| `QUERY_PARAMETERIZED_HASH_VERSION` | 参数化算法版本号 |

```sql
-- Top-N 模板按 QUERY_PARAMETERIZED_HASH 聚合
SELECT QUERY_PARAMETERIZED_HASH,
       COUNT(*) AS exec_count,
       SUM(TOTAL_ELAPSED_TIME)/1000 AS total_sec,
       AVG(TOTAL_ELAPSED_TIME)/1000 AS avg_sec,
       MAX(QUERY_TEXT) AS sample
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME > DATEADD(day, -7, CURRENT_TIMESTAMP())
  AND QUERY_TYPE = 'SELECT'
GROUP BY QUERY_PARAMETERIZED_HASH
ORDER BY total_sec DESC
LIMIT 20;

-- 找到某个模板的所有不同字面值版本
SELECT QUERY_HASH, QUERY_TEXT
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE QUERY_PARAMETERIZED_HASH = '<hash>'
LIMIT 100;
```

### QUERY_HISTORY vs ACCOUNT_USAGE

- `INFORMATION_SCHEMA.QUERY_HISTORY`：当前用户最近 7-14 天，~10000 条
- `SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY`：账号级，**保留 365 天**，更适合长期趋势分析
- 注意 ACCOUNT_USAGE 有 45 分钟到 3 小时的延迟（非实时）

## BigQuery：jobs.query 与去重

BigQuery **不暴露查询指纹字段**，但通过两个机制部分弥补：

### 1. 查询缓存 / 物化视图复用基于 SQL 文本完全相等

```sql
-- BigQuery 的 query cache 命中条件
-- 1. SQL 文本字节完全相等（含空白）
-- 2. 引用的表数据未变化
-- 3. 用户/region 等会话属性匹配
```

### 2. INFORMATION_SCHEMA.JOBS 的 query 列

```sql
-- 自定义聚合：去除字面值后做聚合
SELECT
  REGEXP_REPLACE(
    REGEXP_REPLACE(query, r"'[^']*'", "'?'"),
    r"\b\d+\b", "?"
  ) AS normalized_query,
  COUNT(*) AS exec_count,
  SUM(total_slot_ms) AS total_slot_ms,
  AVG(total_slot_ms) AS avg_slot_ms
FROM `region-us`.INFORMATION_SCHEMA.JOBS
WHERE job_type = 'QUERY'
  AND creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY normalized_query
ORDER BY total_slot_ms DESC
LIMIT 20;
```

这种正则归一化非常粗糙：会错误地把字符串内的数字也替换掉，无法处理 IN 列表，也无法处理多行注释。所以 BigQuery 用户通常依赖外部工具或自行在客户端打 tag（`-- query_tag: report_daily_revenue`）做聚合。

### Job Labels 作为弱指纹

```sql
-- 推荐：在客户端给所有相同模板的查询打相同 label
-- bq query --label=template:daily_revenue ...
SELECT
  labels.value AS template,
  COUNT(*),
  SUM(total_slot_ms)
FROM `region-us`.INFORMATION_SCHEMA.JOBS,
     UNNEST(labels) AS labels
WHERE labels.key = 'template'
GROUP BY template;
```

## ClickHouse：normalized_query_hash

ClickHouse 21.3 引入查询规范化与 hash：

```sql
-- system.query_log 表中的关键字段
-- query: 原始 SQL
-- normalized_query: 规范化后的 SQL (字面值替换为 ?)
-- normalized_query_hash: sipHash64 of normalized_query

SELECT normalized_query_hash,
       any(normalized_query) AS template,
       count() AS exec_count,
       sum(query_duration_ms) AS total_ms,
       avg(query_duration_ms) AS avg_ms,
       sum(read_rows) AS total_rows,
       sum(memory_usage) AS total_mem
FROM system.query_log
WHERE event_date >= today() - 7
  AND type = 'QueryFinish'
GROUP BY normalized_query_hash
ORDER BY total_ms DESC
LIMIT 20;
```

ClickHouse 的归一化在 Parser 层做，源码 `src/Parsers/queryNormalization.cpp`。其特点：

- 数字、字符串字面值替换为 `?`
- IN 列表按长度分类：`IN (?, ?, ?, ?)` 与 `IN (?, ?, ?)` hash 不同（21.3 默认行为；可配置）
- `query_id` 是会话级 UUID，与 normalized_query_hash 不同

## CockroachDB：fingerprint_id

CockroachDB 把 SQL 解析为 AST 后，对 AST 做 walk 生成 `fingerprint_id`（FNV-1a 64-bit）：

```sql
-- 内部表 crdb_internal.statement_statistics
SELECT
    aggregated_ts,
    fingerprint_id,
    metadata->>'query' AS query,
    statistics->'statistics'->'cnt' AS exec_count,
    statistics->'statistics'->'rowsRead'->'mean' AS avg_rows,
    statistics->'statistics'->'svcLat'->'mean' AS avg_latency_sec
FROM crdb_internal.statement_statistics
WHERE aggregated_ts > now() - INTERVAL '1 hour'
ORDER BY (statistics->'statistics'->'svcLat'->'mean')::FLOAT DESC
LIMIT 20;

-- DB Console 中也可以可视化
-- 22.1+ 引入 statement diagnostics：可以为某个 fingerprint 主动收集一次执行详情
SELECT crdb_internal.request_statement_bundle(
    'SELECT * FROM users WHERE id = $1',  -- 模板（注意是带占位符的）
    0,                                     -- 采样概率（0 = 下次匹配）
    '0s'::interval,                        -- 最小延迟阈值
    '5m'::interval                         -- 收集窗口
);
```

CockroachDB 的归一化：

- 数字/字符串/布尔/字节串都替换为 `_`
- IN 列表折叠为 `_`（不区分长度）
- 标识符大小写归一为小写
- 注释剥离

## TiDB：digest 与 STATEMENTS_SUMMARY

TiDB 4.0 引入 statement summary，对所有 SQL 做规范化与 hash：

```sql
-- 时间窗口聚合（默认 30 分钟一桶）
SELECT digest,
       digest_text,
       sum_latency / 1e6 AS sum_latency_ms,
       avg_latency / 1e6 AS avg_latency_ms,
       exec_count,
       sum_cop_task_num,
       avg_processed_keys,
       max_mem
FROM information_schema.statements_summary
ORDER BY sum_latency DESC
LIMIT 20;

-- 历史窗口
SELECT * FROM information_schema.statements_summary_history
WHERE summary_begin_time >= NOW() - INTERVAL 1 HOUR
ORDER BY sum_latency DESC
LIMIT 20;

-- 慢查询日志中也带 digest
-- /tidb-slow.log 每条记录有 # Digest: <hex>
```

TiDB 的 digest：

- SHA-256 取前 16 字符（实际是 64-bit）
- 算法在 `parser/format/format.go` 的 `Digest` 函数
- 与 MySQL 的 digest 算法**不兼容**（即使同一 SQL，digest 值不同）

```sql
-- TiDB digest 例子
EXPLAIN ANALYZE SELECT digest('select * from users where id = 1');
-- 返回: 6e90c1bb5b50c79a...
```

## OceanBase：SQL_ID

OceanBase 是 Oracle 兼容的国产数据库，沿用 Oracle 的 `SQL_ID` 概念，但是用 MD5 哈希：

```sql
-- 查询 GV$OB_SQL_AUDIT
SELECT SQL_ID,
       COUNT(*) AS exec_count,
       SUM(ELAPSED_TIME)/1000 AS elapsed_ms,
       AVG(ELAPSED_TIME)/1000 AS avg_ms,
       MIN(QUERY_SQL) AS sample
FROM oceanbase.GV$OB_SQL_AUDIT
WHERE REQUEST_TIME > UNIX_TIMESTAMP(NOW() - INTERVAL 1 HOUR) * 1e6
GROUP BY SQL_ID
ORDER BY elapsed_ms DESC
LIMIT 20;
```

## SQL Server：query_hash 与 query_plan_hash 的区别

```sql
-- 同一模板，不同执行计划的情况
SELECT * FROM Orders WHERE CustomerID = 100;
-- 假设 CustomerID = 100 时优化器选择了 Index Seek（统计信息显示 100 条）
-- query_hash = 0xAAA, query_plan_hash = 0x111

SELECT * FROM Orders WHERE CustomerID = 999;
-- CustomerID = 999 时统计信息显示 100 万条，优化器选择 Full Scan
-- query_hash = 0xAAA (相同), query_plan_hash = 0x222 (不同)
```

这是 **parameter sniffing** 问题的根源——同一模板因不同字面值导致不同计划，性能波动。Query Store 的强制计划（force_plan）正是为了固定 plan_hash。

## 其他关键引擎一览

### MariaDB

继承 MySQL 的 Performance Schema digest 机制，10.5+ 改进了 sys schema 视图。

### Spanner

```sql
SELECT text_fingerprint,
       SUM(execution_count) AS execs,
       SUM(avg_latency_seconds * execution_count) / SUM(execution_count) AS avg_latency
FROM SPANNER_SYS.QUERY_STATS_TOP_HOUR
WHERE INTERVAL_END > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
GROUP BY text_fingerprint
ORDER BY avg_latency DESC
LIMIT 20;
```

### Vertica

```sql
SELECT request_label, COUNT(*), SUM(query_duration_us)
FROM v_monitor.query_profiles
WHERE query_start > NOW() - INTERVAL '1 hour'
GROUP BY request_label
ORDER BY SUM(query_duration_us) DESC;
```

### SAP HANA

```sql
SELECT STATEMENT_HASH,
       AVG_EXECUTION_TIME,
       EXECUTION_COUNT,
       STATEMENT_STRING
FROM M_SQL_PLAN_CACHE
ORDER BY TOTAL_EXECUTION_TIME DESC
LIMIT 20;
```

### Greenplum / TimescaleDB / AlloyDB / Aurora PG

完全继承 PostgreSQL 的 `pg_stat_statements` 与 `queryid`。Aurora PG 额外提供 Performance Insights，把 queryid 关联到 wait events。

### Aurora MySQL / PolarDB-MySQL

继承 MySQL 的 Performance Schema digest，PolarDB 额外把 digest 数据持久化到 OSS。

### Trino / Presto

无跨执行的"模板指纹"，只有会话级 `query_id`。但 Trino 通过 **event listener 接口**允许插件接收每条查询的归一化文本，常见做法是用 [Trino's BasicQueryInfo](https://trino.io/docs/current/admin/event-listeners-mysql.html) 自行做 fingerprint。

### Spark SQL

每个 query 在执行计划生成时会有内部的 `LogicalPlan` hash，但**不暴露给用户**。Databricks 通过 query history UI 提供查询历史，但聚合靠文本相等。

### Hive

仅有会话级 `operationId`，跨执行无法关联。`pt-query-digest` 类工具是常见替代方案。

## 算法深入：什么决定了归一化的"颗粒度"

### 维度 1：字面值替换的彻底程度

| 引擎 | 数字 | 字符串 | 布尔 | NULL | 日期字面值 | 数组字面值 |
|------|------|--------|------|------|-----------|-----------|
| PostgreSQL | $N | $N | $N | $N | $N | 列表保留 |
| MySQL | ? | ? | ? | ? | ? | IN(...) 折叠 |
| Snowflake | ? | ? | ? | ? | ? | 折叠 |
| Oracle | :SYS_B_N | :SYS_B_N | -- | -- | -- | 折叠 |
| ClickHouse | ? | ? | -- | NULL 保留 | ? | 折叠 |

### 维度 2：IN 列表折叠

```sql
-- 折叠的引擎（视为同一模板）
SELECT * FROM t WHERE id IN (1, 2, 3);
SELECT * FROM t WHERE id IN (10, 20);
-- MySQL/Snowflake/Oracle/CockroachDB/SQL Server: 同一指纹

-- 不折叠的引擎（不同模板）
-- PostgreSQL 9.4-13、ClickHouse 早期版本: 不同指纹
-- 这导致一个常见问题：循环中的 IN 列表逐渐增长会爆掉 fingerprint 表
```

### 维度 3：AS 别名

```sql
SELECT a.id FROM users AS a;
SELECT b.id FROM users AS b;
-- 多数引擎视为相同（别名只是局部符号）
-- 但少数引擎（如某些 ClickHouse 版本）会因为别名字符不同导致不同 hash
```

### 维度 4：注释处理

```sql
SELECT /*+ HASH_JOIN */ * FROM t;
-- Oracle/MySQL: hint 注释保留（影响 plan）
-- PostgreSQL: 全部注释剥离（PG 不支持注释 hint）
```

### 维度 5：限定与对象名

```sql
SELECT * FROM users;             -- a
SELECT * FROM public.users;      -- b
SELECT * FROM "public"."users";  -- c

-- PostgreSQL: a/b/c 都是不同 queryid（除非 search_path 一致）
-- MySQL: a 与 c 不同（反引号 vs 无）
-- SQL Server: 内部规范化后，a/b/c 取决于默认 schema
```

## 工程实践

### 用 pt-query-digest 做事后聚合

`pt-query-digest`（Percona Toolkit）是 MySQL 生态最常用的指纹工具：

```bash
# 解析 slow log 并聚合
pt-query-digest /var/log/mysql/slow.log --limit 20

# 输出包含每个模板的统计：
# Query 1: 0.05 QPS, 0.12x concurrency, ID 0x1A2B3C
# Time range: 2024-01-01 00:00:00 to 2024-01-01 23:59:59
# Attribute    pct   total     min     max     avg     95%  stddev  median
# Count         42  150000
# Exec time    65   18000s    50ms     5s   120ms  300ms   180ms   100ms
# Lock time     2     350s     1us    50ms   2.3ms   8ms    5ms     1ms
# Rows sent    23   45000K       0    100      30      50    25      10
# Rows examine 35  120000K      10  10000     800   2500   1200    600
# Query_time distribution
#   1us  ████
#  10us  ████
# 100us  ████████████
#   1ms  ████████████████
#  10ms  ████████████████████████████████
# 100ms  ████████████████████████████
#    1s  ████
#  10s+
# Tables
#    SHOW TABLE STATUS LIKE 'orders'\G
#    SHOW CREATE TABLE `orders`\G
# EXPLAIN /*!50100 PARTITIONS*/
# SELECT * FROM orders WHERE id = 12345\G
```

### 用 pg_stat_statements 做趋势分析

```sql
-- 创建快照表
CREATE TABLE pgss_snapshot AS
SELECT now() AS snapshot_at, * FROM pg_stat_statements;

-- 定时 INSERT INTO pgss_snapshot SELECT now(), * FROM pg_stat_statements;
-- 然后做差值（注意 reset 后 cumulative 计数会归零）

-- 跨快照计算增量
WITH t1 AS (SELECT * FROM pgss_snapshot WHERE snapshot_at = '2024-01-01 00:00'),
     t2 AS (SELECT * FROM pgss_snapshot WHERE snapshot_at = '2024-01-01 01:00')
SELECT t1.queryid,
       t2.calls - t1.calls AS calls_delta,
       t2.total_exec_time - t1.total_exec_time AS time_delta_ms,
       LEFT(t1.query, 200) AS query
FROM t1 JOIN t2 USING (queryid, dbid, userid)
ORDER BY time_delta_ms DESC
LIMIT 20;
```

### 用 OpenTelemetry 把 fingerprint 关联到 trace

```python
# 应用层埋点
from opentelemetry import trace
import hashlib

def normalize_sql(sql):
    # 简易归一化（生产用专业 parser）
    import re
    sql = re.sub(r"'[^']*'", '?', sql)
    sql = re.sub(r"\b\d+\b", '?', sql)
    sql = re.sub(r"\s+", ' ', sql).strip()
    return sql

def execute_query(sql, params):
    normalized = normalize_sql(sql)
    fingerprint = hashlib.md5(normalized.encode()).hexdigest()[:16]
    with trace.get_tracer(__name__).start_as_current_span("db.query") as span:
        span.set_attribute("db.statement.fingerprint", fingerprint)
        span.set_attribute("db.statement.template", normalized)
        return cursor.execute(sql, params)
```

之后在 Jaeger/Tempo 中可以按 fingerprint 聚合 trace。

### 在 ORM 层注入 fingerprint label

```python
# SQLAlchemy 示例：给所有 query 加上 hint comment
from sqlalchemy import event

@event.listens_for(Engine, "before_cursor_execute")
def comment_sql(conn, cursor, statement, parameters, context, executemany):
    # 提取调用栈中的业务标识
    label = get_request_template()  # e.g., "GET /api/orders"
    return f"/* tag:{label} */ {statement}", parameters

# 在 PG/MySQL 的查询日志中可以按 tag 聚合
```

## 关键发现

### 1. 指纹支持的"统一性鸿沟"

OLTP 老牌引擎（PostgreSQL、MySQL、SQL Server、Oracle、DB2）都有成熟的指纹机制，且都在 2008-2014 年间引入。OLAP / Cloud / 流引擎在指纹支持上参差不齐：BigQuery 至今无原生指纹，Trino 只有会话级 query_id，Flink SQL 完全没有。

### 2. 64-bit 是事实标准

绝大多数引擎选择 64-bit hash（PG / SQL Server / Oracle FORCE_MATCHING / Snowflake / ClickHouse / CockroachDB）。MySQL 与 TiDB 用 SHA-256 取 256 bit / 取前 64 bit。理由：64-bit 空间下，10^6 fingerprint 的碰撞率 ~ 2.7×10^-8，对统计聚合足够；存储与索引开销低；可放进单个 `bigint` 列。

### 3. 算法分两大流派

- **Token-based**（MySQL / TiDB / ClickHouse）：在 Lexer/Parser 阶段逐 token 累积 hash，跳过字面值 token。优点：简单、快、可与 Parser 复用工作；缺点：无法处理"语义等价但 token 不同"（如 `SELECT 1+1` vs `SELECT 1 + 1` 的中间空白依赖处理逻辑）
- **AST-based**（PostgreSQL / CockroachDB / Spanner）：在 Parser 输出 AST 后做 walk，跳过 Const 节点。优点：彻底归一化，对空白/大小写完全不敏感；缺点：实现复杂，需要为每种 AST 节点写 jumble 逻辑，DDL 后 OID 变化可能导致 hash 失效

### 4. IN 列表折叠是常见痛点

PG 14 之前不折叠 IN 列表是历史包袱，社区抱怨长达多年。原因是 jumble 算法基于 AST 节点，而 `IN (1,2,3)` 与 `IN (1,2,3,4)` 是不同长度的 List 节点。PG 14 引入"列表项数量归一化"才解决。MySQL/Snowflake/Oracle 等更早就支持折叠，但折叠粒度差异（按长度分桶 vs 完全忽略长度）也会影响指纹聚合粒度。

### 5. 持久化与上限是另一个分水岭

- PG 默认 `pg_stat_statements.max = 5000`，多数生产环境需要调到 10000-20000
- MySQL 5.7+ `performance_schema_digests_size` 由自动调优（`-1`）通常落在约 10000 (5.6 历史默认 200，是已被修正的常见踩坑)；高负载仍建议显式调到 10000+
- SQL Server Query Store 是唯一**默认持久化到数据库文件**的设计
- Snowflake 的 ACCOUNT_USAGE 保留 365 天最长，便于年度对比

### 6. 指纹与执行计划的解耦

只有 SQL Server 把 `query_hash`（语义）与 `query_plan_hash`（执行）分成两个独立字段。这是诊断 parameter sniffing 的关键——同一模板不同计划的对比一目了然。其他引擎要么不暴露 plan hash（PG / MySQL），要么需要从计划文本自己 hash。

### 7. 字面值反查的取舍

- 完整保留所有字面值的引擎：Oracle V$SQL（同 SQL_ID 多行）、Snowflake QUERY_HISTORY、ClickHouse query_log
- 只保留一个样本的引擎：PG（pg_stat_statements 只存最后一次）、MySQL（DIGEST_TEXT 是规范化文本）
- 完全不保留具体值的引擎：BigQuery（仅 query 原文）、CockroachDB（metadata 中保留示例）

权衡点：保留全部字面值便于 debug，但会泄露敏感数据（手机号、身份证）；只保留模板更安全但失去了重现能力。

### 8. 指纹的"语义不变性"边界

哪些改动应该改变指纹？哪些不该？

| 改动 | PG | MySQL | SQL Server | 评论 |
|------|----|----|----|------|
| 字面值变化 | 不变 | 不变 | 不变 | 一致 |
| 空白/大小写 | 不变 | 不变 | 不变 | 一致 |
| 列顺序 | 变 | 变 | 变 | 都视为不同模板 |
| `SELECT *` vs 列出列 | 变 | 变 | 变 | 一致 |
| `WHERE a AND b` vs `WHERE b AND a` | 变 | 变 | 变 | AST 不同 |
| 加入冗余 `WHERE TRUE` | 变 | 变 | 变 | 多了一个 AST 节点 |
| Hint 注释 | 不变（PG 无 hint） | 变 | 变 | 影响 plan 故应区分 |

唯一不一致的是 hint 处理，源于 PG 设计上没有 SQL hint（依赖 `pg_hint_plan` 扩展）。

### 9. 给引擎开发者的建议

如果你正在设计一款新数据库的指纹机制：

1. **首选 AST-based + 64-bit hash**：彻底归一化，碰撞概率可接受
2. **必须支持 IN 列表折叠**：否则会被 ORM 生成的变长 IN 列表打爆
3. **暴露规范化文本字段**：仅暴露 hash 不够，运维需要看到模板长什么样
4. **保留至少一个样本**：用于 debug 和 reproduce
5. **持久化是重要选项**：进程重启不应丢失统计
6. **separate query_hash 与 plan_hash**：诊断价值巨大
7. **支持手动 reset**：让运维可以清零统计窗口
8. **暴露在标准系统视图中**：便于第三方工具集成（如 Grafana）

### 10. 给应用开发者的建议

1. **始终用 prepared statement / 参数绑定**：避免每个字面值产生新指纹
2. **避免动态拼接 IN 列表**：要么用临时表，要么固定列表长度（PG 14 之前尤其重要）
3. **给关键查询打 hint comment**：`/* tag: order_summary */` 便于跨工具聚合
4. **监控 fingerprint 表大小**：突然增长往往意味着有动态 SQL 在污染统计
5. **定期 reset 统计**：避免老数据占用空间
6. **跨引擎迁移时重新评估指纹**：不同引擎的归一化算法不同，老的 dashboard 可能失效

## 参考资料

- PostgreSQL: [pg_stat_statements](https://www.postgresql.org/docs/current/pgstatstatements.html)
- PostgreSQL: [Query Jumble source](https://github.com/postgres/postgres/blob/master/src/backend/utils/misc/queryjumble.c)
- MySQL: [Performance Schema Statement Digests](https://dev.mysql.com/doc/refman/8.0/en/performance-schema-statement-digests.html)
- MySQL Source: [sql/sql_digest.cc](https://github.com/mysql/mysql-server/blob/trunk/sql/sql_digest.cc)
- SQL Server: [query_hash and query_plan_hash](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-query-stats-transact-sql)
- SQL Server: [Query Store Overview](https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
- Oracle: [V$SQLAREA](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-SQLAREA.html)
- Oracle: [CURSOR_SHARING](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/CURSOR_SHARING.html)
- Snowflake: [QUERY_HISTORY view](https://docs.snowflake.com/en/sql-reference/account-usage/query_history)
- ClickHouse: [system.query_log](https://clickhouse.com/docs/en/operations/system-tables/query_log)
- CockroachDB: [Statement Diagnostics](https://www.cockroachlabs.com/docs/stable/ui-statements-page.html)
- TiDB: [Statement Summary Tables](https://docs.pingcap.com/tidb/stable/statement-summary-tables)
- Spanner: [Query Statistics](https://cloud.google.com/spanner/docs/introspection/query-statistics)
- Percona: [pt-query-digest](https://docs.percona.com/percona-toolkit/pt-query-digest.html)
- pgBadger: [PostgreSQL log analyzer](https://github.com/darold/pgbadger)
- pganalyze: [Comparing Postgres queryid algorithms](https://pganalyze.com/blog/pg14-query-id)
