# 聚合函数 (AGGREGATE FUNCTIONS)

各数据库聚合函数对比，包括 COUNT、SUM、AVG、MIN、MAX、GROUP_CONCAT 等。

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

1. **字符串聚合**：MySQL 用 GROUP_CONCAT()，PostgreSQL 用 STRING_AGG()（9.0+），Oracle 用 LISTAGG()，SQL Server 用 STRING_AGG()（2017+），分隔符参数位置和默认行为各不相同
2. **COUNT(DISTINCT) 多列**：MySQL 支持 `COUNT(DISTINCT a, b)`，PostgreSQL/Oracle/SQL Server 不支持（需要子查询或 CONCAT 模拟）
3. **NULL 处理**：所有标准聚合函数（SUM/AVG/MIN/MAX）跳过 NULL 值，`COUNT(*)` 计所有行但 `COUNT(column)` 跳过 NULL
4. **FILTER 子句**：PostgreSQL 9.4+ 支持 `SUM(x) FILTER (WHERE condition)`，其他方言需要用 `SUM(CASE WHEN condition THEN x END)` 模拟
5. **近似聚合**：BigQuery/ClickHouse/Snowflake 提供 APPROX_COUNT_DISTINCT 等近似聚合函数，大数据量下性能远优于精确计算

## 选型建议

COUNT(DISTINCT) 在大基数列上性能差，大数据场景考虑使用 HyperLogLog 等近似算法。GROUP_CONCAT/STRING_AGG 的结果长度可能受限（MySQL 默认 1024 字节限制，需调整 group_concat_max_len）。FILTER 子句是 PostgreSQL 的杀手级特性，比 CASE WHEN 更简洁。

## 版本演进

- PostgreSQL 9.4+：引入聚合函数的 FILTER 子句
- SQL Server 2017+：引入 STRING_AGG()（替代 FOR XML PATH 拼接字符串的复杂写法）
- MySQL 8.0：GROUP_CONCAT 仍是主要的字符串聚合方式，无 STRING_AGG
