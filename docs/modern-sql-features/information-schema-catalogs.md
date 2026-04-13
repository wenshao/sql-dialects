# 系统目录与信息模式 (System Catalogs and Information Schema)

每一个数据库都需要回答"我有哪些表？"、"这一列是什么类型？"、"这个约束指向谁？"这类自省 (introspection) 问题。然而，从 SQLite 的 `sqlite_master` 单表，到 Oracle 的三层 `USER_/ALL_/DBA_` 体系，再到 BigQuery 的按数据集分区的 `INFORMATION_SCHEMA`，元数据访问方式的差异之大几乎无法想象。SQL:1992 标准早在三十多年前就引入了 `INFORMATION_SCHEMA`，试图用一组与具体存储无关的视图统一这一切，但直到今天，仍有像 Oracle 这样的核心引擎完全不实现它。理解每个引擎的元数据模型，是写出可移植的迁移工具、ORM、BI 连接器、Schema 比较器的前提。

## SQL 标准定义

`INFORMATION_SCHEMA` 在 SQL:1992 (ISO/IEC 9075-1992) 中作为强制要求引入，目的是为应用提供一个**与实现无关**的元数据访问层。SQL:1999 和 SQL:2003 在此基础上扩展了大量新视图（涵盖触发器、UDT、SQL/MED 外部数据等）。标准要求每个 catalog（数据库）下都存在一个名为 `INFORMATION_SCHEMA` 的 schema，其中包含一系列只读视图，所有视图的列名、列序、语义都由标准强制规定。

### 核心视图清单（SQL:2003 摘要）

| 视图 | 用途 | 引入版本 |
|------|------|---------|
| `SCHEMATA` | 当前 catalog 内可见的 schema 列表 | SQL:1992 |
| `TABLES` | 表、视图、临时表 | SQL:1992 |
| `COLUMNS` | 表/视图的列定义、数据类型、可空性、默认值 | SQL:1992 |
| `VIEWS` | 视图定义（含视图正文 SQL） | SQL:1992 |
| `TABLE_CONSTRAINTS` | 表级约束（PRIMARY KEY/UNIQUE/CHECK/FOREIGN KEY） | SQL:1992 |
| `KEY_COLUMN_USAGE` | 主键、唯一键、外键所涉及的列 | SQL:1992 |
| `REFERENTIAL_CONSTRAINTS` | 外键的引用动作（CASCADE/SET NULL...） | SQL:1992 |
| `CHECK_CONSTRAINTS` | CHECK 约束的表达式 | SQL:1992 |
| `ROUTINES` | 存储过程和函数 | SQL:1999 |
| `PARAMETERS` | 例程的参数列表 | SQL:1999 |
| `TRIGGERS` | 触发器定义 | SQL:1999 |
| `DOMAINS` | 用户自定义域 | SQL:1992 |
| `USER_DEFINED_TYPES` | UDT（结构类型、distinct 类型） | SQL:1999 |
| `TABLE_PRIVILEGES` | 表级权限授予 | SQL:1992 |
| `COLUMN_PRIVILEGES` | 列级权限授予 | SQL:1992 |
| `USAGE_PRIVILEGES` | 对域、字符集、序列等对象的 USAGE 权限 | SQL:1992 |
| `ROLE_TABLE_GRANTS` | 通过角色授予的表权限 | SQL:1999 |
| `ROUTINE_PRIVILEGES` | 例程的 EXECUTE 权限 | SQL:1999 |

标准视图的关键特点：

1. **大写命名**：`INFORMATION_SCHEMA` 和所有视图名一律使用大写，便于跨引擎引用。
2. **三段式命名**：标准列 `TABLE_CATALOG`、`TABLE_SCHEMA`、`TABLE_NAME` 形成完整定位。
3. **行级权限过滤**：用户只能看到自己有权访问的对象（基于 ISO 定义的 `_USABLE_` 视图过滤规则）。
4. **只读**：`INFORMATION_SCHEMA` 不允许 INSERT/UPDATE/DELETE，DDL 才是修改元数据的唯一途径。

## 支持矩阵

下表覆盖 49 个引擎，列出标准视图和原生目录（native catalog）两种访问方式的支持情况。"是"表示完全实现，"部分"表示存在但缺列或非标准，"--"表示不支持。

### INFORMATION_SCHEMA.TABLES / COLUMNS / VIEWS / SCHEMATA 基础视图

