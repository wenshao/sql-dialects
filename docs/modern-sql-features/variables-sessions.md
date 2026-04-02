# 变量与会话管理 (Variables and Session Management)

变量语法和会话控制是 SQL 方言中差异最大的领域之一。SQL 标准仅在 SQL:1999 中引入了极其有限的 SET 语句和会话属性，而各引擎在此基础上发展出截然不同的变量体系：MySQL 用 `@var` 表示用户变量，SQL Server 用 `@var` 表示局部变量，PostgreSQL 依赖 GUC 参数系统，Oracle 则完全在 PL/SQL 块中处理变量。对于引擎开发者而言，理解这些差异不仅影响 SQL 解析器的设计，也决定了会话状态机的复杂度。

## SQL 标准中的变量与会话管理

### SQL:1999 / SQL:2003 标准

SQL 标准对变量和会话管理的规定相对简洁：

```sql
-- SQL:1999 SET 语句（会话属性）
SET <session characteristic> = <value>

-- 标准定义的会话属性
SET SCHEMA 'schema_name'               -- 设置默认 schema
SET CATALOG 'catalog_name'             -- 设置默认 catalog
SET TIME ZONE 'timezone'               -- 设置时区
SET SESSION AUTHORIZATION 'user'       -- 设置会话用户
SET TRANSACTION ISOLATION LEVEL ...    -- 设置事务隔离级别
SET ROLE 'role_name'                   -- 设置当前角色

-- SQL:2003 复合语句中的局部变量
BEGIN ATOMIC
    DECLARE x INTEGER DEFAULT 0;
    SET x = x + 1;
END
```

标准中 **没有** 定义用户变量（如 `@var`）、全局/系统变量、`SHOW VARIABLES` 等概念——这些全是各引擎的扩展。

## 支持矩阵

### 用户变量 (User-Defined Variables)

用户变量是会话级的命名值，在语句之间保持状态。MySQL 的 `@var` 语法最为知名，但各引擎实现差异极大。

| 引擎 | 语法 | 赋值方式 | 作用域 | 类型 | 版本 |
|------|------|---------|--------|------|------|
| PostgreSQL | 无原生用户变量 | `SET myapp.var = 'val'`（GUC 自定义参数） | 会话 | 字符串 | 9.2+ |
| MySQL | `@var` | `SET @var = val` / `SELECT @var := val` | 会话 | 动态类型 | 3.23+ |
| MariaDB | `@var` | `SET @var = val` / `SELECT @var := val` | 会话 | 动态类型 | 5.1+ |
| SQLite | 无 | 无 | — | — | — |
| Oracle | 无 SQL 级用户变量 | SQL*Plus `VARIABLE` / `DEFINE`; PL/SQL `DECLARE` | 会话（SQL*Plus） | 按声明 | — |
| SQL Server | `@var`（局部变量） | `DECLARE @var TYPE; SET @var = val` | 批处理 | 静态类型 | 2000+ |
| DB2 | 无 SQL 级用户变量 | `CREATE VARIABLE`（模块变量，9.7+） | 会话 | 静态类型 | 9.7+ |
| Snowflake | `$var`（会话变量） | `SET var = val` | 会话 | 动态类型 | GA |
| BigQuery | 无持久用户变量 | `DECLARE var TYPE; SET var = val`（脚本级） | 脚本 | 静态类型 | GA |
| Redshift | 无原生用户变量 | `SET var TO val`（自定义 GUC，类似 PG） | 会话 | 字符串 | GA |
| DuckDB | `$var`（预处理参数） | `SET VARIABLE var = val`（0.10+） | 会话 | 动态类型 | 0.10+ |
| ClickHouse | 无用户变量 | SET + 查询设置 | 会话/查询 | — | — |
| Trino | 无用户变量 | `SET SESSION prop = val` | 会话 | 按属性 | — |
| Presto | 无用户变量 | `SET SESSION prop = val` | 会话 | 按属性 | — |
| Spark SQL | 无 SQL 级用户变量 | `SET var = val`（conf 参数） | 会话 | 字符串 | 2.0+ |
| Hive | `${hivevar:var}` | `SET hivevar:var = val` | 会话 | 字符串 | 0.8+ |
| Flink SQL | 无用户变量 | `SET 'key' = 'val'`（配置参数） | 会话 | 字符串 | 1.11+ |
| Databricks | 无 SQL 级用户变量 | `SET var = val`（Spark conf） | 会话 | 字符串 | GA |
| Teradata | 无 SQL 级用户变量 | 宏参数 / BTEQ `.SET` | 工具级 | — | — |
| Greenplum | 无原生用户变量 | `SET myapp.var = 'val'`（GUC，同 PG） | 会话 | 字符串 | 5.0+ |
| CockroachDB | 无原生用户变量 | `SET var = val`（会话变量） | 会话 | 字符串 | 19.1+ |
| TiDB | `@var` | `SET @var = val`（兼容 MySQL） | 会话 | 动态类型 | 2.0+ |
| OceanBase | `@var`（MySQL 模式） | `SET @var = val`（MySQL 模式） | 会话 | 动态类型 | 3.0+ |
| YugabyteDB | 无原生用户变量 | `SET myapp.var = 'val'`（GUC，同 PG） | 会话 | 字符串 | 2.0+ |
| SingleStore | `@var` | `SET @var = val`（兼容 MySQL） | 会话 | 动态类型 | 6.0+ |
| Vertica | 无 SQL 级用户变量 | `\set`（vsql 工具） | 工具级 | — | — |
| Impala | 无用户变量 | `SET var = val`（查询选项） | 会话 | 字符串 | 1.0+ |
| StarRocks | `@var` | `SET @var = val`（兼容 MySQL，3.0+） | 会话 | 动态类型 | 3.0+ |
| Doris | `@var` | `SET @var = val`（兼容 MySQL） | 会话 | 动态类型 | 1.0+ |
| MonetDB | 无用户变量 | `DECLARE var TYPE`（过程内） | 过程 | 静态类型 | — |
| CrateDB | 无用户变量 | `SET GLOBAL / SET SESSION` | 会话 | — | — |
| TimescaleDB | 无原生用户变量 | `SET myapp.var = 'val'`（GUC，继承 PG） | 会话 | 字符串 | 继承 PG |
| QuestDB | 无用户变量 | 无 | — | — | — |
| Exasol | 无 SQL 级用户变量 | `DEFINE` / `COLUMN` ... `NEW_VALUE` (SQL*Plus 兼容) | 工具级 | — | — |
| SAP HANA | 无 SQL 级用户变量 | SQLScript `DECLARE` / `SESSION_CONTEXT` | 过程/会话 | 静态类型 | 1.0+ |
| Informix | 无 SQL 级用户变量 | SPL `DEFINE` | 过程 | 静态类型 | — |
| Firebird | 无 SQL 级用户变量 | PSQL `DECLARE VARIABLE` / `RDB$SET_CONTEXT` | 过程/会话 | 按声明 | 2.0+ |
| H2 | `@var` | `SET @var = val` | 会话 | 动态类型 | 1.0+ |
| HSQLDB | 无用户变量 | `DECLARE var TYPE`（过程内） | 过程 | 静态类型 | — |
| Derby | 无用户变量 | `DECLARE var TYPE`（过程内） | 过程 | 静态类型 | — |
| Amazon Athena | 无用户变量 | 预处理语句参数 | 语句 | — | — |
| Azure Synapse | `@var`（T-SQL） | `DECLARE @var TYPE; SET @var = val` | 批处理 | 静态类型 | GA |
| Google Spanner | 无用户变量 | 查询参数（客户端绑定） | 语句 | — | — |
| Materialize | 无原生用户变量 | `SET var = val`（会话参数，继承 PG） | 会话 | 字符串 | 0.26+ |
| RisingWave | 无原生用户变量 | `SET var = val`（会话参数，PG 兼容） | 会话 | 字符串 | 0.18+ |
| InfluxDB | 无用户变量 | 无（InfluxQL / Flux 绑定参数） | — | — | — |
| Databend | `$var`（引用阶段参数） | `SET VARIABLE var = val`（1.2+） | 会话 | 动态类型 | 1.2+ |
| Yellowbrick | 无原生用户变量 | `SET var = val`（PG 兼容会话参数） | 会话 | 字符串 | GA |
| Firebolt | 无用户变量 | `SET var = val`（引擎参数） | 会话 | 字符串 | GA |

### 会话变量 / 会话参数 (Session Variables / Parameters)

会话参数控制当前连接的行为，如默认 schema、时区、排序规则等。

