# 建表 (CREATE TABLE)

各数据库 CREATE TABLE 语法对比。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

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

1. **自增主键**：MySQL 用 `AUTO_INCREMENT`，PostgreSQL 用 `SERIAL`/`GENERATED AS IDENTITY`（推荐后者），Oracle 12c+ 才支持 IDENTITY，之前必须用 SEQUENCE + TRIGGER
2. **IF NOT EXISTS**：MySQL/PostgreSQL/SQLite 支持，Oracle/SQL Server 不直接支持，需要用过程式代码或条件判断
3. **存储引擎指定**：ClickHouse 必须指定引擎（MergeTree 等），Hive 必须指定行列格式和存储位置，传统 RDBMS 通常有默认引擎
4. **排序键/分区键**：ClickHouse 的 ORDER BY 是表级的（排序键），BigQuery 可指定 clustering，Hive 用 PARTITIONED BY，这些概念在传统 RDBMS 中不存在
5. **临时表语法**：`CREATE TEMPORARY TABLE` vs `CREATE GLOBAL TEMPORARY TABLE` vs `#table_name`（SQL Server）

## 选型建议

传统业务系统选 MySQL/PostgreSQL 的标准 CREATE TABLE 语法即可。需要分析场景时，重点掌握 ClickHouse 的引擎选择和 Hive/Spark 的分区分桶策略。云数仓（BigQuery/Snowflake）的建表语法最简洁，大部分存储细节由平台自动管理。

## 版本演进

- PostgreSQL 10+：引入 `GENERATED AS IDENTITY`（替代 SERIAL），这是 SQL 标准语法
- MySQL 8.0：支持 `CHECK` 约束（之前只解析不执行）、支持降序索引
- Oracle 12c：引入 IDENTITY 列，不再强制依赖 SEQUENCE
- SQL Server 2016+：支持 `DROP IF EXISTS` 语法简化 DDL 脚本