| 引擎 | TABLES | COLUMNS | VIEWS | SCHEMATA | 大小写 | 备注 |
|------|--------|---------|-------|----------|--------|------|
| PostgreSQL | 是 | 是 | 是 | 是 | 大写或小写均可 | 与 pg_catalog 共存 |
| MySQL | 是 | 是 | 是 | 是 | Linux 不区分 | 增加大量私有列 |
| MariaDB | 是 | 是 | 是 | 是 | Linux 不区分 | 兼容 MySQL |
| SQLite | -- | -- | -- | -- | -- | 仅 sqlite_schema |
| Oracle | 23ai+ | 23ai+ | 23ai+ | -- | 大写 | 23ai (2024 May) 引入基本 INFORMATION_SCHEMA 视图 (TABLES/COLUMNS/VIEWS)；历史上以 USER_/ALL_/DBA_ 为主 |
| SQL Server | 是 | 是 | 是 | 是 (SCHEMATA) | 大小写敏感取决于排序规则 | 与 sys.* 共存，部分列缺失 |
| DB2 (LUW) | 是 | 是 | 是 | 是 | 大写 | SYSCAT 是主目录 |
| Snowflake | 是 | 是 | 是 | 是 | 大写 | 每库独立 |
| BigQuery | 是 | 是 | 是 | 是 | 大写区域限定 | 每数据集独立 |
| Redshift | 是 | 是 | 是 | 是 | 兼容 PG | 与 PG_/SVV_ 并存 |
| DuckDB | 是 | 是 | 是 | 是 | 不区分 | + duckdb_tables() |
| ClickHouse | 是 (20.x+) | 是 | 是 | 是 | 区分 | + system.tables |
| Trino | 是 | 是 | 是 | 是 | 不区分 | 跨连接器统一 |
| Presto | 是 | 是 | 是 | 是 | 不区分 | 同 Trino |
| Spark SQL | 部分 | 部分 | 部分 | 部分 | 不区分 | Spark 3.4+ 才有 |
| Hive | -- | -- | -- | -- | -- | DESCRIBE/SHOW 为主 |
| Flink SQL | -- | -- | -- | -- | -- | Catalog API 替代 |
| Databricks | 是 | 是 | 是 | 是 | 不区分 | Unity Catalog 提供 |
| Teradata | 部分 | 部分 | 部分 | 部分 | 大小写敏感 | DBC.* 是主目录 |
| Greenplum | 是 | 是 | 是 | 是 | 兼容 PG | 继承 PostgreSQL |
| CockroachDB | 是 | 是 | 是 | 是 | 不区分 | + crdb_internal |
| TiDB | 是 | 是 | 是 | 是 | 不区分 | 兼容 MySQL |
| OceanBase | 是 | 是 | 是 | 是 | 模式相关 | MySQL/Oracle 双模式 |
| YugabyteDB | 是 | 是 | 是 | 是 | 兼容 PG | 继承 PG |
| SingleStore | 是 | 是 | 是 | 是 | 不区分 | 兼容 MySQL |
| Vertica | 是 | 是 | 是 | 是 | 大小写敏感 | + V_CATALOG |
| Impala | -- | -- | -- | -- | -- | DESCRIBE/SHOW 为主 |
| StarRocks | 是 | 是 | 是 | 是 | 不区分 | 兼容 MySQL |
| Doris | 是 | 是 | 是 | 是 | 不区分 | 兼容 MySQL |
| MonetDB | 是 | 是 | 是 | 是 | 大小写敏感 | + sys.* |
| CrateDB | 是 | 是 | 是 | 是 | 大小写敏感 | sys.* 提供集群信息 |
| TimescaleDB | 是 | 是 | 是 | 是 | 兼容 PG | 继承 PG |
| QuestDB | 部分 | 部分 | -- | -- | 大小写敏感 | tables() 函数为主 |
| Exasol | 是 | 是 | 是 | 是 | 大写 | 同时提供 EXA_*/SYS |
| SAP HANA | -- | -- | -- | -- | -- | SYS/PUBLIC.M_* 替代 |
| Informix | -- | -- | -- | -- | -- | systables/syscolumns |
| Firebird | -- | -- | -- | -- | -- | RDB$* 系统表 |
| H2 | 是 | 是 | 是 | 是 | 不区分 | 标准化最完整的嵌入库 |
| HSQLDB | 是 | 是 | 是 | 是 | 不区分 | INFORMATION_SCHEMA 完整 |
| Derby | 是 | 是 | 是 | 是 | 不区分 | 部分列限制 |
| Amazon Athena | 是 | 是 | 是 | 是 | 不区分 | 继承 Trino |
| Azure Synapse | 是 | 是 | 是 | 是 | 排序规则相关 | 与 sys.* 并存 |
| Google Spanner | 是 | 是 | 是 | 是 | 大小写敏感 | + SPANNER_SYS |
| Materialize | 是 | 是 | 是 | 是 | 不区分 | + mz_catalog |
| RisingWave | 是 | 是 | 是 | 是 | 不区分 | + rw_catalog |
| InfluxDB (IOx SQL) | 是 | 是 | -- | 是 | 不区分 | DataFusion 衍生 |
| Databend | 是 | 是 | 是 | 是 | 不区分 | + system.* |
| Yellowbrick | 是 | 是 | 是 | 是 | 兼容 PG | 继承 PG |
| Firebolt | 是 | 是 | 是 | 是 | 不区分 | 标准化优先 |

> 共约 38 个引擎实现了 `INFORMATION_SCHEMA.TABLES/COLUMNS`，约 11 个完全不实现（Oracle、SQLite、Hive、Impala、Flink、Firebird、Informix、SAP HANA、Teradata 限于部分、QuestDB 限于部分等）。

### INFORMATION_SCHEMA.KEY_COLUMN_USAGE / TABLE_CONSTRAINTS

约束元数据是 ORM 工具最依赖的视图。

| 引擎 | KEY_COLUMN_USAGE | TABLE_CONSTRAINTS | REFERENTIAL_CONSTRAINTS | CHECK_CONSTRAINTS |
|------|------------------|-------------------|------------------------|------------------|
| PostgreSQL | 是 | 是 | 是 | 是 |
| MySQL | 是 | 是 | 是 | 8.0.16+ |
| MariaDB | 是 | 是 | 是 | 10.2.22+ |
| SQLite | -- | -- | -- | -- |
| Oracle | -- | -- | -- | -- |
| SQL Server | 是 | 是 | 是 | 是 |
| DB2 | 是 | 是 | 是 | 是 |
| Snowflake | 是 | 是 | 是 | 是（仅信息性） |
| BigQuery | 是 | 是 | 是 | 是（仅信息性） |
| Redshift | 是 | 是 | 是 | 是 |
| DuckDB | 是 | 是 | 是 | 是 |
| ClickHouse | -- | -- | -- | -- |
| Trino | 部分 | 部分 | -- | -- |
| Presto | 部分 | 部分 | -- | -- |
| Spark SQL | -- | -- | -- | -- |
| Hive | -- | -- | -- | -- |
| Flink SQL | -- | -- | -- | -- |
| Databricks | 是 | 是 | 是 | 是 |
| Teradata | -- | -- | -- | -- |
| Greenplum | 是 | 是 | 是 | 是 |
| CockroachDB | 是 | 是 | 是 | 是 |
| TiDB | 是 | 是 | 是 | -- |
| OceanBase | 是 | 是 | 是 | 部分 |
| YugabyteDB | 是 | 是 | 是 | 是 |
| SingleStore | 是 | 是 | 是 | -- |
| Vertica | 是 | 是 | 是 | -- |
| Impala | -- | -- | -- | -- |
| StarRocks | 是 | 是 | -- | -- |
| Doris | 是 | 是 | -- | -- |
| MonetDB | 是 | 是 | 是 | 是 |
| CrateDB | 是 | 是 | -- | -- |
| TimescaleDB | 是 | 是 | 是 | 是 |
| QuestDB | -- | -- | -- | -- |
| Exasol | 是 | 是 | 是 | -- |
| SAP HANA | -- | -- | -- | -- |
| Informix | -- | -- | -- | -- |
| Firebird | -- | -- | -- | -- |
| H2 | 是 | 是 | 是 | 是 |
| HSQLDB | 是 | 是 | 是 | 是 |
| Derby | 是 | 是 | 是 | 是 |
| Athena | -- | -- | -- | -- |
| Synapse | 是 | 是 | 是 | 是 |
| Spanner | 是 | 是 | 是 | 是 |
| Materialize | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- |
| Databend | -- | -- | -- | -- |
| Yellowbrick | 是 | 是 | 是 | 是 |
| Firebolt | -- | -- | -- | -- |

> 注意：很多 OLAP/列存引擎（ClickHouse、Spark、Hive、Impala、StarRocks 部分列、Athena、Databend、Firebolt）完全不维护外键和 CHECK 约束的元数据，因为它们本身就不强制这些约束。Snowflake/BigQuery/Databricks 虽然提供约束视图，但约束本身仅作为优化器提示（informational only），并不强制。

### INFORMATION_SCHEMA.ROUTINES / PARAMETERS

