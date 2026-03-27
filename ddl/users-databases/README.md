# 数据库/Schema/用户管理

各数据库的数据库、Schema、用户创建与管理语法对比。

## 方言列表

### 传统关系型数据库
| 方言 | 链接 |
|---|---|
| MySQL | [mysql.sql](mysql.sql) |
| PostgreSQL | [postgres.sql](postgres.sql) |
| SQLite | [sqlite.sql](sqlite.sql) |
| Oracle | [oracle.sql](oracle.sql) |
| SQL Server | [sqlserver.sql](sqlserver.sql) |
| MariaDB | [mariadb.sql](mariadb.sql) |
| Firebird | [firebird.sql](firebird.sql) |
| IBM Db2 | [db2.sql](db2.sql) |
| SAP HANA | [saphana.sql](saphana.sql) |

### 大数据 / 分析型引擎
| 方言 | 链接 |
|---|---|
| BigQuery | [bigquery.sql](bigquery.sql) |
| Snowflake | [snowflake.sql](snowflake.sql) |
| ClickHouse | [clickhouse.sql](clickhouse.sql) |
| Hive | [hive.sql](hive.sql) |
| Spark SQL | [spark.sql](spark.sql) |
| Flink SQL | [flink.sql](flink.sql) |
| StarRocks | [starrocks.sql](starrocks.sql) |
| Doris | [doris.sql](doris.sql) |
| Trino | [trino.sql](trino.sql) |
| DuckDB | [duckdb.sql](duckdb.sql) |
| MaxCompute | [maxcompute.sql](maxcompute.sql) |
| Hologres | [hologres.sql](hologres.sql) |

### 云数仓
| 方言 | 链接 |
|---|---|
| Redshift | [redshift.sql](redshift.sql) |
| Azure Synapse | [synapse.sql](synapse.sql) |
| Databricks SQL | [databricks.sql](databricks.sql) |
| Greenplum | [greenplum.sql](greenplum.sql) |
| Impala | [impala.sql](impala.sql) |
| Vertica | [vertica.sql](vertica.sql) |
| Teradata | [teradata.sql](teradata.sql) |

### 分布式 / NewSQL
| 方言 | 链接 |
|---|---|
| TiDB | [tidb.sql](tidb.sql) |
| OceanBase | [oceanbase.sql](oceanbase.sql) |
| CockroachDB | [cockroachdb.sql](cockroachdb.sql) |
| Spanner | [spanner.sql](spanner.sql) |
| YugabyteDB | [yugabytedb.sql](yugabytedb.sql) |
| PolarDB | [polardb.sql](polardb.sql) |
| openGauss | [opengauss.sql](opengauss.sql) |
| TDSQL | [tdsql.sql](tdsql.sql) |

### 国产数据库
| 方言 | 链接 |
|---|---|
| DamengDB | [dameng.sql](dameng.sql) |
| KingbaseES | [kingbase.sql](kingbase.sql) |

### 时序数据库
| 方言 | 链接 |
|---|---|
| TimescaleDB | [timescaledb.sql](timescaledb.sql) |
| TDengine | [tdengine.sql](tdengine.sql) |

### 流处理
| 方言 | 链接 |
|---|---|
| ksqlDB | [ksqldb.sql](ksqldb.sql) |
| Materialize | [materialize.sql](materialize.sql) |

### 嵌入式 / 轻量
| 方言 | 链接 |
|---|---|
| H2 | [h2.sql](h2.sql) |
| Derby | [derby.sql](derby.sql) |

### SQL 标准
| 方言 | 链接 |
|---|---|
| SQL Standard | [sql-standard.sql](sql-standard.sql) |

## 核心差异

1. **命名空间层次**：PostgreSQL 有 database → schema → table 三层结构，MySQL 的 database 等同于 schema，Oracle 用 user 约等于 schema，SQL Server 有 server → database → schema → table 四层
2. **跨库查询**：PostgreSQL 不支持跨 database 查询（需要 dblink/FDW），MySQL 可以直接 `SELECT * FROM other_db.table`，SQL Server/Oracle 都支持跨库查询
3. **用户认证**：PostgreSQL 通过 pg_hba.conf 配置认证方式，MySQL 在 user 表中管理，Oracle 有内部认证和 OS 认证，云数据库通常集成 IAM
4. **角色系统**：PostgreSQL 的 ROLE 统一了用户和角色概念，MySQL 8.0+ 才支持 ROLE，Oracle 一直区分 USER 和 ROLE

## 选型建议

设计数据库架构时，PostgreSQL 的 schema 机制适合多租户隔离，MySQL 的多 database 方案更简单直接。云数据库（BigQuery/Snowflake）通常有自己的项目/账户/仓库层次结构，与传统 RDBMS 差异较大。

## 版本演进

- MySQL 8.0：引入角色（ROLE）机制，之前只能直接给用户授权
- PostgreSQL 16+：支持 `GRANT ... ON ALL TABLES IN SCHEMA` 的改进
- BigQuery：使用 IAM 角色代替传统 SQL 权限，与 Google Cloud 深度集成

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **权限系统** | 无 GRANT/REVOKE，完全依赖文件系统权限控制访问 | 有完整的 GRANT/REVOKE 和用户/角色系统 | 使用 Google Cloud IAM，不用 SQL GRANT | 完整的 GRANT/REVOKE 权限体系 |
| **用户管理** | 无用户概念，无 CREATE USER | 支持 CREATE USER、角色管理 | 通过 IAM 管理用户和服务账号 | CREATE USER / CREATE ROLE |
| **数据库层次** | 单文件即一个数据库，无 schema 概念 | database → table 两层结构 | project → dataset → table 三层结构 | PG: database→schema→table，MySQL: database=schema |
| **多租户隔离** | 每个租户一个数据库文件实现隔离 | 通过 database 或行级权限隔离 | 通过 dataset 权限 + IAM 策略隔离 | schema 隔离（PG）或 database 隔离（MySQL） |
| **跨库查询** | 通过 ATTACH DATABASE 可跨文件查询 | 支持跨 database 查询 | 支持跨 dataset/跨 project 查询 | 各方言支持程度不同（PG 需 dblink/FDW） |
