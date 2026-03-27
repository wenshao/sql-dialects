# 类型转换 (TYPE CONVERSION)

各数据库类型转换语法对比，包括 CAST、CONVERT、隐式转换等。

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

1. **CAST 语法**：`CAST(expr AS type)` 是 SQL 标准，所有方言都支持，但目标类型名称不同（如 MySQL 的 SIGNED vs PostgreSQL 的 INTEGER）
2. **PostgreSQL :: 运算符**：PostgreSQL 特有的 `expr::type` 简写（如 `'123'::int`），简洁但不可移植
3. **CONVERT 函数**：MySQL 的 CONVERT(expr, type) 和 SQL Server 的 CONVERT(type, expr, style) 参数顺序不同
4. **隐式转换**：MySQL 隐式转换极为宽松（`'abc' = 0` 为 true），PostgreSQL 极为严格（类型不匹配直接报错），Oracle 居中
5. **TRY_CAST**：SQL Server/Snowflake/Databricks 支持 TRY_CAST（转换失败返回 NULL 而非报错），PostgreSQL/MySQL 需要用 CASE WHEN + 正则模拟

## 选型建议

始终使用显式 CAST 而非依赖隐式转换，这是最重要的跨方言最佳实践。MySQL 的隐式转换是安全隐患（WHERE varchar_col = 0 会匹配所有非数字字符串）。PostgreSQL 的严格类型检查虽然初期不便但长期更安全。

## 版本演进

- SQL Server 2012+：引入 TRY_CAST/TRY_CONVERT（安全转换）
- Snowflake/Databricks：也支持 TRY_CAST 语法
- PostgreSQL：无 TRY_CAST，但可以通过自定义函数实现类似功能
- MySQL 8.0：CAST 支持的目标类型更丰富（如 CAST(... AS FLOAT)）

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **类型系统** | 动态类型：声明类型仅为亲和性，任何值可存入任何列 | 严格类型：有丰富类型（UInt8~256、Decimal、DateTime64 等） | 严格类型：INT64/FLOAT64/STRING/BYTES 等 | 严格类型系统 |
| **CAST 语法** | 支持 CAST(x AS type)，但实际只是亲和性转换 | 支持 CAST 和特有的 toInt32/toString 等转换函数 | CAST / SAFE_CAST（转换失败返回 NULL） | 标准 CAST / PG `::` / MySQL CONVERT |
| **隐式转换** | 极度宽松（核心是动态类型，比较时按亲和性规则） | 较严格，但有自动类型提升规则 | 严格，不自动隐式转换 | MySQL 极宽松 / PG 极严格 / Oracle 居中 |
| **TRY_CAST** | 不需要（动态类型天然不会因类型不匹配报错） | 不支持 TRY_CAST，转换失败报错 | SAFE_CAST（等价于 TRY_CAST） | SQL Server TRY_CAST / PG 无（需自定义函数） |
| **迁移风险** | 从 SQLite 迁出时，动态类型数据可能包含混合类型值 | 类型精度高，迁入时需仔细映射 | BigQuery 类型有限，某些精度可能损失 | 各方言间类型映射是迁移核心挑战 |