| 引擎 | ROUTINES | PARAMETERS | TRIGGERS | 备注 |
|------|----------|------------|----------|------|
| PostgreSQL | 是 | 是 | 是 | 含函数、过程 |
| MySQL | 是 | 是 | 是 | 5.0+ |
| MariaDB | 是 | 是 | 是 | -- |
| SQLite | -- | -- | -- | 不支持存储过程 |
| Oracle | -- | -- | -- | DBA_PROCEDURES 替代 |
| SQL Server | 是 | 是 | 是 | -- |
| DB2 | 是 | 是 | 是 | -- |
| Snowflake | 是 | 是 | -- | 无触发器概念 |
| BigQuery | 是 | 是 | -- | 含 UDF/SP |
| Redshift | 是 | 是 | -- | -- |
| DuckDB | 是 | 是 | -- | -- |
| ClickHouse | -- | -- | -- | -- |
| Trino | -- | -- | -- | -- |
| Spark SQL | -- | -- | -- | -- |
| Hive | -- | -- | -- | -- |
| Flink SQL | -- | -- | -- | -- |
| Databricks | 是 | 是 | -- | -- |
| Teradata | 部分 | 部分 | 部分 | DBC.* 主导 |
| Greenplum | 是 | 是 | 是 | -- |
| CockroachDB | 是 | 是 | -- | -- |
| TiDB | 是 | 是 | 是 | -- |
| OceanBase | 是 | 是 | 是 | -- |
| YugabyteDB | 是 | 是 | 是 | -- |
| SingleStore | 是 | 是 | -- | -- |
| Vertica | 是 | 是 | -- | -- |
| StarRocks | 部分 | -- | -- | -- |
| Doris | 部分 | -- | -- | -- |
| MonetDB | 是 | 是 | -- | -- |
| CrateDB | -- | -- | -- | -- |
| TimescaleDB | 是 | 是 | 是 | -- |
| Exasol | 是 | 是 | -- | -- |
| H2 | 是 | 是 | 是 | -- |
| HSQLDB | 是 | 是 | 是 | -- |
| Derby | 是 | 是 | -- | -- |
| Athena | -- | -- | -- | -- |
| Synapse | 是 | 是 | 是 | -- |
| Spanner | -- | -- | -- | -- |
| Materialize | -- | -- | -- | -- |
| Databend | -- | -- | -- | -- |
| Yellowbrick | 是 | 是 | 是 | -- |
| Firebolt | -- | -- | -- | -- |

### 权限视图（PRIVILEGES / ROLE_*）

| 引擎 | TABLE_PRIVILEGES | COLUMN_PRIVILEGES | ROLE_TABLE_GRANTS | USAGE_PRIVILEGES |
|------|------------------|-------------------|-------------------|------------------|
| PostgreSQL | 是 | 是 | 是 | 是 |
| MySQL | 是 | 是 | -- | 是 |
| MariaDB | 是 | 是 | -- | 是 |
| SQL Server | 是 | 是 | -- | 是 |
| DB2 | 是 | 是 | 是 | 是 |
| Snowflake | 是 | -- | -- | 是 |
| BigQuery | 是 (OBJECT_PRIVILEGES) | -- | -- | -- |
| Redshift | 是 | 是 | -- | 是 |
| DuckDB | 是 | -- | -- | -- |
| Trino | 是 | -- | 是 | -- |
| Databricks | 是 | -- | -- | 是 |
| Greenplum | 是 | 是 | 是 | 是 |
| CockroachDB | 是 | 是 | 是 | 是 |
| TiDB | 是 | 是 | -- | 是 |
| Vertica | 是 | -- | -- | -- |
| Synapse | 是 | 是 | -- | 是 |
| Spanner | 是 | -- | -- | -- |
| Yellowbrick | 是 | 是 | 是 | 是 |
| 其他引擎 | 大多不支持或仅依赖原生目录 | | | |

### 原生目录与捷径命令

