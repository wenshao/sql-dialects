# 错误处理 (ERROR HANDLING)

各数据库错误处理语法对比，包括 TRY-CATCH、EXCEPTION、HANDLER 等。

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

1. **语法体系**：SQL Server 用 TRY...CATCH，PostgreSQL 用 EXCEPTION WHEN（PL/pgSQL BEGIN 块中），Oracle 用 EXCEPTION WHEN（PL/SQL），MySQL 用 DECLARE HANDLER
2. **错误代码**：PostgreSQL 使用 5 字符 SQLSTATE 代码（如 '23505' 唯一违反），MySQL 有自己的错误号体系，Oracle 有 ORA-xxxxx 错误号
3. **RAISE/SIGNAL**：PostgreSQL 用 RAISE EXCEPTION/NOTICE/WARNING，MySQL 用 SIGNAL SQLSTATE，Oracle 用 RAISE_APPLICATION_ERROR()，SQL Server 用 THROW/RAISERROR
4. **事务回滚行为**：PostgreSQL 的异常处理会自动回滚到 BEGIN 块开始的 SAVEPOINT，MySQL 不自动回滚需要显式处理

## 选型建议

错误处理逻辑几乎无法跨方言复用，迁移时需要完全重写。建议将错误处理逻辑保持简单：记录错误日志、回滚事务、返回错误代码。复杂的错误恢复逻辑最好放在应用层而非数据库层。

## 版本演进

- MySQL 5.5+：引入 SIGNAL/RESIGNAL 语法（替代之前非标准的错误处理）
- PostgreSQL：PL/pgSQL 的 EXCEPTION 处理一直很强大，支持获取异常详情（SQLSTATE, SQLERRM, PG_EXCEPTION_DETAIL 等）
- SQL Server 2012+：引入 THROW 语句替代 RAISERROR（语法更简洁）
