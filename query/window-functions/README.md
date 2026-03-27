# 窗口函数 (WINDOW FUNCTIONS)

各数据库窗口函数语法对比，包括 ROW_NUMBER、RANK、LAG/LEAD、NTILE 等。

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

1. **支持时间线**：Oracle 8i 最早支持（2000 年），PostgreSQL 8.4（2009 年），SQL Server 2012，MySQL 8.0（2018 年），SQLite 3.25.0（2018 年）
2. **RANGE vs ROWS**：ROWS 按物理行计算窗口帧，RANGE 按逻辑值计算；大多数方言默认 RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW，这可能导致意外结果
3. **QUALIFY 子句**：BigQuery/Snowflake/Databricks 支持 QUALIFY 直接过滤窗口函数结果，其他方言需要用子查询或 CTE 包装
4. **窗口函数嵌套**：不能在窗口函数内嵌套窗口函数（SQL 标准限制），需要用子查询分层计算
5. **GROUPS 窗口帧**：SQL:2011 标准的 GROUPS 帧类型只有少数方言支持（PostgreSQL 11+、SQLite 3.28.0+），MySQL 8.0 不支持

## 选型建议

ROW_NUMBER/RANK/DENSE_RANK 是最常用的三个窗口函数，务必理解它们处理并列值的差异。LAG/LEAD 适合计算环比/同比。SUM/AVG OVER 适合累计和移动平均。始终显式指定窗口帧（ROWS BETWEEN ...）避免默认帧的意外行为。

## 版本演进

- MySQL 8.0：首次支持窗口函数（之前需要用变量模拟 ROW_NUMBER）
- PostgreSQL 11+：支持 GROUPS 帧类型和窗口函数中的 EXCLUDE 子句
- SQLite 3.25.0+：引入窗口函数支持
- Hive 0.11+：引入窗口函数支持，是大数据引擎中较早支持的

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **支持状态** | 3.25.0+（2018 年）才支持，覆盖主要窗口函数 | 支持但函数覆盖不如 PG 全面 | 完整支持，且独有 QUALIFY 子句直接过滤 | PG 8.4+/Oracle 8i+/MySQL 8.0+ |
| **QUALIFY 子句** | 不支持（需子查询包装过滤） | 不支持 | 支持：`SELECT ... QUALIFY ROW_NUMBER() OVER(...) = 1` | 不支持（Snowflake/Databricks 也支持） |
| **GROUPS 帧** | 3.28.0+ 支持 GROUPS 帧类型 | 不支持 GROUPS | 不支持 GROUPS | PG 11+ 支持，MySQL 8.0 不支持 |
| **命名窗口** | 支持 WINDOW w AS (...) | 支持 | 支持 | PG/MySQL 8.0+ 支持 |
| **性能考量** | 单线程执行，大数据量下窗口函数慢 | 列式存储利于聚合类窗口函数，但分布式窗口可能需 shuffle | 按扫描量计费，窗口函数扫描数据会产生费用 | 优化器成熟，利用索引优化窗口操作 |