| 引擎 | 原生目录 | SHOW TABLES | DESCRIBE | 性能/会话视图 |
|------|---------|-------------|----------|---------------|
| PostgreSQL | `pg_catalog.pg_class/pg_attribute/pg_constraint` | -- | psql `\d` | `pg_stat_activity`, `pg_stat_user_tables` |
| MySQL | `mysql.*` 库 | 是 | 是 | `performance_schema.*`, `sys.*` |
| MariaDB | `mysql.*` 库 | 是 | 是 | `performance_schema`, OQGRAPH/FederatedX |
| SQLite | `sqlite_schema`（旧名 `sqlite_master`） | -- | -- | `sqlite_stat1` |
| Oracle | `USER_*/ALL_*/DBA_*/V$*/X$*` | -- | DESC | `V$SESSION`, `V$SQL`, `V$LOCK`, AWR |
| SQL Server | `sys.objects/sys.columns/sys.indexes/sys.foreign_keys` | -- | sp_help | `sys.dm_exec_*`, `sys.dm_os_*` |
| DB2 (LUW) | `SYSCAT.*` (视图) / `SYSIBM.*` (基表) | -- | DESCRIBE | `SYSIBMADM.*` |
| Snowflake | -- | 是 | DESC | `SNOWFLAKE.ACCOUNT_USAGE.*`（45 分钟延迟） |
| BigQuery | `__TABLES__`, `__TABLES_SUMMARY__` | -- | -- | `INFORMATION_SCHEMA.JOBS_BY_*`, `JOBS_TIMELINE_BY_*` |
| Redshift | `PG_*`, `SVV_*`, `SVL_*`, `STV_*`, `STL_*` | 是 | -- | `SVV_TABLE_INFO`, `STL_QUERY` |
| DuckDB | `duckdb_tables()/duckdb_columns()/duckdb_constraints()` 表函数 | 是 | DESCRIBE | `pragma_database_size()` |
| ClickHouse | `system.tables/columns/parts/databases` | 是 | DESCRIBE | `system.processes`, `system.query_log` |
| Trino | -- | 是 | DESCRIBE / SHOW COLUMNS | `system.runtime.queries` |
| Presto | -- | 是 | DESCRIBE | `system.runtime.queries` |
| Spark SQL | -- | 是 | DESCRIBE [EXTENDED] | `spark_catalog`, Listener API |
| Hive | -- | 是 | DESCRIBE FORMATTED | -- |
| Flink SQL | -- | 是 | DESCRIBE | `Catalog/CatalogManager` API |
| Databricks | Unity Catalog (`system.*` schema) | 是 | DESCRIBE [EXTENDED] | `system.query.history` |
| Teradata | `DBC.Tables`, `DBC.Columns`, `DBC.Indices`, `DBC.AllRights` | 是 | HELP TABLE/COLUMN | `DBC.SessionInfo`, `DBC.QryLogV` |
| Greenplum | `pg_catalog` + `gp_*`（如 `gp_segment_id`） | -- | psql `\d` | `gp_toolkit.*` |
| CockroachDB | `crdb_internal.*` | 是 | -- | `crdb_internal.cluster_queries` |
| TiDB | `mysql.*` + `INFORMATION_SCHEMA` 扩展 | 是 | DESC | `INFORMATION_SCHEMA.PROCESSLIST`, `tidb_*` |
| OceanBase | 双兼容：MySQL `mysql.*` 或 Oracle `DBA_*` | 是 | -- | `oceanbase.gv$*` |
| YugabyteDB | `pg_catalog` + `yb_*` | -- | -- | `yb_local_tablets`, `pg_stat_*` |
| SingleStore | `INFORMATION_SCHEMA.MV_*` 物化视图 | 是 | DESC | `MV_ACTIVITIES`, `MV_QUERIES` |
| Vertica | `V_CATALOG.*`, `V_MONITOR.*`, `V_INTERNAL.*` | -- | -- | `V_MONITOR.SESSIONS`, `QUERY_REQUESTS` |
| Impala | `metastore` (HMS) | 是 | DESCRIBE [FORMATTED] | -- |
| StarRocks | `INFORMATION_SCHEMA` 扩展 | 是 | DESC | `INFORMATION_SCHEMA.tasks/loads` |
| Doris | 同 StarRocks | 是 | DESC | `INFORMATION_SCHEMA.processlist` |
| MonetDB | `sys.tables/columns/keys/idxs` | -- | -- | `sys.queue()` |
| CrateDB | `sys.*`（节点、集群、分片） | 是 | -- | `sys.jobs`, `sys.operations` |
| TimescaleDB | `_timescaledb_catalog.*` + PG | -- | -- | `timescaledb_information.*` |
| QuestDB | `tables()`, `table_columns()` 函数 | 是 | -- | `query_activity()` |
| Exasol | `EXA_ALL_*`, `EXA_USER_*`, `EXA_DBA_*`, `SYS.*` | -- | DESCRIBE | `EXA_DBA_SESSIONS`, `EXA_SQL_LAST_DAY` |
| SAP HANA | `SYS.TABLES`, `SYS.TABLE_COLUMNS`, `SYS.CONSTRAINTS`, `PUBLIC.M_*` | -- | -- | `M_ACTIVE_STATEMENTS`, `M_SERVICE_STATISTICS` |
| Informix | `systables`, `syscolumns`, `sysindexes` | -- | -- | `sysmaster:*` |
| Firebird | `RDB$RELATIONS`, `RDB$RELATION_FIELDS` | SHOW TABLES (isql) | -- | `MON$ATTACHMENTS`, `MON$STATEMENTS` |
| H2 | INFO_SCHEMA 完整 | 是 | -- | `INFORMATION_SCHEMA.SESSIONS` |
| HSQLDB | INFO_SCHEMA 完整 | -- | -- | -- |
| Derby | INFO_SCHEMA + `SYSCS_DIAG.*` | -- | -- | -- |
| Amazon Athena | -- (Glue Data Catalog) | 是 | DESCRIBE | -- |
| Azure Synapse | `sys.*` 同 SQL Server | -- | sp_help | `sys.dm_pdw_*` |
| Google Spanner | `INFORMATION_SCHEMA` + `SPANNER_SYS.*` | -- | -- | `SPANNER_SYS.QUERY_STATS_*` |
| Materialize | `mz_catalog.*`, `mz_internal.*` | 是 | -- | `mz_catalog.mz_recent_activity_log` |
| RisingWave | `rw_catalog.*` | 是 | DESCRIBE | `rw_catalog.rw_meta_snapshot` |
| InfluxDB IOx | -- | 是 | -- | `system.queries` |
| Databend | `system.*`, `system_history.*` | 是 | DESC | `system.query_log`, `system.processes` |
| Yellowbrick | `pg_catalog` + `sys.*` | -- | -- | `sys.session`, `sys.query` |
| Firebolt | -- | 是 | DESCRIBE | `information_schema.engine_*` |

## 详细引擎分析

### PostgreSQL: 双轨制典范

PostgreSQL 是少数严格实现 SQL 标准 `INFORMATION_SCHEMA` 同时保留完整原生目录的引擎。它把 `pg_catalog` 当作"源真相"——所有 DDL 直接写入 `pg_class`、`pg_attribute`、`pg_constraint`、`pg_index`、`pg_proc`、`pg_namespace` 等基表；而 `information_schema` 则是这些底层目录之上的一组视图。

```sql
-- 标准方式：列出当前数据库中所有用户表
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_type = 'BASE TABLE'
  AND table_schema NOT IN ('pg_catalog', 'information_schema');

-- PG 原生方式：等价但更快、更详细
SELECT n.nspname AS schema, c.relname AS table,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS size,
       c.reltuples::BIGINT AS rows
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema');
```

经验法则：跨库迁移工具用 `information_schema`，性能调优脚本用 `pg_catalog`。`pg_catalog` 包含 `relfilenode`、`reltuples`、`relpages`、`relallvisible` 等存储统计，是 `INFORMATION_SCHEMA` 永远没有的。

PostgreSQL 还提供一组 `pg_stat_*` 动态视图：

- `pg_stat_activity` — 当前会话和等待事件
- `pg_stat_user_tables` — 表级 DML 计数和 vacuum 时间戳
- `pg_stat_user_indexes` — 索引扫描计数
- `pg_stat_statements` — 规范化 SQL 的累计统计（需安装扩展）
- `pg_locks` — 当前锁

### Oracle: USER_/ALL_/DBA_ 三层制

Oracle 是主流引擎中**唯一明确不实现 INFORMATION_SCHEMA 的**。Oracle 文档解释：他们认为自己 1979 年起就有自己的数据字典体系，且 ISO 标准在 1992 年才出现，所以选择继续维持原有约定。Oracle 数据字典分为两层：

1. **基表**：`SYS` 模式下名字以 `$` 结尾的内部表，如 `TAB$`、`COL$`、`OBJ$`、`USER$`。这些是 Oracle 启动时由 `sql.bsq` 脚本创建的，不允许直接访问。
2. **静态字典视图**：基表之上的三层视图。

#### 三层视图命名约定

| 前缀 | 范围 | 关键字段 |
|------|------|---------|
| `USER_*` | 当前用户拥有的对象 | 没有 `OWNER` 列（隐含为 CURRENT_USER） |
| `ALL_*` | 当前用户有权访问的所有对象（含他人授予的） | 有 `OWNER` 列 |
| `DBA_*` | 数据库内全部对象（需 SELECT_CATALOG_ROLE） | 有 `OWNER` 列 |

```sql
-- 当前用户的表
SELECT table_name, num_rows, last_analyzed
FROM user_tables;

-- 当前用户能看到的所有表
SELECT owner, table_name FROM all_tables WHERE owner != 'SYS';

-- DBA 视角：全部表
SELECT owner, table_name, tablespace_name FROM dba_tables;
```

经典的 Oracle 元数据查询场景：

