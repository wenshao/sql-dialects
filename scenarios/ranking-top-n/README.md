# TopN 查询 (RANKING / TOP-N)

各数据库 TopN 查询最佳实践，包括窗口函数、子查询、LIMIT 等方案。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | ROW_NUMBER(8.0+) 或 LIMIT+变量模拟 |
| [PostgreSQL](postgres.sql) | ROW_NUMBER/RANK + DISTINCT ON 简洁方案 |
| [SQLite](sqlite.sql) | ROW_NUMBER(3.25+) 或 LIMIT 子查询 |
| [Oracle](oracle.sql) | ROW_NUMBER/RANK + ROWNUM，分析函数丰富 |
| [SQL Server](sqlserver.sql) | ROW_NUMBER/RANK + TOP WITH TIES |
| [MariaDB](mariadb.sql) | ROW_NUMBER(10.2+) 或 LIMIT |
| [Firebird](firebird.sql) | ROW_NUMBER(3.0+) + FIRST/SKIP |
| [IBM Db2](db2.sql) | ROW_NUMBER + FETCH FIRST 排名 |
| [SAP HANA](saphana.sql) | ROW_NUMBER/RANK 完整支持 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | ROW_NUMBER+QUALIFY 一步 Top-N |
| [Snowflake](snowflake.sql) | ROW_NUMBER+QUALIFY 一步 Top-N |
| [ClickHouse](clickhouse.sql) | ROW_NUMBER + LIMIT BY(独有) |
| [Hive](hive.sql) | ROW_NUMBER/RANK 排名 |
| [Spark SQL](spark.sql) | ROW_NUMBER/RANK 排名 |
| [Flink SQL](flink.sql) | ROW_NUMBER TOP-N 模式(流式) |
| [StarRocks](starrocks.sql) | ROW_NUMBER/RANK 排名 |
| [Doris](doris.sql) | ROW_NUMBER/RANK 排名 |
| [Trino](trino.sql) | ROW_NUMBER/RANK 排名 |
| [DuckDB](duckdb.sql) | ROW_NUMBER+QUALIFY 一步 Top-N |
| [MaxCompute](maxcompute.sql) | ROW_NUMBER/RANK 排名 |
| [Hologres](hologres.sql) | ROW_NUMBER(PG 兼容) |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | ROW_NUMBER/RANK 排名 |
| [Azure Synapse](synapse.sql) | ROW_NUMBER/RANK + TOP(T-SQL) |
| [Databricks SQL](databricks.sql) | ROW_NUMBER+QUALIFY 排名 |
| [Greenplum](greenplum.sql) | PG 兼容 ROW_NUMBER + DISTINCT ON |
| [Impala](impala.sql) | ROW_NUMBER/RANK 排名 |
| [Vertica](vertica.sql) | ROW_NUMBER/RANK + LIMIT |
| [Teradata](teradata.sql) | QUALIFY ROW_NUMBER 原创方案 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 ROW_NUMBER |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 模式排名 |
| [CockroachDB](cockroachdb.sql) | PG 兼容 ROW_NUMBER |
| [Spanner](spanner.sql) | ROW_NUMBER/RANK 排名 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 DISTINCT ON |
| [PolarDB](polardb.sql) | MySQL 兼容 ROW_NUMBER |
| [openGauss](opengauss.sql) | PG 兼容 DISTINCT ON |
| [TDSQL](tdsql.sql) | MySQL 兼容 ROW_NUMBER |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | ROWNUM/ROW_NUMBER(Oracle 兼容) |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG ROW_NUMBER |
| [TDengine](tdengine.sql) | TOP()/BOTTOM() 内建函数 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | TOPK/TOPKDISTINCT 聚合 |
| [Materialize](materialize.sql) | ROW_NUMBER(PG 兼容) |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | ROW_NUMBER/RANK 支持 |
| [Derby](derby.sql) | ROW_NUMBER + FETCH FIRST |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 ROW_NUMBER/RANK + FETCH FIRST |

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **窗口函数方案** | 3.25.0+ 支持 ROW_NUMBER/RANK/DENSE_RANK | 支持 ROW_NUMBER 等基本窗口函数 | 完整支持 + QUALIFY 可直接过滤 Top-N 无需子查询 | PG 8.4+/MySQL 8.0+/Oracle 8i+ 支持 |
| **无窗口函数替代** | 旧版本需自连接或 LIMIT 分组模拟 | 通常有窗口函数可用 | 通常有窗口函数可用 | MySQL 5.7 需变量模拟 ROW_NUMBER |
| **LIMIT 语法** | LIMIT/OFFSET（简单 Top-N 直接可用） | LIMIT/OFFSET | LIMIT/OFFSET | 各方言语法不同（TOP/FETCH FIRST/ROWNUM） |
| **性能** | 单文件，小数据高效 | 列式存储分布式 Top-N 高效 | Serverless 按扫描量计费 | 索引辅助排序可加速 |

## 引擎开发者视角

**核心设计决策**：Top-N 查询是最常见的分析模式之一。优化器对 `ORDER BY ... LIMIT N` 的优化能力（是否能避免全量排序）直接影响查询性能。

**实现建议**：
- Top-N 优化（ORDER BY + LIMIT）应使用堆排序（只维护 N 个元素的堆），而非全量排序后截取——对于从百万行中取 Top 10，堆排序的 O(n*log(k)) 远优于全量排序的 O(n*log(n))
- 分组 Top-N（每组取前 N 行）通常用 ROW_NUMBER 窗口函数 + 子查询过滤实现。QUALIFY 子句是更优雅的方案：`SELECT * FROM t QUALIFY ROW_NUMBER() OVER(PARTITION BY group_col ORDER BY val DESC) <= 3`
- 分布式 Top-N 需要两阶段执行：每个节点先计算局部 Top-N，协调节点再合并全局 Top-N。对于 Top-N 较小的场景（如 Top 10），每个节点只需传输少量数据
- ROW_NUMBER vs RANK vs DENSE_RANK 的区别应在文档和错误提示中清晰说明——用户经常混淆。ROW_NUMBER 保证唯一编号（并列时随机），RANK 并列相同编号但跳号，DENSE_RANK 并列相同编号且不跳号
- 如果索引已按 ORDER BY 列排序，Top-N 可以直接从索引读取前 N 行——优化器应能识别此场景避免任何排序操作
- 常见错误：Top-N 查询的稳定性（determinism）。如果 ORDER BY 列有重复值，每次执行可能返回不同的行——引擎应在 ORDER BY 中默认追加主键作为 tie-breaker，或至少发出警告
