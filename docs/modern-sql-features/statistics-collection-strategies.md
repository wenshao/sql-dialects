# 统计信息采集策略 (Statistics Collection Strategies)

统计信息错一倍，执行计划可能慢一千倍——但很少有人讨论统计信息**何时采集、如何采集、采多少**。这篇文章不讨论统计信息的内容（直方图、MCV、相关性），而是聚焦在 CBO 体系中最容易被忽视、也最容易出问题的一环：**采集机制本身**。一张 100 亿行的事实表，全表扫描一次需要数小时；而采样不当又会导致 NDV 失真、MCV 漏掉热点。如何在"准确性"和"采集开销"之间走钢丝，是优化器质量的隐形战场。

> 本文是统计信息系列的第四篇。其他三篇：
> - [`statistics-histograms.md`](./statistics-histograms.md)：直方图与基础统计的内容结构
> - [`extended-statistics.md`](./extended-statistics.md)：多列 / 函数依赖 / 相关性统计
> - [`selectivity-estimation.md`](./selectivity-estimation.md)：基于统计的选择性估计算法
>
> 本文专注于 **采集机制（collection mechanics）**：触发时机、采样策略、增量更新、自动化调度，与上述三篇互补。

## 为什么采集机制至关重要

考虑一张订单表：100 亿行、200 列、按月分区。如果优化器以为某分区有 100 万行而实际有 10 亿行，HashJoin 的 build-side 可能 OOM；如果以为某列有 1000 个 distinct 值而实际有 100 万，aggregation 的 hash table 大小会被低估 1000 倍。

但要避免这种"过期统计"，每次数据变动都全量重算 ANALYZE 显然不现实——百亿行表的全扫描可能需要数小时，期间业务读写性能受严重影响。所以每个数据库都必须回答以下问题：

1. **何时触发采集（when）**：
   - 完全手动？由 DBA 决定？
   - 自动后台任务？以何种条件、多久一次？
   - 增删改超过多少比例触发？
   - 维护窗口（maintenance window）调度？
2. **采集多少（how much）**：
   - 全表扫描？
   - 采样？采样比例多少？
   - 自适应采样（根据表大小动态决定）？
3. **采集方式（how）**：
   - 阻塞式同步采集？
   - 后台异步采集？
   - 并行采集？
   - 增量采集（只算新增数据）？
4. **粒度（granularity）**：
   - 表级、分区级、列级？
   - 索引统计 vs 列统计？
   - 直方图是否单独触发？

不同回答带来截然不同的运维体验和性能特征。Oracle 默认在维护窗口内执行 `DBMS_STATS.GATHER_DATABASE_STATS`，并使用 `AUTO_SAMPLE_SIZE`（11g 起的哈希采样算法）；PostgreSQL 由 autovacuum 后台触发 `ANALYZE`，固定 `300 * default_statistics_target` 行采样；SQL Server 在 2014 之前用"每 20% 行变更触发"的硬阈值，2014 后改成 `SQRT(1000 * N)` 的动态阈值；Snowflake 在每个 micropartition 写入时同步算好统计，用户完全无感。这些设计差异决定了每个引擎在"DBA 手动维护"和"开箱即用"两个极端之间所处的位置。

## 没有 SQL 标准

ISO/IEC 9075（SQL 标准的所有版本）**完全没有**对统计信息收集做任何规定——既没有标准的 `ANALYZE` 语句，也没有标准的"自动收集"机制，更没有标准的"采样比例"参数。每家数据库各自定义：

- PostgreSQL: `ANALYZE [VERBOSE] [table [(column_list)]]`，由 autovacuum 后台触发
- Oracle: `DBMS_STATS.GATHER_TABLE_STATS(schema, table, ...)`，由 `auto_stats_job` 在维护窗口执行
- SQL Server: `UPDATE STATISTICS table_name`，由 `AUTO_UPDATE_STATISTICS` 在查询时触发
- MySQL: `ANALYZE TABLE t`，由 `innodb_stats_auto_recalc` 触发
- DB2: `RUNSTATS ON TABLE t`，由 `auto_runstats` 触发
- Snowflake / BigQuery: 完全托管，无用户接口
- CockroachDB: `CREATE STATISTICS ... FROM t`，由内置自动机制触发
- TiDB: `ANALYZE TABLE t [WITH N SAMPLES]`，由 `tidb_enable_auto_analyze` 触发

不仅语法各异，**触发机制、采样算法、调度策略都完全私有**。一段在 PostgreSQL 上"刚好够用"的统计信息，迁移到 SQL Server 上可能需要完全不同的维护节奏；而 Snowflake 用户完全不需要思考这些问题。本文从"采集机制"角度横向对比 45+ 数据库的实现差异。

## 支持矩阵

### 自动采集守护进程 / 任务

| 引擎 | 自动采集机制 | 默认开启 | 触发方式 | 配置入口 |
|------|------------|---------|---------|---------|
| PostgreSQL | autovacuum analyze | 是 | 后台守护进程，按表更新比例触发 | `autovacuum_analyze_threshold/scale_factor` |
| MySQL | InnoDB persistent stats | 是（5.6.6+） | 行变更后台异步重算 | `innodb_stats_auto_recalc` (默认 ON) |
| MariaDB | engine-independent stats | 否（默认） | 手动 ANALYZE | `use_stat_tables = PREFERABLY` |
| SQLite | -- | 否 | 完全手动 | -- |
| Oracle | `auto_stats_job` (10g+) | 是 | 维护窗口内（夜间 22:00–6:00） | `DBMS_AUTO_TASK_ADMIN` |
| SQL Server | `AUTO_UPDATE_STATISTICS` | 是 | 查询编译时检查阈值，按需同步采集 | `ALTER DATABASE SET AUTO_UPDATE_STATISTICS ON` |
| DB2 | `auto_runstats` (LUW 9.5+) | 是 | 后台任务 + 健康度评估 | `auto_runstats = ON` |
| Snowflake | micropartition 内置 | 是（强制） | 写入时同步采集 | 不可配置 |
| BigQuery | column auto-stats | 是（强制） | 后台异步 | 不可配置 |
| Redshift | Auto Analyze | 是 | 增量自动收集 | `auto_analyze = true` |
| DuckDB | -- | -- | 大多依赖运行时统计 | -- |
| ClickHouse | -- | -- | 不依赖传统统计 | -- |
| Trino | -- | 否 | 完全手动 ANALYZE | -- |
| Presto | -- | 否 | 完全手动 ANALYZE | -- |
| Spark SQL | -- | 否 | 完全手动 ANALYZE | -- |
| Hive | `hive.stats.autogather` | 是（INSERT 时） | DML 时联动 | `hive.stats.autogather = true` |
| Flink SQL | -- | 否 | 完全手动 ANALYZE | -- |
| Databricks | Auto Optimize | 部分 | Delta Lake 写入时维护 | `delta.autoOptimize.optimizeWrite` |
| Teradata | -- | 否 | 完全手动 COLLECT STATISTICS | -- |
| Greenplum | autovacuum analyze | 是 | 继承 PostgreSQL | `autovacuum` |
| CockroachDB | 自动采集 | 是 | 行变更比例触发 | `sql.stats.automatic_collection.enabled` |
| TiDB | `tidb_enable_auto_analyze` | 是 | 健康度阈值触发 | `tidb_auto_analyze_ratio` (默认 0.5) |
| OceanBase | 自动采集 | 是 | DBMS_STATS 兼容 + 后台 | `_enable_optimizer_dynamic_sampling` |
| YugabyteDB | -- | 否 | 继承 PG 但默认关闭 autoanalyze | YB-TServer flags |
| SingleStore | columnstore 自动维护 | 是 | 写入时维护 | `optimizer_statistics` |
| Vertica | -- | 否 | 显式 `ANALYZE_STATISTICS` | -- |
| Impala | -- | 否 | `COMPUTE STATS` 手动 | -- |
| StarRocks | 自动采集 | 是 | 后台周期 + 健康度 | `enable_auto_collect_statistics` |
| Doris | 自动采集 | 是 | 后台周期 | `enable_auto_analyze` (2.0+) |
| MonetDB | -- | 否 | 显式 `ANALYZE` | -- |
| CrateDB | 自动采集 | 是 | 后台周期 | `stats.service.interval` |
| TimescaleDB | autovacuum analyze | 是 | 继承 PG，hypertable 按 chunk | 继承 PG |
| QuestDB | -- | -- | 时序索引替代 | -- |
| Exasol | 内部自动 | 是 | 完全托管 | 不可配置 |
| SAP HANA | 自动 | 是 | data statistics auto-create | `data_statistics_auto_create` |
| Informix | UPDATE STATISTICS HIGH/MEDIUM/LOW | 否 | 完全手动 | -- |
| Firebird | -- | 否 | 完全手动 `SET STATISTICS INDEX` | -- |
| H2 | -- | 否 | 完全手动 `ANALYZE` | -- |
| HSQLDB | -- | -- | 不支持 | -- |
| Derby | -- | 否 | 完全手动 `SYSCS_UPDATE_STATISTICS` | -- |
| Amazon Athena | -- | 否 | 继承 Trino，手动 ANALYZE | -- |
| Azure Synapse | `AUTO_UPDATE_STATISTICS` | 部分 | Dedicated Pool 与 SQL Server 类似 | `AUTO_CREATE_STATISTICS` |
| Google Spanner | 自动 | 是 | 完全托管 | 不可配置 |
| Materialize | -- | -- | 增量计算无传统统计 | -- |
| RisingWave | -- | -- | 流式系统不依赖 | -- |
| InfluxDB | -- | -- | 时序无传统统计 | -- |
| DatabendDB | snapshot 级 | 是 | snapshot commit 时维护 | -- |
| Yellowbrick | autovacuum 兼容 | 是 | 继承 PG | -- |
| Firebolt | 内部自动 | 是 | 完全托管 | 不可配置 |

