# 窗口分析 (WINDOW ANALYTICS)

各数据库窗口分析最佳实践，包括移动平均、同环比、占比计算等。

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

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **移动平均** | 3.25.0+ 支持 AVG() OVER (ROWS BETWEEN) | 支持窗口聚合 | 完整支持 + QUALIFY 过滤 | PG 8.4+/MySQL 8.0+/Oracle 8i+ |
| **同环比计算** | LAG/LEAD 窗口函数（3.25.0+） | 支持 LAG/LEAD | 完整支持 | 各方言窗口函数支持 |
| **占比计算** | SUM() OVER() 实现总计后除以 | SUM() OVER() 或 ratio 系列函数 | SUM() OVER() + QUALIFY | 标准窗口聚合方案 |
| **性能** | 单线程，大数据量下窗口函数较慢 | 列式存储聚合高效，分布式窗口可能需 shuffle | Serverless 弹性，按扫描量计费 | 优化器利用索引辅助 |

## 引擎开发者视角

**核心设计决策**：窗口分析（移动平均、同环比、占比计算）是窗口函数的综合应用。引擎对多窗口函数查询的优化能力（窗口合并、排序共享）决定了分析查询的性能。

**实现建议**：
- 多个窗口函数共享相同的 PARTITION BY + ORDER BY 时应只排序一次——优化器应自动检测兼容的窗口规范并合并为同一个排序阶段。WINDOW 子句（`WINDOW w AS (PARTITION BY ... ORDER BY ...)`）为此提供了显式的用户提示
- 同环比计算（LAG(value, 1)/LAG(value, 12) 按月/按年偏移）对 ORDER BY 的确定性有严格要求——如果时间列不唯一，LAG/LEAD 的结果会不确定。引擎应在此场景下发出警告
- 占比计算（`value / SUM(value) OVER()`）涉及两层窗口：分子是当前行值，分母是全窗口聚合。优化器应识别出分母是常量（每行相同）并只计算一次
- RATIO_TO_REPORT 是 Oracle 的内置占比函数——对分析场景很有用但 PostgreSQL/MySQL 没有。如果目标是分析型引擎，提供此函数可以减少用户的样板代码
- 流处理引擎（Flink SQL/ksqlDB）的窗口分析涉及时间窗口概念（Tumbling/Sliding/Session Window），与批处理引擎的窗口函数语义不同——需要在文档中明确区分
- 常见错误：窗口函数中的 ORDER BY 与外层查询的 ORDER BY 不一致导致结果混乱。引擎应在可能时警告用户显式指定外层 ORDER BY