```sql
-- 列出某表的所有列（替代 INFORMATION_SCHEMA.COLUMNS）
SELECT column_name, data_type, data_length, nullable, data_default
FROM all_tab_columns
WHERE owner = 'HR' AND table_name = 'EMPLOYEES'
ORDER BY column_id;

-- 主键和外键
SELECT c.constraint_name, c.constraint_type, cc.column_name,
       c.r_constraint_name AS referenced_pk
FROM all_constraints c
JOIN all_cons_columns cc
  ON c.owner = cc.owner AND c.constraint_name = cc.constraint_name
WHERE c.owner = 'HR' AND c.table_name = 'EMPLOYEES';

-- 存储过程和函数
SELECT object_name, object_type, status FROM all_procedures WHERE owner = 'HR';
SELECT text FROM all_source WHERE owner = 'HR' AND name = 'CALC_BONUS' ORDER BY line;
```

Oracle 的 **动态性能视图**（V$ 视图）则是另一套体系，用于实时监控：

| 视图 | 用途 |
|------|------|
| `V$SESSION` | 当前会话和等待事件 |
| `V$SQL` / `V$SQLAREA` | 共享 SQL 缓存 |
| `V$LOCK` / `V$LOCKED_OBJECT` | 锁信息 |
| `V$DATAFILE` / `V$LOGFILE` | 物理文件 |
| `V$INSTANCE` / `V$DATABASE` | 实例与数据库元信息 |
| `V$PROCESS` | 后台和服务器进程 |
| `V$SYSSTAT` / `V$SESSTAT` | 系统/会话累计计数 |

`V$` 视图的本质是 `GV$`（global view）按当前实例过滤的子集；在 RAC 集群中通过 `GV$` 可看到全部节点。

### SQL Server: sys.* 与 INFORMATION_SCHEMA 并行

SQL Server 的元数据访问有两条路径：

1. **INFORMATION_SCHEMA**：标准视图，但实现不完整，例如不返回 SQL Server 特有的列扩展属性、计算列表达式、CHECK 约束的 Disabled 状态等。
2. **sys.*** 目录视图：自 SQL Server 2005 引入，是微软推荐的方式。基于内部元数据表，性能更好且暴露所有 SQL Server 特性。

```sql
-- 列出表
SELECT s.name AS schema_name, t.name AS table_name,
       p.rows, t.create_date
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0,1);

-- 列出列
SELECT c.name, ty.name AS type, c.max_length, c.is_nullable, c.is_identity
FROM sys.columns c
JOIN sys.types ty ON c.user_type_id = ty.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.Orders');

-- 外键
SELECT fk.name, OBJECT_NAME(fk.parent_object_id) AS child,
       OBJECT_NAME(fk.referenced_object_id) AS parent
FROM sys.foreign_keys fk;
```

SQL Server 的 `sys.dm_*` 动态管理视图（DMV）系列是性能调优的核心：

- `sys.dm_exec_requests` / `sys.dm_exec_sessions` — 当前活动
- `sys.dm_exec_query_stats` + `sys.dm_exec_sql_text()` — 累计执行统计
- `sys.dm_os_wait_stats` — 实例级等待事件
- `sys.dm_db_index_usage_stats` — 索引使用频率
- `sys.dm_tran_locks` — 锁
- `sys.dm_exec_query_plan()` — 查询计划缓存

### MySQL / MariaDB: INFORMATION_SCHEMA + performance_schema + mysql

MySQL 同时维护三套元数据：

| 库 | 内容 |
|----|------|
| `information_schema` | 标准视图（自 5.0 起，5.7 后大量私有列）+ MySQL 特有的 `INNODB_*`、`STATISTICS` 等 |
| `performance_schema` | 仪器级运行时统计：等待事件、SQL 摘要、锁、内存、复制 |
| `mysql` | 真正的系统数据库：用户、权限、时区、复制元数据、存储过程主体 |
| `sys` | MariaDB 5.7.7+ / MySQL 5.7+ 提供的 helper schema，对 performance_schema 做易读封装 |

MySQL 8.0 完成了一次重大重构——将所有元数据从 MyISAM 系统表迁移到事务性的 InnoDB 数据字典（"data dictionary tables"），但这些底层表对用户隐藏，只能通过 `INFORMATION_SCHEMA` 访问。

```sql
-- 列出表
SELECT table_schema, table_name, engine, table_rows, data_length
FROM information_schema.tables
WHERE table_schema = 'mydb';

-- 当前活动
SELECT * FROM performance_schema.threads WHERE processlist_id IS NOT NULL;
SELECT * FROM sys.session;  -- sys schema 封装

-- 慢查询摘要
SELECT digest_text, count_star, avg_timer_wait/1e9 AS avg_ms
FROM performance_schema.events_statements_summary_by_digest
ORDER BY sum_timer_wait DESC LIMIT 20;
```

**大小写陷阱**：MySQL 在 Linux 下默认 `lower_case_table_names=0`，表名区分大小写；但 `INFORMATION_SCHEMA` 自身的视图名和列名永远不区分大小写——`select * from INFORMATION_SCHEMA.TABLES` 与 `select * from information_schema.tables` 等价。然而其中的 `TABLE_NAME` 列值会保留原始大小写，跨平台迁移（macOS/Windows 默认 `lower_case_table_names=2`）会被坑。

### DB2: SYSCAT / SYSIBM 双层

DB2 LUW 的元数据有两层：

- `SYSIBM.*` — 基表（实际存储）
- `SYSCAT.*` — 公开视图，过滤掉权限不足的行

```sql
SELECT tabschema, tabname, type, card, npages
FROM syscat.tables
WHERE tabschema = 'HR';

SELECT colname, typename, length, scale, nulls, default
FROM syscat.columns
WHERE tabschema = 'HR' AND tabname = 'EMPLOYEES';
```

DB2 也实现了 `INFORMATION_SCHEMA`（SQLJ.SCHEMA），但管理员通常使用 `SYSCAT`。`SYSIBMADM.*` 提供管理与监控视图，类似 Oracle 的 `V$`。

### SQLite: 极简

SQLite 没有 schema 概念（不算 `main`/`temp`/`attached`），只有一张系统表：

```sql
SELECT type, name, tbl_name, sql
FROM sqlite_schema      -- 3.33+ 推荐名称
WHERE type IN ('table', 'view', 'index', 'trigger');

-- 旧名 sqlite_master 仍可用
PRAGMA table_info('users');     -- 列出列
PRAGMA foreign_key_list('orders');
PRAGMA index_list('users');
```

`PRAGMA` 是 SQLite 特有的元命令，相当于其他数据库的 `INFORMATION_SCHEMA.COLUMNS` 等。

### Snowflake: 三层时间维度

Snowflake 元数据访问有三个层次：

| 来源 | 实时性 | 范围 | 历史保留 |
|------|--------|------|---------|
| `INFORMATION_SCHEMA` (每数据库) | 实时 | 当前数据库 | 7 天到 14 天的部分对象历史 |
| `SNOWFLAKE.ACCOUNT_USAGE` | **45 分钟延迟** | 整个账户 | 365 天 |
| `SNOWFLAKE.READER_ACCOUNT_USAGE` | 同上 | 阅读者账户 | 365 天 |

