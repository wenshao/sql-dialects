# 数据去重 (DEDUPLICATION)

各数据库数据去重最佳实践，包括 DISTINCT、ROW_NUMBER、GROUP BY 等方案。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | ROW_NUMBER+DELETE 或 GROUP BY+临时表 |
| [PostgreSQL](postgres.sql) | DISTINCT ON 最简洁，ctid 物理删除 |
| [SQLite](sqlite.sql) | ROWID 去重，ROW_NUMBER(3.25+) |
| [Oracle](oracle.sql) | ROWID 去重，ROW_NUMBER 分析函数 |
| [SQL Server](sqlserver.sql) | ROW_NUMBER+CTE DELETE，DISTINCT 查询 |
| [MariaDB](mariadb.sql) | 兼容 MySQL 去重方案 |
| [Firebird](firebird.sql) | ROW_NUMBER+DELETE 方案 |
| [IBM Db2](db2.sql) | ROW_NUMBER+DELETE，RID() 物理行 |
| [SAP HANA](saphana.sql) | ROW_NUMBER+DELETE 去重 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | ROW_NUMBER+QUALIFY 一步去重 |
| [Snowflake](snowflake.sql) | ROW_NUMBER+QUALIFY 一步去重 |
| [ClickHouse](clickhouse.sql) | ReplacingMergeTree 引擎级去重 |
| [Hive](hive.sql) | ROW_NUMBER+INSERT OVERWRITE 覆盖 |
| [Spark SQL](spark.sql) | dropDuplicates()/ROW_NUMBER 去重 |
| [Flink SQL](flink.sql) | ROW_NUMBER TOP-1 模式去重 |
| [StarRocks](starrocks.sql) | Unique Key 模型自动去重 |
| [Doris](doris.sql) | Unique Key 模型自动去重 |
| [Trino](trino.sql) | ROW_NUMBER 去重查询 |
| [DuckDB](duckdb.sql) | ROW_NUMBER+QUALIFY 去重 |
| [MaxCompute](maxcompute.sql) | ROW_NUMBER+INSERT OVERWRITE |
| [Hologres](hologres.sql) | PG 兼容 ctid/ROW_NUMBER 去重 |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | ROW_NUMBER+临时表覆盖 |
| [Azure Synapse](synapse.sql) | ROW_NUMBER+CTAS 去重 |
| [Databricks SQL](databricks.sql) | ROW_NUMBER+QUALIFY/Delta MERGE |
| [Greenplum](greenplum.sql) | PG 兼容 ctid 去重 |
| [Impala](impala.sql) | ROW_NUMBER 去重查询 |
| [Vertica](vertica.sql) | ANALYZE_STATISTICS + ROW_NUMBER |
| [Teradata](teradata.sql) | QUALIFY ROW_NUMBER 一步去重 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 ROW_NUMBER 去重 |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 模式去重 |
| [CockroachDB](cockroachdb.sql) | PG 兼容 DISTINCT ON |
| [Spanner](spanner.sql) | ROW_NUMBER 去重查询 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 DISTINCT ON |
| [PolarDB](polardb.sql) | MySQL 兼容去重 |
| [openGauss](opengauss.sql) | PG 兼容 DISTINCT ON/ctid |
| [TDSQL](tdsql.sql) | MySQL 兼容去重 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | ROWID 去重(Oracle 兼容) |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 去重方案 |
| [TDengine](tdengine.sql) | 相同时间戳自动覆盖(天然去重) |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | LATEST_BY_OFFSET 取最新值 |
| [Materialize](materialize.sql) | DISTINCT ON(PG 兼容) |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | ROW_NUMBER 去重 |
| [Derby](derby.sql) | ROW_NUMBER 去重 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 ROW_NUMBER/DISTINCT 规范 |

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
