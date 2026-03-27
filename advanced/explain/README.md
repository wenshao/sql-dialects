# 执行计划 (EXPLAIN)

各数据库执行计划语法对比，包括 EXPLAIN、EXPLAIN ANALYZE 等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | EXPLAIN/EXPLAIN ANALYZE(8.0+)，JSON 格式 |
| [PostgreSQL](postgres.sql) | EXPLAIN ANALYZE + BUFFERS/COSTS/TIMING 详细 |
| [SQLite](sqlite.sql) | EXPLAIN QUERY PLAN，简洁输出 |
| [Oracle](oracle.sql) | EXPLAIN PLAN/DBMS_XPLAN/V$SQL_PLAN |
| [SQL Server](sqlserver.sql) | SET SHOWPLAN_XML/实际执行计划/Statistics IO |
| [MariaDB](mariadb.sql) | EXPLAIN ANALYZE(10.1+)，兼容 MySQL |
| [Firebird](firebird.sql) | SET PLANONLY/EXPLAIN，简洁计划 |
| [IBM Db2](db2.sql) | EXPLAIN + db2exfmt 格式化工具 |
| [SAP HANA](saphana.sql) | EXPLAIN PLAN/PLAN VISUALIZATION |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | EXPLAIN(预估)/ INFORMATION_SCHEMA.JOBS |
| [Snowflake](snowflake.sql) | EXPLAIN + Query Profile(Web UI 可视化) |
| [ClickHouse](clickhouse.sql) | EXPLAIN PIPELINE/AST/SYNTAX/PLAN |
| [Hive](hive.sql) | EXPLAIN/EXPLAIN EXTENDED/EXPLAIN DEPENDENCY |
| [Spark SQL](spark.sql) | EXPLAIN EXTENDED/CODEGEN/COST/FORMATTED |
| [Flink SQL](flink.sql) | EXPLAIN PLAN FOR，执行图预览 |
| [StarRocks](starrocks.sql) | EXPLAIN/EXPLAIN ANALYZE/PROFILE |
| [Doris](doris.sql) | EXPLAIN/EXPLAIN ANALYZE |
| [Trino](trino.sql) | EXPLAIN/EXPLAIN ANALYZE + 分布式 Stage |
| [DuckDB](duckdb.sql) | EXPLAIN ANALYZE，内存分析 |
| [MaxCompute](maxcompute.sql) | EXPLAIN + Cost Estimator |
| [Hologres](hologres.sql) | EXPLAIN ANALYZE(PG 兼容) |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | EXPLAIN + SVL_QUERY_SUMMARY 系统表 |
| [Azure Synapse](synapse.sql) | EXPLAIN(T-SQL 执行计划) |
| [Databricks SQL](databricks.sql) | EXPLAIN EXTENDED/COST |
| [Greenplum](greenplum.sql) | PG 兼容 EXPLAIN + 分布式 Slice |
| [Impala](impala.sql) | EXPLAIN/PROFILE 查询剖析 |
| [Vertica](vertica.sql) | EXPLAIN + EXPLAIN VERBOSE |
| [Teradata](teradata.sql) | EXPLAIN 文本计划(Step 描述) |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | EXPLAIN ANALYZE，TiFlash 执行路径 |
| [OceanBase](oceanbase.sql) | EXPLAIN + 计划缓存 GV$PLAN_CACHE |
| [CockroachDB](cockroachdb.sql) | EXPLAIN ANALYZE(DISTSQL)分布式计划 |
| [Spanner](spanner.sql) | EXPLAIN/Query Execution Plan |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 EXPLAIN ANALYZE |
| [PolarDB](polardb.sql) | MySQL 兼容 EXPLAIN |
| [openGauss](opengauss.sql) | PG 兼容 EXPLAIN ANALYZE |
| [TDSQL](tdsql.sql) | MySQL 兼容 EXPLAIN |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | EXPLAIN 支持 |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG EXPLAIN + chunk 过滤可见 |
| [TDengine](tdengine.sql) | EXPLAIN 支持(3.0+) |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | EXPLAIN 查询拓扑 |
| [Materialize](materialize.sql) | EXPLAIN PLAN/TIMESTAMP/DECORRELATED |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | EXPLAIN ANALYZE 支持 |
| [Derby](derby.sql) | RUNTIMESTATISTICS 执行统计 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 无标准 EXPLAIN(厂商扩展) |

