# 公共表表达式 (CTE)

各数据库 CTE 语法对比，包括普通 CTE 和递归 CTE。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | 8.0+ CTE 和递归 CTE 支持 |
| [PostgreSQL](postgres.sql) | 完整 CTE，RECURSIVE，可写 CTE(INSERT/UPDATE) |
| [SQLite](sqlite.sql) | 3.8.3+ CTE，3.34+ 物化提示 |
| [Oracle](oracle.sql) | CTE + 递归(11gR2+)，SEARCH/CYCLE 子句 |
| [SQL Server](sqlserver.sql) | CTE + 递归，OPTION(MAXRECURSION) |
| [MariaDB](mariadb.sql) | 10.2.1+ CTE + 递归支持 |
| [Firebird](firebird.sql) | 3.0+ CTE + 递归支持 |
| [IBM Db2](db2.sql) | CTE + 递归，最早支持的方言之一 |
| [SAP HANA](saphana.sql) | CTE + 递归支持 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | CTE + 递归(脚本模式中) |
| [Snowflake](snowflake.sql) | CTE + 递归支持 |
| [ClickHouse](clickhouse.sql) | CTE 支持(非物化)，无递归 |
| [Hive](hive.sql) | CTE 支持，无递归 |
| [Spark SQL](spark.sql) | CTE 支持，无递归 |
| [Flink SQL](flink.sql) | CTE 支持，无递归 |
| [StarRocks](starrocks.sql) | CTE 支持(2.5+)，无递归 |
| [Doris](doris.sql) | CTE 支持(1.2+)，无递归 |
| [Trino](trino.sql) | CTE + 递归支持 |
| [DuckDB](duckdb.sql) | CTE + 递归，自动物化 |
| [MaxCompute](maxcompute.sql) | CTE 支持，无递归 |
| [Hologres](hologres.sql) | CTE 支持(PG 兼容) |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | CTE 支持，无递归(截止最新版) |
| [Azure Synapse](synapse.sql) | CTE + 递归支持 |
| [Databricks SQL](databricks.sql) | CTE 支持，无递归 |
| [Greenplum](greenplum.sql) | PG 兼容 CTE + 递归 |
| [Impala](impala.sql) | CTE 支持，无递归 |
| [Vertica](vertica.sql) | CTE + 递归支持 |
| [Teradata](teradata.sql) | CTE + 递归支持，最早标准化 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 CTE(5.1+)，递归支持 |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式 CTE |
| [CockroachDB](cockroachdb.sql) | PG 兼容 CTE + 递归 |
| [Spanner](spanner.sql) | CTE + 递归支持 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 CTE + 递归 |
| [PolarDB](polardb.sql) | MySQL 兼容 CTE |
| [openGauss](opengauss.sql) | PG 兼容 CTE + 递归 |
| [TDSQL](tdsql.sql) | MySQL 兼容 CTE |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容 CTE |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG CTE + 递归 |
| [TDengine](tdengine.sql) | 不支持 CTE |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 不支持 CTE |
| [Materialize](materialize.sql) | PG 兼容 CTE |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | CTE + 递归支持 |
| [Derby](derby.sql) | CTE 支持(10.14+) |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:1999 WITH RECURSIVE 规范 |

## 核心差异

1. **递归 CTE 终止**：各方言的最大递归深度不同：PostgreSQL 默认无限（需自行控制），MySQL 默认 1000（cte_max_recursion_depth），SQL Server 默认 100（OPTION MAXRECURSION）
2. **CTE 物化行为**：PostgreSQL 12+ 可以用 MATERIALIZED/NOT MATERIALIZED 控制 CTE 是否物化，MySQL 的优化器自动决定，Oracle 的 CTE 通常会物化
3. **DML 中的 CTE**：PostgreSQL 支持 WITH ... INSERT/UPDATE/DELETE（可写 CTE），MySQL 8.0 只支持 WITH ... SELECT，SQL Server 支持部分场景
4. **多个 CTE**：所有支持 CTE 的方言都支持用逗号分隔多个 CTE，后面的 CTE 可以引用前面定义的 CTE

## 选型建议

CTE 的最大价值是提高 SQL 可读性：将复杂查询分解为命名的逻辑步骤。递归 CTE 用于层级查询和序列生成。注意 CTE 不一定比子查询更快——在某些方言中 CTE 会强制物化导致无法利用外层查询的过滤条件下推。

## 版本演进

- MySQL 8.0：首次支持 CTE（包括递归 CTE），之前完全不支持
- SQLite 3.8.3+：支持普通 CTE，3.34.0+ 支持递归 CTE 的 MATERIALIZED hint
- PostgreSQL 12+：CTE 默认从"总是物化"改为"按需物化"，这是重大性能改进
- ClickHouse：支持非递归 CTE（WITH 子句），但递归 CTE 支持有限

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **CTE 支持** | 3.8.3+ 支持普通 CTE，3.34.0+ 支持 MATERIALIZED hint | 支持非递归 CTE（WITH 子句），递归 CTE 支持有限 | 完整支持普通和递归 CTE | MySQL 8.0+/PG/Oracle/SQL Server 均支持 |
| **递归 CTE** | 支持，默认递归深度限制可配置 | 有限支持（部分版本/场景） | 支持递归 CTE，有递归深度限制 | PG 默认无限制，MySQL 默认 1000，SQL Server 默认 100 |
| **物化控制** | 3.34.0+ 支持 MATERIALIZED/NOT MATERIALIZED | 通常内联展开 | 优化器自动决定 | PG 12+ 支持 MATERIALIZED/NOT MATERIALIZED |
| **可写 CTE** | 不支持 | 不支持 | 不支持 | PG 支持 WITH ... INSERT/UPDATE/DELETE |
| **事务上下文** | CTE 在 SQLite 事务中执行 | 无传统事务，CTE 在查询管道中执行 | CTE 在查询的快照隔离中执行 | CTE 在当前事务隔离级别中执行 |

## 引擎开发者视角

**核心设计决策**：CTE 的物化策略直接影响查询性能。需要决定：CTE 默认是物化（独立计算并缓存结果）还是内联展开（作为子查询嵌入外层查询）。

**实现建议**：
- PostgreSQL 12 之前的"CTE 总是物化"是设计教训——阻止了优化器将外层过滤条件下推到 CTE 内部。推荐默认内联展开，让优化器决定是否物化（PostgreSQL 12+ 的行为）
- MATERIALIZED / NOT MATERIALIZED hint 应提供给用户——当 CTE 被多次引用时，物化可以避免重复计算；当 CTE 只引用一次时，内联展开允许更多优化
- 递归 CTE 的终止条件检测是安全要求：必须有最大递归深度限制（MySQL 的 1000 或 SQL Server 的 100 都是合理默认值），并在达到限制时报明确的错误
- 递归 CTE 的实现通常使用工作表（working table）方式：每次迭代将新产生的行放入工作表，作为下次迭代的输入。终止条件是工作表为空。循环检测（避免无限递归）可以用 CYCLE 子句实现
- 可写 CTE（WITH ... INSERT/UPDATE/DELETE，PostgreSQL 特有）实现复杂但功能强大——可以在一条语句中完成 ETL 流水线。不建议新引擎优先实现
- 常见错误：CTE 的列类型推导在递归 CTE 中特别容易出错——递归部分的列类型必须与基础部分兼容，否则每次迭代可能产生类型变化
