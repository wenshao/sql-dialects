# 类型转换 (TYPE CONVERSION)

各数据库类型转换语法对比，包括 CAST、CONVERT、隐式转换等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | CAST/CONVERT()，隐式转换宽松 |
| [PostgreSQL](postgres.sql) | CAST/::运算符，严格类型系统 |
| [SQLite](sqlite.sql) | 动态类型，CAST 支持但隐式转换灵活 |
| [Oracle](oracle.sql) | TO_NUMBER/TO_CHAR/TO_DATE，显式转换体系 |
| [SQL Server](sqlserver.sql) | CAST/CONVERT/TRY_CAST/TRY_CONVERT |
| [MariaDB](mariadb.sql) | 兼容 MySQL CAST/CONVERT |
| [Firebird](firebird.sql) | CAST 标准支持 |
| [IBM Db2](db2.sql) | CAST/DECIMAL/CHAR/INTEGER 类型函数 |
| [SAP HANA](saphana.sql) | CAST/TO_INT/TO_VARCHAR/TO_DATE |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | CAST/SAFE_CAST(失败返回 NULL) |
| [Snowflake](snowflake.sql) | CAST/TRY_CAST/::运算符 |
| [ClickHouse](clickhouse.sql) | toInt32/toString 类型函数族，严格 |
| [Hive](hive.sql) | CAST，隐式转换规则宽松 |
| [Spark SQL](spark.sql) | CAST，TRY_CAST(3.4+) |
| [Flink SQL](flink.sql) | CAST/TRY_CAST 支持 |
| [StarRocks](starrocks.sql) | CAST 支持 |
| [Doris](doris.sql) | CAST 支持 |
| [Trino](trino.sql) | CAST/TRY_CAST/TRY() 安全转换 |
| [DuckDB](duckdb.sql) | CAST/TRY_CAST/::运算符 |
| [MaxCompute](maxcompute.sql) | CAST 支持 |
| [Hologres](hologres.sql) | CAST/::(PG 兼容) |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | CAST/::(PG 兼容)，隐式转换 |
| [Azure Synapse](synapse.sql) | CAST/CONVERT/TRY_CAST(T-SQL) |
| [Databricks SQL](databricks.sql) | CAST/TRY_CAST 支持 |
| [Greenplum](greenplum.sql) | PG 兼容 CAST/:: |
| [Impala](impala.sql) | CAST 支持 |
| [Vertica](vertica.sql) | CAST/::/TO_NUMBER/TO_CHAR |
| [Teradata](teradata.sql) | CAST/FORMAT 组合转换 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 CAST/CONVERT |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式转换 |
| [CockroachDB](cockroachdb.sql) | PG 兼容 CAST/:: |
| [Spanner](spanner.sql) | CAST/SAFE_CAST |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 CAST/:: |
| [PolarDB](polardb.sql) | MySQL 兼容 CAST |
| [openGauss](opengauss.sql) | PG 兼容 CAST/:: |
| [TDSQL](tdsql.sql) | MySQL 兼容 CAST |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容 TO_NUMBER/TO_CHAR |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG CAST/:: |
| [TDengine](tdengine.sql) | CAST 支持基础类型 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | CAST 支持基础类型 |
| [Materialize](materialize.sql) | PG 兼容 CAST/:: |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | CAST/CONVERT 标准支持 |
| [Derby](derby.sql) | CAST 标准支持 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 CAST 规范 |

## 核心差异

1. **CAST 语法**：`CAST(expr AS type)` 是 SQL 标准，所有方言都支持，但目标类型名称不同（如 MySQL 的 SIGNED vs PostgreSQL 的 INTEGER）
2. **PostgreSQL :: 运算符**：PostgreSQL 特有的 `expr::type` 简写（如 `'123'::int`），简洁但不可移植
3. **CONVERT 函数**：MySQL 的 CONVERT(expr, type) 和 SQL Server 的 CONVERT(type, expr, style) 参数顺序不同
4. **隐式转换**：MySQL 隐式转换极为宽松（`'abc' = 0` 为 true），PostgreSQL 极为严格（类型不匹配直接报错），Oracle 居中
5. **TRY_CAST**：SQL Server/Snowflake/Databricks 支持 TRY_CAST（转换失败返回 NULL 而非报错），PostgreSQL/MySQL 需要用 CASE WHEN + 正则模拟

