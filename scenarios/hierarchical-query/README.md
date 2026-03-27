# 层级查询 (HIERARCHICAL QUERY)

各数据库层级/树形查询最佳实践，包括递归 CTE、CONNECT BY 等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | 递归 CTE(8.0+)，此前无原生层级查询 |
| [PostgreSQL](postgres.sql) | 递归 CTE + SEARCH/CYCLE(14+)，ltree 扩展 |
| [SQLite](sqlite.sql) | 递归 CTE(3.8.3+)，轻量层级查询 |
| [Oracle](oracle.sql) | CONNECT BY 经典语法 + 递归 CTE(11gR2+) |
| [SQL Server](sqlserver.sql) | 递归 CTE + hierarchyid 类型 |
| [MariaDB](mariadb.sql) | 递归 CTE(10.2.1+)，兼容 MySQL |
| [Firebird](firebird.sql) | 递归 CTE(2.1+) 层级查询 |
| [IBM Db2](db2.sql) | 递归 CTE，最早支持的方言之一 |
| [SAP HANA](saphana.sql) | HIERARCHY 函数原生层级支持 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | 递归 CTE 层级查询 |
| [Snowflake](snowflake.sql) | 递归 CTE + CONNECT BY 兼容 |
| [ClickHouse](clickhouse.sql) | 无递归 CTE，hierarchicalDictionary 有限 |
| [Hive](hive.sql) | 无递归 CTE，需多次 JOIN 或 UDF |
| [Spark SQL](spark.sql) | 无递归 CTE，GraphX/DataFrame 迭代 |
| [Flink SQL](flink.sql) | 无递归 CTE 支持 |
| [StarRocks](starrocks.sql) | 无递归 CTE 支持 |
| [Doris](doris.sql) | 无递归 CTE 支持 |
| [Trino](trino.sql) | 递归 CTE(362+) 支持 |
| [DuckDB](duckdb.sql) | 递归 CTE 完整支持 |
| [MaxCompute](maxcompute.sql) | 无递归 CTE，需多次迭代 |
| [Hologres](hologres.sql) | 递归 CTE(PG 兼容) |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | 无递归 CTE 支持 |
| [Azure Synapse](synapse.sql) | 递归 CTE 支持 |
| [Databricks SQL](databricks.sql) | 无递归 CTE 支持 |
| [Greenplum](greenplum.sql) | 递归 CTE(PG 兼容) |
| [Impala](impala.sql) | 无递归 CTE 支持 |
| [Vertica](vertica.sql) | 递归 CTE + CONNECT BY 兼容 |
| [Teradata](teradata.sql) | 递归 CTE，最早标准化 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | 递归 CTE(5.1+) 支持 |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 模式递归查询 |
| [CockroachDB](cockroachdb.sql) | 递归 CTE(PG 兼容) |
| [Spanner](spanner.sql) | 递归 CTE 支持 |
| [YugabyteDB](yugabytedb.sql) | 递归 CTE(PG 兼容) |
| [PolarDB](polardb.sql) | MySQL 兼容递归 CTE |
| [openGauss](opengauss.sql) | 递归 CTE + CONNECT BY 兼容 |
| [TDSQL](tdsql.sql) | MySQL 兼容递归 CTE |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | CONNECT BY(Oracle 兼容) + 递归 CTE |
| [KingbaseES](kingbase.sql) | PG 兼容递归 CTE |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 递归 CTE |
| [TDengine](tdengine.sql) | 不支持层级查询 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 不支持层级查询 |
| [Materialize](materialize.sql) | 递归 CTE 不支持(非递归 CTE 可用) |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 递归 CTE 支持 |
| [Derby](derby.sql) | 递归 CTE 支持(10.14+) |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:1999 WITH RECURSIVE 规范 |

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
