# 窗口分析 (WINDOW ANALYTICS)

各数据库窗口分析最佳实践，包括移动平均、同环比、占比计算等。

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | 8.0+ 窗口聚合，移动平均/累计/占比 |
| [PostgreSQL](postgres.sql) | 完整窗口帧，FILTER 条件聚合 |
| [SQLite](sqlite.sql) | 3.25+ 窗口分析支持 |
| [Oracle](oracle.sql) | RATIO_TO_REPORT/PERCENT_RANK，分析最丰富 |
| [SQL Server](sqlserver.sql) | SUM/AVG/COUNT OVER，PERCENTILE_CONT |
| [MariaDB](mariadb.sql) | 10.2+ 窗口分析支持 |
| [Firebird](firebird.sql) | 3.0+ 窗口分析支持 |
| [IBM Db2](db2.sql) | OLAP 规范，完整窗口分析 |
| [SAP HANA](saphana.sql) | 内存加速窗口分析 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | 完整窗口分析 + QUALIFY 过滤 |
| [Snowflake](snowflake.sql) | 完整窗口分析 + QUALIFY 过滤 |
| [ClickHouse](clickhouse.sql) | 窗口函数 + -If 组合器灵活 |
| [Hive](hive.sql) | 0.11+ 窗口分析，大数据场景常用 |
| [Spark SQL](spark.sql) | 完整窗口分析，分布式执行 |
| [Flink SQL](flink.sql) | Over Window 流式增量分析 |
| [StarRocks](starrocks.sql) | 完整窗口分析支持 |
| [Doris](doris.sql) | 完整窗口分析支持 |
| [Trino](trino.sql) | 完整窗口分析支持 |
| [DuckDB](duckdb.sql) | 完整窗口分析 + QUALIFY |
| [MaxCompute](maxcompute.sql) | 完整窗口分析支持 |
| [Hologres](hologres.sql) | PG 兼容窗口分析 |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | 完整窗口分析支持 |
| [Azure Synapse](synapse.sql) | 完整窗口分析(T-SQL 兼容) |
| [Databricks SQL](databricks.sql) | 完整窗口分析 + QUALIFY |
| [Greenplum](greenplum.sql) | PG 兼容窗口分析 |
| [Impala](impala.sql) | 完整窗口分析支持 |
| [Vertica](vertica.sql) | 分析优化，投影加速 |
| [Teradata](teradata.sql) | QUALIFY 原创，窗口分析完整 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容窗口分析 |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 模式窗口分析 |
| [CockroachDB](cockroachdb.sql) | PG 兼容窗口分析 |
| [Spanner](spanner.sql) | 完整窗口分析支持 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容窗口分析 |
| [PolarDB](polardb.sql) | MySQL 兼容窗口分析 |
| [openGauss](opengauss.sql) | PG 兼容窗口分析 |
| [TDSQL](tdsql.sql) | MySQL 兼容窗口分析 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容分析函数 |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 窗口 + time_bucket 分析 |
| [TDengine](tdengine.sql) | 内建 TWA/SPREAD/DIFF 时序分析 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 不支持窗口函数(用 WINDOW 聚合) |
| [Materialize](materialize.sql) | PG 兼容窗口分析 |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 标准窗口分析支持 |
| [Derby](derby.sql) | 有限窗口函数支持 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 窗口分析规范 |

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
