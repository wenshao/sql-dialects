# 条件函数 (CONDITIONAL)

各数据库条件函数对比，包括 CASE、IF、COALESCE、NULLIF、IIF 等。

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

1. **CASE 表达式**：SQL 标准语法，所有方言都支持。分为简单 CASE（CASE x WHEN 1 THEN ...）和搜索 CASE（CASE WHEN x > 1 THEN ...）
2. **IF 函数**：MySQL/MariaDB 有 IF(condition, true_val, false_val)，其他方言用 CASE WHEN 替代。SQL Server 有 IIF()（2012+）
3. **COALESCE vs NVL/ISNULL**：COALESCE 是 SQL 标准（支持多参数），NVL 是 Oracle 特有（只支持两参数），ISNULL 是 SQL Server 特有
4. **NULLIF**：所有方言都支持，`NULLIF(a, b)` 当 a=b 时返回 NULL，常用于避免除零错误 `x / NULLIF(y, 0)`
5. **DECODE**：Oracle 特有函数（类似简单 CASE），迁移时必须改写为 CASE WHEN

## 选型建议

跨方言代码始终使用 CASE WHEN 和 COALESCE（SQL 标准），避免使用 IF()、NVL()、ISNULL()、DECODE() 等方言特有函数。NULLIF 配合除法避免除零错误是通用技巧。COALESCE 可以串联多个备选值（如 COALESCE(a, b, c, 0)）。

## 版本演进

- SQL Server 2012+：引入 IIF() 函数（从 Access 移植），但建议使用 CASE WHEN
- 条件函数在各方言中变化较小，属于最稳定的语法领域
- ClickHouse：独有的 multiIf() 函数提供多条件判断，比嵌套 if() 更清晰

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **CASE WHEN** | 完整支持（SQL 标准） | 完整支持 | 完整支持 | 所有方言均支持 |
| **IF 函数** | 不支持 IF() 函数（用 CASE WHEN 替代） | 支持 if(cond, then, else)，还有独特的 multiIf() | 支持 IF(cond, then, else) | MySQL 有 IF()，PG 无，SQL Server 有 IIF() |
| **COALESCE** | 完整支持 | 完整支持 | 完整支持 | 所有方言均支持（SQL 标准） |
| **NULLIF** | 完整支持 | 完整支持 | 完整支持 | 所有方言均支持 |
| **NULL 行为** | 动态类型下 NULL 处理较宽松 | 严格的 Nullable 类型系统，非 Nullable 列不存 NULL | 严格类型，NULL 处理符合 SQL 标准 | Oracle 空字符串=NULL 是独特陷阱 |