```sql
-- 实时但只看当前数据库
SELECT table_name, row_count, bytes
FROM mydb.information_schema.tables
WHERE table_schema = 'PUBLIC';

-- 全账户历史，但有延迟
SELECT query_text, total_elapsed_time, credits_used_cloud_services
FROM snowflake.account_usage.query_history
WHERE start_time > DATEADD(day, -7, CURRENT_TIMESTAMP);
```

`ACCOUNT_USAGE` 的 45 分钟延迟是 Snowflake 故意设计的——它通过异步聚合管道生成，便于 BI 工具长期分析，但不适合实时告警。需要实时数据时必须使用 `INFORMATION_SCHEMA` 或 `INFORMATION_SCHEMA.QUERY_HISTORY()` 表函数。

### BigQuery: 区域和数据集双重限定

BigQuery 的 `INFORMATION_SCHEMA` 必须用区域和数据集双重前缀：

```sql
-- 数据集级
SELECT table_name, row_count, size_bytes
FROM `my-project.my_dataset.INFORMATION_SCHEMA.TABLES`;

-- 区域级（跨数据集）
SELECT table_catalog, table_schema, table_name
FROM `my-project.region-us.INFORMATION_SCHEMA.TABLES`;

-- 项目级 JOB 历史
SELECT job_id, user_email, total_bytes_processed
FROM `my-project.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY);
```

BigQuery 还保留了一个**遗留**的 `__TABLES__` 视图，不属于标准但被广泛使用：

```sql
SELECT table_id, row_count, size_bytes,
       TIMESTAMP_MILLIS(creation_time) AS created
FROM `my-project.my_dataset.__TABLES__`;
```

`__TABLES__` 提供了 `INFORMATION_SCHEMA.TABLES` 缺失的 `row_count` 和 `size_bytes`（在 BigQuery 标准视图中需要查 `TABLE_STORAGE`）。Google 一直没有正式弃用 `__TABLES__`，因为太多脚本依赖它。

### Redshift: PG 兼容 + SVV/STV/STL 私有视图

Redshift 派生自 PostgreSQL 8.0，因此保留了 `pg_catalog` 和 `information_schema`，但很多 PG 视图返回的数据**不准确**（如 `pg_class.reltuples`）。Redshift 推荐使用自家的私有视图体系：

| 前缀 | 含义 |
|------|------|
| `STV_*` | "Snapshot Table, Virtual"——内存中的瞬时快照，重启丢失 |
| `STL_*` | "Snapshot Table, Logged"——磁盘日志，保留 2-5 天 |
| `SVV_*` | "System View, Virtual"——基于 STV 的派生视图 |
| `SVL_*` | "System View, Logged"——基于 STL 的派生视图 |
| `SVCS_*` | 并发缩放集群相关 |

```sql
-- 表大小和分布
SELECT "schema", "table", size, tbl_rows, diststyle
FROM svv_table_info;

-- 最近的查询
SELECT query, userid, starttime, endtime, substring
FROM stl_query
WHERE starttime > GETDATE() - INTERVAL '1 hour'
ORDER BY starttime DESC;

-- 列出列
SELECT * FROM svv_columns WHERE table_name = 'orders';
```

### ClickHouse: system.* 一统天下

ClickHouse 的元数据全部集中在 `system` 数据库下。ClickHouse 20.x 之后才补上 `INFORMATION_SCHEMA`（同时存在 `INFORMATION_SCHEMA` 和 `information_schema` 两个名字以兼容大小写），但绝大多数 ClickHouse 用户依然使用 `system.*`。

```sql
SELECT database, name, engine, total_rows, total_bytes
FROM system.tables
WHERE database NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema');

-- 列
SELECT name, type, default_kind, default_expression
FROM system.columns
WHERE database = 'default' AND table = 'events';

-- 数据 part 详情
SELECT partition, name, rows, bytes_on_disk, modification_time
FROM system.parts
WHERE table = 'events' AND active;

-- 当前查询
SELECT query_id, user, query, elapsed FROM system.processes;

-- 历史查询
SELECT query, query_duration_ms, read_rows, memory_usage
FROM system.query_log
WHERE event_time > now() - INTERVAL 1 HOUR AND type = 'QueryFinish';
```

`system.parts`、`system.merges`、`system.replicas`、`system.mutations` 这些在其他数据库里完全没有对应物的视图，是 ClickHouse 运维不可或缺的工具。

### DuckDB: 表函数与 INFO_SCHEMA 双轨

DuckDB 同时提供 `INFORMATION_SCHEMA` 视图和 `duckdb_*()` 表函数：

```sql
-- 标准方式
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'main';

-- DuckDB 表函数（更详细）
SELECT * FROM duckdb_tables();
SELECT * FROM duckdb_columns() WHERE table_name = 'orders';
SELECT * FROM duckdb_constraints();
SELECT * FROM duckdb_indexes();
SELECT * FROM duckdb_databases();   -- 多数据库 attach
SELECT * FROM duckdb_extensions();
```

`duckdb_*()` 函数返回比 `information_schema` 更丰富的列，包括统计信息、压缩、分区元数据。

### Teradata: DBC 字典

Teradata 的元数据完全通过 `DBC` 数据库下的视图访问：

```sql
SELECT DatabaseName, TableName, TableKind, RowCount
FROM DBC.TablesV
WHERE DatabaseName = 'Sales';

SELECT ColumnName, ColumnType, ColumnLength, Nullable
FROM DBC.ColumnsV
WHERE DatabaseName = 'Sales' AND TableName = 'Orders';

-- 权限
SELECT * FROM DBC.AllRightsV WHERE UserName = 'JOHN';

-- 当前会话
SELECT * FROM DBC.SessionInfoV;
```

`DBC.*V` 是受保护的视图层；底层 `DBC.*X` 是基表。Teradata 对 `INFORMATION_SCHEMA` 的支持非常有限，仅作为兼容层。

### SAP HANA: SYS + M_* 监控

SAP HANA 完全没有 `INFORMATION_SCHEMA`，元数据全部在 `SYS` 下：

```sql
SELECT schema_name, table_name, record_count, table_size
FROM sys.m_tables
WHERE schema_name = 'SALES';

SELECT column_name, data_type_name, length, nullable
FROM sys.table_columns
WHERE schema_name = 'SALES' AND table_name = 'ORDERS';

-- 性能监控（M_ 前缀表示 monitoring）
SELECT * FROM sys.m_active_statements;
SELECT * FROM sys.m_service_memory;
SELECT * FROM sys.m_cs_tables;  -- 列存表
```

`SYS` 包含静态元数据，`PUBLIC` 中的 `M_*` 同义词指向各种实时监控视图。

## Oracle USER_/ALL_/DBA_ 三层制深入

Oracle 的字典视图三层制是关系数据库历史上影响最深远的元数据约定，理解它有助于理解为什么 Oracle 拒绝 `INFORMATION_SCHEMA`。

### 设计原理

Oracle 的字典视图设计假设：

1. **数据库是多用户的**——每个 schema = 一个用户
2. **权限是细粒度的**——A 看不到 B 的对象除非显式授权
3. **行级过滤优于元数据 API**——通过视图自动过滤，而非应用层判断

因此三层视图实际上只是同一组基表上的三个不同 WHERE 子句：

```sql
-- USER_TABLES 简化定义
CREATE VIEW user_tables AS
SELECT t.name AS table_name, ...
FROM sys.tab$ t, sys.obj$ o
WHERE o.obj# = t.obj# AND o.owner# = USERENV('SCHEMAID');

