# 字符串类型 (STRING)

各数据库字符串类型对比，包括 CHAR、VARCHAR、TEXT、CLOB 等。

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

1. **VARCHAR 上限**：MySQL 最大 65535 字节（行总长限制），PostgreSQL VARCHAR 最大 1GB，Oracle VARCHAR2 最大 4000 字节（EXTENDED 模式 32767），SQL Server VARCHAR(MAX) 最大 2GB
2. **空字符串 vs NULL**：Oracle 中 `''` 等于 NULL，这是最著名的跨方言陷阱之一，其他所有方言中 `''` 和 NULL 是不同的
3. **字符集/编码**：MySQL 的 utf8 实际只支持 3 字节 UTF-8（不含 emoji），需要 utf8mb4 才完整支持；PostgreSQL 数据库级设置编码，Oracle 用 NCHAR/NVARCHAR2 处理 Unicode
4. **TEXT 类型**：MySQL/PostgreSQL/SQLite 有 TEXT 类型（不限长度），Oracle 用 CLOB，SQL Server 用 VARCHAR(MAX)

## 选型建议

现代应用一律使用 UTF-8 编码（MySQL 必须是 utf8mb4）。VARCHAR 长度应设合理值而非总用最大值（影响内存分配和排序缓冲区）。Oracle 迁移时务必处理空字符串 = NULL 的差异。大数据引擎通常只有 STRING 类型，不区分 CHAR/VARCHAR。

## 版本演进

- MySQL 5.5+：默认字符集从 latin1 改为 utf8（但推荐显式使用 utf8mb4）
- MySQL 8.0：默认字符集改为 utf8mb4，默认排序规则改为 utf8mb4_0900_ai_ci
- Oracle 12c+：VARCHAR2 最大长度可扩展到 32767 字节（MAX_STRING_SIZE=EXTENDED）
