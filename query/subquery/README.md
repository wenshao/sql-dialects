# 子查询 (SUBQUERY)

各数据库子查询语法对比，包括标量子查询、行子查询、EXISTS、IN 等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | 标量/表/EXISTS 子查询，8.0 优化器增强 |
| [PostgreSQL](postgres.sql) | 完整子查询 + LATERAL，优化器成熟 |
| [SQLite](sqlite.sql) | 标量/表/EXISTS 子查询，基本支持 |
| [Oracle](oracle.sql) | 完整子查询，标量子查询缓存 |
| [SQL Server](sqlserver.sql) | 完整子查询 + CROSS/OUTER APPLY |
| [MariaDB](mariadb.sql) | 兼容 MySQL 子查询 |
| [Firebird](firebird.sql) | 标准子查询支持 |
| [IBM Db2](db2.sql) | 完整子查询 + LATERAL 支持 |
| [SAP HANA](saphana.sql) | 标准子查询支持 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | 相关/非相关子查询 + ARRAY 子查询 |
| [Snowflake](snowflake.sql) | 完整子查询支持 |
| [ClickHouse](clickhouse.sql) | IN/JOIN 子查询，全局分布式(GLOBAL IN) |
| [Hive](hive.sql) | IN/EXISTS(0.13+)，相关子查询有限 |
| [Spark SQL](spark.sql) | 完整子查询(2.0+)，优化器下推 |
| [Flink SQL](flink.sql) | IN/EXISTS 子查询，有限相关子查询 |
| [StarRocks](starrocks.sql) | 完整子查询支持 |
| [Doris](doris.sql) | 完整子查询支持 |
| [Trino](trino.sql) | 完整子查询 + 相关子查询 |
| [DuckDB](duckdb.sql) | 完整子查询 + LATERAL |
| [MaxCompute](maxcompute.sql) | IN/EXISTS 子查询支持 |
| [Hologres](hologres.sql) | PG 兼容子查询 |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | 完整子查询(PG 兼容) |
| [Azure Synapse](synapse.sql) | 完整子查询支持 |
| [Databricks SQL](databricks.sql) | 完整子查询支持 |
| [Greenplum](greenplum.sql) | PG 兼容子查询 |
| [Impala](impala.sql) | IN/EXISTS 子查询(2.0+) |
| [Vertica](vertica.sql) | 完整子查询支持 |
| [Teradata](teradata.sql) | 完整子查询支持 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容子查询，自动去相关 |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式子查询 |
| [CockroachDB](cockroachdb.sql) | PG 兼容子查询 |
| [Spanner](spanner.sql) | 完整子查询支持 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容子查询 |
| [PolarDB](polardb.sql) | MySQL 兼容子查询 |
| [openGauss](opengauss.sql) | PG 兼容子查询 |
| [TDSQL](tdsql.sql) | MySQL 兼容子查询 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容子查询 |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 子查询 |
| [TDengine](tdengine.sql) | 有限子查询支持 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 不支持子查询 |
| [Materialize](materialize.sql) | PG 兼容子查询 |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 标准子查询支持 |
| [Derby](derby.sql) | 标准子查询支持 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:1992 子查询 / SQL:2003 LATERAL |

## 核心差异

1. **关联子查询性能**：MySQL 5.7 对 IN 子查询的优化较弱（可能逐行执行），8.0 改进显著；PostgreSQL 自动将 IN 子查询优化为 semi-join
2. **标量子查询位置**：所有方言支持 SELECT/WHERE 中的标量子查询，但 FROM 子句中的子查询（派生表）的列别名要求不同
3. **EXISTS vs IN**：语义上等价，但 EXISTS 在关联子查询中通常更高效（可以短路返回），IN 对 NULL 值有特殊行为（NOT IN 遇到 NULL 会返回空）
4. **LATERAL 子查询**：PostgreSQL/MySQL 8.0+ 支持 LATERAL 关键字使子查询可以引用外层 FROM 子句的列

## 选型建议

能用 JOIN 的场景优先用 JOIN 而非子查询（更易读且通常更高效）。需要"存在性检查"时用 EXISTS 而非 IN（避免 NOT IN 的 NULL 陷阱）。复杂子查询建议改写为 CTE（WITH 语法），可读性和可维护性更好。

## 版本演进

- MySQL 8.0：对 IN 子查询的 semi-join 优化显著改进，性能比 5.7 大幅提升
- PostgreSQL：子查询优化器一直很强，自动选择 semi-join/anti-join/materialize 等策略
- ClickHouse：IN 子查询会自动物化为临时集合，但 JOIN 子查询的分布式执行需要注意数据分布

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **子查询支持** | 完整支持标量/关联/派生表子查询 | 支持但关联子查询有限制，IN 子查询自动物化 | 完整支持所有子查询类型 | 完整支持 |
| **优化能力** | 优化器较简单，复杂子查询可能效率低 | IN 子查询自动物化为集合，避免重复执行 | Serverless 分布式优化器，自动选择执行策略 | PG/Oracle 优化器强大，自动 semi-join 等优化 |
| **LATERAL 子查询** | 不支持 | 有限支持 | 支持 | PG/MySQL 8.0+ 支持 |
| **动态类型影响** | 动态类型使子查询的类型匹配更宽松 | 严格类型，子查询返回类型必须匹配 | 严格类型，需显式 CAST | PG 严格 / MySQL 宽松 |

## 引擎开发者视角

**核心设计决策**：子查询的优化能力是衡量查询优化器成熟度的关键指标。朴素实现（逐行执行关联子查询）和高级优化（子查询解关联/semi-join 转换）的性能差距可达数个数量级。

**实现建议**：
- 子查询解关联（decorrelation/unnesting）是查询优化器最重要的优化之一：将关联子查询转换为 JOIN 操作，从 O(n*m) 降低到 O(n+m)。这是 MySQL 5.7 到 8.0 性能跃升的关键原因
- IN 子查询应自动转换为 Semi-Join：`WHERE id IN (SELECT id FROM t2)` 等价于 `WHERE EXISTS (SELECT 1 FROM t2 WHERE t2.id = t1.id)`，但 Semi-Join 可以利用 Hash Join 算法
- NOT IN 的 NULL 语义是著名陷阱：如果子查询结果包含 NULL，`NOT IN` 永远返回空集（三值逻辑）。优化器应将 NOT IN 转换为 NOT EXISTS + IS NOT NULL 检查
- 标量子查询（返回单一值的子查询）在 SELECT 列表中常见。如果标量子查询每行返回相同结果，应缓存其结果避免重复执行
- LATERAL 子查询（允许引用外层 FROM 子句的列）是参数化子查询的 SQL 语法表示。实现上等价于对外层每行执行一次嵌套循环——优化器应尝试解关联
- 常见错误：派生表（FROM 子句中的子查询）上的过滤条件无法下推到子查询内部。CTE 有同样的问题——优化器应能跨越子查询/CTE 边界进行谓词下推