-- ALL_TABLES 简化定义
CREATE VIEW all_tables AS
SELECT u.name AS owner, t.name AS table_name, ...
FROM sys.tab$ t, sys.obj$ o, sys.user$ u
WHERE o.obj# = t.obj# AND o.owner# = u.user#
  AND (o.owner# = USERENV('SCHEMAID')
       OR EXISTS (SELECT 1 FROM v$enabledprivs WHERE ...));

-- DBA_TABLES 简化定义（无 WHERE 过滤，需 SELECT_CATALOG_ROLE）
CREATE VIEW dba_tables AS
SELECT u.name AS owner, t.name AS table_name, ...
FROM sys.tab$ t, sys.obj$ o, sys.user$ u
WHERE o.obj# = t.obj# AND o.owner# = u.user#;
```

### 完整对象类别

Oracle 为几乎每种对象都有三层视图：

| USER_/ALL_/DBA_ 视图 | 内容 |
|---------------------|------|
| `_TABLES` | 表 |
| `_TAB_COLUMNS` | 表的列 |
| `_VIEWS` | 视图 |
| `_INDEXES` | 索引 |
| `_IND_COLUMNS` | 索引的列 |
| `_CONSTRAINTS` | 约束 |
| `_CONS_COLUMNS` | 约束的列 |
| `_SYNONYMS` | 同义词 |
| `_SEQUENCES` | 序列 |
| `_TRIGGERS` | 触发器 |
| `_PROCEDURES` | 存储过程/函数/包 |
| `_SOURCE` | PL/SQL 源代码 |
| `_OBJECTS` | 所有对象的统一视图 |
| `_TAB_PRIVS` / `_COL_PRIVS` | 权限 |
| `_ROLE_PRIVS` | 角色授予 |
| `_TAB_PARTITIONS` | 分区 |
| `_LOBS` | LOB 列 |

### 与 INFORMATION_SCHEMA 对照

| INFORMATION_SCHEMA | Oracle 等价 |
|-------------------|------------|
| `TABLES` | `ALL_TABLES` + `ALL_VIEWS` |
| `COLUMNS` | `ALL_TAB_COLUMNS` |
| `VIEWS` | `ALL_VIEWS` |
| `KEY_COLUMN_USAGE` | `ALL_CONS_COLUMNS` 配合 `ALL_CONSTRAINTS` |
| `TABLE_CONSTRAINTS` | `ALL_CONSTRAINTS WHERE constraint_type IN ('P','U','C','R')` |
| `REFERENTIAL_CONSTRAINTS` | `ALL_CONSTRAINTS WHERE constraint_type='R'` |
| `ROUTINES` | `ALL_PROCEDURES` + `ALL_OBJECTS WHERE object_type IN ('PROCEDURE','FUNCTION','PACKAGE')` |
| `TRIGGERS` | `ALL_TRIGGERS` |
| `SCHEMATA` | `ALL_USERS` |
| `TABLE_PRIVILEGES` | `ALL_TAB_PRIVS` |

社区有第三方包（如 EnterpriseDB 和 ora2pg 项目）在 Oracle 上构建 `INFORMATION_SCHEMA` 兼容层，但官方坚决不提供。

## SHOW 命令 vs 标准 INFORMATION_SCHEMA

在 OLAP 和 NoSQL 衍生引擎中，`SHOW` 类命令往往比 `INFORMATION_SCHEMA` 更被开发者熟悉，也常常是某些操作的唯一接口。

### 常见 SHOW 命令族

```sql
SHOW DATABASES;            -- MySQL/Hive/Spark/Trino/CH/Doris/...
SHOW SCHEMAS [FROM db];    -- 同上的别名（有些引擎区分）
SHOW TABLES [FROM db];     -- 几乎所有 OLAP 引擎
SHOW TABLES LIKE 'pat%';   -- 模式过滤
SHOW COLUMNS FROM tbl;     -- MySQL/CH/Trino
SHOW CREATE TABLE tbl;     -- 重建 DDL
SHOW INDEX FROM tbl;       -- MySQL/MariaDB
SHOW PARTITIONS tbl;       -- Hive/Spark/Impala/Trino
SHOW FUNCTIONS;            -- Hive/Spark/Trino/CH
SHOW VARIABLES;            -- MySQL/MariaDB/CH
SHOW STATUS;               -- MySQL/MariaDB
SHOW GRANTS FOR user;      -- MySQL/MariaDB/SnowSQL
SHOW PROCESSLIST;          -- MySQL/MariaDB/TiDB/StarRocks/Doris
SHOW WAREHOUSES;           -- Snowflake
SHOW LOCKS;                -- ClickHouse/Hive
```

### DESCRIBE / DESC 简写

`DESCRIBE table` 几乎是所有 SQL 引擎的"列出列"快捷命令：

| 引擎 | 等价完整查询 |
|------|------------|
| MySQL/MariaDB | `SELECT * FROM information_schema.columns WHERE table_name = ?` |
| Oracle | `SELECT column_name, data_type FROM all_tab_columns WHERE table_name = ?`（仅 SQL*Plus） |
| Snowflake | `DESC TABLE` 等价 `INFORMATION_SCHEMA.COLUMNS` 查询 |
| Spark/Hive | `DESCRIBE EXTENDED` 含分区、存储格式 |
| Trino/Presto | `DESCRIBE` 等价 `SHOW COLUMNS` |
| ClickHouse | `DESCRIBE TABLE` 含编解码器、TTL |
| BigQuery | 无 DESC，但 BQ Console 显示 schema |

### SHOW 与 INFORMATION_SCHEMA 的区别

| 维度 | SHOW | INFORMATION_SCHEMA |
|------|------|-------------------|
| 标准化 | 各引擎语法各异 | ISO 标准 |
| 可组合性 | 不能 JOIN/WHERE/聚合 | 可以作为 SELECT 的源 |
| 列扩展 | 引擎可任意添加 | 列固定 |
| 性能 | 通常更快（直读元数据缓存） | 经过视图层 |
| 覆盖度 | 引擎特性优先 | 仅标准对象 |

最佳实践：交互式探索用 `SHOW`，应用代码用 `INFORMATION_SCHEMA`。

## 现实世界的元数据查询模式

### 1. 找出某个数据库的总大小

```sql
-- PostgreSQL
SELECT pg_size_pretty(pg_database_size(current_database()));

