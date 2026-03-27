# 缓慢变化维 (SLOWLY CHANGING DIMENSION)

各数据库缓慢变化维（SCD）实现最佳实践，包括 Type 1/2/3 实现。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | 手动 INSERT/UPDATE 实现 SCD，无原生支持 |
| [PostgreSQL](postgres.sql) | TRIGGER + 历史表，temporal_tables 扩展 |
| [SQLite](sqlite.sql) | 手动 INSERT/UPDATE 实现 SCD |
| [Oracle](oracle.sql) | Flashback Data Archive / MERGE 实现 SCD2 |
| [SQL Server](sqlserver.sql) | Temporal Table(2016+) 原生系统版本化 |
| [MariaDB](mariadb.sql) | System Versioned Table(10.3+) 原生支持 |
| [Firebird](firebird.sql) | 手动实现 SCD，无原生支持 |
| [IBM Db2](db2.sql) | Temporal Table(时态表)原生支持 |
| [SAP HANA](saphana.sql) | History Table / SCD 存储过程 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | MERGE INTO 实现 SCD2 |
| [Snowflake](snowflake.sql) | MERGE + Stream/Task 自动化 SCD |
| [ClickHouse](clickhouse.sql) | ReplacingMergeTree + VERSION 列 |
| [Hive](hive.sql) | INSERT OVERWRITE 全量快照/MERGE SCD2 |
| [Spark SQL](spark.sql) | Delta Lake MERGE INTO 实现 SCD2 |
| [Flink SQL](flink.sql) | CDC + Temporal Table 实时维度 |
| [StarRocks](starrocks.sql) | Primary Key 模型 + 版本列 |
| [Doris](doris.sql) | Unique Key + 序列列实现版本 |
| [Trino](trino.sql) | MERGE INTO(401+) 实现 SCD |
| [DuckDB](duckdb.sql) | MERGE/INSERT OR REPLACE 实现 SCD |
| [MaxCompute](maxcompute.sql) | 全量快照覆盖/增量 MERGE |
| [Hologres](hologres.sql) | Binlog CDC + MERGE 方案 |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | MERGE INTO(2023+) 或 DELETE+INSERT |
| [Azure Synapse](synapse.sql) | Temporal Table / CTAS 方案 |
| [Databricks SQL](databricks.sql) | Delta Lake MERGE INTO SCD2 原生 |
| [Greenplum](greenplum.sql) | MERGE 或 DELETE+INSERT 方案 |
| [Impala](impala.sql) | Kudu UPSERT / Iceberg MERGE |
| [Vertica](vertica.sql) | MERGE INTO 实现 SCD |
| [Teradata](teradata.sql) | Temporal Table 原生支持 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 MERGE 替代方案 |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 模式 MERGE |
| [CockroachDB](cockroachdb.sql) | 无原生 SCD，INSERT+UPDATE 方案 |
| [Spanner](spanner.sql) | DML MERGE 实现 SCD |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 TRIGGER 方案 |
| [PolarDB](polardb.sql) | MySQL 兼容，手动实现 |
| [openGauss](opengauss.sql) | PG 兼容 TRIGGER 方案 |
| [TDSQL](tdsql.sql) | MySQL 兼容，手动实现 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容 MERGE |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG + 时间维度天然适配 |
| [TDengine](tdengine.sql) | 不适用(时序追加模型) |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 不适用(流式处理) |
| [Materialize](materialize.sql) | 不适用(流式增量视图) |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 手动实现 SCD |
| [Derby](derby.sql) | 手动实现 SCD |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2011 Temporal Table 规范 |

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **SCD Type 1** | 标准 UPDATE 覆盖旧值 | ALTER TABLE UPDATE（异步 mutation），代价高 | UPDATE 语法（受 DML 配额限制） | 标准 UPDATE |
| **SCD Type 2** | INSERT 新行 + UPDATE 旧行关闭 | INSERT 新行 + UPDATE 关闭旧行（mutation 代价高） | MERGE 语法实现 SCD2（最简洁） | MERGE / INSERT + UPDATE |
| **时间旅行** | 不支持（需手动管理版本） | 不支持时间旅行查询 | 支持 FOR SYSTEM_TIME（7 天时间旅行查询） | Oracle Flashback / PG 无原生支持 |
| **适用场景** | 小型数仓的维度管理 | 大数据量维度表，但 UPDATE 代价高 | 云数仓 SCD 管理的首选方案 | 传统数仓标准方案 |

## 引擎开发者视角

**核心设计决策**：缓慢变化维（SCD）是数仓的经典模式。引擎是否提供内置的时间旅行查询（temporal query）或版本化表决定了 SCD 实现的复杂度。

**实现建议**：
- SCD Type 2（保留历史版本，用 valid_from/valid_to 标记有效期）在引擎层面可以通过 SYSTEM VERSIONING（SQL:2011 的时态表标准）原生支持——MariaDB 的 System-Versioned Tables 是参考实现
- MERGE 语句是 SCD Type 2 的最自然实现方式：WHEN MATCHED AND data_changed THEN UPDATE（关闭旧行）+ INSERT（新版本行）。引擎如果支持 MERGE 的多分支语义，SCD 实现会非常简洁
- 时间旅行查询（`SELECT * FROM t FOR SYSTEM_TIME AS OF '2024-01-01'`）对审计和历史分析至关重要。BigQuery 的 7 天时间旅行和 Snowflake 的 90 天时间旅行基于存储层的版本保留实现
- 对于列式引擎，SCD Type 1（直接覆盖更新）代价高昂（需要重写数据块）。替代方案：用 SCD Type 2（追加新版本）+ 查询时取最新版本（ROW_NUMBER 过滤），这与列式引擎的 append-only 哲学更契合
- DELETE + INSERT 模式在 SCD 中常见——引擎应确保这两个操作在同一事务中的原子性
- 常见错误：SCD Type 2 的 valid_to 列使用 NULL 表示"当前有效"还是使用极大日期（如 '9999-12-31'）。NULL 语义上更正确但 JOIN 条件中 NULL 需要特殊处理——引擎应在文档中给出最佳实践建议