## 选型建议

始终使用显式 CAST 而非依赖隐式转换，这是最重要的跨方言最佳实践。MySQL 的隐式转换是安全隐患（WHERE varchar_col = 0 会匹配所有非数字字符串）。PostgreSQL 的严格类型检查虽然初期不便但长期更安全。

## 版本演进

- SQL Server 2012+：引入 TRY_CAST/TRY_CONVERT（安全转换）
- Snowflake/Databricks：也支持 TRY_CAST 语法
- PostgreSQL：无 TRY_CAST，但可以通过自定义函数实现类似功能
- MySQL 8.0：CAST 支持的目标类型更丰富（如 CAST(... AS FLOAT)）

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **类型系统** | 动态类型：声明类型仅为亲和性，任何值可存入任何列 | 严格类型：有丰富类型（UInt8~256、Decimal、DateTime64 等） | 严格类型：INT64/FLOAT64/STRING/BYTES 等 | 严格类型系统 |
| **CAST 语法** | 支持 CAST(x AS type)，但实际只是亲和性转换 | 支持 CAST 和特有的 toInt32/toString 等转换函数 | CAST / SAFE_CAST（转换失败返回 NULL） | 标准 CAST / PG `::` / MySQL CONVERT |
| **隐式转换** | 极度宽松（核心是动态类型，比较时按亲和性规则） | 较严格，但有自动类型提升规则 | 严格，不自动隐式转换 | MySQL 极宽松 / PG 极严格 / Oracle 居中 |
| **TRY_CAST** | 不需要（动态类型天然不会因类型不匹配报错） | 不支持 TRY_CAST，转换失败报错 | SAFE_CAST（等价于 TRY_CAST） | SQL Server TRY_CAST / PG 无（需自定义函数） |
| **迁移风险** | 从 SQLite 迁出时，动态类型数据可能包含混合类型值 | 类型精度高，迁入时需仔细映射 | BigQuery 类型有限，某些精度可能损失 | 各方言间类型映射是迁移核心挑战 |

## 引擎开发者视角

**核心设计决策**：隐式类型转换的宽松程度是引擎设计中最具争议的决策之一。MySQL 的极度宽松（'abc' = 0 为 true）vs PostgreSQL 的极度严格（类型不匹配直接报错）代表两个极端。

**实现建议**：
- 推荐偏向严格的类型检查——长期来看减少用户 bug。但完全不做隐式转换（如 INT + FLOAT 报错）又过于激进，推荐在数值类型家族内自动提升（INT -> BIGINT -> FLOAT -> DOUBLE -> DECIMAL）
- CAST(expr AS type) 是 SQL 标准，必须支持。TRY_CAST/SAFE_CAST（转换失败返回 NULL 而非报错）是极其有用的扩展——ETL/数据清洗场景中必不可少，推荐从第一天就支持
- PostgreSQL 的 `::` 运算符（如 `'123'::int`）虽然不是标准但非常受用户欢迎——如果兼容 PostgreSQL 生态则应支持
- 类型转换的规则矩阵（哪些类型可以转换为哪些类型）需要完整文档化。转换分为三类：可以隐式转换、需要显式 CAST、不允许转换。每对类型组合都应有明确的分类
- CONVERT 函数的参数顺序在 MySQL 和 SQL Server 之间不同——如果支持 CONVERT，需要明确选择哪种语义
- 常见错误：字符串到数值的隐式转换在 WHERE 条件中导致索引失效。`WHERE varchar_col = 123` 如果对 varchar_col 做隐式转换，会导致无法使用索引——正确做法是对常量做转换而非对列做转换