> 统计：约 28 个引擎提供"自动采集"机制并默认开启；约 11 个完全依赖手动；其余完全托管或不暴露。

### 手动 ANALYZE 命令

| 引擎 | 命令语法 | 列粒度 | 分区粒度 | 强制重收 |
|------|---------|--------|---------|---------|
| PostgreSQL | `ANALYZE [VERBOSE] [table [(col, ...)]]` | 是 | 是（PG 14+ 自动维护，但可手动） | 总是重收 |
| MySQL | `ANALYZE TABLE t [, t2, ...]` | -- | `ANALYZE TABLE t PARTITION (p1)` | 总是重收 |
| MariaDB | `ANALYZE TABLE t [PERSISTENT FOR ALL]` | 是 | 是 | 总是 |
| SQLite | `ANALYZE [table\|index]` | -- | -- | 总是 |
| Oracle | `DBMS_STATS.GATHER_TABLE_STATS(schema, table, ...)` | `method_opt 'FOR COLUMNS ...'` | `partname` 参数 | 通过 `force=>TRUE` |
| SQL Server | `UPDATE STATISTICS t [, stats_name]` | 是 | `INCREMENTAL = ON` | `WITH RESAMPLE` |
| DB2 | `RUNSTATS ON TABLE t [ON COLUMNS (...)]` | 是 | `ON SAMPLE` 子句 | -- |
| Snowflake | -- | -- | -- | -- |
| BigQuery | -- | -- | -- | -- |
| Redshift | `ANALYZE [t [(col)]] [PREDICATE COLUMNS \| ALL COLUMNS]` | 是 | -- | `THRESHOLD 0` |
| DuckDB | `ANALYZE` | -- | -- | -- |
| ClickHouse | -- | -- | -- | -- |
| Trino | `ANALYZE table_name [WITH (...)]` | `'columns' = ARRAY[...]` | `'partitions' = ARRAY[...]` | 总是 |
| Presto | `ANALYZE table_name [WITH (...)]` | 同 Trino | 同 Trino | 总是 |
| Spark SQL | `ANALYZE TABLE t COMPUTE STATISTICS [FOR COLUMNS ... \| FOR ALL COLUMNS]` | 是 | `PARTITION (...)` | 总是 |
| Hive | `ANALYZE TABLE t [PARTITION (...)] COMPUTE STATISTICS [FOR COLUMNS]` | 是 | 是 | 总是 |
| Flink SQL | `ANALYZE TABLE t [PARTITION (...)] COMPUTE STATISTICS [FOR COLUMNS]` | 是 (1.16+) | 是 | 总是 |
| Databricks | `ANALYZE TABLE t COMPUTE [DELTA] STATISTICS [FOR COLUMNS \| FOR ALL COLUMNS]` | 是 | 是 | 总是 |
| Teradata | `COLLECT STATISTICS [USING SAMPLE n PERCENT] ON t [COLUMN (col1, col2)]` | 是 | 是（PPI） | 总是 |
| Greenplum | `ANALYZE [ROOTPARTITION] [VERBOSE] [t]` | 是 | `ROOTPARTITION` 参数 | 总是 |
| CockroachDB | `CREATE STATISTICS name [ON cols] FROM t [AS OF SYSTEM TIME -10s]` | 是 | -- | 命名后总是 |
| TiDB | `ANALYZE TABLE t [PARTITION (...)] [WITH N SAMPLES \| WITH N TOPN]` | 是 | 是 | 总是 |
| OceanBase | `ANALYZE TABLE t` 或 `DBMS_STATS.GATHER_TABLE_STATS` | 是 | 是 | `force=>TRUE` |
| YugabyteDB | `ANALYZE [t [(col)]]` | 是 | 是 | 总是 |
| SingleStore | `ANALYZE TABLE t [COLUMNS col1, col2]` | 是 | -- | 总是 |
| Vertica | `SELECT ANALYZE_STATISTICS('schema.t' [, 'col1, col2'])` | 是 | -- | 总是 |
| Impala | `COMPUTE STATS t [(col1, col2)] [TABLESAMPLE SYSTEM(n)]` | 是 | -- (用 INCREMENTAL) | 总是 |
| StarRocks | `ANALYZE TABLE t [(col1)] [WITH SYNC \| ASYNC] MODE` | 是 | 是 | -- |
| Doris | `ANALYZE TABLE t [(col)] [WITH SYNC] [WITH SAMPLE PERCENT n]` | 是 | 是 | -- |
| MonetDB | `ANALYZE [schema.t [(col1, col2)]]` | 是 | -- | 总是 |
| CrateDB | `ANALYZE` | -- | -- | 总是 |
| TimescaleDB | `ANALYZE [hypertable]` | 是 | 是 (按 chunk) | 总是 |
| QuestDB | -- | -- | -- | -- |
| Exasol | -- | -- | -- | -- |
| SAP HANA | `CREATE STATISTICS s ON t(c) TYPE HISTOGRAM` / `REFRESH STATISTICS` | 是 | 是 | `REFRESH` |
| Informix | `UPDATE STATISTICS HIGH/MEDIUM/LOW [FOR TABLE t [(col)]]` | 是 | -- | 总是 |
| Firebird | `SET STATISTICS INDEX idx_name` | -- (仅索引) | -- | 总是 |
| H2 | `ANALYZE [SAMPLE_SIZE n]` | -- | -- | 总是 |
| HSQLDB | -- | -- | -- | -- |
| Derby | `CALL SYSCS_UTIL.SYSCS_UPDATE_STATISTICS(schema, table, index)` | -- | -- | 总是 |
| Amazon Athena | `ANALYZE TABLE t` | 同 Trino | 同 Trino | 总是 |
| Azure Synapse | `UPDATE STATISTICS t [(stats_name)]` / `CREATE STATISTICS` | 是 | -- | `WITH FULLSCAN` |
| Google Spanner | -- | -- | -- | -- |
| Materialize | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- |
| InfluxDB | -- | -- | -- | -- |
| DatabendDB | `ANALYZE TABLE t` | -- | -- | 总是 |
| Yellowbrick | `ANALYZE [t]` | 是 | -- | 总是 |
| Firebolt | -- | -- | -- | -- |

### 采样 vs 全扫描

