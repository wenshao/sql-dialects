# 数值类型 (NUMERIC)

各数据库数值类型对比，包括整数、浮点数、定点数、DECIMAL 等。

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

1. **整数类型**：MySQL 有 TINYINT/SMALLINT/MEDIUMINT/INT/BIGINT，PostgreSQL 没有 TINYINT/MEDIUMINT，BigQuery 只有 INT64，ClickHouse 有 UInt8/UInt16/UInt32/UInt64 等无符号类型
2. **DECIMAL 精度**：MySQL DECIMAL 最大 65 位精度，PostgreSQL NUMERIC 最大 1000 位，Oracle NUMBER 最大 38 位，BigQuery NUMERIC 最大 29 位整数 + 9 位小数
3. **浮点精度**：FLOAT/DOUBLE 是近似类型（IEEE 754），金融计算必须用 DECIMAL/NUMERIC，0.1 + 0.2 在 FLOAT 中不等于 0.3
4. **除法行为**：PostgreSQL/Oracle 的整数除法返回整数（5/2=2），MySQL 返回浮点数（5/2=2.5000），这是常见的迁移陷阱
5. **溢出行为**：PostgreSQL 整数溢出报错，MySQL 默认静默截断（STRICT 模式下报错），ClickHouse 默认溢出回绕

## 选型建议

金融/货币场景必须用 DECIMAL 类型，绝不使用 FLOAT/DOUBLE。科学计算可以用 DOUBLE。计数/ID 用整数类型。注意整数除法的跨方言差异，必要时显式 CAST 为 DECIMAL 再除。

## 版本演进

- PostgreSQL 14+：改进 NUMERIC 的计算性能
- MySQL 8.0：严格模式默认开启，整数溢出和截断会报错而非静默处理
- ClickHouse：独有的 Decimal32/Decimal64/Decimal128/Decimal256 类型，精度选择灵活
