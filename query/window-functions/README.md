# 窗口函数 (WINDOW FUNCTIONS)

各数据库窗口函数语法对比，包括 ROW_NUMBER、RANK、LAG/LEAD、NTILE 等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | 8.0+ 首次支持，ROW_NUMBER/RANK/LAG 等 |
| [PostgreSQL](postgres.sql) | 8.4+ 最完整，GROUPS 帧/EXCLUDE 子句 |
| [SQLite](sqlite.sql) | 3.25+ 支持，3.28+ GROUPS 帧 |
| [Oracle](oracle.sql) | 8i 最早支持，分析函数最丰富 |
| [SQL Server](sqlserver.sql) | 2012+ 完整支持，优化器成熟 |
| [MariaDB](mariadb.sql) | 10.2+ 窗口函数支持 |
| [Firebird](firebird.sql) | 3.0+ 窗口函数支持 |
| [IBM Db2](db2.sql) | 丰富窗口函数，OLAP 规范 |
| [SAP HANA](saphana.sql) | 完整窗口函数，内存加速 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | 完整支持 + QUALIFY 过滤 |
| [Snowflake](snowflake.sql) | 完整支持 + QUALIFY 过滤 |
| [ClickHouse](clickhouse.sql) | 支持主要窗口函数，部分限制 |
| [Hive](hive.sql) | 0.11+ 支持，覆盖常用函数 |
| [Spark SQL](spark.sql) | 完整窗口函数支持 |
| [Flink SQL](flink.sql) | 流式窗口(Over Window)，批模式完整 |
| [StarRocks](starrocks.sql) | 完整窗口函数支持 |
| [Doris](doris.sql) | 完整窗口函数支持 |
| [Trino](trino.sql) | 完整窗口函数支持 |
| [DuckDB](duckdb.sql) | 完整窗口函数 + QUALIFY |
| [MaxCompute](maxcompute.sql) | 完整窗口函数支持 |
| [Hologres](hologres.sql) | PG 兼容窗口函数 |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | 完整窗口函数(PG 兼容) |
| [Azure Synapse](synapse.sql) | 完整窗口函数支持 |
| [Databricks SQL](databricks.sql) | 完整窗口函数 + QUALIFY |
| [Greenplum](greenplum.sql) | PG 兼容窗口函数 |
| [Impala](impala.sql) | 完整窗口函数支持 |
| [Vertica](vertica.sql) | 完整窗口函数，分析优化 |
| [Teradata](teradata.sql) | QUALIFY 原创，完整窗口函数 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容窗口函数 |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式窗口函数 |
| [CockroachDB](cockroachdb.sql) | PG 兼容窗口函数 |
| [Spanner](spanner.sql) | 完整窗口函数支持 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容窗口函数 |
| [PolarDB](polardb.sql) | MySQL 兼容窗口函数 |
| [openGauss](opengauss.sql) | PG 兼容窗口函数 |
| [TDSQL](tdsql.sql) | MySQL 兼容窗口函数 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容分析函数 |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 窗口函数，时序分析利器 |
| [TDengine](tdengine.sql) | 有限分析函数(DIFF/SPREAD 等) |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 不支持窗口函数(用 WINDOW 聚合替代) |
| [Materialize](materialize.sql) | PG 兼容窗口函数 |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 标准窗口函数支持 |
| [Derby](derby.sql) | 10.4+ 有限窗口函数(ROW_NUMBER) |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 WINDOW 规范 / SQL:2011 GROUPS |

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

## 引擎开发者视角

**核心设计决策**：窗口函数是现代 SQL 的分水岭功能。实现复杂度高但价值大——缺少窗口函数的引擎会被归类为"不完整的 SQL 实现"。

**实现建议**：
- 最低实现：ROW_NUMBER + RANK + DENSE_RANK + LAG/LEAD + SUM/AVG/MIN/MAX OVER，覆盖 80% 的使用场景。NTILE 和 PERCENT_RANK 可延后
- ROWS 帧比 RANGE 帧实现简单得多（RANGE 需要处理值相等的情况，涉及有序集合操作）。GROUPS 帧（SQL:2011）更复杂，可以延后到成熟阶段
- 窗口函数的执行应尽可能共享排序：多个窗口函数使用相同的 PARTITION BY + ORDER BY 时只需排序一次。优化器应识别并合并兼容的窗口规范
- QUALIFY 子句（Snowflake/BigQuery/Teradata 首创）实现成本低但用户价值大——直接过滤窗口函数结果而无需子查询包装，推荐支持
- 窗口帧的默认值是常见的正确性陷阱：SQL 标准默认 RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW（不是 ROWS），这导致 SUM OVER (ORDER BY x) 在有重复值时行为不直观。引擎应在文档中明确此行为
- 常见错误：窗口函数不能嵌套（`ROW_NUMBER() OVER(ORDER BY SUM(x) OVER(...))`是不合法的）——解析器应给出清晰的错误信息而非通用语法错误