| 引擎 | 默认策略 | 采样支持 | 全扫描支持 | 自适应采样 |
|------|---------|---------|----------|----------|
| PostgreSQL | 固定行数采样（`300 * statistics_target` 行） | 是 | 否（采样模型固定） | 否 |
| MySQL | 采样固定页数 (`innodb_stats_persistent_sample_pages`) | 是 | -- (采样为唯一模式) | -- |
| MariaDB | 采样比例可配 (`analyze_sample_percentage`) | 是 | 是 (`SET SESSION analyze_sample_percentage=100`) | -- |
| SQLite | 全扫描 | -- | 是 (sqlite_stat1) | -- |
| Oracle | `AUTO_SAMPLE_SIZE` (11g+ 默认，哈希采样近似全扫描精度) | 是 (`estimate_percent`) | 是 (`estimate_percent => 100`) | 是 (AUTO_SAMPLE_SIZE) |
| SQL Server | 采样（默认 `SAMPLE` 大小由表大小决定） | 是 (`WITH SAMPLE n PERCENT`) | 是 (`WITH FULLSCAN`) | 是 (默认采样比例) |
| DB2 | 全扫描 | 是 (`WITH SAMPLING`) | 是（默认） | -- |
| Snowflake | micropartition 元数据（无传统采样） | -- | 是（写入时全扫描） | -- |
| BigQuery | 后台异步 | -- | 是（后台） | -- |
| Redshift | `analyze_threshold_percent` 增量 | 是 | 是 (`PREDICATE COLUMNS`) | -- |
| Trino | 全扫描 | -- | 是 | -- |
| Spark SQL | 全扫描 | -- | 是 | -- |
| Hive | 全扫描 | -- | 是 | -- |
| Databricks | 全扫描 (Delta) | -- | 是 | -- |
| Teradata | 默认 100% | 是 (`USING SAMPLE n PERCENT`) | 是（默认） | 是 (`USING SAMPLE`) |
| Greenplum | 继承 PG | 是 | -- | -- |
| CockroachDB | 采样（默认 10000 行） | 是 (`AS OF SYSTEM TIME` + 内部采样) | -- | 是（按表大小） |
| TiDB | 采样 (`tidb_analyze_version=2` 默认 100k 行) | 是 (`WITH N SAMPLES`) | 否 | 是 (analyze v2) |
| OceanBase | 兼容 Oracle 默认 AUTO_SAMPLE_SIZE | 是 | 是 | 是 |
| YugabyteDB | 继承 PG | 是 | -- | -- |
| SingleStore | 采样 | 是 | 是 | -- |
| Vertica | 默认 10% | 是 (`PERCENT n`) | 是 (`PERCENT 100`) | -- |
| Impala | 全扫描 | 是 (`TABLESAMPLE SYSTEM(n)`, 4.0+) | 是（默认） | -- |
| StarRocks | 采样 (`statistic_sample_collect_rows`，默认 200000) | 是 | 是 (full ANALYZE) | -- |
| Doris | 采样 (`analyze.sample.rows`) | 是 | 是 | -- |
| Azure Synapse | 与 SQL Server 一致 | 是 | 是 (`WITH FULLSCAN`) | 是 |
| SAP HANA | 采样 | 是 (`WITH SAMPLE n`) | 是 | -- |

### 增量统计

| 引擎 | 增量统计 | 命令/配置 | 增量粒度 |
|------|---------|----------|---------|
| Oracle | 是（11g+） | `INCREMENTAL = TRUE` (`DBMS_STATS.SET_TABLE_PREFS`) | 分区级 |
| SQL Server | 是（2014+） | `WITH INCREMENTAL = ON` | 分区级 |
| DB2 | -- | -- | -- |
| PostgreSQL | -- (依靠 autovacuum 增量触发，但单次 ANALYZE 总是重算) | -- | -- |
| MySQL | -- | -- | -- |
| Redshift | 是（自动） | `auto_analyze = true` | 块级 |
| Snowflake | 是（micropartition 增量） | 内置 | micropartition 级 |
| BigQuery | 是（后台） | 内置 | column 级 |
| CockroachDB | -- (但自动调度由 mutation 比例触发) | -- | -- |
| TiDB | -- | -- | -- |
| Impala | 是（COMPUTE INCREMENTAL STATS） | `COMPUTE INCREMENTAL STATS t` | 分区级 |
| Spark SQL | -- | -- | -- |
| Hive | -- | -- | -- |
| Databricks | 是 (Delta auto-collected) | 写入时维护 | 文件级 |
| Teradata | 是（USING） | `COLLECT STATISTICS USING SUMMARY` | 增量直方图 |
| Doris | 是（2.0+） | `ANALYZE TABLE ... WITH INCREMENTAL` | 分区级 |
| StarRocks | -- (整体重新采集) | -- | -- |
| Greenplum | -- | -- | -- |
| OceanBase | 是（兼容 Oracle） | `INCREMENTAL` 选项 | 分区级 |
| Azure Synapse | -- | -- | -- |
| SAP HANA | 部分 | `REFRESH STATISTICS ... INCREMENTAL` | -- |

> 统计：约 11 个引擎实现了真正意义的"增量统计"。其中 Oracle 11g 引入的"分区级 incremental + global synopsis 合并"是行业开创性设计，被 SQL Server 2014、Impala、OceanBase、Doris 等借鉴。

### 采样比例配置

| 引擎 | 配置参数 | 默认值 | 范围 | 单位 |
|------|---------|-------|------|------|
| PostgreSQL | `default_statistics_target` | 100 | 1–10000 | 间接（×300 = 采样行数） |
| PostgreSQL | `ALTER TABLE ... ALTER COLUMN ... SET STATISTICS` | 继承 default | 1–10000 | per-column |
| MySQL | `innodb_stats_persistent_sample_pages` | 20 | 1–unlimited | 页数 |
| MySQL | `innodb_stats_transient_sample_pages` | 8 | 1–unlimited | 页数 |
| MariaDB | `analyze_sample_percentage` | 100.0 | 0–100 | 百分比 |
| Oracle | `DBMS_STATS.SET_TABLE_PREFS('ESTIMATE_PERCENT')` | `AUTO_SAMPLE_SIZE` | 0.000001–100 或 AUTO | 百分比 |
| SQL Server | `WITH SAMPLE n PERCENT` 或 `WITH SAMPLE n ROWS` | 由表大小动态决定 | 0–100 / 行数 | 百分比 / 行数 |
| DB2 | `WITH SAMPLING n` | -- | 0–100 | 百分比 |
| Trino | `ANALYZE WITH (sample_percentage = n)` | -- | -- | 实现相关 |
| Spark SQL | `spark.sql.statistics.fallBackToHdfs` | -- | -- | 间接 |
| Teradata | `USING SAMPLE n PERCENT` | 默认 100% | 2–100 | 百分比 |
| Vertica | `PERCENT n` | 10 | 1–100 | 百分比 |
| Impala | `TABLESAMPLE SYSTEM(n)` | -- | 0–100 | 百分比 |
| TiDB | `WITH N SAMPLES` 或 `WITH N TOPN` | 100000 行 | -- | 行数 |
| StarRocks | `statistic_sample_collect_rows` | 200000 | 1–unlimited | 行数 |
| Doris | `WITH SAMPLE PERCENT n` 或 `WITH SAMPLE ROWS n` | 全扫描 | 0–100 / 行数 | 百分比 / 行数 |
| CockroachDB | `sql.stats.histogram_samples.count` | 10000 | -- | 行数 |
| OceanBase | `estimate_percent` | AUTO | 0–100 | 百分比 |
| SAP HANA | `WITH SAMPLE n` | -- | -- | 百分比 |
| Azure Synapse | `WITH SAMPLE n PERCENT` | 与 SQL Server 同 | 0–100 | 百分比 |

### 统计新鲜度阈值

不同引擎判断"统计是否过期、需要重收"的阈值：

| 引擎 | 触发条件 | 阈值参数 | 默认值 |
|------|---------|---------|-------|
| PostgreSQL | 表行变更（INSERT/UPDATE/DELETE）超过阈值 | `autovacuum_analyze_threshold + autovacuum_analyze_scale_factor * reltuples` | 50 + 0.1 × N |
| MySQL | 行变更超过 10% | `innodb_stats_auto_recalc` (开关) + 内置 10% | 10% |
| Oracle | 自动判定"stale"：行变更 ≥ 10% | `DBMS_STATS.SET_TABLE_PREFS('STALE_PERCENT')` | 10% |
| SQL Server (2008–2012) | 行变更 ≥ 500 + 20% × N（rowmodctr） | 硬编码 | 500+20% |
| SQL Server (2014+, CL120+) | `SQRT(1000 × N)` 动态阈值 | 自动启用 (TF 2371 在 2008/2012 下) | dynamic |
| DB2 | 健康度评分（HealthMon） | `auto_runstats` policies | -- |
| CockroachDB | 行变更超过 20% | `sql.stats.automatic_collection.fraction_stale_rows` | 0.2 |
| TiDB | 健康度（healthy）< 阈值 | `tidb_auto_analyze_ratio` | 0.5（变更 50% 触发） |
| Redshift | `stats_off` 列 ≥ 阈值 | `analyze_threshold_percent` | 10 |
| StarRocks | 行变更比例 | `statistic_auto_collect_ratio` | 0.8 |
| Doris | 行变更比例 | `auto_analyze_table_width_threshold` 等 | 实现相关 |
| Snowflake | -- | 内置 micropartition 增量 | -- |
| BigQuery | -- | 内置 | -- |

### 分区级统计

