# 改表 (ALTER TABLE)

各数据库 ALTER TABLE 语法对比，包括加列、改列、删列、重命名等操作。

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

1. **ADD COLUMN**：所有方言都支持，但 PostgreSQL 11+ 对带 DEFAULT 的 ADD COLUMN 是即时操作，MySQL 5.6 之前可能锁全表
2. **MODIFY/ALTER COLUMN**：MySQL 用 `MODIFY COLUMN`，PostgreSQL 用 `ALTER COLUMN ... TYPE`，SQL Server 用 `ALTER COLUMN`，语法完全不同
3. **DROP COLUMN**：SQLite 3.35.0 之前不支持，ClickHouse 支持但是异步操作，BigQuery 用 `DROP COLUMN` 但有限制
4. **RENAME COLUMN**：MySQL 8.0+/PostgreSQL/Oracle 支持 `RENAME COLUMN`，MySQL 5.7 需要用 `CHANGE COLUMN`（必须重写完整列定义）
5. **在线 DDL**：MySQL 8.0 的 `ALGORITHM=INSTANT` 可即时完成部分 ALTER 操作，PostgreSQL 大多数 ADD COLUMN 天然即时

## 选型建议

生产环境做 ALTER TABLE 前务必在测试环境验证是否会锁表。MySQL 大表改列推荐使用 pt-online-schema-change 或 gh-ost 工具。PostgreSQL 的大多数 ALTER 操作更友好，但 ALTER COLUMN TYPE 仍可能需要重写表。

## 版本演进

- MySQL 8.0.12+：ALGORITHM=INSTANT 支持更多即时 ALTER 操作
- PostgreSQL 11+：ADD COLUMN WITH DEFAULT 不再需要重写全表
- SQLite 3.35.0：首次支持 DROP COLUMN
- SQLite 3.25.0：首次支持 RENAME COLUMN
