# 复合类型 (ARRAY / MAP / STRUCT)

各数据库复合类型对比，包括 ARRAY、MAP、STRUCT/ROW 的定义与操作。

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

1. **ARRAY 支持**：PostgreSQL 原生支持 ARRAY 类型（任意元素类型），BigQuery/ClickHouse/Hive/Spark 都支持 ARRAY，MySQL/SQL Server/Oracle 不原生支持
2. **MAP 类型**：Hive/Spark/ClickHouse/Flink 支持 MAP 类型（键值对），PostgreSQL 用 hstore 扩展或 JSONB 模拟，传统 RDBMS 大多不支持
3. **STRUCT/ROW 类型**：BigQuery 的 STRUCT、PostgreSQL 的 ROW/复合类型、Hive 的 STRUCT，适合嵌套数据但查询语法各不相同
4. **展开操作**：PostgreSQL 用 unnest()，BigQuery 用 UNNEST()，Hive/Spark 用 explode()/LATERAL VIEW，ClickHouse 用 arrayJoin()

## 选型建议

复合类型在分析型引擎中很常见（处理嵌套 JSON/Parquet 数据），但在 OLTP 数据库中应谨慎使用（违反第一范式）。PostgreSQL 的 ARRAY 适合存储标签列表等简单场景。需要复杂嵌套数据结构时优先考虑 BigQuery/Spark 等原生支持 STRUCT 的引擎。

## 版本演进

- PostgreSQL：ARRAY 类型从早期版本就支持，是传统 RDBMS 中支持最完善的
- Hive 0.7+：引入复合类型（ARRAY、MAP、STRUCT）
- BigQuery：原生支持 ARRAY 和 STRUCT，是云数仓中嵌套数据能力最强的
- ClickHouse：ARRAY 和 MAP 支持完善，近年引入 Tuple/Named Tuple 类型

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **ARRAY 支持** | 不支持原生 ARRAY（可用 JSON 数组模拟） | 完整支持 Array(T) 类型，丰富的数组函数 | 完整支持 ARRAY 类型 | PG 原生支持 / MySQL 不支持 / Oracle 需 VARRAY |
| **MAP 类型** | 不支持（可用 JSON 对象模拟） | 支持 Map(K,V) 类型 | 不原生支持（用 STRUCT 的 ARRAY 模拟） | PG 用 hstore 或 JSONB / MySQL 不支持 |
| **STRUCT/ROW** | 不支持 | 支持 Tuple/Named Tuple | 完整支持 STRUCT（嵌套数据的核心类型） | PG 支持 ROW/复合类型 / MySQL 不支持 |
| **展开操作** | 不支持 | arrayJoin() 展开数组为多行 | UNNEST() 展开数组/结构体 | PG unnest() / Hive explode() |
| **动态类型影响** | 用 JSON 模拟复合类型，灵活但无类型检查 | 严格类型的复合类型，高性能列式操作 | 严格类型 | PG 严格 / MySQL 不支持原生复合类型 |
