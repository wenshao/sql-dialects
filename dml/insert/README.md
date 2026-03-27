# 插入 (INSERT)

各数据库 INSERT 语法对比，包括单行插入、批量插入、INSERT INTO SELECT 等。

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

1. **多行 VALUES**：MySQL/PostgreSQL/SQLite 支持 `INSERT INTO t VALUES (1,'a'),(2,'b')`，Oracle 12c 之前必须用 `INSERT ALL` 或 `UNION ALL` 子查询
2. **INSERT ... RETURNING**：PostgreSQL/Oracle/MariaDB 10.5+ 支持返回插入后的数据（含自增 ID），MySQL 不支持需要用 LAST_INSERT_ID()
3. **INSERT OVERWRITE**：Hive/Spark/MaxCompute 支持 INSERT OVERWRITE（覆盖写入分区），传统 RDBMS 没有此语法
4. **批量插入性能**：MySQL 的多值 INSERT 和 LOAD DATA INFILE 性能差异可达 10-50 倍，PostgreSQL 的 COPY 命令是最快的批量导入方式
5. **默认值处理**：`INSERT INTO t DEFAULT VALUES` 在 PostgreSQL/SQL Server 中有效，MySQL 用 `INSERT INTO t () VALUES ()`

## 选型建议

少量数据插入用标准 INSERT VALUES。大批量数据导入应使用专用工具：MySQL 的 LOAD DATA INFILE、PostgreSQL 的 COPY、BigQuery 的 Load Job、Snowflake 的 COPY INTO。ORM 生成的逐行 INSERT 在大批量场景下性能极差。

## 版本演进

- Oracle 12c+：支持多行 VALUES 语法，告别 INSERT ALL 的繁琐写法
- MariaDB 10.5+：INSERT ... RETURNING 支持
- MySQL 8.0：VALUES 语句可以作为独立的行构造器使用