| 引擎 | 分区级统计 | 全局合并 | 增量分区 | 命令 |
|------|----------|---------|---------|------|
| PostgreSQL | 是 | 父表合并 | -- | `ANALYZE partition_name` |
| Oracle | 是 | global stats（两种模式） | 是 | `DBMS_STATS.GATHER_TABLE_STATS(... granularity=>'PARTITION')` |
| SQL Server | 是 | -- | 是 (`INCREMENTAL = ON`) | `UPDATE STATISTICS t WITH FULLSCAN ON PARTITIONS(p1)` |
| DB2 | 是（range partition） | 是 | -- | `RUNSTATS ON TABLE t` |
| MySQL | 是 | -- | -- | `ANALYZE TABLE t PARTITION (p1)` |
| Snowflake | -- (micropartition 内置) | -- | 内置 | -- |
| BigQuery | 是（partition 级） | 是 | -- | 内置 |
| Redshift | -- | -- | -- | -- |
| Hive | 是 | 表级聚合 | -- | `ANALYZE TABLE t PARTITION (...) COMPUTE STATISTICS` |
| Spark SQL | 是 | -- | -- | `ANALYZE TABLE t PARTITION (...) COMPUTE STATISTICS` |
| Impala | 是 | 表级 | 是（INCREMENTAL） | `COMPUTE INCREMENTAL STATS t` |
| TiDB | 是（partition pruning 关键） | -- | 是 | `ANALYZE TABLE t PARTITION (p1)` |
| OceanBase | 是 | global stats（兼容 Oracle） | 是 | `DBMS_STATS` 兼容接口 |
| StarRocks | 是 | -- | -- | `ANALYZE TABLE t PARTITION p1` |
| Doris | 是 | -- | 是 | `ANALYZE TABLE t.p1` |
| Greenplum | 是 | 父表合并 | -- | 继承 PG |
| TimescaleDB | 是（hypertable chunk 级） | -- | -- | 继承 PG，按 chunk |
| Teradata | 是（PPI 分区级） | -- | -- | `COLLECT STATISTICS ... ON t PARTITION p` |
| Azure Synapse | 是 | -- | -- | -- |

## 关键引擎深度解析

### PostgreSQL：autovacuum analyze + default_statistics_target

PostgreSQL 的统计采集由两个独立机制协同工作：

1. **手动 ANALYZE**：用户主动触发
2. **autovacuum analyze**：后台守护进程根据"行变更比例"自动触发

#### 手动 ANALYZE

```sql
ANALYZE;                          -- 全库
ANALYZE orders;                   -- 单表
ANALYZE orders (customer_id);     -- 单列
ANALYZE VERBOSE orders;           -- 显示详细信息

-- 查看默认采样目标
SHOW default_statistics_target;   -- 默认 100

-- 修改全局采样目标
SET default_statistics_target = 500;

-- 修改单列采样目标（覆盖全局）
ALTER TABLE orders ALTER COLUMN customer_id SET STATISTICS 1000;
```

`default_statistics_target` 是 PostgreSQL 采集机制的核心参数：

- **默认值 100**
- **直方图桶数 = `default_statistics_target`**
- **MCV 列表最大长度 = `default_statistics_target`**
- **采样行数 = `300 * default_statistics_target` = 30000 行（默认）**
- **取值范围 1–10000**

注：完整的内部实现中，每个直方图桶由"边界点 + 1 个起始点"构成，因此 100 个桶对应 101 个 `histogram_bounds` 数组元素。

#### 采样算法：两阶段 Vitter 蓄水池

PostgreSQL 使用经典的两阶段采样：

1. **阶段 1：Vitter 算法 S（page-level）**：随机选择 `300 * statistics_target` 个数据页
2. **阶段 2：Vitter 算法 R（row-level）**：从选中的页中随机选取行

这种"块级 + 行级"两阶段采样在表大小未知时有较好的近似随机性，但对极度倾斜数据（极少数页包含大量重复值）可能有偏差。

#### autovacuum 触发逻辑

```
analyze_threshold = autovacuum_analyze_threshold +
                    autovacuum_analyze_scale_factor * reltuples

if (n_mod_since_analyze > analyze_threshold)
    trigger ANALYZE
```

默认参数：

- `autovacuum_analyze_threshold = 50`
- `autovacuum_analyze_scale_factor = 0.1`

含义：表行数变更（INSERT + UPDATE + DELETE）累计超过 `50 + 10% × N` 时，autovacuum 触发 ANALYZE。

对 100 万行的表：变更 100,050 行后触发。
对 10 亿行的表：变更 1,000,000,050 行后触发。

**关键问题**：大表的"10%"绝对值太大，可能导致统计长期严重过期。生产实践中应将大表的 scale_factor 调小：

```sql
ALTER TABLE big_table SET (autovacuum_analyze_scale_factor = 0.01);
ALTER TABLE big_table SET (autovacuum_analyze_threshold = 1000);
```

#### 分区表

PostgreSQL 13+ 对分区表的处理改进显著：

- PG 10–12：分区父表的统计需要手动触发（`ANALYZE parent`），autovacuum 只对叶子分区生效
- PG 13+：autovacuum 也维护分区父表统计
- PG 14+：分区表的扩展统计支持改善

```sql
-- 仅分析单个分区
ANALYZE orders_2025q1;

-- 分析整个分区表（包括所有分区和父表）
ANALYZE orders;
```

### Oracle：DBMS_STATS + AUTO_SAMPLE_SIZE 哈希采样

Oracle 是工业界对统计采集投入最深的厂商，其 `DBMS_STATS` 包是事实上的工业基准。

#### DBMS_STATS 包结构

```sql
-- 收集表统计
EXEC DBMS_STATS.GATHER_TABLE_STATS(
    ownname => 'SCOTT',
    tabname => 'ORDERS',
    estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
    method_opt => 'FOR ALL COLUMNS SIZE AUTO',
    granularity => 'AUTO',
    cascade => TRUE,                  -- 同时收集索引统计
    degree => DBMS_STATS.DEFAULT_DEGREE,
    no_invalidate => DBMS_STATS.AUTO_INVALIDATE
);

-- 收集 schema 内所有表
EXEC DBMS_STATS.GATHER_SCHEMA_STATS('SCOTT');

-- 收集整库
EXEC DBMS_STATS.GATHER_DATABASE_STATS();

-- 收集字典统计
EXEC DBMS_STATS.GATHER_DICTIONARY_STATS();

-- 收集固定对象（X$ 表）统计
EXEC DBMS_STATS.GATHER_FIXED_OBJECTS_STATS();
```

#### auto_stats_job：维护窗口内自动采集

Oracle 10g 引入 `GATHER_STATS_JOB`，11g 起改为 `auto_stats_task`，由 `DBMS_AUTO_TASK_ADMIN` 管理：

```sql
-- 默认维护窗口
-- 工作日: MON-FRI 22:00-02:00 (4 小时)
-- 周末:   SAT-SUN 06:00-02:00 (20 小时)

-- 查看自动任务状态
SELECT client_name, status FROM dba_autotask_client;

-- 自动统计任务的客户端名称是 'auto optimizer stats collection'

-- 启用 / 禁用
EXEC DBMS_AUTO_TASK_ADMIN.ENABLE(
    client_name => 'auto optimizer stats collection',
    operation => NULL,
    window_name => NULL
);

EXEC DBMS_AUTO_TASK_ADMIN.DISABLE(
    client_name => 'auto optimizer stats collection',
    operation => NULL,
    window_name => NULL
);
```

`auto_stats_task` 在维护窗口内对所有"stale"对象执行 ANALYZE。判定 stale 的标准：

- 表的 DML 行数（监控自 `dba_tab_modifications`）/ 总行数 ≥ 10%（默认 `STALE_PERCENT`）
- 该比例可按表配置：

```sql
EXEC DBMS_STATS.SET_TABLE_PREFS('SCOTT', 'ORDERS', 'STALE_PERCENT', '5');
```

#### ESTIMATE_PERCENT：从启发式到 AUTO_SAMPLE_SIZE

Oracle 11g（2007）引入 `AUTO_SAMPLE_SIZE`，是采集机制史上的关键节点：

**11g 之前**：
- 默认 `ESTIMATE_PERCENT` 是固定百分比（10g 默认 `DBMS_STATS.AUTO_SAMPLE_SIZE` 但实现是启发式）
- 用户必须手动权衡精度与速度
- 大表无法获得高精度统计

**11g 之后（默认）**：
- `AUTO_SAMPLE_SIZE` 使用基于哈希的近似算法
- 一次扫描全表，对每行计算 hash，仅保留若干唯一值估算 NDV
- 计算成本类似 10% 采样，但精度接近 100% 全扫描
- 这是 Oracle CBO 在 11g/12c 时代领先竞品的核心因素之一

```sql
-- 11g+ 推荐
EXEC DBMS_STATS.GATHER_TABLE_STATS(
    'SCOTT', 'ORDERS',
    estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE
);

-- 显式 100% 全扫描
EXEC DBMS_STATS.GATHER_TABLE_STATS(
    'SCOTT', 'ORDERS',
    estimate_percent => 100
);

-- 显式 10% 采样
EXEC DBMS_STATS.GATHER_TABLE_STATS(
    'SCOTT', 'ORDERS',
    estimate_percent => 10
);
```

#### 增量统计（Incremental Statistics, 11g+）

对于大型分区表，每次都重算全表统计代价过大。Oracle 11g 引入 incremental statistics：

