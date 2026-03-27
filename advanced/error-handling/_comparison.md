# 错误处理 (Error Handling) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| TRY...CATCH | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| DECLARE HANDLER | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |
| EXCEPTION WHEN | ❌ | ✅ PL/pgSQL | ❌ | ✅ PL/SQL | ❌ | ❌ | ✅ WHEN | ❌ | ✅ |
| SIGNAL / RESIGNAL | ✅ 5.5+ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| RAISE | ❌ | ✅ | ❌ | ✅ RAISE_APPLICATION_ERROR | ❌ | ❌ | ✅ EXCEPTION | ❌ | ❌ |
| RAISERROR / THROW | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| GET DIAGNOSTICS | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| SQLSTATE | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ SQLCODE | ✅ | ✅ |
| SQLCODE | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| SQLERRM | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| @@ERROR | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| ERROR_MESSAGE() | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| ERROR_NUMBER() | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| 命名异常 | ❌ | ❌ | ❌ | ✅ 预定义异常 | ❌ | ❌ | ❌ | ❌ | ❌ |
| 用户自定义异常 | ⚠️ SIGNAL | ✅ RAISE | ❌ | ✅ PRAGMA EXCEPTION_INIT | ✅ THROW | ⚠️ SIGNAL | ✅ | ✅ | ✅ |
| CONTINUE HANDLER | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |
| EXIT HANDLER | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |
| UNDO HANDLER | ⚠️ 保留字 | ❌ | ❌ | ❌ | ❌ | ⚠️ | ❌ | ✅ | ❌ |
| SAVEPOINT + ROLLBACK | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 嵌套异常处理 | ✅ 嵌套 BEGIN | ✅ 嵌套 BEGIN | ❌ | ✅ 嵌套 BEGIN | ✅ 嵌套 TRY | ✅ | ✅ | ✅ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| TRY...CATCH | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| EXCEPTION HANDLER | ✅ 脚本 | ✅ 存储过程 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| RAISE | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| TRY 函数 | ❌ | ✅ TRY_CAST | ❌ | ❌ | ❌ | ❌ | ✅ try() | ❌ | ❌ | ✅ TRY_CAST | ❌ | ❌ |
| SAFE 前缀函数 | ✅ SAFE_CAST | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| TRY...CATCH | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| EXCEPTION HANDLER | ✅ PL/pgSQL | ✅ | ❌ | ✅ PL/pgSQL | ❌ | ✅ | ❌ |
| RAISE | ✅ | ✅ THROW | ❌ | ✅ | ❌ | ✅ | ❌ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| DECLARE HANDLER | ✅ | ✅ MySQL 模式 | ❌ | ❌ | ❌ | ✅ MySQL 模式 | ❌ | ✅ | ❌ | ❌ |
| EXCEPTION WHEN | ❌ | ⚠️ Oracle 模式 | ✅ PL/pgSQL | ❌ | ✅ PL/pgSQL | ⚠️ PG 模式 | ✅ | ❌ | ✅ | ✅ |
| SIGNAL | ✅ | ✅ MySQL 模式 | ❌ | ❌ | ❌ | ✅ MySQL 模式 | ❌ | ✅ | ❌ | ❌ |
| RAISE | ❌ | ⚠️ Oracle 模式 | ✅ | ❌ | ✅ | ⚠️ PG 模式 | ✅ | ❌ | ✅ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| EXCEPTION WHEN | ✅ PL/pgSQL | ❌ | ❌ | ❌ | ❌ | ❌ |
| RAISE | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 错误处理支持 | ✅ | ❌ | ❌ | ❌ | ⚠️ | ⚠️ |

## 关键差异

- **SQL Server** 使用独特的 TRY...CATCH 块（2005+）和 THROW/RAISERROR
- **MySQL/MariaDB** 使用 DECLARE HANDLER（CONTINUE/EXIT），SIGNAL/RESIGNAL 抛出异常
- **PostgreSQL** 使用 EXCEPTION WHEN 块（在 PL/pgSQL 中），RAISE 抛出异常
- **Oracle** 使用 EXCEPTION WHEN 块（在 PL/SQL 中），有丰富的预定义异常（NO_DATA_FOUND, TOO_MANY_ROWS 等）
- **SQLite** 不支持服务端错误处理（需在应用层处理）
- **BigQuery** 在脚本（Scripting）中支持 BEGIN...EXCEPTION...END
- **Snowflake** 在存储过程中支持 EXCEPTION 处理
- **大数据引擎（Hive/Spark/ClickHouse/Flink）** 一般不支持错误处理，需在调度层或应用层处理
- **BigQuery** 独有 SAFE 前缀函数（如 SAFE_CAST），转换失败返回 NULL 而非报错
- **Trino/DuckDB/Snowflake** 支持 TRY_CAST 等 TRY 函数作为轻量级错误处理
