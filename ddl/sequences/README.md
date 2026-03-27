# 序列与自增 (SEQUENCES)

各数据库序列与自增策略对比，包括 SEQUENCE、AUTO_INCREMENT、IDENTITY 等。

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

1. **自增机制**：MySQL 用 AUTO_INCREMENT（表级属性），PostgreSQL 推荐 GENERATED AS IDENTITY（SQL 标准），Oracle 传统上用独立 SEQUENCE 对象
2. **SEQUENCE 对象**：PostgreSQL/Oracle/SQL Server/Db2 支持独立的 SEQUENCE 对象，MySQL 不支持独立 SEQUENCE（MariaDB 10.3+ 支持）
3. **ID 不连续性**：所有自增方案在回滚、批量插入、服务器重启后都可能产生间隙，这是正常行为而非 bug
4. **分布式 ID**：分布式数据库（TiDB/CockroachDB/Spanner）的自增 ID 通常是非单调递增的，可能跳跃或乱序，以避免成为写入热点
5. **UUID 替代**：现代实践中越来越多使用 UUID/ULID 替代自增 ID，PostgreSQL 的 gen_random_uuid()、MySQL 8.0 的 UUID() 等

## 选型建议

简单应用使用 AUTO_INCREMENT/IDENTITY 即可。需要跨表共享序列时使用 SEQUENCE 对象。分布式系统推荐 UUID 或雪花算法（Snowflake ID），避免自增 ID 成为分布式写入瓶颈。

## 版本演进

- PostgreSQL 10+：推荐 `GENERATED { ALWAYS | BY DEFAULT } AS IDENTITY` 替代 SERIAL
- Oracle 12c+：引入 IDENTITY 列，简化了之前 SEQUENCE + TRIGGER 的模式
- MariaDB 10.3+：引入 CREATE SEQUENCE 语法（MySQL 至今不支持）

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **自增机制** | ROWID 自动生成；INTEGER PRIMARY KEY 自动成为 ROWID 别名 | 无自增机制，分布式架构不适用单调递增 ID | 无自增列，推荐 GENERATE_UUID() 或 ROW_NUMBER() | AUTO_INCREMENT / SERIAL / IDENTITY / SEQUENCE |
| **SEQUENCE 对象** | 不支持独立 SEQUENCE 对象 | 不支持 | 不支持 | PG/Oracle/SQL Server/Db2 支持 |
| **ID 策略** | ROWID 或 AUTOINCREMENT（严格递增但更慢） | 通常用 UUID、雪花 ID 或业务键 | UUID 或应用层生成的分布式 ID | 自增 ID / SEQUENCE / UUID |
| **分布式考量** | 单文件数据库，无分布式 ID 问题 | 多节点写入，单调递增 ID 会成为热点 | Serverless 架构，无需关心 ID 生成的并发问题 | 分布式 NewSQL（TiDB/CockroachDB）ID 可能非连续 |
| **并发安全** | 单写模型天然避免 ID 冲突 | INSERT 批量写入，ID 由应用层保证 | 并发 INSERT 由平台管理 | 行锁 / 序列缓存保证并发安全 |
