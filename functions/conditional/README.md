# 条件函数 (CONDITIONAL)

各数据库条件函数对比，包括 CASE、IF、COALESCE、NULLIF、IIF 等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | IF()/IFNULL()/NULLIF()/CASE WHEN 完整 |
| [PostgreSQL](postgres.sql) | CASE WHEN/COALESCE/NULLIF/GREATEST/LEAST |
| [SQLite](sqlite.sql) | CASE WHEN/COALESCE/NULLIF/IIF(3.32+) |
| [Oracle](oracle.sql) | DECODE/NVL/NVL2/CASE WHEN，DECODE 独有 |
| [SQL Server](sqlserver.sql) | IIF/CHOOSE/COALESCE/ISNULL/CASE WHEN |
| [MariaDB](mariadb.sql) | IF()/IFNULL()，兼容 MySQL |
| [Firebird](firebird.sql) | IIF()/CASE WHEN/COALESCE/NULLIF |
| [IBM Db2](db2.sql) | CASE WHEN/COALESCE/NULLIF/DECODE(兼容) |
| [SAP HANA](saphana.sql) | CASE WHEN/IFNULL/NULLIF/COALESCE |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | IF()/IFNULL()/COALESCE/CASE WHEN |
| [Snowflake](snowflake.sql) | IFF()/NVL()/COALESCE/DECODE/CASE WHEN |
| [ClickHouse](clickhouse.sql) | if()/multiIf()/CASE WHEN，三值逻辑 |
| [Hive](hive.sql) | IF()/NVL()/COALESCE/CASE WHEN |
| [Spark SQL](spark.sql) | IF()/NVL()/COALESCE/CASE WHEN |
| [Flink SQL](flink.sql) | IF()/COALESCE/CASE WHEN |
| [StarRocks](starrocks.sql) | IF()/IFNULL()/COALESCE/CASE WHEN |
| [Doris](doris.sql) | IF()/IFNULL()/COALESCE/CASE WHEN |
| [Trino](trino.sql) | IF()/COALESCE/NULLIF/CASE WHEN |
| [DuckDB](duckdb.sql) | CASE WHEN/COALESCE/IF/IIF |
| [MaxCompute](maxcompute.sql) | IF()/COALESCE/CASE WHEN/DECODE |
| [Hologres](hologres.sql) | PG 兼容 CASE/COALESCE |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | NVL/DECODE/COALESCE/CASE WHEN |
| [Azure Synapse](synapse.sql) | IIF/CHOOSE/COALESCE/CASE WHEN(T-SQL) |
| [Databricks SQL](databricks.sql) | IF()/NVL()/COALESCE/CASE WHEN |
| [Greenplum](greenplum.sql) | PG 兼容条件函数 |
| [Impala](impala.sql) | IF()/NVL()/COALESCE/CASE WHEN |
| [Vertica](vertica.sql) | NVL/DECODE/COALESCE/CASE WHEN |
| [Teradata](teradata.sql) | NULLIFZERO/ZEROIFNULL/COALESCE/CASE WHEN |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 IF()/IFNULL() |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式条件函数 |
| [CockroachDB](cockroachdb.sql) | PG 兼容条件函数 |
| [Spanner](spanner.sql) | IF()/IFNULL()/COALESCE/CASE WHEN |
| [YugabyteDB](yugabytedb.sql) | PG 兼容条件函数 |
| [PolarDB](polardb.sql) | MySQL 兼容条件函数 |
| [openGauss](opengauss.sql) | PG 兼容，DECODE 扩展 |
| [TDSQL](tdsql.sql) | MySQL 兼容条件函数 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | DECODE/NVL(Oracle 兼容) |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 条件函数 |
| [TDengine](tdengine.sql) | 仅基础 CASE WHEN 支持 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | CASE WHEN/IF 支持 |
| [Materialize](materialize.sql) | PG 兼容条件函数 |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | CASE WHEN/COALESCE/IFNULL/NVL |
| [Derby](derby.sql) | CASE WHEN/COALESCE/NULLIF |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:1992 CASE/COALESCE/NULLIF 规范 |

