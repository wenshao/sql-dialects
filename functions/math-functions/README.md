# 数学函数 (MATH FUNCTIONS)

各数据库数学函数对比，包括 ABS、ROUND、CEIL、FLOOR、MOD、POWER 等。

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

1. **ROUND 舍入规则**：PostgreSQL/Oracle 使用四舍五入，SQL Server 使用四舍五入，MySQL 使用四舍五入，但某些方言的 ROUND 对 .5 的处理可能采用银行家舍入（round half to even）
2. **取模运算符**：MySQL/PostgreSQL 支持 `%` 运算符和 MOD() 函数，Oracle 只有 MOD() 函数（不支持 `%`），SQL Server 支持 `%`
3. **整数除法**：MySQL 的 `5/2=2.5`，PostgreSQL 的 `5/2=2`（整数除法），Oracle 的 `5/2=2.5`，这个差异在迁移时极易出错
4. **随机数**：MySQL 用 RAND()，PostgreSQL 用 RANDOM()，Oracle 用 DBMS_RANDOM.VALUE，SQL Server 用 RAND() 或 NEWID()
5. **数学常量**：MySQL 有 PI()，PostgreSQL 有 PI()，Oracle 需要 `ACOS(-1)` 计算 PI，SQL Server 有 PI()

## 选型建议

数学函数是跨方言差异较小的领域（ABS/CEIL/FLOOR/POWER/SQRT 几乎通用），但整数除法行为差异是重大陷阱。涉及精确数值计算时始终使用 DECIMAL 类型避免浮点误差。随机排序（ORDER BY RAND()/RANDOM()）在大表上性能极差。

## 版本演进

- 数学函数在各方言中变化极少，属于最稳定的语法领域
- PostgreSQL 16+：增强统计函数支持
- ClickHouse：拥有极其丰富的数学函数库（含近似计算和统计函数）