| 引擎 | SET 语法 | ALTER SESSION | SHOW 语法 | 典型参数 | 版本 |
|------|---------|--------------|-----------|---------|------|
| PostgreSQL | `SET param = val` | 无 | `SHOW param` / `SHOW ALL` | search_path, timezone, client_encoding | 7.0+ |
| MySQL | `SET [SESSION] var = val` | 无 | `SHOW [SESSION] VARIABLES` | character_set_client, time_zone, sql_mode | 3.23+ |
| MariaDB | `SET [SESSION] var = val` | 无 | `SHOW [SESSION] VARIABLES` | character_set_client, time_zone, sql_mode | 5.1+ |
| SQLite | `PRAGMA name = val` | 无 | `PRAGMA name` | journal_mode, encoding, foreign_keys | 3.0+ |
| Oracle | `ALTER SESSION SET param = val` | ✅ | `SHOW PARAMETER param`（SQL*Plus） | NLS_DATE_FORMAT, OPTIMIZER_MODE, TIME_ZONE | 7.0+ |
| SQL Server | `SET option val` | 无 | `DBCC USEROPTIONS` / `@@options` | ANSI_NULLS, QUOTED_IDENTIFIER, LANGUAGE | 2000+ |
| DB2 | `SET var = val` | 无 | `VALUES CURRENT SCHEMA` 等 | CURRENT SCHEMA, CURRENT PATH, CURRENT ISOLATION | 7.0+ |
| Snowflake | `ALTER SESSION SET param = val` | ✅ | `SHOW PARAMETERS IN SESSION` | TIMEZONE, QUERY_TAG, DATE_INPUT_FORMAT | GA |
| BigQuery | `SET @@param = val`（限脚本） | 无 | 无通用 SHOW | @@dataset_id, @@time_zone | GA |
| Redshift | `SET param TO val` | 无 | `SHOW param` / `SHOW ALL` | search_path, timezone, query_group | GA |
| DuckDB | `SET param = val` / `PRAGMA` | 无 | `SELECT current_setting('param')` | search_path, timezone, threads | 0.3+ |
| ClickHouse | `SET param = val` | 无 | `SHOW SETTINGS` / `SELECT getSetting('name')` | max_threads, max_memory_usage | 18.1+ |
| Trino | `SET SESSION prop = val` | 无 | `SHOW SESSION` | query_max_memory, join_distribution_type | 351+ |
| Presto | `SET SESSION prop = val` | 无 | `SHOW SESSION` | query_max_memory, join_distribution_type | 0.100+ |
| Spark SQL | `SET spark.conf = val` | 无 | `SET` / `SET -v` | spark.sql.shuffle.partitions | 1.0+ |
| Hive | `SET param = val` | 无 | `SET` / `SET -v` | hive.exec.parallel, mapred.reduce.tasks | 0.2+ |
| Flink SQL | `SET 'key' = 'val'` | 无 | `SET` | pipeline.name, table.exec.state.ttl | 1.11+ |
| Databricks | `SET param = val` | 无 | `SET` / `SET -v` | spark.sql.shuffle.partitions | GA |
| Teradata | `SET SESSION param` | 无 | `HELP SESSION` | DATEFORM, DEFAULT DATABASE, ACCOUNT | V2R5+ |
| Greenplum | `SET param = val` | 无 | `SHOW param` / `SHOW ALL` | search_path, optimizer, timezone | 4.0+ |
| CockroachDB | `SET param = val` | 无 | `SHOW param` / `SHOW ALL` | database, timezone, default_transaction_isolation | 1.0+ |
| TiDB | `SET [SESSION] var = val` | 无 | `SHOW [SESSION] VARIABLES` | tidb_mem_quota_query, time_zone | 2.0+ |
| OceanBase | `SET [SESSION] var = val` | `ALTER SESSION SET`（Oracle 模式） | `SHOW [SESSION] VARIABLES` | ob_query_timeout, time_zone | 3.0+ |
| YugabyteDB | `SET param = val` | 无 | `SHOW param` / `SHOW ALL` | search_path, timezone | 2.0+ |
| SingleStore | `SET [SESSION] var = val` | 无 | `SHOW [SESSION] VARIABLES` | collation_server, max_allowed_packet | 6.0+ |
| Vertica | `SET param TO val` / `ALTER SESSION SET param = val` | ✅ | `SHOW param` / `SHOW ALL` | search_path, timezone, locale | 7.0+ |
| Impala | `SET param = val` | 无 | `SET` / `SET ALL` | MEM_LIMIT, NUM_SCANNER_THREADS | 1.0+ |
| StarRocks | `SET [SESSION] var = val` | 无 | `SHOW [SESSION] VARIABLES` | parallel_fragment_exec_instance_num | 2.0+ |
| Doris | `SET [SESSION] var = val` | 无 | `SHOW [SESSION] VARIABLES` | exec_mem_limit, time_zone | 0.12+ |
| MonetDB | `SET SCHEMA 'name'` / `SET TIMEZONE` | 无 | `SELECT current_schema` | SCHEMA, TIMEZONE, ROLE | 11.0+ |
| CrateDB | `SET SESSION param = val` | 无 | `SHOW param` | search_path, timezone | 4.0+ |
| TimescaleDB | `SET param = val`（继承 PG） | 无 | `SHOW param`（继承 PG） | 同 PostgreSQL | 继承 PG |
| QuestDB | 无 SET 语法 | 无 | 无 | 通过配置文件 | — |
| Exasol | `ALTER SESSION SET param = val` | ✅ | `SELECT CURRENT_SESSION` / 系统表 | NLS_DATE_FORMAT, QUERY_TIMEOUT | 6.0+ |
| SAP HANA | `SET 'param' = 'val'` / `ALTER SESSION SET` | ✅ | `SELECT SESSION_CONTEXT('key')` | SCHEMA, LOCALE, TEMPORAL_TABLES | 1.0+ |
| Informix | `SET var val` | 无 | 无通用 SHOW | PDQPRIORITY, ISOLATION, LOCK MODE | 7.0+ |
| Firebird | `SET param val`（isql） | 无 | 无 SQL 级 SHOW | 通过 `RDB$GET_CONTEXT` | 2.0+ |
| H2 | `SET param val` | 无 | `SHOW param` | SCHEMA, LOCK_TIMEOUT, THROTTLE | 1.0+ |
| HSQLDB | `SET SESSION param val` | 无 | 无通用 SHOW | SCHEMA, INITIAL SCHEMA | 2.0+ |
| Derby | `SET SCHEMA name` / `SET CURRENT ISOLATION` | 无 | `VALUES CURRENT SCHEMA` | CURRENT SCHEMA, CURRENT ISOLATION | 10.0+ |
| Amazon Athena | 无 SET 语法 | 无 | 无 | 通过 Workgroup 配置 | — |
| Azure Synapse | `SET option val`（T-SQL） | 无 | `DBCC USEROPTIONS` | ANSI_NULLS, QUOTED_IDENTIFIER | GA |
| Google Spanner | `SET STATEMENT_TIMEOUT = '30s'`（Spanner SQL） | 无 | `SHOW VARIABLE var` | STATEMENT_TIMEOUT, READ_ONLY_STALENESS | GA |
| Materialize | `SET param = val`（PG 兼容） | 无 | `SHOW param` | cluster, timezone, database | 0.26+ |
| RisingWave | `SET param = val`（PG 兼容） | 无 | `SHOW param` | search_path, timezone | 0.18+ |
| InfluxDB | 无 SQL 级 SET | 无 | 无 | API / 配置文件 | — |
| Databend | `SET [GLOBAL] param = val` | 无 | `SHOW SETTINGS` | timezone, max_threads, storage_format | 0.8+ |
| Yellowbrick | `SET param = val`（PG 兼容） | 无 | `SHOW param` | search_path, timezone | GA |
| Firebolt | `SET param = val` | 无 | 无通用 SHOW | time_zone, max_result_rows | GA |

### 局部变量 (Local Variables in Stored Procedures / Scripts)

局部变量在过程化 SQL 块中声明，作用域限于声明所在的 BEGIN...END 块或过程体。

