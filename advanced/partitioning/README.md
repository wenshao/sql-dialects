# 分区 (PARTITIONING)

各数据库分区语法对比，包括 RANGE、LIST、HASH 分区等。

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

1. **分区类型**：RANGE（按范围，最常用于日期分区）、LIST（按枚举值）、HASH（均匀分布），Oracle/PostgreSQL/MySQL 都支持这三种，ClickHouse/Hive 有自己的分区语法
2. **声明式 vs 继承式**：PostgreSQL 10+ 用声明式分区（原生语法），10 之前用表继承模拟分区。MySQL 一直使用声明式
3. **自动分区管理**：Oracle 有自动间隔分区（INTERVAL PARTITIONING），PostgreSQL/MySQL 需要手动创建新分区或用 pg_partman 等扩展
4. **分区裁剪**：查询优化器自动跳过无关分区，但 WHERE 条件必须直接引用分区键才能触发裁剪（函数包装会破坏裁剪）
5. **大数据引擎**：Hive/Spark 的分区是目录级别的（每个分区一个目录），与 RDBMS 的分区概念不同

## 选型建议

分区的核心目的是查询裁剪和数据生命周期管理（快速删除旧分区）。日志类数据按时间 RANGE 分区最常见。分区数不宜过多（MySQL 单表限制约 8192 个分区），大数据引擎分区数通常也建议控制在合理范围。

## 版本演进

- PostgreSQL 10+：引入声明式分区（取代表继承），PostgreSQL 11+ 支持 hash 分区和默认分区
- PostgreSQL 13+：改进分区裁剪性能，支持逻辑复制分区表
- MySQL 8.0：分区与索引的交互改进，支持在分区表上使用 InnoDB 全部功能
