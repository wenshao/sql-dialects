# TopN 查询 (RANKING / TOP-N)

各数据库 TopN 查询最佳实践，包括窗口函数、子查询、LIMIT 等方案。

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