| 引擎 | 声明语法 | 赋值语法 | 块作用域 | 默认值 | 版本 |
|------|---------|---------|---------|--------|------|
| PostgreSQL | `DECLARE v TYPE [:= expr]` | `v := expr` / `SELECT INTO v` | ✅ | 支持 | 8.0+ |
| MySQL | `DECLARE v TYPE [DEFAULT expr]` | `SET v = expr` / `SELECT expr INTO v` | ✅ | 支持 | 5.0+ |
| MariaDB | `DECLARE v TYPE [DEFAULT expr]` | `SET v = expr` / `SELECT expr INTO v` | ✅ | 支持 | 5.0+ |
| SQLite | 无过程化 SQL | — | — | — | — |
| Oracle | `v TYPE [:= expr]`（DECLARE 块） | `v := expr` / `SELECT expr INTO v` | ✅ | 支持 | 7.0+ |
| SQL Server | `DECLARE @v TYPE [= expr]` | `SET @v = expr` / `SELECT @v = expr` | 批处理级 | 2008+ | 2000+ |
| DB2 | `DECLARE v TYPE [DEFAULT expr]` | `SET v = expr` / `SELECT expr INTO v` | ✅ | 支持 | 7.0+ |
| Snowflake | `LET v TYPE := expr` / `DECLARE v TYPE` | `v := expr` | ✅ | 支持 | GA |
| BigQuery | `DECLARE v TYPE [DEFAULT expr]` | `SET v = expr` | ✅ | 支持 | GA |
| Redshift | `DECLARE v TYPE [:= expr]` | `v := expr` / `SELECT INTO v` | ✅ | 支持 | GA |
| DuckDB | 无过程化 SQL | — | — | — | — |
| ClickHouse | 无过程化 SQL | — | — | — | — |
| Trino | `DECLARE v TYPE [DEFAULT expr]`（SQL routine 419+） | `SET v = expr` | ✅ | 支持 | 419+ |
| Presto | 无过程化 SQL | — | — | — | — |
| Spark SQL | 无原生过程化 SQL（Databricks SQL 扩展） | — | — | — | — |
| Hive | 无过程化 SQL | — | — | — | — |
| Flink SQL | 无过程化 SQL | — | — | — | — |
| Databricks | `DECLARE v TYPE [DEFAULT expr]`（SQL Scripting, DBR 14+） | `SET VAR v = expr` | ✅ | 支持 | DBR 14+ |
| Teradata | `DECLARE v TYPE [DEFAULT expr]` | `SET v = expr` | ✅ | 支持 | V2R5+ |
| Greenplum | `DECLARE v TYPE [:= expr]` | `v := expr` / `SELECT INTO v` | ✅ | 支持 | 4.0+ |
| CockroachDB | `DECLARE v TYPE [:= expr]`（PL/pgSQL, 23.1+） | `v := expr` | ✅ | 支持 | 23.1+ |
| TiDB | 无过程化 SQL | — | — | — | — |
| OceanBase | `DECLARE v TYPE`（Oracle 模式）/ MySQL 语法 | `SET v = expr` / `v := expr` | ✅ | 支持 | 3.0+ |
| YugabyteDB | `DECLARE v TYPE [:= expr]` | `v := expr` | ✅ | 支持 | 2.6+ |
| SingleStore | `DECLARE v TYPE [DEFAULT expr]` | `SET v = expr` | ✅ | 支持 | 7.0+ |
| Vertica | 无过程化变量 | — | — | — | — |
| Impala | 无过程化 SQL | — | — | — | — |
| StarRocks | 无过程化 SQL | — | — | — | — |
| Doris | 无过程化 SQL | — | — | — | — |
| MonetDB | `DECLARE v TYPE` | `SET v = expr` | ✅ | 支持 | 11.0+ |
| CrateDB | 无过程化 SQL | — | — | — | — |
| TimescaleDB | `DECLARE v TYPE [:= expr]`（继承 PG） | `v := expr` | ✅ | 支持 | 继承 PG |
| QuestDB | 无过程化 SQL | — | — | — | — |
| Exasol | `DECLARE v TYPE [:= expr]` | `v := expr` | ✅ | 支持 | 6.0+ |
| SAP HANA | `DECLARE v TYPE [:= expr]` | `v := expr` / `v = expr` | ✅ | 支持 | SPS09+ |
| Informix | `DEFINE v TYPE` | `LET v = expr` | ✅ | 支持 | 7.0+ |
| Firebird | `DECLARE VARIABLE v TYPE` | `v = expr` | ✅ | 支持 | 1.5+ |
| H2 | `DECLARE v TYPE [DEFAULT expr]`（过程内） | `SET v = expr` | ✅ | 支持 | 1.0+ |
| HSQLDB | `DECLARE v TYPE [DEFAULT expr]` | `SET v = expr` | ✅ | 支持 | 2.0+ |
| Derby | `DECLARE v TYPE`（过程内） | `SET v = expr` | ✅ | 支持 | 10.0+ |
| Amazon Athena | 无过程化 SQL | — | — | — | — |
| Azure Synapse | `DECLARE @v TYPE [= expr]` | `SET @v = expr` | 批处理级 | 支持 | GA |
| Google Spanner | 无过程化 SQL | — | — | — | — |
| Materialize | 无过程化 SQL | — | — | — | — |
| RisingWave | 无过程化 SQL | — | — | — | — |
| InfluxDB | 无过程化 SQL | — | — | — | — |
| Databend | 无过程化 SQL | — | — | — | — |
| Yellowbrick | 无过程化 SQL | — | — | — | — |
| Firebolt | 无过程化 SQL | — | — | — | — |

### 系统/全局变量 (System / Global Variables)

系统变量影响服务器全局行为。修改全局变量通常需要管理员权限，且变更对新会话生效。

| 引擎 | SET GLOBAL 语法 | 持久化语法 | 查看语法 | 典型变量 | 版本 |
|------|----------------|-----------|---------|---------|------|
| PostgreSQL | `ALTER SYSTEM SET param = val` | 自动写入 `postgresql.auto.conf` | `SHOW param` / `pg_settings` | shared_buffers, max_connections | 9.4+ |
| MySQL | `SET GLOBAL var = val` | `SET PERSIST var = val`（8.0+） | `SHOW GLOBAL VARIABLES` | max_connections, innodb_buffer_pool_size | 3.23+ |
| MariaDB | `SET GLOBAL var = val` | 无 PERSIST（需改配置文件） | `SHOW GLOBAL VARIABLES` | max_connections, innodb_buffer_pool_size | 5.1+ |
| SQLite | `PRAGMA name = val`（部分为数据库级） | 编译时宏 | `PRAGMA name` | page_size, cache_size | 3.0+ |
| Oracle | `ALTER SYSTEM SET param = val` | `SCOPE=SPFILE/BOTH/MEMORY` | `SHOW PARAMETER` / `V$PARAMETER` | processes, sga_target | 7.0+ |
| SQL Server | `sp_configure 'option', val; RECONFIGURE` | 自动持久化 | `sp_configure` / `sys.configurations` | max server memory, max degree of parallelism | 2000+ |
| DB2 | `UPDATE DBM CFG USING param val` | 自动持久化 | `GET DBM CFG` / `GET DB CFG` | SHEAPTHRES, MAXLOCKS | 7.0+ |
| Snowflake | `ALTER ACCOUNT SET param = val` | 自动持久化 | `SHOW PARAMETERS IN ACCOUNT` | NETWORK_POLICY, STATEMENT_TIMEOUT_IN_SECONDS | GA |
| BigQuery | 项目/数据集设置（无 SET GLOBAL） | API / Console | 无 SQL 级查看 | 通过 API 配置 | — |
| Redshift | `ALTER USER ... SET param` / 参数组 | 参数组持久化 | `SHOW param` / `pg_settings` | wlm_json_configuration | GA |
| DuckDB | `SET GLOBAL param = val`（进程级） | 无持久化 | `SELECT current_setting('param')` | memory_limit, threads | 0.8+ |
| ClickHouse | `SET param = val`（server 配置 XML） | 配置文件 / `profiles` | `SHOW SETTINGS` / `system.settings` | max_threads, max_memory_usage | 18.1+ |
| Trino | 配置文件（无 SET GLOBAL） | `config.properties` | `SHOW SESSION` | 通过配置文件 | — |
| Presto | 配置文件（无 SET GLOBAL） | `config.properties` | `SHOW SESSION` | 通过配置文件 | — |
| Spark SQL | `SET spark.conf = val`（driver 级） | `spark-defaults.conf` | `SET` | spark.sql.adaptive.enabled | 1.0+ |
| Hive | `SET param = val`（Metastore 配置） | `hive-site.xml` | `SET` | hive.exec.parallel | 0.2+ |
| Flink SQL | 配置文件 `flink-conf.yaml` | 配置文件 | `SET` | taskmanager.memory.process.size | 1.0+ |
| Databricks | Cluster 配置 | Cluster 配置持久化 | `SET` | spark.sql.shuffle.partitions | GA |
| Teradata | `DATABASE dbc; MODIFY SYSTEM` | 自动持久化 | `HELP SESSION` / DBC 表 | MaxSpool, DefaultAccount | V2R5+ |
| Greenplum | `ALTER SYSTEM SET param = val`（PG 兼容） | `postgresql.auto.conf` | `SHOW param` / `pg_settings` | gp_vmem_protect_limit | 5.0+ |
| CockroachDB | `SET CLUSTER SETTING param = val` | 自动持久化 | `SHOW CLUSTER SETTING param` | server.time_until_store_dead | 1.0+ |
| TiDB | `SET GLOBAL var = val` | 写入 mysql.global_variables | `SHOW GLOBAL VARIABLES` | tidb_distsql_scan_concurrency | 2.0+ |
| OceanBase | `SET GLOBAL var = val` | 自动持久化 | `SHOW GLOBAL VARIABLES` | ob_query_timeout | 3.0+ |
| YugabyteDB | `SET param = val`（gflag） | `yb-tserver --flagfile` | `SHOW param` | yb_enable_expression_pushdown | 2.0+ |
| SingleStore | `SET GLOBAL var = val` | `SET PERSIST var = val`（8.5+） | `SHOW GLOBAL VARIABLES` | max_connections, default_partitions_per_leaf | 6.0+ |
| Vertica | `ALTER DATABASE db SET param = val` | 自动持久化 | `SHOW param` | MaxClientSessions, MemorySize | 7.0+ |
| Impala | 配置文件 / `--flagfile` | 配置文件 | `SET ALL` | mem_limit, num_scanner_threads | 1.0+ |
| StarRocks | `SET GLOBAL var = val`（Admin 需要 FE 配置修改） | 写入 FE 配置 | `SHOW GLOBAL VARIABLES` | parallel_fragment_exec_instance_num | 2.0+ |
| Doris | `SET GLOBAL var = val` | 写入 FE 元数据 | `SHOW GLOBAL VARIABLES` | exec_mem_limit | 0.12+ |
| MonetDB | `monetdb set param=val dbname`（CLI） | 自动持久化 | `SELECT * FROM sys.env()` | max_clients, gdk_nr_threads | 11.0+ |
| CrateDB | `SET GLOBAL param = val` | `SET GLOBAL PERSISTENT` | `SHOW param` | stats.enabled, cluster.routing | 4.0+ |
| TimescaleDB | `ALTER SYSTEM SET param = val`（继承 PG） | `postgresql.auto.conf` | `SHOW param` | timescaledb.max_background_workers | 继承 PG |
| QuestDB | 配置文件 `server.conf` | 配置文件 | 无 SQL 级 | cairo.commit.lag, shared.worker.count | — |
| Exasol | `ALTER SYSTEM SET param = val` | 自动持久化 | 系统表查询 | NLS_DATE_FORMAT | 6.0+ |
| SAP HANA | `ALTER SYSTEM ALTER CONFIGURATION ...` | 自动持久化 | `M_INIFILE_CONTENTS` 系统视图 | global_allocation_limit | 1.0+ |
| Informix | `onmode -wf param=val` | 自动持久化 | `onstat -g cfg` | LOCKS, BUFFERS | 7.0+ |
| Firebird | `firebird.conf` 修改 | 配置文件 | `RDB$GET_CONTEXT('SYSTEM', ...)` | DefaultDbCachePages, TempCacheLimit | 1.5+ |
| H2 | `SET param val`（数据库级） | 写入数据库 | `SHOW param` | MAX_MEMORY_ROWS, LOCK_TIMEOUT | 1.0+ |
| HSQLDB | `SET DATABASE param val` | 写入 `.properties` | `SELECT * FROM information_schema.system_properties` | FILES_SCALE, RESULT_MEMORY_ROWS | 2.0+ |
| Derby | `CALL SYSCS_UTIL.SYSCS_SET_DATABASE_PROPERTY(...)` | 自动持久化 | `VALUES SYSCS_UTIL.SYSCS_GET_DATABASE_PROPERTY(...)` | derby.database.defaultConnectionMode | 10.0+ |
| Amazon Athena | 工作组设置 | API 持久化 | 无 SQL 级 | 通过 Workgroup 管理 | — |
| Azure Synapse | `sp_configure`（部分 T-SQL 兼容） | — | `sp_configure` | — | GA |
| Google Spanner | 实例配置（无 SET GLOBAL） | API 持久化 | 无 SQL 级 | 通过 API 管理 | — |
| Materialize | 无全局变量 | — | — | 通过配置文件 | — |
| RisingWave | `ALTER SYSTEM SET param = val` | 自动持久化 | `SHOW param` | streaming_parallelism | 1.0+ |
| InfluxDB | 配置文件 `influxdb.conf` | 配置文件 | 无 SQL 级 | max-concurrent-queries | — |
| Databend | `SET GLOBAL param = val` | Meta Service 持久化 | `SHOW SETTINGS` | max_threads, storage_format | 0.8+ |
| Yellowbrick | `ALTER SYSTEM SET param = val` | 自动持久化 | `SHOW param` | 连接与资源参数 | GA |
| Firebolt | 引擎参数（无 SET GLOBAL） | 引擎配置 | 无 SQL 级 | 通过引擎设置 | — |