```sql
-- 启用增量统计
EXEC DBMS_STATS.SET_TABLE_PREFS('SCOTT', 'ORDERS_FACT', 'INCREMENTAL', 'TRUE');
EXEC DBMS_STATS.SET_TABLE_PREFS('SCOTT', 'ORDERS_FACT', 'GRANULARITY', 'AUTO');

-- 之后只需采集变更分区的统计，全局统计自动从 partition synopsis 合并
EXEC DBMS_STATS.GATHER_TABLE_STATS(
    'SCOTT', 'ORDERS_FACT',
    partname => 'P_2025_03'
);
-- 自动合并所有分区 synopsis 生成全局统计，无需扫描其他分区
```

核心机制——**partition-level synopses**：每个分区维护一个 NDV 草图（基于 HyperLogLog 类的算法），新增 / 修改分区时仅重算该分区的 synopsis，全局 NDV 通过合并所有 synopsis 得到。这避免了"修改一个分区却必须重扫全表"的代价灾难。

### SQL Server：UPDATE STATISTICS + AUTO_UPDATE_STATISTICS

#### 命令语法

```sql
-- 单表全部统计
UPDATE STATISTICS dbo.Orders;

-- 单个统计对象
UPDATE STATISTICS dbo.Orders IX_Orders_CustomerID;

-- 全扫描（最高精度）
UPDATE STATISTICS dbo.Orders WITH FULLSCAN;

-- 显式采样
UPDATE STATISTICS dbo.Orders WITH SAMPLE 10 PERCENT;
UPDATE STATISTICS dbo.Orders WITH SAMPLE 1000000 ROWS;

-- 用上次的采样比例重收
UPDATE STATISTICS dbo.Orders WITH RESAMPLE;

-- 仅更新创建时分区
UPDATE STATISTICS dbo.Orders WITH FULLSCAN ON PARTITIONS(2025);
```

#### 阈值演变：20% 硬阈值 → SQRT(1000×N) 动态阈值

SQL Server 的 `AUTO_UPDATE_STATISTICS` 触发阈值经历了重大演进：

**SQL Server 2005–2012**：

```
触发阈值（rowmodctr）:
  小表（≤ 500 行）: 500 + 20% × N
  大表（> 500 行）: 500 + 20% × N
```

含义：当 `rowmodctr` 超过 `500 + 20% × N` 时，下次查询编译触发统计更新。

**问题**：1 亿行表需要 2000 万行变更才触发，统计长期严重过期。

**2008/2012 解决方案**：trace flag 2371

```sql
-- 启用 TF 2371: 大表使用动态阈值
DBCC TRACEON(2371, -1);
```

启用后，大表使用动态阈值 `SQRT(1000 × N)`：

```
N = 1,000:    阈值 ≈ 1000 行
N = 10,000:   阈值 ≈ 3162 行
N = 100,000:  阈值 ≈ 10000 行
N = 1,000,000: 阈值 ≈ 31623 行 (3.16%)
N = 10,000,000: 阈值 ≈ 100000 行 (1%)
N = 100,000,000: 阈值 ≈ 316228 行 (0.32%)
N = 1,000,000,000: 阈值 ≈ 1000000 行 (0.1%)
```

**SQL Server 2014（兼容级别 120+）**：默认启用 `SQRT(1000 × N)` 动态阈值，无需 TF 2371。

**SQL Server 2016+**：兼容级别 130+ 强制使用动态阈值。

这一改动是 SQL Server CBO 历史上最重要的"采集机制"改进，因为它直接解决了大表统计过期的问题。

#### 增量统计（2014+）

```sql
-- 创建表时启用 incremental
CREATE TABLE Orders (
    ...
) ON ps_orders_by_year(order_date);

CREATE STATISTICS stats_order_total ON Orders(order_total)
    WITH INCREMENTAL = ON;

-- 仅更新单个分区，全局统计自动合并
UPDATE STATISTICS Orders WITH RESAMPLE ON PARTITIONS(2025);
```

#### 异步采集

```sql
-- 启用异步统计更新（避免编译时阻塞）
ALTER DATABASE myDB SET AUTO_UPDATE_STATISTICS_ASYNC ON;
```

启用后，过期统计触发的更新放入后台队列，当前查询继续使用旧统计，下次查询使用新统计。代价：第一次查询计划可能仍然糟糕，但避免了编译时长时间阻塞。

### MySQL：innodb_stats_persistent（5.6.6+ 默认开启）

MySQL InnoDB 的统计采集在 5.6.6（2012）有质的飞跃：

**5.6.6 之前**：
- 仅 transient（瞬时）统计：每次 InnoDB 启动时基于采样页计算
- 表打开时随机选 8 个页（`innodb_stats_sample_pages`）
- 统计随机性大，跨重启不一致
- 优化器经常选错计划

**5.6.6 之后（默认）**：
- `innodb_stats_persistent = ON`（默认值改为 ON）
- 统计持久化到 `mysql.innodb_table_stats` / `mysql.innodb_index_stats`
- 默认采样 20 个页（`innodb_stats_persistent_sample_pages = 20`）
- 跨重启稳定

#### 命令与配置

```sql
-- 手动触发
ANALYZE TABLE orders;

-- 仅指定分区
ANALYZE TABLE orders PARTITION (p2025q1);

-- 直方图（8.0+）
ANALYZE TABLE orders UPDATE HISTOGRAM ON customer_id;
ANALYZE TABLE orders UPDATE HISTOGRAM ON customer_id WITH 32 BUCKETS;

-- 删除直方图
ANALYZE TABLE orders DROP HISTOGRAM ON customer_id;

-- 查看
SELECT * FROM mysql.innodb_table_stats WHERE table_name = 'orders';
SELECT * FROM mysql.innodb_index_stats WHERE table_name = 'orders';
SELECT * FROM information_schema.column_statistics
    WHERE table_name = 'orders';
```

#### 自动采集

```sql
-- 全局开关
SET GLOBAL innodb_stats_auto_recalc = ON;     -- 默认 ON

-- 表级开关（覆盖全局）
ALTER TABLE orders STATS_AUTO_RECALC = 0;     -- 关闭单表自动采集

-- 触发条件: 表 10% 行变更
-- 行为: 后台异步重算
```

#### 直方图（8.0.3+）

直方图需要**显式 ANALYZE**触发，**不会**自动维护：

```sql
-- 创建（一次性）
ANALYZE TABLE orders UPDATE HISTOGRAM ON status WITH 32 BUCKETS;

-- 数据变化后手动重算
ANALYZE TABLE orders UPDATE HISTOGRAM ON status;
```

桶数范围 1–1024，超过 NDV 时用 SINGLETON（频率直方图），否则用 EQUI-HEIGHT。

### DB2：RUNSTATS + Auto Runstats

#### 命令语法

```sql
-- 基本
RUNSTATS ON TABLE schema.orders;

-- 完整
RUNSTATS ON TABLE schema.orders
    ON ALL COLUMNS
    WITH DISTRIBUTION ON ALL COLUMNS NUM_QUANTILES 100
    AND INDEXES ALL
    SAMPLED DETAILED;

-- 列组（多列统计）
RUNSTATS ON TABLE schema.orders
    ON COLUMNS ((city, state, zip));

-- 采样
RUNSTATS ON TABLE schema.orders WITH SAMPLING 10;

-- 增量直方图（incremental quantiles）
RUNSTATS ON TABLE schema.orders
    WITH DISTRIBUTION DEFAULT NUM_QUANTILES 50;
```

#### Auto Runstats（LUW 9.5+）

DB2 LUW 9.5（2007）默认启用 `auto_runstats`，由后台健康度监控（HealthMon）评估表是否需要重收：

```sql
UPDATE DB CFG FOR mydb USING AUTO_MAINT ON;
UPDATE DB CFG FOR mydb USING AUTO_TBL_MAINT ON;
UPDATE DB CFG FOR mydb USING AUTO_RUNSTATS ON;

-- 增加更激进的统计 profile
UPDATE DB CFG FOR mydb USING AUTO_STATS_PROF ON;
UPDATE DB CFG FOR mydb USING AUTO_PROF_UPD ON;
```

DB2 的"Real-time Statistics"（10.5+）允许**编译时即时收集少量样本**，对从未 RUNSTATS 过的对象动态生成临时统计。

### Snowflake：micropartition 内置统计

Snowflake 的统计采集机制在云原生数据库中独树一帜：

- **没有显式 ANALYZE 命令**
- **没有可配置的采集任务**
- **统计在写入 micropartition 时同步生成**

每个 micropartition（约 16MB 压缩，50–500MB 解压）写入时记录：

- 行数、字节数
- 每列：min、max、NDV（HyperLogLog 草图）、null 计数
- 每列：MCV 列表（部分情况下）

这些元数据存储在 micropartition header，查询时通过 cloud services layer 读取，剪枝时无需扫描数据。

**关键设计哲学**：

- 用户完全无需思考统计维护
- 写入时的微小开销换取查询时零延迟
- 增量天然：每个新 micropartition 自带统计
- micropartition 不可变（COW），统计永远新鲜

