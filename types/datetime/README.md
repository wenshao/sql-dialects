# 日期时间类型 (DATETIME)

各数据库日期时间类型对比，包括 DATE、TIME、TIMESTAMP、INTERVAL 等。

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

1. **精度默认值**：MySQL DATETIME 默认秒级（可指定到微秒 DATETIME(6)），PostgreSQL TIMESTAMP 默认微秒级，Oracle TIMESTAMP 默认微秒级但 DATE 包含时间到秒
2. **时区处理**：PostgreSQL 的 `TIMESTAMP WITH TIME ZONE` 存储 UTC 并自动转换，MySQL 的 TIMESTAMP 自动转 UTC 但 DATETIME 不处理时区，Oracle 有 `TIMESTAMP WITH TIME ZONE` 和 `TIMESTAMP WITH LOCAL TIME ZONE`
3. **日期范围**：MySQL DATETIME 范围 1000-01-01 到 9999-12-31，MySQL TIMESTAMP 范围 1970-01-01 到 2038-01-19（2038 问题），PostgreSQL 范围 4713 BC 到 294276 AD
4. **INTERVAL 类型**：PostgreSQL/Oracle 有原生 INTERVAL 类型（`INTERVAL '1 day'`），MySQL 的 INTERVAL 只能在日期函数中使用不能独立存储
5. **获取当前时间**：MySQL 用 NOW()/CURRENT_TIMESTAMP，PostgreSQL 用 NOW()/CURRENT_TIMESTAMP（事务内时间固定），Oracle 用 SYSDATE/SYSTIMESTAMP

## 选型建议

新项目一律使用带时区的时间戳类型存储时间。MySQL 建议用 DATETIME(3)（毫秒级）或 DATETIME(6)（微秒级）而非 TIMESTAMP（避免 2038 问题和范围限制）。PostgreSQL 推荐 TIMESTAMPTZ。日期计算逻辑在迁移时务必全面测试。

## 版本演进

- MySQL 5.6+：DATETIME/TIMESTAMP 支持指定小数秒精度（最多 6 位微秒）
- MySQL 8.0.28+：TIMESTAMP 的 2038 年上限问题在内部有缓解方案（但建议迁移到 DATETIME）
- PostgreSQL 12+：增强 JSON 路径中的日期时间处理能力

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **日期类型** | 无原生日期类型：以 TEXT('YYYY-MM-DD')/REAL(Julian)/INTEGER(Unix) 存储 | Date(日级)/Date32/DateTime(秒级)/DateTime64(亚秒) | DATE/DATETIME/TIMESTAMP/TIME | 各方言有原生日期时间类型 |
| **时区支持** | 无时区概念，应用层自行管理 | DateTime 可绑定时区（如 DateTime('Asia/Shanghai')） | TIMESTAMP 自动 UTC 管理 | PG TIMESTAMPTZ / MySQL TIMESTAMP 自动 UTC |
| **精度范围** | 取决于存储格式（TEXT 可存任意精度字符串） | DateTime64 可指定精度（毫秒/微秒/纳秒） | DATETIME 微秒级，TIMESTAMP 微秒级 | MySQL DATETIME(6)微秒 / PG 微秒级 |
| **日期范围** | 无限制（TEXT 存储任意字符串） | Date: 1970-2149，DateTime64: 1900-2299 | 0001-01-01 到 9999-12-31 | MySQL TIMESTAMP 有 2038 问题 |
| **INTERVAL 类型** | 不支持原生 INTERVAL，用字符串参数模拟 | 支持 INTERVAL（在函数中使用） | 支持 INTERVAL | PG/Oracle 原生 INTERVAL / MySQL 仅函数中可用 |