### SET 语句语法变体

不同引擎的 SET 语句语法存在微妙但关键的差异：

| 引擎 | SET 基本语法 | 多变量同时设置 | 赋值运算符 | 值引用 | 特殊形式 |
|------|-------------|--------------|-----------|--------|---------|
| PostgreSQL | `SET param TO val` / `SET param = val` | 每条一个 | `=` / `TO` | 字符串用引号 | `SET LOCAL`（事务级） |
| MySQL | `SET var = val` / `SET @@var = val` | `SET a=1, b=2` | `=` / `:=` | 按类型 | `SET @@SESSION.` / `SET @@GLOBAL.` |
| MariaDB | `SET var = val` | `SET a=1, b=2` | `=` / `:=` | 按类型 | `SET STATEMENT var=val FOR stmt` |
| SQLite | `PRAGMA name = val` | 每条一个 | `=` | 无需引号 | `PRAGMA name(val)` |
| Oracle | `ALTER SESSION SET param = val` | 每条一个 | `=` | 按类型 | 无 SET 关键字 |
| SQL Server | `SET @var = expr` / `SET option ON\|OFF` | 每条一个 | `=` | 按类型 | `SET NOCOUNT ON` / `SET XACT_ABORT ON` |
| DB2 | `SET var = val` | `SET (a, b) = (1, 2)` | `=` | 按类型 | `SET CURRENT SCHEMA = 'name'` |
| Snowflake | `SET var = expr` | 每条一个 | `=` | 按类型 | `UNSET var` |
| BigQuery | `SET var = expr` | 每条一个 | `=` | 按类型 | `SET @@param = val` |
| Redshift | `SET param TO val` / `SET param = val` | 每条一个 | `=` / `TO` | 字符串用引号 | `RESET param` |
| DuckDB | `SET param = val` | 每条一个 | `=` | 按类型 | `RESET param` |
| ClickHouse | `SET param = val` | `SET a=1, b=2` | `=` | 按类型 | `SETTINGS` 子句（查询级） |
| Trino | `SET SESSION prop = val` | 每条一个 | `=` | 按类型 | `RESET SESSION prop` |
| CockroachDB | `SET param = val` / `SET param TO val` | 每条一个 | `=` / `TO` | 按类型 | `RESET param` |
| TiDB | `SET [SESSION\|GLOBAL] var = val` | `SET a=1, b=2` | `=` | 按类型 | `SET @@var = val` |
| Hive | `SET param = val` | 每条一个 | `=` | 字符串 | `RESET` 全部重置 |
| SAP HANA | `SET 'key' = 'val'` | 每条一个 | `=` | 字符串 | `UNSET 'key'` |
| Firebird | `SET TERM ^;`（isql 工具）| — | — | — | 多为工具级命令 |

### SHOW VARIABLES / SHOW PARAMETERS

| 引擎 | 查看全部会话参数 | 查看单个参数 | 过滤语法 | 系统视图 |
|------|----------------|-------------|---------|---------|
| PostgreSQL | `SHOW ALL` | `SHOW param` | 无 LIKE | `pg_settings` |
| MySQL | `SHOW [SESSION] VARIABLES` | `SELECT @@var` | `LIKE 'pattern'` | `performance_schema.session_variables` |
| MariaDB | `SHOW [SESSION] VARIABLES` | `SELECT @@var` | `LIKE 'pattern'` | `information_schema.SESSION_VARIABLES` |
| SQLite | 无 | `PRAGMA name` | — | — |
| Oracle | `SHOW PARAMETER`（SQL*Plus） | `SHOW PARAMETER name` | 模糊匹配 | `V$PARAMETER` / `V$NLS_PARAMETERS` |
| SQL Server | `DBCC USEROPTIONS` | `SELECT @@option` | — | `sys.configurations` |
| DB2 | `GET DB CFG` | `VALUES CURRENT param` | — | `SYSIBMADM.DBCFG` |
| Snowflake | `SHOW PARAMETERS IN SESSION` | `SHOW PARAMETERS LIKE 'name' IN SESSION` | `LIKE` | `INFORMATION_SCHEMA.PARAMETERS`（表函数） |
| BigQuery | 无通用 SHOW | `SELECT @@var` | — | — |
| Redshift | `SHOW ALL` | `SHOW param` | 无 LIKE | `pg_settings`（部分） |
| DuckDB | `SELECT * FROM duckdb_settings()` | `SELECT current_setting('param')` | SQL WHERE | `duckdb_settings()` |
| ClickHouse | `SHOW SETTINGS` | `SELECT getSetting('name')` | `LIKE 'pattern'` | `system.settings` |
| Trino | `SHOW SESSION` | — | `LIKE 'pattern'` | — |
| Presto | `SHOW SESSION` | — | `LIKE 'pattern'` | — |
| Spark SQL | `SET` 不带参数 | `SET param`（仅显示） | — | — |
| Hive | `SET` 不带参数 | `SET param` | — | — |
| Flink SQL | `SET` 不带参数 | — | — | — |
| CockroachDB | `SHOW ALL` | `SHOW param` | — | `crdb_internal.session_variables` |
| TiDB | `SHOW [SESSION] VARIABLES` | `SELECT @@var` | `LIKE 'pattern'` | `information_schema.SESSION_VARIABLES` |
| OceanBase | `SHOW [SESSION] VARIABLES` | `SELECT @@var` | `LIKE 'pattern'` | `information_schema.SESSION_VARIABLES` |
| StarRocks | `SHOW [SESSION] VARIABLES` | `SELECT @@var` | `LIKE 'pattern'` | — |
| Doris | `SHOW [SESSION] VARIABLES` | `SELECT @@var` | `LIKE 'pattern'` | — |
| Impala | `SET` / `SET ALL` | — | — | — |
| Exasol | 查询系统表 | 查询系统表 | SQL WHERE | `EXA_PARAMETERS` |
| SAP HANA | `SELECT * FROM M_SESSION_CONTEXT` | `SELECT SESSION_CONTEXT('key')` | SQL WHERE | `M_SESSION_CONTEXT` |
| Google Spanner | `SHOW VARIABLE var` | `SHOW VARIABLE var` | — | — |

### 连接/会话属性（时区、区域、隔离级别）