代价：用户**无法**控制统计精度、无法手动 ANALYZE、出现统计倾斜也无解。这是 Snowflake "easy of use" 哲学的极致体现。

### BigQuery：column auto-stats

BigQuery 与 Snowflake 类似，统计完全后台维护：

- 写入时立即记录 column 级元数据（min/max/NDV/null）
- 后台 reorg 时合并、刷新统计
- 用户无显式 ANALYZE 命令
- 唯一可见接口是 `INFORMATION_SCHEMA` 视图

BigQuery 的统计粒度更细：每个 capacitor block 都有独立 footer 元数据。查询编译期通过元数据 metadata cache 完成大部分剪枝决策。

### CockroachDB：CREATE STATISTICS + 自动调度

CockroachDB（19.x+）的统计采集强调**自动化**与**MVCC 友好**：

```sql
-- 命名统计（手动）
CREATE STATISTICS my_stats FROM orders;

-- 仅特定列
CREATE STATISTICS stats_status ON status FROM orders;

-- 历史时间点（避免阻塞）
CREATE STATISTICS my_stats FROM orders AS OF SYSTEM TIME '-30s';

-- 查看
SHOW STATISTICS FOR TABLE orders;
```

#### 自动收集

```sql
-- 默认开启
SET CLUSTER SETTING sql.stats.automatic_collection.enabled = true;

-- 触发阈值: 20% 行变更
SHOW CLUSTER SETTING sql.stats.automatic_collection.fraction_stale_rows;
-- 默认 0.2

-- 最小阈值（小表也至少这么多变更才触发）
SHOW CLUSTER SETTING sql.stats.automatic_collection.min_stale_rows;
-- 默认 500
```

#### 采样算法

CockroachDB 默认采样 10000 行（`sql.stats.histogram_samples.count`），用 reservoir sampling 在分布式 KV 扫描中收集。

由于是分布式数据库，采集本身需要协调：

- 每个 range 各自采样
- 在 gateway node 合并
- 合并后写入 system.table_statistics

`AS OF SYSTEM TIME` 子句让采集发生在历史时间点，避免与活跃写入冲突，是分布式环境下的关键设计。

### TiDB：ANALYZE TABLE WITH X SAMPLES

TiDB 的统计采集经历了 v1（2017）→ v2（v5.1，2021）的重要迭代：

**Analyze v1**：
- 类似 PostgreSQL 的 Vitter 采样
- 默认 10000 行
- CMSketch（Count-Min Sketch）做高频值估算
- 在大表上 NDV 估算偏差大

**Analyze v2（默认 v5.1+）**：
- 默认采样 100000 行
- 改用 HLL（HyperLogLog）做 NDV 估算
- TopN 列表（默认 1024）独立于直方图存储
- 直方图边界基于 NDV-based bucket 选择

```sql
-- 全表自动选择 v1/v2
ANALYZE TABLE orders;

-- 显式控制采样行数
ANALYZE TABLE orders WITH 200000 SAMPLES;

-- TopN 列表大小
ANALYZE TABLE orders WITH 1024 TOPN;

-- 全表分析（昂贵）
ANALYZE TABLE orders WITH 1 BUCKETS;  -- 实际上没有 FULLSCAN 选项
```

#### 自动采集

```sql
-- 全局开关
SET GLOBAL tidb_enable_auto_analyze = ON;

-- 健康度阈值（行变更比例）
SET GLOBAL tidb_auto_analyze_ratio = 0.5;

-- 自动 analyze 时间窗口
SET GLOBAL tidb_auto_analyze_start_time = '01:00 +0800';
SET GLOBAL tidb_auto_analyze_end_time = '07:00 +0800';
```

TiDB 的"健康度（healthy）"机制：

```
healthy = 100 - (modify_count / row_count) * 100
当 healthy < (100 - tidb_auto_analyze_ratio * 100) 时触发
```

例如默认 `ratio = 0.5`：当变更行数超过总行数的 50%，healthy 降到 50 以下，触发自动 analyze。

#### Analyze 进度查看

```sql
-- 查看正在运行的 analyze 任务
SHOW ANALYZE STATUS;

-- 取消运行中的 analyze
KILL TIDB <connection_id>;
```

### 其他典型引擎

#### MariaDB

```sql
-- 持久化统计
ANALYZE TABLE orders PERSISTENT FOR ALL;

-- 仅特定列
ANALYZE TABLE orders PERSISTENT FOR COLUMNS (city) INDEXES();

-- engine-independent stats（独立于存储引擎）
SET GLOBAL use_stat_tables = PREFERABLY;

-- 直方图（10.0+）
ANALYZE TABLE orders PERSISTENT FOR COLUMNS (status) INDEXES();

-- 配置
SET histogram_size = 254;          -- 直方图桶数 (1-255)
SET histogram_type = DOUBLE_PREC_HB; -- 默认类型
SET analyze_sample_percentage = 10; -- 默认 100，改为 10 表示采样
```

#### Redshift

```sql
-- 自动采集（默认开启）
SHOW auto_analyze;

-- 阈值控制
ALTER TABLE orders SET TABLE PROPERTIES('analyze_threshold_percent' = '5');

-- 手动
ANALYZE orders;
ANALYZE orders PREDICATE COLUMNS;       -- 只分析 WHERE 中出现过的列
ANALYZE orders ALL COLUMNS;             -- 分析所有列

-- 查看哪些列需要 analyze
SELECT * FROM stv_tbl_perm WHERE name = 'orders';
```

#### Trino / Presto

```sql
-- Trino 完全手动
ANALYZE table_name;

-- 带选项
ANALYZE table_name WITH (
    partitions = ARRAY[ARRAY['2025-01-01']],
    columns = ARRAY['user_id', 'amount']
);

-- 查看统计
SHOW STATS FOR table_name;
```

Trino 的统计存储在 connector 元数据中（Hive metastore、Iceberg metadata）。**Trino 自身不采集任何统计**，全部依赖底层 connector。

#### Spark SQL

```sql
-- 表级
ANALYZE TABLE orders COMPUTE STATISTICS;

-- 分区
ANALYZE TABLE orders PARTITION(year=2025, month=1) COMPUTE STATISTICS;

-- 列级
ANALYZE TABLE orders COMPUTE STATISTICS FOR COLUMNS user_id, amount;

-- 全列
ANALYZE TABLE orders COMPUTE STATISTICS FOR ALL COLUMNS;

-- noscan 模式（仅基于 HDFS file size 估算行数）
ANALYZE TABLE orders COMPUTE STATISTICS NOSCAN;

-- 配置直方图
SET spark.sql.statistics.histogram.enabled = true;
SET spark.sql.statistics.histogram.numBins = 254;
```

Spark 的统计存储在 Hive metastore 或 Spark catalog。Spark 3.x 的 AQE（Adaptive Query Execution）可以**运行时**重新调整执行计划，部分弥补静态统计的缺陷。

#### Hive

```sql
-- 自动采集（默认 INSERT 时启用）
SET hive.stats.autogather = true;        -- 默认 true
SET hive.stats.fetch.column.stats = true;
SET hive.stats.column.autogather = true;

-- 手动表统计
ANALYZE TABLE orders COMPUTE STATISTICS;

-- 列统计
ANALYZE TABLE orders COMPUTE STATISTICS FOR COLUMNS;

-- 分区
ANALYZE TABLE orders PARTITION(year=2025) COMPUTE STATISTICS;
```

#### Impala

```sql
-- 全表
COMPUTE STATS orders;

-- 列
COMPUTE STATS orders (user_id, amount);

-- 增量（4.0+）
COMPUTE INCREMENTAL STATS orders;

-- 单个分区增量
COMPUTE INCREMENTAL STATS orders PARTITION(year=2025);

-- 采样（4.0+）
COMPUTE STATS orders TABLESAMPLE SYSTEM(10);
```

`COMPUTE INCREMENTAL STATS` 是 Impala 的关键采集机制，它存储 partition synopsis 在 HMS 中，仅重算变化分区。

#### StarRocks

```sql
-- 自动采集（默认开启）
ADMIN SET FRONTEND CONFIG ('enable_statistic_collect' = 'true');

-- 手动
ANALYZE TABLE orders;
ANALYZE TABLE orders (col1, col2);
ANALYZE FULL TABLE orders;        -- 全扫描

-- 同步 / 异步
ANALYZE TABLE orders WITH SYNC MODE;
ANALYZE TABLE orders WITH ASYNC MODE;

-- 配置
ADMIN SET FRONTEND CONFIG ('statistic_sample_collect_rows' = '500000');
```

StarRocks 默认采样 200000 行，可配。自动收集时检查表的"健康度"决定是否触发。

#### Doris

