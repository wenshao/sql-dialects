# 层级查询 (HIERARCHICAL QUERY)

各数据库层级/树形查询最佳实践，包括递归 CTE、CONNECT BY 等。

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
| **递归 CTE** | 3.8.3+ 支持递归 CTE（层级查询标准方案） | 有限递归 CTE 支持 | 支持递归 CTE | PG/MySQL 8.0+/SQL Server 支持 |
| **CONNECT BY** | 不支持 | 不支持 | 不支持 | Oracle 独有的 CONNECT BY LEVEL/PRIOR 语法 |
| **递归深度** | 可配置（SQLITE_MAX_VARIABLE_NUMBER） | 有限制 | 有递归深度限制 | PG 默认无限 / MySQL 默认 1000 / SQL Server 默认 100 |
| **替代方案** | 递归 CTE 是唯一方案 | 物化路径（path 列）预计算层级 | 递归 CTE 或预计算嵌套集合 | 递归 CTE / CONNECT BY / 嵌套集合模型 |

## 引擎开发者视角

**核心设计决策**：层级查询是递归 CTE 的核心应用场景。是否支持 Oracle 的 CONNECT BY 语法（非标准但功能强大）是兼容性决策。

**实现建议**：
- 递归 CTE 是 SQL 标准的层级查询方案，应优先实现。Oracle 的 CONNECT BY PRIOR 语法虽然更简洁但不可移植——如果需要 Oracle 兼容则同时支持两者
- 递归 CTE 的循环检测是安全要求：树形数据中如果存在循环引用（A->B->C->A），朴素的递归会无限循环。SQL:1999 定义了 CYCLE 子句（`CYCLE id SET is_cycle TO 'Y' DEFAULT 'N'`），推荐实现
- 路径构建（在递归过程中拼接祖先到当前节点的路径字符串）是层级查询的常见需求。引擎应确保字符串拼接在递归中高效执行
- 递归 CTE 的并行化是难点：每次迭代依赖前一次的结果，天然是串行的。对于宽树（每层节点多、层数少），可以考虑在每层内部并行处理
- 物化路径（path 列预计算层级关系，如 '/1/2/3/'）是避免运行时递归的替代方案——引擎可以通过触发器或生成列自动维护物化路径
- 常见错误：递归 CTE 中 UNION 和 UNION ALL 的选择。UNION 会在每次迭代时去重（可以检测循环但性能差），UNION ALL 不去重（性能好但可能无限循环）。大多数层级查询应使用 UNION ALL 配合显式的循环检测