| 引擎 | 设置时区 | 设置 Schema/Database | 设置隔离级别 | 设置字符集 |
|------|---------|---------------------|------------|-----------|
| PostgreSQL | `SET timezone = 'UTC'` | `SET search_path TO schema` | `SET default_transaction_isolation` | `SET client_encoding = 'UTF8'` |
| MySQL | `SET time_zone = '+08:00'` | `USE database` | `SET transaction_isolation = '...'`（8.0+） | `SET NAMES 'utf8mb4'` |
| MariaDB | `SET time_zone = '+08:00'` | `USE database` | `SET transaction_isolation = '...'` | `SET NAMES 'utf8mb4'` |
| SQLite | 无（应用层处理） | `ATTACH DATABASE ... AS schema` | 无 | `PRAGMA encoding = 'UTF-8'`（创建时） |
| Oracle | `ALTER SESSION SET TIME_ZONE = 'UTC'` | `ALTER SESSION SET CURRENT_SCHEMA = name` | `SET TRANSACTION ISOLATION LEVEL ...` | `ALTER SESSION SET NLS_CHARACTERSET`（受限） |
| SQL Server | 无原生时区 SET（DATEFIRST/DATEFORMAT） | `USE database` | `SET TRANSACTION ISOLATION LEVEL ...` | 无（数据库级排序规则） |
| DB2 | `SET CURRENT TIMEZONE = val` | `SET CURRENT SCHEMA = 'name'` | `SET CURRENT ISOLATION = val` | 无（数据库级） |
| Snowflake | `ALTER SESSION SET TIMEZONE = 'UTC'` | `USE SCHEMA schema` / `USE DATABASE db` | 无（自动 SI） | 无（UTF-8 固定） |
| BigQuery | `SET @@time_zone = 'UTC'`（脚本内） | `SET @@dataset_id = 'ds'`（脚本内） | 无 | 无（UTF-8 固定） |
| Redshift | `SET timezone TO 'UTC'` | `SET search_path TO schema` | 无（固定 SERIALIZABLE） | `SET client_encoding TO 'UTF8'` |
| DuckDB | `SET timezone = 'UTC'` | `SET search_path = 'schema'`（0.10+） | 无 | 无（UTF-8 固定） |
| ClickHouse | `SET timezone = 'UTC'`（23.3+） | `USE database` | 无 | 无（UTF-8 固定） |
| Trino | `SET SESSION timezone = 'UTC'`（via connector） | `USE schema` / `USE catalog.schema` | 无 | 无 |
| Spark SQL | `SET spark.sql.session.timeZone = 'UTC'` | `USE database` / `USE CATALOG cat` | 无 | 无 |
| Hive | 无原生时区 SET | `USE database` | 无 | 无 |
| CockroachDB | `SET timezone = 'UTC'` | `SET database = name` / `USE name` | `SET default_transaction_isolation` | `SET client_encoding = 'UTF8'` |
| TiDB | `SET time_zone = '+08:00'` | `USE database` | `SET transaction_isolation = '...'` | `SET NAMES 'utf8mb4'` |
| OceanBase | `SET time_zone = '+08:00'` | `USE database` | `SET transaction_isolation = '...'` | `SET NAMES 'utf8mb4'` |
| Teradata | `SET TIME ZONE ...` | `DATABASE dbname` | `SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL ...` | 无 |
| Greenplum | `SET timezone = 'UTC'` | `SET search_path TO schema` | `SET default_transaction_isolation` | `SET client_encoding` |
| SAP HANA | `SET 'TIMEZONE' = 'UTC'` | `SET SCHEMA schema` | `SET TRANSACTION ISOLATION LEVEL ...` | 无（UTF-8 固定） |
| Firebird | 无原生时区 SET（Firebird 4.0+ 有时区类型） | 无（单数据库架构） | `SET TRANSACTION ISOLATION LEVEL ...` | 连接字符串参数 |
| Exasol | `ALTER SESSION SET TIME_ZONE = 'UTC'` | `OPEN SCHEMA schema` | 无 | `ALTER SESSION SET NLS_LANGUAGE` |
| Google Spanner | 无（UTC 固定） | 无（单数据库） | 无（外部一致性固定） | 无（UTF-8 固定） |

### SELECT INTO 变量 / SET var = (SELECT ...)

将查询结果赋值给变量是过程化 SQL 的基本操作，但各引擎的语法差异显著：

| 引擎 | SELECT INTO 变量 | SET = (SELECT) | FETCH INTO | 多行赋值行为 |
|------|-----------------|---------------|-----------|-------------|
| PostgreSQL | `SELECT expr INTO v FROM ...` | 不支持 | `FETCH cur INTO v` | 报错（STRICT 模式） |
| MySQL | `SELECT expr INTO v FROM ...` | `SET v = (SELECT expr)` | `FETCH cur INTO v` | 取最后一行 |
| MariaDB | `SELECT expr INTO v FROM ...` | `SET v = (SELECT expr)` | `FETCH cur INTO v` | 取最后一行 |
| Oracle | `SELECT expr INTO v FROM ...` | 不支持（用 SELECT INTO） | `FETCH cur INTO v` | 抛出 TOO_MANY_ROWS |
| SQL Server | `SELECT @v = expr FROM ...` | `SET @v = (SELECT expr)` | `FETCH cur INTO @v` | SELECT: 取最后一行; SET: 标量子查询报错 |
| DB2 | `SELECT expr INTO v FROM ...` / `SET v = (SELECT expr)` | `SET v = (SELECT expr)` | `FETCH cur INTO v` | 报错 |
| Snowflake | `SELECT expr INTO :v FROM ...`（Scripting） | `LET v := (SELECT expr)` | `FETCH cur INTO v` | 取第一行 |
| BigQuery | 不支持 SELECT INTO | `SET v = (SELECT expr)` | 无游标 | 标量子查询要求单行 |
| Redshift | `SELECT expr INTO v FROM ...` | 不支持 | `FETCH cur INTO v` | 报错 |
| Trino | 不支持 SELECT INTO | `SET v = (SELECT expr)`（419+） | 无游标 | 标量子查询要求单行 |
| Databricks | 不支持 SELECT INTO | `SET VAR v = (SELECT expr)` | 无游标 | 标量子查询要求单行 |
| Teradata | `SELECT expr INTO v FROM ...` | `SET v = (SELECT expr)` | `FETCH cur INTO v` | 报错 |
| SAP HANA | `SELECT expr INTO v FROM ...` | `v = (SELECT expr)` | `FETCH cur INTO v` | 报错 |
| Informix | `SELECT expr INTO v FROM ...` / `LET v = (SELECT expr)` | `LET v = (SELECT expr)` | `FETCH cur INTO v` | 报错 |
| Firebird | `SELECT expr FROM ... INTO :v`（注意: INTO 在末尾） | 不支持 | `FETCH cur INTO v` | 报错 |
| H2 | `SELECT expr INTO v FROM ...` | `SET v = (SELECT expr)` | 不支持 | 取第一行 |

> 注意 Firebird 的特殊语法: `SELECT col FROM table WHERE ... INTO :var`——INTO 子句放在语句末尾而非 SELECT 与 FROM 之间。这在 PSQL（Firebird 的过程化 SQL）中是唯一正确的语法。

### 数组变量与表变量 (Array / Table Variables)

| 引擎 | 数组变量 | 表变量 | 集合类型 | 版本 |
|------|---------|--------|---------|------|
| PostgreSQL | `DECLARE a INT[]` | 无原生表变量（用临时表替代） | 数组、复合类型 | 7.0+ |
| MySQL | 无 | 无 | 无 | — |
| MariaDB | 无 | 无 | 无 | — |
| Oracle | `TYPE arr IS TABLE OF ...` / `VARRAY` | 无（PL/SQL 集合替代） | TABLE / VARRAY / 关联数组 | 8i+ |
| SQL Server | 无原生数组 | `DECLARE @t TABLE (...)` | 表变量、TVP | 2000+ |
| DB2 | `DECLARE a INT ARRAY[100]` | 无原生表变量 | ARRAY（SQL:2003 兼容） | 9.5+ |
| Snowflake | `LET a := ARRAY_CONSTRUCT(1,2,3)` | 无 | ARRAY / OBJECT（VARIANT 子类型） | GA |
| BigQuery | `DECLARE a ARRAY<INT64>` | 无 | ARRAY / STRUCT | GA |
| Redshift | 无 | 无 | 无（SUPER 类型可模拟） | — |
| DuckDB | 无过程化变量 | 无 | LIST / STRUCT / MAP（查询级） | 0.3+ |
| ClickHouse | 无过程化变量 | 无 | Array(T)（查询级） | — |
| Trino | `DECLARE a ARRAY(INTEGER)` | 无 | ARRAY / MAP / ROW（419+） | 419+ |
| Teradata | 无原生数组变量 | 无 | ARRAY / VARRAY（数据类型） | TD 14+ |
| SAP HANA | `DECLARE a INT ARRAY` | `DECLARE t TABLE (...)` | ARRAY / TABLE TYPE | SPS09+ |
| Exasol | 无 | 无 | 无 | — |
| Firebird | 无 | 无 | 无 | — |
| H2 | 无原生数组变量 | 无 | ARRAY（列类型） | 2.0+ |

> SQL Server 的表变量 `DECLARE @t TABLE (col1 INT, col2 VARCHAR(50))` 是独有的特性。表变量在内存中创建，事务回滚不影响表变量，且不会触发重编译。但对于大数据量（超过约 100 行），临时表通常有更好的统计信息和查询计划。

