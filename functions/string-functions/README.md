# 字符串函数 (STRING FUNCTIONS)

各数据库字符串函数对比，包括 CONCAT、SUBSTRING、TRIM、REPLACE 等。

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

1. **字符串拼接**：MySQL 用 CONCAT()，PostgreSQL/Oracle 用 `||` 运算符（也支持 CONCAT()），SQL Server 用 `+` 运算符或 CONCAT()。注意：Oracle 的 `||` 对 NULL 透明（NULL || 'a' = 'a'），PostgreSQL 的 `||` 遇 NULL 返回 NULL
2. **SUBSTRING 语法**：标准语法 `SUBSTRING(s FROM pos FOR len)`，MySQL 也支持 `SUBSTRING(s, pos, len)`，Oracle 用 SUBSTR()
3. **长度函数**：MySQL/PostgreSQL 用 LENGTH()（字符数）/CHAR_LENGTH()，Oracle 用 LENGTH()（字符数），SQL Server 用 LEN()（去尾部空格）/DATALENGTH()（字节数）
4. **正则表达式**：PostgreSQL 支持 `~` 运算符和 REGEXP_REPLACE/MATCH，MySQL 8.0+ 支持 REGEXP_REPLACE()，Oracle 用 REGEXP_LIKE/REGEXP_REPLACE
5. **TRIM 语法**：标准 `TRIM(LEADING/TRAILING/BOTH 'x' FROM s)` 被大多数方言支持，MySQL/PostgreSQL 也有简化的 LTRIM/RTRIM

## 选型建议

字符串拼接优先用 CONCAT() 函数（跨方言最安全，且 MySQL 的 CONCAT 对 NULL 参数返回 NULL 但 SQL Server 的 CONCAT 将 NULL 视为空字符串）。正则表达式功能强大但性能差，大数据量场景慎用。LENGTH() 的字节 vs 字符语义在多字节编码下差异显著。

## 版本演进

- MySQL 8.0+：引入 REGEXP_REPLACE()、REGEXP_SUBSTR() 等正则函数（5.7 只有 REGEXP/RLIKE 匹配）
- PostgreSQL：正则支持一直很完善，包括命名捕获组等高级特性
- SQL Server 2017+：引入 STRING_AGG()、CONCAT_WS()、TRIM() 等现代字符串函数