## 核心差异

1. **输出格式**：MySQL 的 EXPLAIN 默认表格格式（8.0+ 支持 TREE/JSON），PostgreSQL 默认文本树形（支持 JSON/YAML/XML），Oracle 用 DBMS_XPLAN，SQL Server 用图形化执行计划
2. **EXPLAIN ANALYZE**：PostgreSQL 和 MySQL 8.0+ 支持 EXPLAIN ANALYZE（实际执行并返回真实耗时），Oracle 需要 SQL Trace + TKPROF
3. **成本模型**：各方言的成本单位和估算算法完全不同，PostgreSQL 的 cost 是相对值，MySQL 的 cost 是估算的 IO + CPU 操作数
4. **关键指标**：MySQL 重点看 type（ALL/index/range/ref/eq_ref）和 rows，PostgreSQL 重点看 Seq Scan vs Index Scan 和 actual time

## 选型建议

EXPLAIN 是 SQL 性能优化的第一工具，每个 DBA 都应精通所用方言的执行计划解读。EXPLAIN ANALYZE 会实际执行查询，对生产环境的 DML 语句（UPDATE/DELETE）要谨慎使用。PostgreSQL 的 EXPLAIN (ANALYZE, BUFFERS) 提供最详细的性能信息。

## 版本演进

- MySQL 8.0.18+：引入 EXPLAIN ANALYZE（之前只有 EXPLAIN 估算值）
- MySQL 8.0：引入 TREE 格式输出和 JSON 格式详细信息
- PostgreSQL 13+：EXPLAIN 增加 WAL 和 incremental sort 信息
- ClickHouse：clickhouse-client 的 `SET send_logs_level = 'trace'` 可以查看详细的查询管道

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **EXPLAIN 语法** | EXPLAIN QUERY PLAN（返回简单树形结构） | EXPLAIN 和 clickhouse-client 的 trace 日志 | EXPLAIN（DRY RUN 模式估算扫描量和费用） | MySQL EXPLAIN / PG EXPLAIN (ANALYZE) / Oracle DBMS_XPLAN |
| **EXPLAIN ANALYZE** | 不支持（无实际执行的性能分析） | 不支持传统 EXPLAIN ANALYZE | 不支持（但查询完成后可在 Job 信息中查看统计） | PG/MySQL 8.0.18+ 支持 |
| **关键指标** | 查看是否使用了索引（SEARCH vs SCAN） | 查看读取的 parts/marks 数量和处理行数 | 估算扫描字节数和计费金额（成本优化核心） | MySQL type/rows / PG Seq Scan vs Index Scan |
| **优化重点** | 确保使用索引，避免全表扫描 | 确保分区裁剪和排序键利用 | 减少扫描数据量降低费用 | 索引利用率和 JOIN 策略 |
| **分析深度** | 较浅，信息有限 | 中等，trace 日志可查看管道细节 | 侧重成本估算而非执行细节 | PG/Oracle 的 EXPLAIN 信息最详细 |

## 引擎开发者视角

**核心设计决策**：EXPLAIN 是引擎可观测性的窗口，输出质量直接影响用户能否有效优化查询。需要决定：输出格式（文本树/JSON/图形化）、是否支持 EXPLAIN ANALYZE（实际执行并返回运行时统计）。

**实现建议**：
- 最低实现：EXPLAIN 返回逻辑计划树，标注每个算子（Scan/Filter/Join/Sort/Aggregate）和预估行数。JSON 格式从第一天就应该支持——工具集成依赖结构化输出
- EXPLAIN ANALYZE 价值极大但要注意：DML 语句的 EXPLAIN ANALYZE 会真实执行写操作，PostgreSQL 的做法是在事务中运行然后回滚，这是推荐方案
- 成本模型要有意义：PostgreSQL 的相对成本单位（startup_cost + total_cost）比 MySQL 老版本的简单行估算更有用。但成本模型不需要一步到位，迭代改进即可
- 分布式引擎的 EXPLAIN 要额外展示数据移动（shuffle/broadcast）和网络传输量，这是性能调优的关键信息
- 提供 EXPLAIN VERBOSE 或类似选项展示额外信息（列投影、过滤条件下推情况、分区裁剪结果）
- 常见错误：EXPLAIN 的预估行数与实际行数差距过大。这通常源于统计信息过时——引擎应有自动或手动的 ANALYZE/统计信息收集机制