### 变量作用域规则 (Variable Scoping)

| 引擎 | 作用域模型 | 嵌套块访问外层变量 | 同名变量遮蔽 | 事务回滚影响变量 |
|------|----------|------------------|------------|----------------|
| PostgreSQL | 块作用域 | ✅ 可读写 | ✅ 内层遮蔽外层 | ❌ 变量不受回滚影响 |
| MySQL | 块作用域 | ✅ 可读写 | ✅ 内层遮蔽外层 | ❌ 变量不受回滚影响 |
| MariaDB | 块作用域 | ✅ 可读写 | ✅ 内层遮蔽外层 | ❌ 变量不受回滚影响 |
| Oracle | 块作用域 | ✅ 可读写 | ✅（可用 `<<label>>.var` 引用外层） | ❌ 变量不受回滚影响 |
| SQL Server | 批处理级 | ✅（同一批处理内） | ❌ 同一批处理不允许重复声明 | ❌ 变量不受回滚影响 |
| DB2 | 块作用域 | ✅ 可读写 | ✅（可用 label.var 引用外层） | ❌ 变量不受回滚影响 |
| Snowflake | 块作用域 | ✅ 可读写 | ✅ 内层遮蔽外层 | ❌ 变量不受回滚影响 |
| BigQuery | 脚本/块作用域 | ✅ 可读写 | ✅ 内层遮蔽外层 | ❌ 变量不受回滚影响 |
| Redshift | 块作用域 | ✅ 可读写 | ✅ 内层遮蔽外层 | ❌ 变量不受回滚影响 |
| Trino | 块作用域 | ✅ 可读写 | ✅ 内层遮蔽外层 | — |
| Databricks | 块作用域 | ✅ 可读写 | ✅ 内层遮蔽外层 | ❌ 变量不受回滚影响 |
| Teradata | 过程作用域 | ✅ 可读写 | ✅ 内层遮蔽外层 | ❌ 变量不受回滚影响 |
| SAP HANA | 块作用域 | ✅ 可读写 | ✅ 内层遮蔽外层 | ❌ 变量不受回滚影响 |
| Informix | 过程作用域 | ✅ 可读写 | ❌ SPL 不支持块级变量 | ❌ 变量不受回滚影响 |
| Firebird | 过程作用域 | ✅（过程内全局） | ❌ PSQL 变量在过程头声明 | ❌ 变量不受回滚影响 |
| CockroachDB | 块作用域 | ✅ 可读写 | ✅ 内层遮蔽外层 | ❌ 变量不受回滚影响 |

> **关键观察**: 几乎所有引擎的变量都不受事务回滚影响。变量是会话/块级状态，独立于事务控制。SQL Server 的表变量也具有这一特性——`ROLLBACK` 不会撤销对表变量的修改。

## 各引擎详细语法

### PostgreSQL

PostgreSQL 没有原生的用户变量语法，但提供了多种替代方案：

```sql
-- 方法 1: GUC 自定义参数（9.2+，需要带命名空间前缀）
SET myapp.current_user_id = '42';
SELECT current_setting('myapp.current_user_id');  -- '42'（返回 text 类型）

-- 方法 2: PL/pgSQL 局部变量
DO $$
DECLARE
    v_count INTEGER := 0;
    v_name  TEXT;
BEGIN
    SELECT count(*) INTO v_count FROM users WHERE active;
    SELECT username INTO STRICT v_name FROM users WHERE id = 1;  -- STRICT: 必须恰好一行
    RAISE NOTICE 'Count: %, Name: %', v_count, v_name;
END $$;

-- 方法 3: CTE 模拟变量
WITH params AS (
    SELECT 42 AS user_id, '2024-01-01'::date AS start_date
)
SELECT * FROM orders, params WHERE orders.user_id = params.user_id;

-- 会话参数
SET search_path TO myschema, public;
SET timezone = 'Asia/Shanghai';
SET statement_timeout = '30s';
SET work_mem = '256MB';
SHOW search_path;
SHOW ALL;

-- 事务级参数（仅在当前事务有效）
BEGIN;
SET LOCAL work_mem = '1GB';        -- 仅当前事务有效
SET LOCAL statement_timeout = '5min';
COMMIT;  -- 参数恢复为会话级值

-- RESET 恢复默认值
RESET work_mem;
RESET ALL;
```

### MySQL

MySQL 拥有最完整的用户变量系统：

```sql
-- 用户变量（会话级，无需声明，动态类型）
SET @user_id = 42;
SET @name = 'Alice';
SET @rate = 3.14;
SELECT @user_id, @name, @rate;

-- SELECT 中赋值（:= 运算符）
SELECT @row_num := @row_num + 1 AS row_num, name
FROM users, (SELECT @row_num := 0) AS init;
-- 注: MySQL 8.0+ 推荐使用窗口函数 ROW_NUMBER() 替代此模式

-- 多变量同时赋值
SET @a = 1, @b = 2, @c = @a + @b;

-- 存储过程中的局部变量
DELIMITER //
CREATE PROCEDURE get_user_stats(IN p_user_id INT)
BEGIN
    DECLARE v_order_count INT DEFAULT 0;
    DECLARE v_total_amount DECIMAL(10,2);

    SELECT COUNT(*), SUM(amount)
    INTO v_order_count, v_total_amount
    FROM orders WHERE user_id = p_user_id;

    SELECT v_order_count AS order_count, v_total_amount AS total;
END //
DELIMITER ;

-- 会话变量 vs 全局变量
SET SESSION wait_timeout = 28800;
SET GLOBAL max_connections = 200;
SET PERSIST max_connections = 200;       -- 8.0+: 持久化到 mysqld-auto.cnf
SET PERSIST_ONLY max_connections = 200;  -- 8.0+: 仅持久化，不改当前值

-- 查看变量
SHOW SESSION VARIABLES LIKE 'wait%';
SHOW GLOBAL VARIABLES LIKE 'max_conn%';
SELECT @@session.wait_timeout;
SELECT @@global.max_connections;

-- 系统变量的 @@ 前缀规则
SELECT @@version;           -- 全局只读变量
SELECT @@sql_mode;           -- 先找 SESSION，再找 GLOBAL
SELECT @@session.sql_mode;   -- 显式指定 SESSION
SELECT @@global.sql_mode;    -- 显式指定 GLOBAL
```

### Oracle

Oracle 的变量管理分为 PL/SQL 和 SQL*Plus 两个层面：

```sql
-- PL/SQL 块内变量
DECLARE
    v_emp_name   VARCHAR2(100);
    v_salary     NUMBER(10,2) := 0;
    v_hire_date  DATE;
    TYPE t_names IS TABLE OF VARCHAR2(100) INDEX BY PLS_INTEGER;  -- 关联数组
    v_names      t_names;
BEGIN
    SELECT ename, sal, hiredate
    INTO v_emp_name, v_salary, v_hire_date
    FROM emp WHERE empno = 7369;

    v_names(1) := 'Alice';
    v_names(2) := 'Bob';

    DBMS_OUTPUT.PUT_LINE(v_emp_name || ': ' || v_salary);
END;
/

-- 包变量（会话级持久变量）
CREATE OR REPLACE PACKAGE session_vars AS
    g_user_id   NUMBER;
    g_app_name  VARCHAR2(50);
END;
/
-- 使用
BEGIN session_vars.g_user_id := 42; END;
/
SELECT session_vars.g_user_id FROM dual;  -- 需要包装函数

-- SQL*Plus 变量（工具级）
VARIABLE g_count NUMBER;
EXEC :g_count := 100;
PRINT g_count;

DEFINE myvar = 'hello';
SELECT '&myvar' FROM dual;

-- 会话参数
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS';
ALTER SESSION SET TIME_ZONE = '+08:00';
ALTER SESSION SET CURRENT_SCHEMA = hr;
ALTER SESSION SET OPTIMIZER_MODE = ALL_ROWS;

-- 查看参数
SHOW PARAMETER optimizer;
SELECT name, value FROM V$PARAMETER WHERE name LIKE 'optimizer%';
SELECT * FROM NLS_SESSION_PARAMETERS;

-- 应用上下文（细粒度会话状态）
BEGIN
    DBMS_SESSION.SET_CONTEXT('myapp_ctx', 'user_role', 'admin');
END;
/
SELECT SYS_CONTEXT('myapp_ctx', 'user_role') FROM dual;  -- 'admin'
SELECT SYS_CONTEXT('USERENV', 'SESSION_USER') FROM dual;  -- 当前用户
```

### SQL Server

SQL Server 的变量体系基于 T-SQL 批处理模型：

