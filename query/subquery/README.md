# 子查询 (SUBQUERY)

各数据库子查询语法对比，包括标量子查询、行子查询、EXISTS、IN 等。

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

1. **关联子查询性能**：MySQL 5.7 对 IN 子查询的优化较弱（可能逐行执行），8.0 改进显著；PostgreSQL 自动将 IN 子查询优化为 semi-join
2. **标量子查询位置**：所有方言支持 SELECT/WHERE 中的标量子查询，但 FROM 子句中的子查询（派生表）的列别名要求不同
3. **EXISTS vs IN**：语义上等价，但 EXISTS 在关联子查询中通常更高效（可以短路返回），IN 对 NULL 值有特殊行为（NOT IN 遇到 NULL 会返回空）
4. **LATERAL 子查询**：PostgreSQL/MySQL 8.0+ 支持 LATERAL 关键字使子查询可以引用外层 FROM 子句的列

## 选型建议

能用 JOIN 的场景优先用 JOIN 而非子查询（更易读且通常更高效）。需要"存在性检查"时用 EXISTS 而非 IN（避免 NOT IN 的 NULL 陷阱）。复杂子查询建议改写为 CTE（WITH 语法），可读性和可维护性更好。

## 版本演进

- MySQL 8.0：对 IN 子查询的 semi-join 优化显著改进，性能比 5.7 大幅提升
- PostgreSQL：子查询优化器一直很强，自动选择 semi-join/anti-join/materialize 等策略
- ClickHouse：IN 子查询会自动物化为临时集合，但 JOIN 子查询的分布式执行需要注意数据分布