-- MySQL
SELECT SUM(data_length + index_length) / 1024 / 1024 AS mb
FROM information_schema.tables WHERE table_schema = DATABASE();

-- Oracle
SELECT SUM(bytes)/1024/1024 mb FROM dba_segments WHERE owner = USER;

-- SQL Server
EXEC sp_spaceused;

-- BigQuery
SELECT SUM(size_bytes)/POWER(1024,3) AS gb
FROM `proj.dataset.__TABLES__`;

-- Snowflake
SELECT SUM(bytes)/POWER(1024,3) AS gb
FROM mydb.information_schema.table_storage_metrics;
```

### 2. 找出未使用的索引

```sql
-- PostgreSQL
SELECT schemaname, indexrelname FROM pg_stat_user_indexes WHERE idx_scan = 0;

-- SQL Server
SELECT OBJECT_NAME(s.object_id), i.name
FROM sys.dm_db_index_usage_stats s
JOIN sys.indexes i ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE user_seeks + user_scans + user_lookups = 0;

-- Oracle
SELECT name, total_access_count
FROM v$object_usage
WHERE total_access_count = 0;
```

### 3. 列出所有外键

```sql
-- 标准 INFORMATION_SCHEMA（PG/MySQL/SQL Server/DB2/...）
SELECT
  tc.table_name AS child_table,
  kcu.column_name AS child_column,
  ccu.table_name AS parent_table,
  ccu.column_name AS parent_column
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu
  ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY';

-- Oracle 等价
SELECT
  c.table_name AS child_table,
  cc.column_name AS child_column,
  rc.table_name AS parent_table,
  rcc.column_name AS parent_column
FROM all_constraints c
JOIN all_cons_columns cc ON c.constraint_name = cc.constraint_name
JOIN all_constraints rc ON c.r_constraint_name = rc.constraint_name
JOIN all_cons_columns rcc ON rc.constraint_name = rcc.constraint_name AND cc.position = rcc.position
WHERE c.constraint_type = 'R';
```

### 4. 实时查看长事务

```sql
-- PostgreSQL
SELECT pid, now() - xact_start AS duration, query
FROM pg_stat_activity
WHERE state != 'idle' AND xact_start IS NOT NULL
ORDER BY duration DESC;

-- SQL Server
SELECT session_id, total_elapsed_time, text
FROM sys.dm_exec_requests
CROSS APPLY sys.dm_exec_sql_text(sql_handle)
WHERE total_elapsed_time > 60000;

-- Oracle
SELECT sid, sql_text, last_call_et
FROM v$session s JOIN v$sql q ON s.sql_id = q.sql_id
WHERE status = 'ACTIVE' AND last_call_et > 60;

-- ClickHouse
SELECT query_id, user, elapsed, query
FROM system.processes ORDER BY elapsed DESC;
```

## 关键发现

1. **标准与现实严重背离**：尽管 `INFORMATION_SCHEMA` 是 SQL:1992 强制要求的，30 多年后仍有 Oracle、SQLite、Hive、Impala、SAP HANA、Firebird、Informix 等核心引擎完全不实现它。Oracle 是最大的孤岛——它的字典 (`USER_/ALL_/DBA_`) 比 ISO 标准更早，从未让步。

2. **PostgreSQL 是双标准的最佳实践**：同时维护 `pg_catalog`（性能与完整性）和 `information_schema`（可移植性），让用户根据需要选择。Greenplum、Yellowbrick、Redshift（部分）、CockroachDB、YugabyteDB、TimescaleDB 等都继承了这一双轨制。

3. **三层制 vs 单层制**：Oracle 的 `USER_/ALL_/DBA_` 通过命名前缀实现行级过滤；其他引擎通过视图的内置权限过滤实现同样效果。三层制更显式，单层制更紧凑。

4. **OLAP 引擎对约束元数据冷淡**：ClickHouse、Spark SQL、Hive、Impala、Athena、Databend、Firebolt、Materialize 等几乎不维护外键和 CHECK 约束的元数据，因为它们本身就不强制约束。即使 Snowflake、BigQuery、Databricks 提供约束视图，约束也仅作为优化器提示存在（informational only）。

5. **历史数据有延迟**：Snowflake 的 `ACCOUNT_USAGE` 有 **45 分钟延迟**，但保留 365 天；`INFORMATION_SCHEMA` 实时但保留有限。BigQuery 的 `JOBS_BY_PROJECT` 准实时但仅保留 180 天。设计监控系统时必须区分实时与历史两套数据源。

6. **大小写规则混乱**：MySQL 的 `INFORMATION_SCHEMA` 视图名不区分大小写，但 `TABLE_NAME` 列值区分大小写（取决于 `lower_case_table_names`）。SQL Server 取决于排序规则。Oracle 默认全部大写。PostgreSQL 区分大小写但折叠未加引号的标识符。跨引擎迁移这是头号坑。

7. **BigQuery `__TABLES__` 是历史包袱**：它不属于标准 `INFORMATION_SCHEMA`，但因为提供了 `row_count` 和 `size_bytes` 这两个最常用字段，被广泛使用。Google 始终没有正式弃用，但建议新代码使用 `INFORMATION_SCHEMA.TABLE_STORAGE`。

8. **DuckDB 表函数路线**：DuckDB 在 `INFORMATION_SCHEMA` 之外提供 `duckdb_tables()`、`duckdb_columns()` 等表函数，返回比标准视图更丰富的列。这种"表函数 + 标准视图"的模式可能是未来趋势——`information_schema` 限于 ISO 列，扩展信息走表函数。

9. **嵌入式数据库反而最标准**：H2、HSQLDB、Derby 这些 Java 嵌入式数据库的 `INFORMATION_SCHEMA` 实现度往往比 SQL Server 还高——因为它们没有历史包袱，且面向 ORM 集成场景。

10. **性能与监控视图碎片化最严重**：标准 `INFORMATION_SCHEMA` 完全没有定义性能监控视图。每个引擎都自己造轮子：PostgreSQL `pg_stat_*`、Oracle `V$`、SQL Server `sys.dm_*`、MySQL `performance_schema`、ClickHouse `system.query_log`、Snowflake `QUERY_HISTORY`、Vertica `V_MONITOR`。这是 ANSI SQL 委员会最大的遗漏之一。

11. **Catalog API 在流式引擎中替代 SQL 元数据**：Flink SQL、Materialize、RisingWave 等流式系统更倾向于通过编程 API（`CatalogManager`）暴露元数据，因为流处理本身就是程序化的。SQL 元数据视图对它们而言只是次要接口。

12. **元数据访问的统一未来**：Iceberg/Delta/Hudi 等开放表格式催生了"独立 catalog 服务"（如 Polaris、Unity Catalog、Nessie、AWS Glue），未来引擎可能不再各自维护元数据，而是从共享 catalog 服务读取。届时 `INFORMATION_SCHEMA` 的角色将进一步弱化——它会变成 catalog 服务的标准 SQL 视图。