```sql
-- 局部变量（批处理作用域，静态类型，必须声明）
DECLARE @user_id INT = 42;
DECLARE @name NVARCHAR(100);
DECLARE @today DATE = GETDATE();

SET @name = N'Alice';  -- SET 赋值（推荐，标量子查询多行报错）

-- SELECT 赋值（多行时取最后一行，不报错）
SELECT @name = username FROM users WHERE id = @user_id;

-- 多变量声明
DECLARE @a INT = 1, @b INT = 2, @c INT;
SET @c = @a + @b;

-- 表变量
DECLARE @orders TABLE (
    order_id   INT PRIMARY KEY,
    amount     DECIMAL(10,2),
    order_date DATE
);
INSERT INTO @orders SELECT order_id, amount, order_date
FROM orders WHERE customer_id = @user_id;

SELECT * FROM @orders;  -- 可像表一样查询

-- SET 选项（影响会话行为）
SET NOCOUNT ON;                           -- 不返回影响行数消息
SET XACT_ABORT ON;                        -- 错误时自动回滚事务
SET ANSI_NULLS ON;                        -- NULL 比较遵循 ANSI 标准
SET QUOTED_IDENTIFIER ON;                 -- 双引号为标识符引用
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;  -- 设置隔离级别

-- 全局变量（系统函数，@@前缀，只读）
SELECT @@VERSION;
SELECT @@SERVERNAME;
SELECT @@SPID;              -- 当前会话 ID
SELECT @@ROWCOUNT;           -- 上一条语句影响的行数
SELECT @@TRANCOUNT;          -- 嵌套事务深度
SELECT @@ERROR;              -- 上一条语句的错误号
SELECT @@IDENTITY;           -- 最后插入的 IDENTITY 值

-- sp_configure（服务器级）
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'max degree of parallelism', 4;
RECONFIGURE;
```

### Snowflake

Snowflake 提供会话变量和 Snowflake Scripting 局部变量两套体系：

```sql
-- 会话变量（SET/UNSET，$引用）
SET my_db = 'PRODUCTION';
SET my_date = '2024-01-01';
SET my_threshold = 100;

SELECT * FROM IDENTIFIER($my_db || '.schema.table')
WHERE created_date > $my_date::DATE
  AND amount > $my_threshold;

-- 查看会话变量
SHOW VARIABLES;  -- 显示用户定义的会话变量

-- Snowflake Scripting 局部变量
DECLARE
    v_count INTEGER DEFAULT 0;
    v_name  VARCHAR;
    v_result RESULTSET;
BEGIN
    LET v_count := (SELECT COUNT(*) FROM orders);
    LET v_name := 'test';

    -- RESULTSET 变量
    LET v_result := (SELECT * FROM orders WHERE amount > :v_count);
    RETURN TABLE(v_result);
END;

-- 会话参数
ALTER SESSION SET TIMEZONE = 'UTC';
ALTER SESSION SET DATE_INPUT_FORMAT = 'YYYY-MM-DD';
ALTER SESSION SET QUERY_TAG = 'batch_job_123';
ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = 3600;

-- 查看参数
SHOW PARAMETERS IN SESSION;
SHOW PARAMETERS LIKE 'TIMEZONE' IN SESSION;
SHOW PARAMETERS IN ACCOUNT;

-- UNSET 恢复默认值
ALTER SESSION UNSET TIMEZONE;
UNSET my_db;  -- 取消会话变量
```

### BigQuery

BigQuery 的变量仅在脚本中可用，不支持交互式会话变量：

```sql
-- 脚本级变量（必须在 BEGIN 块或脚本顶层声明）
DECLARE project_id STRING DEFAULT 'my-project';
DECLARE start_date DATE DEFAULT DATE '2024-01-01';
DECLARE row_count INT64;
DECLARE total_amount NUMERIC;

-- 赋值
SET row_count = (SELECT COUNT(*) FROM `dataset.orders`);
SET (row_count, total_amount) = (
    SELECT AS STRUCT COUNT(*), SUM(amount)
    FROM `dataset.orders`
    WHERE order_date >= start_date
);

-- 系统变量（@@前缀）
SET @@time_zone = 'Asia/Shanghai';
SET @@dataset_id = 'my_dataset';

-- 在查询中引用
SELECT * FROM orders WHERE amount > row_count;
SELECT @@time_zone;
SELECT @@script.bytes_processed;  -- 脚本执行统计

-- 数组变量
DECLARE ids ARRAY<INT64> DEFAULT [1, 2, 3, 4, 5];
SELECT * FROM users WHERE user_id IN UNNEST(ids);

-- 变量作用域
BEGIN
    DECLARE outer_var INT64 DEFAULT 10;
    BEGIN
        DECLARE inner_var INT64 DEFAULT 20;
        SET outer_var = outer_var + inner_var;  -- 可以访问外层变量
    END;
    -- inner_var 在此处不可见
    SELECT outer_var;  -- 30
END;
```

### DuckDB

DuckDB 从 0.10 版本开始支持会话变量：

```sql
-- 会话变量（0.10+）
SET VARIABLE my_id = 42;
SET VARIABLE my_name = 'Alice';
SET VARIABLE my_list = [1, 2, 3];

-- 在查询中引用（使用 getvariable 函数）
SELECT * FROM users WHERE id = getvariable('my_id');
SELECT getvariable('my_name');

-- 配置参数
SET threads = 4;
SET memory_limit = '4GB';
SET search_path = 'main,pg_catalog';
SET timezone = 'UTC';

RESET threads;              -- 恢复默认值
SELECT current_setting('threads');

-- PRAGMA 语法（兼容）
PRAGMA threads = 4;
PRAGMA database_list;
PRAGMA show_tables;

-- 查看所有设置
SELECT * FROM duckdb_settings();
```

### ClickHouse

ClickHouse 的变量管理聚焦于查询设置：

```sql
-- 查询设置（SET 语句，会话级）
SET max_threads = 4;
SET max_memory_usage = 10000000000;  -- 10GB
SET allow_experimental_analyzer = 1;

-- 查询级设置（SETTINGS 子句，不影响会话）
SELECT * FROM large_table
SETTINGS max_threads = 8, max_memory_usage = 20000000000;

-- 查看设置
SHOW SETTINGS LIKE 'max_thread%';
SELECT name, value, changed FROM system.settings WHERE name LIKE 'max%';
SELECT getSetting('max_threads');

-- 查询参数（21.1+，参数化查询）
SET param_user_id = 42;
SET param_start_date = '2024-01-01';
SELECT * FROM orders
WHERE user_id = {user_id:UInt32}
  AND order_date >= {start_date:Date};

-- 配置 profile
SET profile = 'readonly';  -- 切换到预定义配置集

-- USE database
USE analytics;
SELECT currentDatabase();
```

### Trino

```sql
-- 会话属性
SET SESSION query_max_memory = '10GB';
SET SESSION join_distribution_type = 'PARTITIONED';
SET SESSION task_concurrency = 8;

-- 目录级会话属性
SET SESSION hive.insert_existing_partitions_behavior = 'OVERWRITE';

-- 查看会话
SHOW SESSION;
SHOW SESSION LIKE 'query%';

-- 重置
RESET SESSION query_max_memory;

-- 切换 catalog/schema
USE hive.production;
USE iceberg.analytics;

-- SQL routine 局部变量（419+）
CREATE FUNCTION my_func(x INTEGER)
RETURNS INTEGER
BEGIN
    DECLARE result INTEGER DEFAULT 0;
    SET result = x * 2;
    RETURN result;
END;
```

### Hive

```sql
-- 配置参数
SET hive.exec.parallel = true;
SET hive.exec.parallel.thread.number = 8;
SET mapred.reduce.tasks = 10;

-- Hive 变量（hivevar 命名空间）
SET hivevar:my_date = '2024-01-01';
SET hivevar:my_db = 'production';

-- 在查询中引用
SELECT * FROM ${hivevar:my_db}.orders
WHERE order_date >= '${hivevar:my_date}';

-- 查看所有配置
SET;      -- 当前已修改的配置
SET -v;   -- 所有配置（包括默认值）

-- 命名空间
SET system:user.name;     -- 系统属性
SET env:HOME;             -- 环境变量
SET hiveconf:param;       -- Hive 配置
SET hivevar:param;        -- 用户变量

-- USE database
USE production;
```

### Flink SQL

```sql
-- 配置参数（键必须用单引号）
SET 'pipeline.name' = 'my_flink_job';
SET 'table.exec.state.ttl' = '3600000';  -- 毫秒
SET 'parallelism.default' = '4';
SET 'table.exec.mini-batch.enabled' = 'true';

-- 查看配置
SET;  -- 显示所有已设置的配置

-- 重置
RESET 'pipeline.name';
RESET;  -- 重置全部

-- USE database/catalog
USE CATALOG my_catalog;
USE my_database;
```

### CockroachDB

```sql
-- 会话变量（PG 兼容语法）
SET database = 'mydb';
SET timezone = 'UTC';
SET default_transaction_isolation = 'serializable';
SET application_name = 'my_app';

-- CockroachDB 特有会话变量
SET experimental_enable_hash_sharded_indexes = true;
SET enable_zigzag_join = true;

-- 集群设置（全局）
SET CLUSTER SETTING server.time_until_store_dead = '5m0s';
SET CLUSTER SETTING kv.snapshot_rebalance.max_rate = '64MiB';

-- 查看
SHOW database;
SHOW ALL;
SHOW CLUSTER SETTING server.time_until_store_dead;
SHOW ALL CLUSTER SETTINGS;

-- 重置
RESET database;
RESET ALL;
```

### Spark SQL / Databricks

