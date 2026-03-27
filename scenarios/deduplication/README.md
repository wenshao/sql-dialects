# 数据去重 (DEDUPLICATION)

各数据库数据去重最佳实践，包括 DISTINCT、ROW_NUMBER、GROUP BY 等方案。

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
| **去重策略** | ROW_NUMBER + DELETE 或 CREATE TABLE AS SELECT 重建 | ReplacingMergeTree 引擎后台自动合并去重（最终一致） | MERGE 或 CREATE TABLE AS SELECT 重建 | ROW_NUMBER + DELETE / MERGE / CTE + DELETE |
| **去重时机** | 即时（DML 操作立即生效） | 最终一致：后台合并时去重，查询时可能看到重复 | DML 操作即时但受配额限制 | 即时 |
| **DISTINCT 性能** | 适合小数据集 | 列式存储 DISTINCT 高效，有 APPROX 近似去重 | 大数据集 DISTINCT 按扫描量计费 | 取决于索引和数据量 |
| **INSERT 防重** | UNIQUE 约束 + ON CONFLICT | PRIMARY KEY/ReplacingMergeTree（不强制即时唯一） | 约束不强制，需应用层防重 | UNIQUE 约束强制去重 |

## 引擎开发者视角

**核心设计决策**：去重是引擎级还是 SQL 级的责任。OLTP 引擎通过唯一约束在写入时防重，分析型引擎（如 ClickHouse 的 ReplacingMergeTree）在后台合并时去重——两种哲学适合不同场景。

**实现建议**：
- 写入时去重（UNIQUE 约束）是 OLTP 引擎的标准方案。实现依赖唯一索引——INSERT 时检查是否冲突，冲突时报错或执行 UPSERT 逻辑
- 读取时去重（查询时 DISTINCT/ROW_NUMBER）适合分析场景。优化器应将 DISTINCT 尽可能下推——如果能在扫描阶段去重就不要等到排序阶段
- ROW_NUMBER + DELETE（删除重复行保留一条）的模式在 CTE 中实现：`WITH dups AS (SELECT *, ROW_NUMBER() OVER(PARTITION BY key ORDER BY id) AS rn FROM t) DELETE FROM t WHERE id IN (SELECT id FROM dups WHERE rn > 1)`。引擎应确保这种模式的执行效率
- ClickHouse 的引擎级去重（ReplacingMergeTree 在后台合并时按版本号保留最新行）是列式引擎的创新方案——适合数据最终一致的场景
- DISTINCT 的实现与 GROUP BY 共享相同的去重基础设施（哈希或排序）。优化器应能将 `SELECT DISTINCT a, b FROM t` 转换为 `SELECT a, b FROM t GROUP BY a, b`
- 常见错误：DISTINCT ON（PostgreSQL 特有语法，按部分列去重）在其他引擎中没有等价语法。如果兼容 PostgreSQL，实现此特性可以减少用户需要写的 ROW_NUMBER 样板代码
