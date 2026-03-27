# 缓慢变化维 (SLOWLY CHANGING DIMENSION)

各数据库缓慢变化维（SCD）实现最佳实践，包括 Type 1/2/3 实现。

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