```sql
-- Spark SQL 配置参数
SET spark.sql.shuffle.partitions = 200;
SET spark.sql.adaptive.enabled = true;
SET spark.sql.session.timeZone = 'UTC';

-- 查看
SET;           -- 已修改的配置
SET -v;         -- 所有配置

-- Databricks SQL Scripting（DBR 14+）
DECLARE OR REPLACE v_count INT DEFAULT 0;
DECLARE OR REPLACE v_name STRING;

SET VAR v_count = (SELECT COUNT(*) FROM orders);
SET VAR v_name = 'test';

-- Databricks IDENTIFIER 参数化
SET spark.sql.variable.myschema = 'production';
SELECT * FROM IDENTIFIER(spark.sql.variable.myschema || '.orders');

-- USE DATABASE / CATALOG
USE CATALOG unity_catalog;
USE DATABASE production;
```

## 无服务器/云引擎的会话管理

无服务器（Serverless）和云原生引擎面临一个根本性挑战：传统的长连接会话模型与无服务器的按需执行模型存在矛盾。各引擎采取了不同策略：

### BigQuery：脚本即会话

BigQuery 没有传统意义上的"会话"。每个查询提交到服务端独立执行，无状态连接。

```sql
-- 变量仅在脚本块内有效
BEGIN
    DECLARE threshold FLOAT64 DEFAULT 100.0;
    CREATE TEMP TABLE filtered AS
    SELECT * FROM orders WHERE amount > threshold;

    SELECT COUNT(*) FROM filtered;
END;
-- 脚本结束后，threshold 和 filtered 均不可用
```

- **会话模式**（2022 GA）: BigQuery 引入了会话支持。通过 `bq query --create_session` 创建会话，后续查询可引用会话内的临时表和变量
- **系统变量**: `@@time_zone`、`@@dataset_id` 等仅在脚本内通过 SET 设置
- **核心限制**: 无 `SET SESSION`、无 `SHOW VARIABLES`、无 `ALTER SESSION`

### Amazon Athena：无状态查询引擎

Athena 基于 Trino/Presto，是纯无状态引擎：

```sql
-- 无 SET 语法、无变量
-- 所有配置通过 Workgroup 管理
-- 预处理语句是唯一的参数化方式
PREPARE my_query FROM SELECT * FROM orders WHERE status = ?;
EXECUTE my_query USING 'shipped';
DEALLOCATE PREPARE my_query;
```

- **Workgroup**: 替代会话参数的机制，设置查询超时、结果位置、扫描限制等
- **无临时状态**: 每次查询独立执行，无法跨查询共享状态
- **Athena v3**（基于 Trino）: 开始支持部分 `SET SESSION` 语法，但仅限引擎选项

### Google Spanner：全球一致性优先

Spanner 的设计目标是全球一致性，会话管理极简：

```sql
-- 有限的会话级设置
SET STATEMENT_TIMEOUT = '30s';
SET READ_ONLY_STALENESS = 'EXACT_STALENESS 10s';  -- 读取一致性
SET AUTOCOMMIT = false;

SHOW VARIABLE STATEMENT_TIMEOUT;
SHOW VARIABLE COMMIT_TIMESTAMP;

-- 无用户变量、无 SET GLOBAL
-- 所有参数通过客户端库绑定
```

- **无过程化 SQL**: 无存储过程、无局部变量
- **参数化查询**: 通过客户端 API 绑定参数，而非 SQL 级变量
- **实例配置**: 通过 API / Console 管理，不暴露 SQL 级设置

### Azure Synapse：混合模型

Azure Synapse 分为 Dedicated Pool（传统数仓）和 Serverless Pool（无服务器），会话管理有所不同：

```sql
-- Dedicated Pool：完整 T-SQL 会话支持
DECLARE @cutoff DATE = '2024-01-01';
SET NOCOUNT ON;
SET ANSI_NULLS ON;

-- Serverless Pool：受限的 T-SQL
-- 支持 DECLARE/SET，但无持久会话状态
-- 每次查询可能路由到不同节点
```

### Snowflake：有状态的云仓库

Snowflake 是少数在云原生架构上提供完整会话状态的引擎：

```sql
-- 完整的会话变量支持
SET warehouse_name = 'COMPUTE_WH';
USE WAREHOUSE IDENTIFIER($warehouse_name);

-- 会话可跨多个查询保持状态
ALTER SESSION SET QUERY_TAG = 'analytics_batch';
-- 后续所有查询都带有此 tag，直到 UNSET 或会话结束
```

- **会话持久性**: Snowflake 维护有状态会话，变量和参数在会话内保持
- **自动暂停/恢复**: 仓库暂停不影响会话状态
- **会话超时**: 默认 4 小时不活动后关闭会话

### Firebolt：引擎级参数

```sql
-- 配置通过引擎设置管理
SET time_zone = 'UTC';
SET max_result_rows = 10000;

-- 无用户变量、无存储过程
-- 引擎参数在引擎创建/修改时设置
```

### 云引擎会话管理对比总结

| 引擎 | 会话模型 | 用户变量 | 会话参数 | 跨查询状态 | 临时表 |
|------|---------|---------|---------|-----------|--------|
| BigQuery | 脚本/可选会话 | 脚本级 DECLARE | 有限（@@前缀） | 仅会话模式 | 脚本级 |
| Athena | 无状态 | ❌ | Workgroup 配置 | ❌ | ❌ |
| Spanner | 极简会话 | ❌ | 少量 SET | 有限 | ❌ |
| Synapse | T-SQL 会话 | DECLARE @var | 完整 SET | ✅（Dedicated） | ✅ |
| Snowflake | 有状态会话 | SET var | ALTER SESSION SET | ✅ | ✅ |
| Redshift | PG 兼容会话 | 无（GUC 替代） | SET param | ✅ | ✅ |
| Databricks | Spark 会话 | Conf 参数 | SET conf | ✅ | 临时视图 |
| Firebolt | 引擎级 | ❌ | 有限 SET | 有限 | ❌ |
| Databend | 有状态会话 | SET VARIABLE | SET param | ✅ | ✅ |
| Yellowbrick | PG 兼容会话 | 无（GUC 替代） | SET param | ✅ | ✅ |

## 关键发现 / Key Differences

1. **`@var` 语义分裂**: MySQL 的 `@var` 是会话级用户变量（动态类型、无需声明），SQL Server 的 `@var` 是批处理级局部变量（静态类型、必须 DECLARE）。这是跨引擎迁移时最常见的陷阱之一。

2. **SET 语句的多义性**: SET 在不同引擎中承载了完全不同的语义——PostgreSQL 用它设置 GUC 参数，MySQL 用它赋值变量和修改系统配置，SQL Server 用它赋值变量和切换开关（`SET NOCOUNT ON`），Snowflake 用它创建会话变量。SQL 解析器必须根据上下文区分这些用途。

3. **无过程化 SQL 的引擎越来越多**: DuckDB、ClickHouse、Trino（419 之前）、Spark SQL、Hive、QuestDB、Athena、Spanner 等分析型/无服务器引擎不提供过程化 SQL 或仅提供极有限的脚本能力。变量管理完全依赖配置参数或客户端绑定。

4. **GUC 模式的扩散**: PostgreSQL 的 GUC（Grand Unified Configuration）模式——`SET param = val` / `SHOW param` / `RESET param`——被 Redshift、CockroachDB、YugabyteDB、Greenplum、TimescaleDB、Materialize、RisingWave、Yellowbrick 等 PG 兼容引擎继承，形成了事实上的"PG 参数管理标准"。

5. **MySQL 兼容阵营**: TiDB、OceanBase（MySQL 模式）、SingleStore、StarRocks、Doris 等兼容 MySQL 的引擎继承了 `@var` 用户变量、`SET SESSION/GLOBAL`、`SHOW VARIABLES LIKE` 等语法，形成了另一个阵营。

6. **会话 vs 无状态的设计张力**: 传统数据库（PostgreSQL、MySQL、Oracle、SQL Server）的变量和参数体系建立在长连接有状态会话之上。云原生无服务器引擎（BigQuery、Athena、Spanner）必须重新思考这一模型。BigQuery 的"脚本即会话"和 Athena 的 Workgroup 是两种不同的解决思路。

7. **变量持久化差异**: MySQL 8.0 的 `SET PERSIST`、PostgreSQL 的 `ALTER SYSTEM`、Oracle 的 `SCOPE=SPFILE` 提供了不同的变量持久化机制。CockroachDB 的 `SET CLUSTER SETTING` 和 CrateDB 的 `SET GLOBAL PERSISTENT` 则面向分布式集群场景。

8. **SELECT INTO 的陷阱**: 当 SELECT 返回多行时，PostgreSQL（STRICT 模式）和 Oracle 报错，MySQL 和 SQL Server（SELECT 赋值模式）静默取最后一行，BigQuery 和 Trino 的标量子查询要求严格单行。这是跨引擎移植过程化代码时需要特别注意的行为差异。

9. **事务对变量的影响**: 几乎所有引擎中，变量值不受 `ROLLBACK` 影响。这是因为变量是会话/执行上下文的一部分，而非事务性数据。SQL Server 的表变量也遵循这一规则——这是表变量与临时表的关键区别之一。

10. **上下文函数 vs 变量**: Oracle 的 `SYS_CONTEXT`、Firebird 的 `RDB$GET_CONTEXT`/`RDB$SET_CONTEXT`、SAP HANA 的 `SESSION_CONTEXT` 提供了类似变量的上下文管理机制，但它们基于函数调用而非赋值语法，更适合行级安全等场景。