## 核心差异

1. **CASE 表达式**：SQL 标准语法，所有方言都支持。分为简单 CASE（CASE x WHEN 1 THEN ...）和搜索 CASE（CASE WHEN x > 1 THEN ...）
2. **IF 函数**：MySQL/MariaDB 有 IF(condition, true_val, false_val)，其他方言用 CASE WHEN 替代。SQL Server 有 IIF()（2012+）
3. **COALESCE vs NVL/ISNULL**：COALESCE 是 SQL 标准（支持多参数），NVL 是 Oracle 特有（只支持两参数），ISNULL 是 SQL Server 特有
4. **NULLIF**：所有方言都支持，`NULLIF(a, b)` 当 a=b 时返回 NULL，常用于避免除零错误 `x / NULLIF(y, 0)`
5. **DECODE**：Oracle 特有函数（类似简单 CASE），迁移时必须改写为 CASE WHEN

## 选型建议

跨方言代码始终使用 CASE WHEN 和 COALESCE（SQL 标准），避免使用 IF()、NVL()、ISNULL()、DECODE() 等方言特有函数。NULLIF 配合除法避免除零错误是通用技巧。COALESCE 可以串联多个备选值（如 COALESCE(a, b, c, 0)）。

## 版本演进

- SQL Server 2012+：引入 IIF() 函数（从 Access 移植），但建议使用 CASE WHEN
- 条件函数在各方言中变化较小，属于最稳定的语法领域
- ClickHouse：独有的 multiIf() 函数提供多条件判断，比嵌套 if() 更清晰

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **CASE WHEN** | 完整支持（SQL 标准） | 完整支持 | 完整支持 | 所有方言均支持 |
| **IF 函数** | 不支持 IF() 函数（用 CASE WHEN 替代） | 支持 if(cond, then, else)，还有独特的 multiIf() | 支持 IF(cond, then, else) | MySQL 有 IF()，PG 无，SQL Server 有 IIF() |
| **COALESCE** | 完整支持 | 完整支持 | 完整支持 | 所有方言均支持（SQL 标准） |
| **NULLIF** | 完整支持 | 完整支持 | 完整支持 | 所有方言均支持 |
| **NULL 行为** | 动态类型下 NULL 处理较宽松 | 严格的 Nullable 类型系统，非 Nullable 列不存 NULL | 严格类型，NULL 处理符合 SQL 标准 | Oracle 空字符串=NULL 是独特陷阱 |

## 引擎开发者视角

**核心设计决策**：条件函数是表达式求值引擎的基础组件。CASE WHEN 是 SQL 标准的条件分支，实现方式影响所有条件逻辑的性能。

**实现建议**：
- CASE WHEN 是必须实现的——它是 SQL 标准中唯一的条件分支表达式，其他条件函数（IF/IIF/DECODE）都可以用 CASE WHEN 表达。在优化器中将 IF/IIF 内部归一化为 CASE WHEN 可以简化优化规则
- COALESCE 的实现应该是短路求值——找到第一个非 NULL 值后不继续计算后续表达式。这对有副作用或计算成本高的表达式很重要
- NULLIF 是避免除零错误的标准模式（`x / NULLIF(y, 0)`），实现简单但用户价值大。内部可转换为 `CASE WHEN a = b THEN NULL ELSE a END`
- IF() 函数虽然不是 SQL 标准但在 MySQL 生态中广泛使用。如果目标兼容 MySQL，建议支持。ClickHouse 的 multiIf() 是更通用的变体，减少了嵌套 IF 的可读性问题
- NULL 的三值逻辑是条件函数实现中的核心复杂性：AND/OR/NOT 与 NULL 的交互必须严格遵循 SQL 标准（NULL AND FALSE = FALSE，NULL OR TRUE = TRUE 等）
- 常见错误：CASE WHEN 的类型推导——各分支返回不同类型时结果类型如何确定。SQL 标准定义了类型提升规则，但 MySQL 的隐式转换规则与标准不同，需要明确设计决策
