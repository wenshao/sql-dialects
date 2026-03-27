# 集合操作 (SET OPERATIONS)

各数据库集合操作语法对比，包括 UNION、INTERSECT、EXCEPT。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | UNION/UNION ALL，8.0+ INTERSECT/EXCEPT |
| [PostgreSQL](postgres.sql) | UNION/INTERSECT/EXCEPT + ALL，完整支持 |
| [SQLite](sqlite.sql) | UNION/INTERSECT/EXCEPT 完整支持 |
| [Oracle](oracle.sql) | UNION/INTERSECT/MINUS(非 EXCEPT) |
| [SQL Server](sqlserver.sql) | UNION/INTERSECT/EXCEPT 完整支持 |
| [MariaDB](mariadb.sql) | 10.3+ INTERSECT/EXCEPT |
| [Firebird](firebird.sql) | UNION 支持，无 INTERSECT/EXCEPT |
| [IBM Db2](db2.sql) | UNION/INTERSECT/EXCEPT 完整支持 |
| [SAP HANA](saphana.sql) | UNION/INTERSECT/EXCEPT 完整支持 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | UNION/INTERSECT/EXCEPT 完整支持 |
| [Snowflake](snowflake.sql) | UNION/INTERSECT/EXCEPT/MINUS |
| [ClickHouse](clickhouse.sql) | UNION ALL 为主，无 INTERSECT/EXCEPT |
| [Hive](hive.sql) | UNION ALL(1.2+)，INTERSECT/EXCEPT(2.1+) |
| [Spark SQL](spark.sql) | UNION/INTERSECT/EXCEPT 完整支持 |
| [Flink SQL](flink.sql) | UNION ALL/INTERSECT/EXCEPT 支持 |
| [StarRocks](starrocks.sql) | UNION/INTERSECT/EXCEPT 支持 |
| [Doris](doris.sql) | UNION/INTERSECT/EXCEPT 支持 |
| [Trino](trino.sql) | UNION/INTERSECT/EXCEPT 完整支持 |
| [DuckDB](duckdb.sql) | UNION/INTERSECT/EXCEPT + BY NAME |
| [MaxCompute](maxcompute.sql) | UNION ALL 支持，INTERSECT/EXCEPT 支持 |
| [Hologres](hologres.sql) | UNION/INTERSECT/EXCEPT(PG 兼容) |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | UNION/INTERSECT/EXCEPT 完整支持 |
| [Azure Synapse](synapse.sql) | UNION/INTERSECT/EXCEPT 完整支持 |
| [Databricks SQL](databricks.sql) | UNION/INTERSECT/EXCEPT 完整支持 |
| [Greenplum](greenplum.sql) | PG 兼容集合操作 |
| [Impala](impala.sql) | UNION ALL 支持，无 INTERSECT/EXCEPT |
| [Vertica](vertica.sql) | UNION/INTERSECT/EXCEPT 完整支持 |
| [Teradata](teradata.sql) | UNION/INTERSECT/EXCEPT/MINUS |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容，INTERSECT/EXCEPT(6.4+) |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式集合操作 |
| [CockroachDB](cockroachdb.sql) | PG 兼容集合操作 |
| [Spanner](spanner.sql) | UNION/INTERSECT/EXCEPT 支持 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容集合操作 |
| [PolarDB](polardb.sql) | MySQL 兼容集合操作 |
| [openGauss](opengauss.sql) | PG 兼容集合操作 |
| [TDSQL](tdsql.sql) | MySQL 兼容集合操作 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容 MINUS |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 集合操作 |
| [TDengine](tdengine.sql) | 不支持集合操作 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 不支持集合操作 |
| [Materialize](materialize.sql) | PG 兼容 UNION/EXCEPT |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | UNION/INTERSECT/EXCEPT 支持 |
| [Derby](derby.sql) | UNION/INTERSECT/EXCEPT 支持 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:1992 UNION/INTERSECT/EXCEPT 规范 |