```sql
-- 手动
ANALYZE TABLE orders;
ANALYZE TABLE orders (col1, col2);

-- 增量（2.0+）
ANALYZE TABLE orders PARTITION(p202503) WITH INCREMENTAL;

-- 采样
ANALYZE TABLE orders WITH SAMPLE PERCENT 10;
ANALYZE TABLE orders WITH SAMPLE ROWS 1000000;

-- 同步
ANALYZE TABLE orders WITH SYNC;

-- 自动开关
SET enable_auto_analyze = true;
```

#### Vertica

```sql
-- 显式
SELECT ANALYZE_STATISTICS('schema.orders');

-- 仅特定列
SELECT ANALYZE_STATISTICS('schema.orders', 'col1, col2');

-- 采样比例
SELECT ANALYZE_STATISTICS('schema.orders', 'col1', 50);  -- 50% 采样
```

#### SAP HANA

```sql
-- 创建
CREATE STATISTICS sales_stats ON sales(amount, region) TYPE HISTOGRAM;

-- 刷新
REFRESH STATISTICS sales_stats;

-- 自动维护
ALTER SYSTEM ALTER CONFIGURATION ('indexserver.ini', 'SYSTEM') SET
  ('optimizer', 'data_statistics_auto_create') = 'true';
```

## Oracle AUTO_SAMPLE_SIZE 深度剖析

Oracle 11g 引入的 `AUTO_SAMPLE_SIZE` 是采集机制史上的一项里程碑。理解它的工作原理对所有数据库优化器开发者都有借鉴意义。

### 11g 之前的痛点

`ESTIMATE_PERCENT` 必须在精度与速度之间权衡：

```
100% 全扫描:
  + 精度最高
  - 时间正比于表大小，1TB 表可能数小时

10% 采样:
  + 时间约 10x 加速
  - NDV 估算精度严重下降（小样本上的 distinct count 偏差最大）
  - MCV 列表可能错过真正的高频值

1% 采样:
  + 时间约 100x 加速
  - NDV 几乎无意义
  - 倾斜数据上完全不准
```

NDV 是统计信息中最难估算的指标，因为采样大小与精度并非线性关系——小样本上的 distinct count 系统性低估真实 NDV。学术上有多种 NDV 估算器（Goodman、Chao84、Schlosser），但都需要较大样本。

### AUTO_SAMPLE_SIZE 的核心思想

11g 起，Oracle 在 `AUTO_SAMPLE_SIZE` 模式下采用一个巧妙的算法：

1. **一次扫描全表**（实际是顺序扫描，IO 顺序）
2. **对每一行的每一列计算 hash**
3. **用 hash 值做 NDV 草图（类似 HyperLogLog 但 Oracle 自研）**
4. **结合表的近似行数估算 NDV**

关键洞察：

- **不是采样**，而是**全扫描 + 流式估算**
- 扫描 IO 与 100% 全扫描相当（顺序扫描）
- CPU 略高（每行 hash 计算），但远低于"100% 模式"的"实际 distinct count"开销（后者需要排序或 hash 聚合全部数据）
- NDV 精度接近 100% 模式

实测数据（Oracle 文档与社区）：
- 速度：与 10% 采样相当
- NDV 精度：误差通常 < 1%（vs 10% 采样的 5–30% 误差）
- MCV：精度接近全扫描

### 实现细节

Oracle 的 `AUTO_SAMPLE_SIZE` 实现使用：

- **顺序全表扫描**：避免随机 IO 开销
- **混合 NDV 算法**：结合 hash sketch 与近似行计数
- **直方图采样自适应**：直方图本身仍可能用部分样本，但 NDV 用全数据

### 对其他引擎的影响

`AUTO_SAMPLE_SIZE` 的成功推动了多个 NDV 估算革新：

- **PostgreSQL**：仍使用 Vitter 采样 + Goodman 估算器，NDV 精度逊于 Oracle
- **TiDB v5.1+**：HLL 算法部分弥补
- **Snowflake**：micropartition 级别天然 HLL
- **BigQuery**：column auto-stats 用类似 HLL 算法
- **DB2**：DETAILED 模式下使用类 sketch 算法

未来趋势：所有现代数据库都在向"采样+sketch"的混合模式靠拢，纯随机采样在大表上已被淘汰。

## SQL Server 2014 SQRT(1000×N) 触发阈值

### 旧阈值的问题

SQL Server 2005–2012 的 `AUTO_UPDATE_STATISTICS` 触发阈值：

```
trigger_threshold = 500 + 0.20 × N   (N >= 500)
```

对小表（N < 500）：固定 500。
对大表：始终是表行数的 20%。

具体例子：

| 表行数 N | 触发阈值 | 阈值占比 |
|---------|---------|---------|
| 1,000 | 700 | 70.0% |
| 10,000 | 2500 | 25.0% |
| 100,000 | 20500 | 20.5% |
| 1,000,000 | 200500 | 20.05% |
| 100,000,000 | 20,000,500 | 20.0% |
| 1,000,000,000 | 200,000,500 | 20.0% |

**痛点**：1 亿行的表需要 2000 万行变更才触发统计更新。在频繁更新的 OLTP 表上，这意味着统计可能数月不更新；在 ETL 批量装载的 OLAP 表上，每天追加几百万行也无法触发。

### TF 2371 与新算法

2008 SP4 引入 trace flag 2371，启用动态阈值：

```
trigger_threshold = SQRT(1000 × N)   (N > 25000)
```

具体例子：

| 表行数 N | 旧阈值 (20%) | 新阈值 SQRT(1000N) | 新阈值占比 |
|---------|--------------|--------------------|-----------|
| 25,000 | 5,500 | 5,000 | 20% |
| 100,000 | 20,500 | 10,000 | 10% |
| 1,000,000 | 200,500 | 31,623 | 3.16% |
| 10,000,000 | 2,000,500 | 100,000 | 1.00% |
| 100,000,000 | 20,000,500 | 316,228 | 0.32% |
| 1,000,000,000 | 200,000,500 | 1,000,000 | 0.10% |

新阈值的关键性质：

- **小表保持 20% 阈值不变**（N < 25000）
- **大表阈值占比按 SQRT 反比下降**
- **N=10亿时仅需变更 100 万行（0.1%）触发**

### 2014 默认启用

SQL Server 2014（兼容级别 120）默认启用动态阈值，无需 TF 2371：

```sql
-- 检查兼容级别
SELECT name, compatibility_level FROM sys.databases;

-- 升级兼容级别
ALTER DATABASE myDB SET COMPATIBILITY_LEVEL = 120;
```

注意：`compatibility_level >= 130`（2016+）时强制使用动态阈值，无法回退。

### 动态阈值的数学合理性

为什么是 `SQRT(1000 × N)` 而不是 `0.01 × N` 或其他？答案与采样统计的方差性质有关：

- 在大表上，**采样估计的方差与样本数的平方根成反比**
- 如果统计本身是在 `K = SQRT(C × N)` 样本上算的，那么变更超过 K 行才有可能在采样中显著改变估计值
- 选择 1000 是经验常数，平衡触发频率和误差容忍度

这个设计理念后来影响了 PostgreSQL 14+ 对 autovacuum scale_factor 的"insert-only" 处理，以及 Oracle 11g+ 对 STALE_PERCENT 的可配置化。

### 配合 AUTO_UPDATE_STATISTICS_ASYNC

为避免编译时阻塞，应同时启用异步更新：

```sql
ALTER DATABASE myDB SET AUTO_UPDATE_STATISTICS ON;
ALTER DATABASE myDB SET AUTO_UPDATE_STATISTICS_ASYNC ON;
```

效果：触发条件成立时，编译继续用旧统计，更新放入后台 worker 队列。代价：第一次查询计划可能仍旧；优势：避免数百毫秒到数秒的编译期阻塞。

## 关键发现

经过对 45+ 数据库的横向对比，统计信息采集策略呈现以下显著模式：

1. **SQL 标准完全缺席**。ISO/IEC 9075 没有规定 ANALYZE 语法，没有规定采样算法，没有规定触发机制。这意味着任何涉及统计采集的脚本都不可移植，DBA 必须为每个引擎单独学习运维节奏。

2. **自动采集已成为主流默认**。45+ 引擎中约 28 个默认开启自动采集（autovacuum、auto_runstats、AUTO_UPDATE_STATISTICS 等）。这是过去 15 年最显著的变化——2005 年以前几乎所有数据库都需要 DBA 手动 ANALYZE。

3. **触发机制有四大流派**：
   - **行变更比例**（PostgreSQL/MySQL/CockroachDB/TiDB）：阈值简单，但大表"10% 绝对值过大"
   - **维护窗口**（Oracle）：与业务低峰对齐，但窗口外的过期严重
   - **查询编译时按需触发**（SQL Server）：精确但增加编译延迟
   - **写入时同步**（Snowflake/BigQuery/Hive）：天然增量但运行时开销

