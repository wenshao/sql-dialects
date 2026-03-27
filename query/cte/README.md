# 公共表表达式 (CTE)

各数据库 CTE 语法对比，包括普通 CTE 和递归 CTE。

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

1. **递归 CTE 终止**：各方言的最大递归深度不同：PostgreSQL 默认无限（需自行控制），MySQL 默认 1000（cte_max_recursion_depth），SQL Server 默认 100（OPTION MAXRECURSION）
2. **CTE 物化行为**：PostgreSQL 12+ 可以用 MATERIALIZED/NOT MATERIALIZED 控制 CTE 是否物化，MySQL 的优化器自动决定，Oracle 的 CTE 通常会物化
3. **DML 中的 CTE**：PostgreSQL 支持 WITH ... INSERT/UPDATE/DELETE（可写 CTE），MySQL 8.0 只支持 WITH ... SELECT，SQL Server 支持部分场景
4. **多个 CTE**：所有支持 CTE 的方言都支持用逗号分隔多个 CTE，后面的 CTE 可以引用前面定义的 CTE

## 选型建议

CTE 的最大价值是提高 SQL 可读性：将复杂查询分解为命名的逻辑步骤。递归 CTE 用于层级查询和序列生成。注意 CTE 不一定比子查询更快——在某些方言中 CTE 会强制物化导致无法利用外层查询的过滤条件下推。

## 版本演进

- MySQL 8.0：首次支持 CTE（包括递归 CTE），之前完全不支持
- SQLite 3.8.3+：支持普通 CTE，3.34.0+ 支持递归 CTE 的 MATERIALIZED hint
- PostgreSQL 12+：CTE 默认从"总是物化"改为"按需物化"，这是重大性能改进
- ClickHouse：支持非递归 CTE（WITH 子句），但递归 CTE 支持有限