## 核心差异

1. **EXCEPT vs MINUS**：SQL 标准用 EXCEPT，Oracle 用 MINUS（语义相同），MySQL 8.0.31+ 才支持 EXCEPT/INTERSECT
2. **UNION ALL vs UNION**：UNION 去重排序开销大，90% 场景应使用 UNION ALL（已知无重复或不需要去重时）
3. **列匹配规则**：所有集合操作要求 SELECT 列表数量相同，但类型兼容性规则各方言不同（MySQL 隐式转换较宽松）
4. **排序限制**：ORDER BY 只能出现在最后一个 SELECT 之后（应用于整个结果集），不能在中间的 SELECT 中使用

## 选型建议

UNION ALL 是性能最好的集合操作，优先使用。INTERSECT 可以用 INNER JOIN 替代，EXCEPT 可以用 LEFT JOIN ... WHERE ... IS NULL 替代（在不支持集合操作的老版本中）。大数据场景下 UNION ALL 常用于合并多个分区的查询结果。

## 版本演进

- MySQL 8.0.31+：首次支持 INTERSECT 和 EXCEPT（之前只支持 UNION/UNION ALL）
- MariaDB 10.3+：支持 INTERSECT 和 EXCEPT
- PostgreSQL：一直完整支持所有集合操作，包括 INTERSECT ALL 和 EXCEPT ALL

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **UNION/UNION ALL** | 完整支持 | 完整支持 | 完整支持 | 均支持 |
| **INTERSECT/EXCEPT** | 完整支持 | 支持 INTERSECT，EXCEPT 用 NOT IN 替代 | 完整支持 INTERSECT/EXCEPT | PG 完整支持，MySQL 8.0.31+ 才支持 |
| **EXCEPT vs MINUS** | 使用 EXCEPT | 使用 EXCEPT | 使用 EXCEPT | Oracle 用 MINUS（语义相同） |
| **类型匹配** | 动态类型，列匹配宽松（不严格检查类型） | 严格类型匹配 | 严格类型匹配 | PG 严格 / MySQL 宽松隐式转换 |
| **性能考量** | 单文件操作，小数据集高效 | 分布式执行，UNION ALL 常用于合并分片结果 | 按扫描量计费，UNION ALL 扫描两倍数据 | 优化器选择合并策略 |

## 引擎开发者视角

**核心设计决策**：集合操作（UNION/INTERSECT/EXCEPT）的实现与排序/哈希去重紧密耦合。UNION ALL 是最简单的（不需要去重），UNION/INTERSECT/EXCEPT 都需要某种形式的去重。

**实现建议**：
- UNION ALL 的实现是简单的结果拼接——优化器应确保不做任何多余操作（不排序、不去重）。在分布式引擎中 UNION ALL 可以并行执行各分支
- UNION（去重）的实现有两种主要方式：排序去重（Sort-based）和哈希去重（Hash-based）。哈希去重在大多数场景下更快但内存消耗大，排序去重内存可控但需要全量排序
- INTERSECT 和 EXCEPT 可以用 Hash Semi-Join 和 Hash Anti-Join 实现——优化器应能将 INTERSECT 改写为 Semi-Join 来利用索引
- EXCEPT 和 MINUS（Oracle 术语）语义完全相同。如果目标兼容 Oracle，支持 MINUS 作为 EXCEPT 的别名即可
- INTERSECT ALL 和 EXCEPT ALL（保留重复行的集合操作）是 SQL 标准但不常用。MySQL 8.0.31+ 直接支持——如果有资源可以实现
- 列数匹配和类型兼容性检查应在编译时完成——运行时发现列数不匹配代价太大。类型不兼容时的隐式转换规则要与 UNION 的各分支结果类型推导一致
- 常见错误：ORDER BY 的作用域不清晰。SQL 标准规定 ORDER BY 只能出现在最后一个 SELECT 之后且应用于整个结果集——引擎应在中间位置的 ORDER BY 处报错或发出警告
