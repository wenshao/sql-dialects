# 触发器 (TRIGGERS)

各数据库触发器语法对比，包括 BEFORE/AFTER、行级/语句级触发器。

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

1. **触发器时机**：PostgreSQL/Oracle 支持 BEFORE/AFTER/INSTEAD OF，MySQL 支持 BEFORE/AFTER（不支持 INSTEAD OF），SQL Server 用 INSTEAD OF 和 AFTER（不支持 BEFORE）
2. **行级 vs 语句级**：PostgreSQL/Oracle 支持 FOR EACH ROW 和 FOR EACH STATEMENT，MySQL 只支持 FOR EACH ROW，SQL Server 只支持语句级
3. **触发器函数**：PostgreSQL 的触发器必须先创建触发器函数再绑定到表，MySQL/SQL Server 直接在 CREATE TRIGGER 中写逻辑
4. **引用新旧值**：MySQL 用 NEW/OLD，PostgreSQL 用 NEW/OLD（在触发器函数中），SQL Server 用 INSERTED/DELETED 伪表，Oracle 用 :NEW/:OLD

## 选型建议

触发器应谨慎使用：它们使数据流变得隐式、调试困难、影响写入性能。适用场景：审计日志、自动维护冗余字段、强制业务规则。分析型引擎大多不支持触发器（ClickHouse 的物化视图可实现类似增量处理的效果）。

## 版本演进

- PostgreSQL 10+：支持在分区表上创建触发器（自动应用到所有分区）
- MySQL 5.7+：允许同一事件的多个触发器（FOLLOWS/PRECEDES 控制顺序）
- 触发器的总体趋势是被应用层事件、CDC（Change Data Capture）等机制替代