4. **Oracle AUTO_SAMPLE_SIZE 是采集机制史的分水岭**（11g，2007）。哈希草图 + 全扫描的组合让 NDV 估算精度从"10% 采样的 ±30%"提升到"接近 100% 全扫描"，同时速度只比 10% 采样略慢。其他引擎用了 5–10 年才陆续追赶（HLL 算法在 TiDB v5.1、Snowflake、BigQuery 中普及）。

5. **SQL Server 2014 的 SQRT(1000×N) 阈值是另一个里程碑**。从"硬编码 20%"到"动态平方根"的改变直接解决了大表统计长期过期的问题。1 亿行表的触发阈值从 2000 万行降到 31.6 万行（0.32%），是数量级的改进。

6. **PostgreSQL 的 default_statistics_target = 100 是开源世界的事实标准**。这一参数同时控制 MCV 长度和直方图桶数，间接控制采样行数（×300）。生产实践常将其调高到 500–2000，特别是大表的关键列。

7. **MySQL InnoDB 持久化统计（5.6.6, 2012）是 MySQL 历史上最重要的优化器改进之一**。从此 MySQL 优化器有了稳定的统计基础，跨重启不再失效。直方图（8.0.3+）虽然到来较晚，但补齐了关键短板。

8. **增量统计是大表的唯一可持续方案**。Oracle 11g 引入的 partition synopsis + global stats 合并机制是行业开创性设计。SQL Server 2014、Impala、OceanBase、Doris 等陆续跟进。增量统计避免了"修改一个分区却需要扫全表"的代价灾难。

9. **MPP / OLAP 引擎自动采集滞后**。Trino、Presto、Spark SQL、Vertica、Teradata、Impala 等仍依赖手动 ANALYZE。原因：这些系统通常依赖底层数据 lake（Hive metastore、Iceberg）的元数据，自动机制需要跨系统协调。代价：DBA 必须在 ETL pipeline 中显式调度 ANALYZE。

10. **云原生服务彻底屏蔽采集复杂度**。Snowflake、BigQuery、Spanner、Firebolt 用户**完全没有** ANALYZE 命令，统计在写入时同步生成。这是云原生数据库的核心卖点之一——把"统计维护"这种历史负担彻底从用户侧移除。代价：用户失去对统计精度的控制权。

11. **采样行数的设定有两条路**：
    - **按表大小固定百分比**（Oracle ESTIMATE_PERCENT、Vertica PERCENT）：适应大小表，但小表过采样
    - **固定行数**（PostgreSQL 30000、CockroachDB 10000、TiDB 100000、StarRocks 200000）：开销可预测，但极大表精度可能不足

12. **直方图的采集独立于基础统计**。MySQL 直方图必须显式 ANALYZE TABLE ... UPDATE HISTOGRAM；PostgreSQL 直方图是 ANALYZE 的副产品；Oracle method_opt 可独立控制。这是因为直方图的代价远高于 NDV/min/max，需要单独管理。

13. **异步统计更新缓解编译阻塞**。SQL Server `AUTO_UPDATE_STATISTICS_ASYNC`、Oracle `AUTO` 模式、CockroachDB `AS OF SYSTEM TIME` 都试图把"长时间统计采集"从查询关键路径上移除。代价：第一次查询可能用旧统计。

14. **分区级统计是大数据时代的必需**。45+ 引擎中约 18 个支持分区级统计。Oracle 的"global stats from partition synopses"、SQL Server 的 `WITH INCREMENTAL = ON`、Impala 的 `COMPUTE INCREMENTAL STATS` 是三种最成熟的实现。

15. **触发阈值的 default 设定决定了引擎的"开箱即用"质量**。PostgreSQL 默认 10% 在大表上偏松；SQL Server 2014+ 的 SQRT 算法在大小表上都合理；Oracle 默认 10% 配合维护窗口在 OLTP 上工作良好。这些 default 值的选择反映了厂商对典型工作负载的理解。

16. **采集是优化器质量的"看不见的战场"**。再完美的 CBO 算法、再精巧的直方图、再先进的扩展统计，如果统计本身是过期的或采样不当导致的偏差大，所有这些都白费。Oracle、SQL Server 在采集机制上的工程积累（AUTO_SAMPLE_SIZE、SQRT 阈值、增量统计），是它们 CBO 在生产环境中持续领先的核心原因——而这些往往是用户和评测者最容易忽视的部分。

17. **采集机制的演进比 SQL 标准快得多**。PG autovacuum（2005）、MySQL persistent stats（2012）、SQL Server SQRT 阈值（2014）、TiDB analyze v2（2021）、Doris incremental（2023）——每个引擎都在持续改进采集机制。可以预见，未来 5 年的差异化竞争将更多发生在采集与维护层面，而非"什么样的直方图"。

## 参考资料

- PostgreSQL: [ANALYZE](https://www.postgresql.org/docs/current/sql-analyze.html)
- PostgreSQL: [The Statistics Collector](https://www.postgresql.org/docs/current/monitoring-stats.html)
- PostgreSQL: [Autovacuum Daemon](https://www.postgresql.org/docs/current/routine-vacuuming.html#AUTOVACUUM)
- PostgreSQL: [Planner Statistics](https://www.postgresql.org/docs/current/planner-stats.html)
- Oracle: [DBMS_STATS Package](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_STATS.html)
- Oracle: [Automatic Optimizer Statistics Collection](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/optimizer-statistics-concepts.html)
- Oracle: [Incremental Statistics](https://blogs.oracle.com/optimizer/incremental-statistics-maintenance-what-statistics-will-be-gathered-after-dml-occurs-on-the-table)
- Oracle: [AUTO_SAMPLE_SIZE Algorithm](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/optimizer-statistics-concepts.html#GUID-CFCBF8B2-04C3-4B30-9354-CC9CE1B95D2A)
- SQL Server: [UPDATE STATISTICS](https://learn.microsoft.com/en-us/sql/t-sql/statements/update-statistics-transact-sql)
- SQL Server: [Statistics](https://learn.microsoft.com/en-us/sql/relational-databases/statistics/statistics)
- SQL Server: [Trace Flag 2371](https://support.microsoft.com/en-us/topic/kb2754171-controlling-autostat-auto-update-statistics-behavior-in-sql-server)
- MySQL: [InnoDB Persistent Stats](https://dev.mysql.com/doc/refman/8.0/en/innodb-persistent-stats.html)
- MySQL: [ANALYZE TABLE](https://dev.mysql.com/doc/refman/8.0/en/analyze-table.html)
- MySQL: [Histogram Statistics](https://dev.mysql.com/doc/refman/8.0/en/optimizer-statistics.html)
- DB2 LUW: [RUNSTATS Command](https://www.ibm.com/docs/en/db2/11.5?topic=commands-runstats)
- DB2 LUW: [Automatic Statistics Collection](https://www.ibm.com/docs/en/db2/11.5?topic=collection-automatic-statistics)
- Snowflake: [Micro-partitions and Data Clustering](https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions)
- BigQuery: [Information Schema Column Stats](https://cloud.google.com/bigquery/docs/information-schema-table-storage)
- Redshift: [ANALYZE](https://docs.aws.amazon.com/redshift/latest/dg/r_ANALYZE.html)
- CockroachDB: [Create Statistics](https://www.cockroachlabs.com/docs/stable/create-statistics.html)
- TiDB: [Introduction to Statistics](https://docs.pingcap.com/tidb/stable/statistics)
- TiDB: [Statistics v2](https://docs.pingcap.com/tidb/stable/statistics#collect-statistics)
- Trino: [ANALYZE](https://trino.io/docs/current/sql/analyze.html)
- Spark SQL: [ANALYZE TABLE](https://spark.apache.org/docs/latest/sql-ref-syntax-aux-analyze-table.html)
- Hive: [Statistics](https://cwiki.apache.org/confluence/display/Hive/StatsDev)
- Impala: [COMPUTE STATS](https://impala.apache.org/docs/build/html/topics/impala_compute_stats.html)
- Teradata: [COLLECT STATISTICS](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Data-Definition-Language-Syntax-and-Examples)
- Vertica: [ANALYZE_STATISTICS](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/VerticaFunctions/ANALYZE_STATISTICS.htm)
- StarRocks: [Gather Statistics](https://docs.starrocks.io/docs/using_starrocks/Cost_based_optimizer/)
- Doris: [Statistics](https://doris.apache.org/docs/query-acceleration/statistics)
- SAP HANA: [Data Statistics](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20d8c17575191014b98fa76b9eada7b7.html)
- Goodman, L. A. "On the Estimation of the Number of Classes in a Population" (1949) — NDV 估算的开山之作
- Chao, A. "Estimating the Population Size for Capture-Recapture Data with Unequal Catchability" (1987) — Chao 估算器
- Schlosser, A. et al. "Sampling-Based Estimation of the Number of Distinct Values of an Attribute" (1995) — 数据库采样估算综述
