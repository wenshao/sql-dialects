# JSON 类型

各数据库 JSON 类型与操作对比，包括 JSON 存储、查询、路径表达式等。

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

1. **存储格式**：PostgreSQL 有 JSON（文本）和 JSONB（二进制，可索引），MySQL 5.7+ 用二进制 JSON 格式，Oracle 12c+ 支持 JSON 但存储为 VARCHAR2/CLOB
2. **路径表达式**：MySQL 用 `$[0].name`（JSON Path），PostgreSQL JSONB 用 `->` / `->>`/ `#>` 运算符或 jsonpath，Oracle 用 JSON_VALUE + JSON Path
3. **索引能力**：PostgreSQL JSONB 可建 GIN 索引支持 `@>` 包含查询，MySQL 只能对虚拟生成列建索引，大多数分析型引擎不支持 JSON 索引
4. **JSON_TABLE**：Oracle 12c+ 和 MySQL 8.0+ 支持 JSON_TABLE 将 JSON 展开为关系表，PostgreSQL 用 jsonb_to_recordset()
5. **SQL/JSON 标准**：SQL:2016 定义了 JSON 标准函数（JSON_VALUE/JSON_QUERY/JSON_TABLE），各方言逐步采纳中

## 选型建议

PostgreSQL 的 JSONB 是关系数据库中 JSON 能力最强的实现，适合需要频繁查询 JSON 内容的场景。如果 JSON 只存取不查询，任何方言都可以。分析场景建议将 JSON 展开为独立列存储（ClickHouse/Hive 等列式引擎性能更好）。

## 版本演进

- PostgreSQL 12+：引入 SQL/JSON 路径语言（jsonpath 类型）
- MySQL 8.0：JSON 函数显著增强，支持 JSON_TABLE、JSON_SCHEMA_VALID 等
- SQLite 3.38.0+：内置 JSON 函数（之前需要加载扩展）
- ClickHouse：近年引入 JSON 对象类型（实验性），逐步增强半结构化数据支持

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **JSON 支持** | 3.38.0+ 内置 JSON 函数（之前需加载扩展），存储为 TEXT | 偏好将 JSON 展开为独立列；近年引入实验性 JSON 对象类型 | 用 STRUCT/ARRAY 表示嵌套数据比 JSON 字符串更高效 | PG JSONB 最强 / MySQL 5.7+ JSON / Oracle 12c+ |
| **JSON 索引** | 不支持 JSON 索引 | 不支持传统 JSON 索引，列式存储天然高效 | 无索引概念（分区+聚簇替代） | PG JSONB GIN 索引强大 / MySQL 虚拟列索引 |
| **路径查询** | json_extract(doc, '$.key') | JSONExtractString/visitParamExtractString 等 | JSON_VALUE/JSON_QUERY（SQL 标准） | PG ->/->> / MySQL $.key / Oracle JSON_VALUE |
| **半结构化策略** | JSON 存为 TEXT 列，查询性能一般 | 推荐 ETL 时展开为独立列（列式存储优势） | 推荐用 STRUCT/ARRAY 建模嵌套数据 | PG JSONB 适合频繁查询 / 其他方言适合存取不查 |
| **动态类型影响** | 动态类型下 JSON 与普通 TEXT 无区别 | 严格类型需要显式的 JSON 解析函数 | 严格类型 | 严格类型 |
