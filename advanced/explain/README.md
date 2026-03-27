# 执行计划 (EXPLAIN)

各数据库执行计划语法对比，包括 EXPLAIN、EXPLAIN ANALYZE 等。

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

1. **输出格式**：MySQL 的 EXPLAIN 默认表格格式（8.0+ 支持 TREE/JSON），PostgreSQL 默认文本树形（支持 JSON/YAML/XML），Oracle 用 DBMS_XPLAN，SQL Server 用图形化执行计划
2. **EXPLAIN ANALYZE**：PostgreSQL 和 MySQL 8.0+ 支持 EXPLAIN ANALYZE（实际执行并返回真实耗时），Oracle 需要 SQL Trace + TKPROF
3. **成本模型**：各方言的成本单位和估算算法完全不同，PostgreSQL 的 cost 是相对值，MySQL 的 cost 是估算的 IO + CPU 操作数
4. **关键指标**：MySQL 重点看 type（ALL/index/range/ref/eq_ref）和 rows，PostgreSQL 重点看 Seq Scan vs Index Scan 和 actual time

## 选型建议

EXPLAIN 是 SQL 性能优化的第一工具，每个 DBA 都应精通所用方言的执行计划解读。EXPLAIN ANALYZE 会实际执行查询，对生产环境的 DML 语句（UPDATE/DELETE）要谨慎使用。PostgreSQL 的 EXPLAIN (ANALYZE, BUFFERS) 提供最详细的性能信息。

## 版本演进

- MySQL 8.0.18+：引入 EXPLAIN ANALYZE（之前只有 EXPLAIN 估算值）
- MySQL 8.0：引入 TREE 格式输出和 JSON 格式详细信息
- PostgreSQL 13+：EXPLAIN 增加 WAL 和 incremental sort 信息
- ClickHouse：clickhouse-client 的 `SET send_logs_level = 'trace'` 可以查看详细的查询管道
