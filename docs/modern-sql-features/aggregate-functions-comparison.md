# 聚合函数对比 (Aggregate Functions Comparison)

聚合函数是 SQL 最基础也最关键的能力之一——从 `COUNT(*)` 到 `PERCENTILE_CONT`，从 `GROUP_CONCAT` 到 `FILTER` 子句，各引擎在聚合函数的覆盖范围、语法风格和语义细节上存在巨大差异。对于 SQL 引擎开发者而言，理解这些差异不仅关乎兼容性适配，更直接影响查询优化器的设计——NULL 处理策略、DISTINCT 消除、聚合下推、部分聚合（partial aggregation）等核心优化都依赖对聚合语义的精确把握。

本文对 49 个主流 SQL 引擎的聚合函数支持进行系统性对比，覆盖基础聚合、统计函数、布尔聚合、位运算聚合、字符串聚合、百分位数、回归分析、FILTER 子句等维度。

## SQL 标准中的聚合函数

### SQL-92 基础聚合

SQL-92 标准定义了五个最基本的聚合函数：

```sql
COUNT(*) | COUNT([ALL | DISTINCT] expression)
SUM([ALL | DISTINCT] expression)
AVG([ALL | DISTINCT] expression)
MIN(expression)
MAX(expression)
```

核心语义规则：
1. **NULL 忽略**：除 `COUNT(*)` 外，所有聚合函数忽略 NULL 值
2. **空集行为**：空集上 `COUNT` 返回 0，其他函数返回 NULL
3. **DISTINCT**：可选修饰符，在聚合前去重
4. **ALL**：默认行为（不去重），通常省略

### SQL:1999 扩展

SQL:1999 引入了 `GROUPING` 函数（配合 GROUPING SETS/CUBE/ROLLUP 使用），以及布尔聚合 `EVERY`。

### SQL:2003 扩展

SQL:2003 是聚合函数标准化的重要版本，新增了：

- **有序集合聚合框架**（`WITHIN GROUP`）：`PERCENTILE_CONT`、`PERCENTILE_DISC`
- **统计聚合**：`STDDEV_POP`、`STDDEV_SAMP`、`VAR_POP`、`VAR_SAMP`
- **回归函数**：`REGR_SLOPE`、`REGR_INTERCEPT`、`REGR_COUNT`、`REGR_R2` 等
- **相关性函数**：`CORR`、`COVAR_POP`、`COVAR_SAMP`
- **FILTER 子句**：`aggregate_function(...) FILTER (WHERE condition)`

### SQL:2016 扩展

SQL:2016 标准化了 `LISTAGG` 字符串聚合函数，并定义了溢出处理机制（`ON OVERFLOW`）。

## 支持矩阵

### 基础聚合函数：COUNT / SUM / AVG / MIN / MAX

所有 SQL 引擎均支持这五个基础聚合函数，这是 SQL-92 合规的最低要求。以下仅列出行为差异：

| 引擎 | COUNT(*) | SUM 溢出行为 | AVG 返回类型 | MIN/MAX 对字符串 | 备注 |
|------|:---:|------|------|:---:|------|
| PostgreSQL | 支持 | 报错 | `numeric` | 支持 | AVG(int) 返回 numeric，不丢精度 |
| MySQL | 支持 | 截断或报错(STRICT) | `DECIMAL`/`DOUBLE` | 支持 | `sql_mode` 影响溢出行为 |
| MariaDB | 支持 | 截断或报错(STRICT) | `DECIMAL`/`DOUBLE` | 支持 | 同 MySQL |
| SQLite | 支持 | 无溢出（任意精度） | `REAL` | 支持 | 动态类型，整数不溢出 |
| Oracle | 支持 | 报错 | `NUMBER` | 支持 | - |
| SQL Server | 支持 | 报错 | 同输入类型 | 支持 | AVG(int) 返回 int，**会丢精度** |
| DB2 | 支持 | 报错 | `DECIMAL` | 支持 | - |
| Snowflake | 支持 | 报错 | `NUMBER` | 支持 | - |
| BigQuery | 支持 | 报错 | `FLOAT64`/`NUMERIC` | 支持 | AVG(INT64) 返回 FLOAT64 |
| Redshift | 支持 | 报错 | `numeric` | 支持 | 继承 PostgreSQL 行为 |
| DuckDB | 支持 | 报错 | `DOUBLE`/`DECIMAL` | 支持 | - |
| ClickHouse | 支持 | 回绕（wraps） | `Float64` | 支持 | 整数 SUM 溢出时默默回绕 |
| Trino | 支持 | 报错 | `DOUBLE` | 支持 | - |
| Spark SQL | 支持 | 返回 NULL | `DOUBLE`/`DECIMAL` | 支持 | `spark.sql.ansi.enabled` 控制 |
| Hive | 支持 | 回绕 | `DOUBLE` | 支持 | 无溢出检查 |
| InfluxDB | 支持 | -- | `FLOAT` | 不支持 | 仅数值列，时序引擎 |

> **关键差异：AVG 的返回类型**。SQL Server 的 `AVG(integer_column)` 返回整数（截断小数部分），这是很多开发者踩过的坑。PostgreSQL、Oracle、DB2 等会自动提升为高精度类型。安全做法是显式转换：`AVG(CAST(col AS DECIMAL(18,4)))`。

### COUNT(DISTINCT) 与多列 COUNT DISTINCT

| 引擎 | COUNT(DISTINCT col) | COUNT(DISTINCT col1, col2) | 近似替代 | 版本/备注 |
|------|:---:|:---:|------|------|
| PostgreSQL | 支持 | 不支持 | -- | 需 `COUNT(DISTINCT ROW(col1,col2))` 或子查询 |
| MySQL | 支持 | **支持** | -- | MySQL 独有的多列 DISTINCT 语法 |
| MariaDB | 支持 | **支持** | -- | 同 MySQL |
| SQLite | 支持 | 不支持 | -- | - |
| Oracle | 支持 | 不支持 | `APPROX_COUNT_DISTINCT` (12c+) | 需子查询模拟 |
| SQL Server | 支持 | 不支持 | `APPROX_COUNT_DISTINCT` (2019+) | 需子查询模拟 |
| DB2 | 支持 | 不支持 | -- | - |
| Snowflake | 支持 | 不支持 | `APPROX_COUNT_DISTINCT` / `HLL` | - |
| BigQuery | 支持 | 不支持 | `APPROX_COUNT_DISTINCT` | - |
| Redshift | 支持 | 不支持 | `APPROXIMATE COUNT(DISTINCT col)` | - |
| DuckDB | 支持 | 不支持 | -- | - |
| ClickHouse | 支持 | 不支持 | `uniq` / `uniqExact` / `uniqHLL12` | 丰富的近似去重函数族 |
| Trino | 支持 | 不支持 | `approx_distinct` | - |
| Presto | 支持 | 不支持 | `approx_distinct` | - |
| Spark SQL | 支持 | 不支持 | `approx_count_distinct` | - |
| Hive | 支持 | 不支持 | `APPROX_DISTINCT` | - |
| Flink SQL | 支持 | 不支持 | -- | - |
| Databricks | 支持 | 不支持 | `approx_count_distinct` | - |
| Teradata | 支持 | 不支持 | -- | - |
| Greenplum | 支持 | 不支持 | `hll_count_distinct`（扩展） | 继承 PostgreSQL |
| CockroachDB | 支持 | 不支持 | -- | - |
| TiDB | 支持 | **支持** | `APPROX_COUNT_DISTINCT` | 兼容 MySQL 多列语法 |
| OceanBase | 支持 | **支持** (MySQL 模式) | `APPROX_COUNT_DISTINCT` | MySQL 模式下支持 |
| YugabyteDB | 支持 | 不支持 | -- | 继承 PostgreSQL |
| SingleStore | 支持 | 不支持 | `APPROX_COUNT_DISTINCT` | - |
| Vertica | 支持 | 不支持 | `APPROXIMATE_COUNT_DISTINCT` | - |
| Impala | 支持 | 不支持 | `NDV` (Number of Distinct Values) | - |
| StarRocks | 支持 | 不支持 | `APPROX_COUNT_DISTINCT` / `HLL_UNION_AGG` | - |
| Doris | 支持 | 不支持 | `APPROX_COUNT_DISTINCT` | - |
| MonetDB | 支持 | 不支持 | -- | - |
| CrateDB | 支持 | 不支持 | `HYPERLOGLOG_DISTINCT` | - |
| TimescaleDB | 支持 | 不支持 | `approx_count_distinct`（扩展） | 继承 PostgreSQL |
| QuestDB | 支持 | 不支持 | -- | - |
| Exasol | 支持 | 不支持 | -- | - |
| SAP HANA | 支持 | 不支持 | -- | - |
| Informix | 支持 | 不支持 | -- | - |
| Firebird | 支持 | 不支持 | -- | - |
| H2 | 支持 | 不支持 | -- | - |
| HSQLDB | 支持 | 不支持 | -- | - |
| Derby | 支持 | 不支持 | -- | - |
| Amazon Athena | 支持 | 不支持 | `approx_distinct` | 继承 Trino |
| Azure Synapse | 支持 | 不支持 | `APPROX_COUNT_DISTINCT` | - |
| Google Spanner | 支持 | 不支持 | `APPROX_COUNT_DISTINCT` | - |
| Materialize | 支持 | 不支持 | -- | - |
| RisingWave | 支持 | 不支持 | `APPROX_COUNT_DISTINCT` | - |
| InfluxDB | 支持 | 不支持 | -- | `DISTINCT` 聚合有限制 |
| DatabendDB | 支持 | 不支持 | `APPROX_COUNT_DISTINCT` | - |
| Yellowbrick | 支持 | 不支持 | -- | - |
| Firebolt | 支持 | 不支持 | `APPROX_COUNT_DISTINCT` | - |

> **MySQL 独有特性**：`COUNT(DISTINCT col1, col2)` 语法仅 MySQL/MariaDB（及其兼容引擎如 TiDB、OceanBase MySQL 模式）支持。该语法计算 `(col1, col2)` 组合的去重行数，等价于其他引擎的 `SELECT COUNT(*) FROM (SELECT DISTINCT col1, col2 FROM t) sub`。注意：如果任一列为 NULL，该行不参与计数。

### 统计聚合函数：STDDEV / VARIANCE 系列

| 引擎 | STDDEV_POP | STDDEV_SAMP | VAR_POP | VAR_SAMP | STDDEV | VARIANCE | 版本 |
|------|:---:|:---:|:---:|:---:|:---:|:---:|------|
| PostgreSQL | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 8.0+ |
| MySQL | 支持 | 支持 | 支持 | 支持 | =POP | =POP | 5.0+ |
| MariaDB | 支持 | 支持 | 支持 | 支持 | =POP | =POP | 5.0+ |
| SQLite | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 需扩展 |
| Oracle | 支持 | 支持 | 支持 | 支持 | =POP | =POP | 8i+ |
| SQL Server | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 2005+ |
| DB2 | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 9.0+ |
| Snowflake | 支持 | 支持 | 支持 | 支持 | =POP | =POP | GA |
| BigQuery | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | GA |
| Redshift | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | GA |
| DuckDB | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 0.3+ |
| ClickHouse | 支持 | 支持 | 支持 | 支持 | =POP | =POP | 早期 |
| Trino | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 早期 |
| Presto | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 早期 |
| Spark SQL | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 1.6+ |
| Hive | 支持 | 支持 | 支持 | 支持 | =POP | =POP | 0.12+ |
| Flink SQL | 支持 | 支持 | 支持 | 支持 | 不支持 | 不支持 | 1.12+ |
| Databricks | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | GA |
| Teradata | 支持 | 支持 | 支持 | 支持 | =POP | =POP | 14+ |
| Greenplum | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 继承 PG |
| CockroachDB | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 20.1+ |
| TiDB | 支持 | 支持 | 支持 | 支持 | =POP | =POP | 5.0+ |
| OceanBase | 支持 | 支持 | 支持 | 支持 | 模式依赖 | 模式依赖 | 3.x+ |
| YugabyteDB | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 继承 PG |
| SingleStore | 支持 | 支持 | 支持 | 支持 | =POP | =POP | GA |
| Vertica | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 7.0+ |
| Impala | 支持 | 支持 | 支持 | 支持 | =POP | =POP | 2.0+ |
| StarRocks | 支持 | 支持 | 支持 | 支持 | =POP | =POP | 2.0+ |
| Doris | 支持 | 支持 | 支持 | 支持 | =POP | =POP | 1.0+ |
| MonetDB | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 早期 |
| CrateDB | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 早期 |
| TimescaleDB | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 继承 PG |
| QuestDB | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Exasol | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 6.0+ |
| SAP HANA | 支持 | 支持 | 支持 | 支持 | =POP | =POP | 1.0+ |
| Informix | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 12.0+ |
| Firebird | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| H2 | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 2.0+ |
| HSQLDB | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 2.3+ |
| Derby | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Amazon Athena | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 继承 Trino |
| Azure Synapse | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | GA |
| Google Spanner | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | GA |
| Materialize | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | 继承 PG |
| RisingWave | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | GA |
| InfluxDB | 支持 | 不支持 | 不支持 | 不支持 | =POP | 不支持 | 有限支持 |
| DatabendDB | 支持 | 支持 | 支持 | 支持 | =POP | =POP | GA |
| Yellowbrick | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | GA |
| Firebolt | 支持 | 支持 | 支持 | 支持 | =SAMP | =SAMP | GA |

> **关键陷阱：STDDEV / VARIANCE 的默认行为不一致**。`STDDEV` 和 `VARIANCE` 这两个简写名在不同引擎中指向的是**总体**（POP）还是**样本**（SAMP）版本完全不同。MySQL/Oracle/ClickHouse/Hive/Teradata 等指向总体版本（除以 N），而 PostgreSQL/SQL Server/BigQuery/DB2/Trino 等指向样本版本（除以 N-1）。**在跨引擎迁移时，务必使用完整名称 `STDDEV_POP`/`STDDEV_SAMP`。**

### 布尔聚合：BOOL_AND / BOOL_OR / EVERY / SOME / ANY

| 引擎 | BOOL_AND | BOOL_OR | EVERY | SOME / ANY (聚合) | 版本 |
|------|:---:|:---:|:---:|:---:|------|
| PostgreSQL | 支持 | 支持 | 支持 | 不支持 | 8.4+ |
| MySQL | 不支持 | 不支持 | 不支持 | 不支持 | 需 `MIN`/`MAX` 模拟 |
| MariaDB | 不支持 | 不支持 | 不支持 | 不支持 | 需 `MIN`/`MAX` 模拟 |
| SQLite | 不支持 | 不支持 | 不支持 | 不支持 | 需 `MIN`/`MAX` 模拟 |
| Oracle | 不支持 | 不支持 | 不支持 | 不支持 | 无布尔类型 |
| SQL Server | 不支持 | 不支持 | 不支持 | 不支持 | 无布尔类型 |
| DB2 | 不支持 | 不支持 | 不支持 | 不支持 | 需 `MIN`/`MAX` 模拟 |
| Snowflake | 支持 | 支持 | 不支持 | 不支持 | GA |
| BigQuery | 支持 | 支持 | 不支持 | 不支持 | `LOGICAL_AND`/`LOGICAL_OR` |
| Redshift | 支持 | 支持 | 支持 | 支持 | GA |
| DuckDB | 支持 | 支持 | 支持 | 不支持 | 0.3+ |
| ClickHouse | 不支持 | 不支持 | 不支持 | 不支持 | 需 `min`/`max` 或 `groupBitAnd` |
| Trino | 支持 | 不支持 | 支持 | 不支持 | `BOOL_AND`/`EVERY` |
| Presto | 不支持 | 不支持 | 支持 | 不支持 | 仅 `EVERY` |
| Spark SQL | 支持 | 支持 | 支持 | 支持 | 3.0+；`BOOL_AND` = `EVERY`，`BOOL_OR` = `SOME` |
| Hive | 不支持 | 不支持 | 不支持 | 不支持 | 需 UDF |
| Flink SQL | 不支持 | 不支持 | 不支持 | 不支持 | 需 UDF |
| Databricks | 支持 | 支持 | 支持 | 支持 | 同 Spark SQL |
| Teradata | 不支持 | 不支持 | 不支持 | 不支持 | 需 CASE WHEN 模拟 |
| Greenplum | 支持 | 支持 | 支持 | 不支持 | 继承 PG |
| CockroachDB | 支持 | 支持 | 支持 | 不支持 | 20.1+ |
| TiDB | 不支持 | 不支持 | 不支持 | 不支持 | 需 `MIN`/`MAX` 模拟 |
| OceanBase | 不支持 | 不支持 | 不支持 | 不支持 | 需 `MIN`/`MAX` 模拟 |
| YugabyteDB | 支持 | 支持 | 支持 | 不支持 | 继承 PG |
| SingleStore | 不支持 | 不支持 | 不支持 | 不支持 | 需 `MIN`/`MAX` 模拟 |
| Vertica | 不支持 | 不支持 | 不支持 | 不支持 | 需 CASE WHEN 模拟 |
| Impala | 不支持 | 不支持 | 不支持 | 不支持 | 需 CASE WHEN 模拟 |
| StarRocks | 不支持 | 不支持 | 不支持 | 不支持 | 需 `MIN`/`MAX` 模拟 |
| Doris | 不支持 | 不支持 | 不支持 | 不支持 | 需 `MIN`/`MAX` 模拟 |
| MonetDB | 不支持 | 不支持 | 支持 | 支持 | SQL:1999 名称 |
| CrateDB | 不支持 | 不支持 | 不支持 | 不支持 | 需模拟 |
| TimescaleDB | 支持 | 支持 | 支持 | 不支持 | 继承 PG |
| QuestDB | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Exasol | 支持 | 支持 | 支持 | 支持 | 6.0+ |
| SAP HANA | 不支持 | 不支持 | 不支持 | 不支持 | 需 CASE WHEN 模拟 |
| Informix | 不支持 | 不支持 | 不支持 | 不支持 | 需模拟 |
| Firebird | 不支持 | 不支持 | 不支持 | 不支持 | 需模拟 |
| H2 | 支持 | 支持 | 支持 | 支持 | 2.0+ |
| HSQLDB | 支持 | 不支持 | 支持 | 不支持 | 2.5+ |
| Derby | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Amazon Athena | 支持 | 不支持 | 支持 | 不支持 | 继承 Trino |
| Azure Synapse | 不支持 | 不支持 | 不支持 | 不支持 | 需 CASE WHEN 模拟 |
| Google Spanner | 支持 | 支持 | 不支持 | 不支持 | `LOGICAL_AND`/`LOGICAL_OR` |
| Materialize | 支持 | 支持 | 不支持 | 不支持 | 继承 PG |
| RisingWave | 支持 | 支持 | 支持 | 不支持 | GA |
| InfluxDB | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| DatabendDB | 不支持 | 不支持 | 不支持 | 不支持 | 需模拟 |
| Yellowbrick | 支持 | 支持 | 支持 | 不支持 | 继承 PG |
| Firebolt | 不支持 | 不支持 | 不支持 | 不支持 | 需模拟 |

> **命名差异**：SQL 标准使用 `EVERY`（对应全称量词）和 `ANY/SOME`，PostgreSQL 使用 `BOOL_AND`/`BOOL_OR`。BigQuery 使用 `LOGICAL_AND`/`LOGICAL_OR`。Google Spanner 同 BigQuery。对于不支持布尔聚合的引擎（Oracle/SQL Server 甚至没有布尔类型），常用 `MIN(CASE WHEN cond THEN 1 ELSE 0 END) = 1` 模拟 `EVERY`，`MAX(...)` 模拟 `ANY`。

### 位运算聚合：BIT_AND / BIT_OR / BIT_XOR

| 引擎 | BIT_AND | BIT_OR | BIT_XOR | 版本/备注 |
|------|:---:|:---:|:---:|------|
| PostgreSQL | 支持 | 支持 | 支持 | 8.2+ |
| MySQL | 支持 | 支持 | 支持 | 4.0+ |
| MariaDB | 支持 | 支持 | 支持 | 4.0+ |
| SQLite | 不支持 | 不支持 | 不支持 | 需扩展 |
| Oracle | 不支持 | 不支持 | 不支持 | 需 PL/SQL 或 `UTL_RAW` |
| SQL Server | 不支持 | 不支持 | 不支持 | 需自定义聚合 CLR |
| DB2 | 不支持 | 不支持 | 不支持 | 需 UDF |
| Snowflake | 支持 | 支持 | 支持 | GA |
| BigQuery | 支持 | 支持 | 支持 | GA |
| Redshift | 支持 | 支持 | 支持 | GA |
| DuckDB | 支持 | 支持 | 支持 | 0.3+ |
| ClickHouse | 支持 | 支持 | 支持 | `groupBitAnd`/`groupBitOr`/`groupBitXor` |
| Trino | 支持 | 支持 | 不支持 | `BITWISE_AND_AGG`/`BITWISE_OR_AGG` |
| Presto | 支持 | 支持 | 不支持 | 同 Trino |
| Spark SQL | 支持 | 支持 | 支持 | 2.4+ |
| Hive | 不支持 | 不支持 | 不支持 | 需 UDF |
| Flink SQL | 不支持 | 不支持 | 不支持 | 需 UDF |
| Databricks | 支持 | 支持 | 支持 | 同 Spark SQL |
| Teradata | 不支持 | 不支持 | 不支持 | 需 UDF |
| Greenplum | 支持 | 支持 | 支持 | 继承 PG |
| CockroachDB | 支持 | 支持 | 支持 | 20.1+ |
| TiDB | 支持 | 支持 | 支持 | 兼容 MySQL |
| OceanBase | 支持 | 支持 | 支持 | MySQL 模式 |
| YugabyteDB | 支持 | 支持 | 支持 | 继承 PG |
| SingleStore | 支持 | 支持 | 支持 | GA |
| Vertica | 不支持 | 不支持 | 不支持 | 需 UDF |
| Impala | 不支持 | 不支持 | 不支持 | 需 UDF |
| StarRocks | 支持 | 支持 | 支持 | 2.0+ |
| Doris | 支持 | 支持 | 支持 | 1.0+ |
| MonetDB | 不支持 | 不支持 | 不支持 | 需模拟 |
| CrateDB | 不支持 | 不支持 | 不支持 | 需模拟 |
| TimescaleDB | 支持 | 支持 | 支持 | 继承 PG |
| QuestDB | 不支持 | 不支持 | 不支持 | 不支持 |
| Exasol | 支持 | 支持 | 支持 | 6.0+ |
| SAP HANA | 不支持 | 不支持 | 不支持 | 需模拟 |
| Informix | 不支持 | 不支持 | 不支持 | 需模拟 |
| Firebird | 不支持 | 不支持 | 不支持 | 需模拟 |
| H2 | 支持 | 支持 | 支持 | 2.0+ |
| HSQLDB | 不支持 | 不支持 | 不支持 | 不支持 |
| Derby | 不支持 | 不支持 | 不支持 | 不支持 |
| Amazon Athena | 支持 | 支持 | 不支持 | 继承 Trino |
| Azure Synapse | 不支持 | 不支持 | 不支持 | 需模拟 |
| Google Spanner | 支持 | 支持 | 支持 | GA |
| Materialize | 支持 | 支持 | 支持 | 继承 PG |
| RisingWave | 支持 | 支持 | 支持 | GA |
| InfluxDB | 不支持 | 不支持 | 不支持 | 不支持 |
| DatabendDB | 不支持 | 不支持 | 不支持 | 需模拟 |
| Yellowbrick | 支持 | 支持 | 支持 | GA |
| Firebolt | 不支持 | 不支持 | 不支持 | 需模拟 |

> **注意**：ClickHouse 使用独有的命名规范——`groupBitAnd`/`groupBitOr`/`groupBitXor`。Trino/Presto 使用 `BITWISE_AND_AGG`/`BITWISE_OR_AGG`，且不支持 XOR 聚合。

### 字符串聚合：STRING_AGG / GROUP_CONCAT / LISTAGG / ARRAY_AGG

详细的字符串聚合对比请参考 [string-agg-evolution.md](string-agg-evolution.md)，以下为精简矩阵：

| 引擎 | STRING_AGG | GROUP_CONCAT | LISTAGG | ARRAY_AGG | 版本/备注 |
|------|:---:|:---:|:---:|:---:|------|
| PostgreSQL | 支持 | 不支持 | 支持 (16+) | 支持 | STRING_AGG: 9.0+, ARRAY_AGG: 8.4+ |
| MySQL | 不支持 | 支持 | 不支持 | 不支持 | 默认 1024 字节截断 |
| MariaDB | 不支持 | 支持 | 不支持 | 不支持 | 同 MySQL |
| SQLite | 不支持 | 支持 | 不支持 | 不支持 | `GROUP_CONCAT` 行为与 MySQL 不同 |
| Oracle | 不支持 | 不支持 | 支持 | 不支持 | LISTAGG: 11gR2+, ON OVERFLOW: 12cR2+ |
| SQL Server | 支持 | 不支持 | 不支持 | 不支持 | 2017+；旧版用 `FOR XML PATH` |
| DB2 | 不支持 | 不支持 | 支持 | 不支持 | 9.7+ |
| Snowflake | 不支持 | 不支持 | 支持 | 支持 | LISTAGG + ARRAY_AGG |
| BigQuery | 支持 | 不支持 | 不支持 | 支持 | - |
| Redshift | 支持 | 不支持 | 支持 | 不支持 | - |
| DuckDB | 支持 | 支持 | 支持 | 支持 | 多别名全部支持 |
| ClickHouse | 不支持 | 不支持 | 不支持 | 支持 | 需 `groupArray` + `arrayStringConcat` |
| Trino | 不支持 | 不支持 | 支持 | 支持 | `LISTAGG`: 357+, `ARRAY_AGG`: 早期 |
| Presto | 不支持 | 不支持 | 不支持 | 支持 | 需 `ARRAY_JOIN(ARRAY_AGG(...))` |
| Spark SQL | 不支持 | 不支持 | 不支持 | 支持 | 需 `CONCAT_WS` + `COLLECT_LIST` |
| Hive | 不支持 | 不支持 | 不支持 | 不支持 | 需 `CONCAT_WS` + `COLLECT_LIST` |
| Flink SQL | 不支持 | 不支持 | 支持 | 支持 | LISTAGG: 1.12+ |
| Databricks | 不支持 | 不支持 | 不支持 | 支持 | 同 Spark SQL |
| Teradata | 不支持 | 不支持 | 不支持 | 不支持 | 需递归 SQL 或 UDF |
| Greenplum | 支持 | 不支持 | 支持 (7+) | 支持 | 继承 PG |
| CockroachDB | 支持 | 不支持 | 不支持 | 支持 | 兼容 PG |
| TiDB | 不支持 | 支持 | 不支持 | 不支持 | 兼容 MySQL |
| OceanBase | 不支持 | 支持 | 支持 | 不支持 | MySQL 模式: GROUP_CONCAT; Oracle 模式: LISTAGG |
| YugabyteDB | 支持 | 不支持 | 不支持 | 支持 | 继承 PG |
| SingleStore | 不支持 | 支持 | 不支持 | 不支持 | 兼容 MySQL 的 GROUP_CONCAT |
| Vertica | 不支持 | 不支持 | 支持 | 不支持 | 9.0+ |
| Impala | 不支持 | 支持 | 不支持 | 不支持 | `GROUP_CONCAT` |
| StarRocks | 支持 | 支持 | 不支持 | 支持 | 同时支持两种风格 |
| Doris | 支持 | 支持 | 不支持 | 支持 | `GROUP_CONCAT` + `STRING_AGG` |
| MonetDB | 不支持 | 支持 | 不支持 | 不支持 | `GROUP_CONCAT` |
| CrateDB | 支持 | 不支持 | 不支持 | 支持 | - |
| TimescaleDB | 支持 | 不支持 | 支持 (16+) | 支持 | 继承 PG |
| QuestDB | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Exasol | 不支持 | 支持 | 支持 | 不支持 | - |
| SAP HANA | 支持 | 不支持 | 不支持 | 支持 | - |
| Informix | 不支持 | 不支持 | 不支持 | 不支持 | 需 UDF |
| Firebird | 不支持 | 不支持 | 不支持 | 不支持 | `LIST` 函数 |
| H2 | 支持 | 支持 | 支持 | 支持 | 多别名 |
| HSQLDB | 支持 | 不支持 | 不支持 | 支持 | 2.5+ |
| Derby | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Amazon Athena | 不支持 | 不支持 | 支持 | 支持 | 继承 Trino |
| Azure Synapse | 支持 | 不支持 | 不支持 | 不支持 | 继承 SQL Server |
| Google Spanner | 支持 | 不支持 | 不支持 | 支持 | - |
| Materialize | 支持 | 不支持 | 不支持 | 支持 | 继承 PG |
| RisingWave | 支持 | 不支持 | 不支持 | 支持 | - |
| InfluxDB | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| DatabendDB | 支持 | 支持 | 不支持 | 不支持 | - |
| Yellowbrick | 支持 | 不支持 | 不支持 | 支持 | 继承 PG |
| Firebolt | 不支持 | 不支持 | 不支持 | 支持 | `ARRAY_AGG` + `ARRAY_JOIN` |

> **Firebird 的 LIST 函数**：Firebird 使用独有的 `LIST` 聚合函数进行字符串拼接（1.5+ 版本），语法为 `LIST(expr, delimiter)`。这在其他引擎中没有对应物。

### 百分位数：PERCENTILE_CONT / PERCENTILE_DISC

详细的有序集合聚合对比请参考 [within-group.md](within-group.md)。

| 引擎 | PERCENTILE_CONT | PERCENTILE_DISC | 语法风格 | 版本 |
|------|:---:|:---:|------|------|
| PostgreSQL | 支持 | 支持 | `WITHIN GROUP (ORDER BY ...)` | 9.4+ |
| MySQL | 不支持 | 不支持 | 需窗口函数模拟 | - |
| MariaDB | 支持 | 支持 | `MEDIAN` 作为简写（10.3.3+），窗口函数语法 | 10.3.3+ |
| SQLite | 不支持 | 不支持 | 需子查询模拟 | - |
| Oracle | 支持 | 支持 | `WITHIN GROUP (ORDER BY ...)` | 9i+ |
| SQL Server | 支持 | 支持 | `WITHIN GROUP (ORDER BY ...) OVER (PARTITION BY ...)` | 2012+ |
| DB2 | 支持 | 支持 | `WITHIN GROUP (ORDER BY ...)` | 9.7+ |
| Snowflake | 支持 | 支持 | `WITHIN GROUP (ORDER BY ...)` | GA |
| BigQuery | 支持 | 支持 | `PERCENTILE_CONT(col, 0.5) OVER()` — 窗口函数语法 | GA |
| Redshift | 支持 | 支持 | `WITHIN GROUP (ORDER BY ...)` — 仅窗口函数 | GA |
| DuckDB | 支持 | 支持 | `WITHIN GROUP (ORDER BY ...)` + 简化语法 | 0.5+ |
| ClickHouse | 不支持 | 不支持 | `quantile(0.5)(col)` — 私有语法 | 早期 |
| Trino | 不支持 | 不支持 | `approx_percentile(col, 0.5)` — 仅近似 | 早期 |
| Presto | 不支持 | 不支持 | `approx_percentile(col, 0.5)` — 仅近似 | 早期 |
| Spark SQL | 支持 | 支持 | `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ...)` | 3.1+ |
| Hive | 不支持 | 不支持 | `percentile(col, 0.5)` — 仅精确整数列 | 0.10+ |
| Flink SQL | 不支持 | 不支持 | 需 UDF | - |
| Databricks | 支持 | 支持 | 同 Spark SQL | GA |
| Teradata | 支持 | 支持 | `WITHIN GROUP (ORDER BY ...)` | 14+ |
| Greenplum | 支持 | 支持 | `WITHIN GROUP (ORDER BY ...)` | 继承 PG |
| CockroachDB | 不支持 | 不支持 | 不支持 | - |
| TiDB | 不支持 | 不支持 | 需窗口函数模拟 | - |
| OceanBase | 支持 | 支持 | Oracle 模式支持 | 3.x+ |
| YugabyteDB | 支持 | 支持 | 继承 PG | 2.6+ |
| SingleStore | 不支持 | 不支持 | `PERCENTILE_CONT` 窗口函数形式 | 限窗口函数 |
| Vertica | 支持 | 支持 | `WITHIN GROUP (ORDER BY ...)` | 7.0+ |
| Impala | 不支持 | 不支持 | `APPX_MEDIAN` 仅近似中位数 | - |
| StarRocks | 支持 | 支持 | `PERCENTILE_CONT(col, 0.5)` | 2.4+ |
| Doris | 支持 | 支持 | `PERCENTILE_CONT(col, 0.5)` | 1.1+ |
| MonetDB | 不支持 | 不支持 | 需子查询模拟 | - |
| CrateDB | 不支持 | 不支持 | 不支持 | - |
| TimescaleDB | 支持 | 支持 | 继承 PG | 继承 PG |
| QuestDB | 不支持 | 不支持 | 不支持 | - |
| Exasol | 支持 | 支持 | `WITHIN GROUP (ORDER BY ...)` | 6.0+ |
| SAP HANA | 支持 | 支持 | `WITHIN GROUP (ORDER BY ...)` | 2.0+ |
| Informix | 不支持 | 不支持 | 不支持 | - |
| Firebird | 不支持 | 不支持 | 不支持 | - |
| H2 | 支持 | 支持 | `WITHIN GROUP (ORDER BY ...)` | 2.0+ |
| HSQLDB | 支持 | 支持 | `WITHIN GROUP (ORDER BY ...)` | 2.5+ |
| Derby | 不支持 | 不支持 | 不支持 | - |
| Amazon Athena | 不支持 | 不支持 | `approx_percentile` | 继承 Trino |
| Azure Synapse | 支持 | 支持 | `WITHIN GROUP (...) OVER (...)` | GA |
| Google Spanner | 不支持 | 不支持 | 不支持 | - |
| Materialize | 不支持 | 不支持 | 不支持 | - |
| RisingWave | 不支持 | 不支持 | 不支持 | - |
| InfluxDB | 不支持 | 不支持 | `PERCENTILE(col, 50)` — 私有语法 | 有限支持 |
| DatabendDB | 不支持 | 不支持 | 不支持 | - |
| Yellowbrick | 支持 | 支持 | `WITHIN GROUP (ORDER BY ...)` | GA |
| Firebolt | 不支持 | 不支持 | 不支持 | - |

> **SQL Server/BigQuery 的特殊限制**：SQL Server 的 `PERCENTILE_CONT`/`PERCENTILE_DISC` 只能作为窗口函数使用，必须带 `OVER(PARTITION BY ...)` 子句，不能作为普通聚合函数。BigQuery 也有类似限制（`PERCENTILE_CONT(col, pct) OVER()`）。这意味着在这两个引擎中，你不能直接 `SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) FROM employees`。

### MODE / MEDIAN

| 引擎 | MODE | MEDIAN | 版本/备注 |
|------|:---:|:---:|------|
| PostgreSQL | 支持 | 不支持 | `MODE() WITHIN GROUP (ORDER BY col)` (9.4+) |
| MySQL | 不支持 | 不支持 | 需子查询模拟 |
| MariaDB | 不支持 | 支持 | `MEDIAN(col)` (10.3.3+) |
| SQLite | 不支持 | 不支持 | 需 `PERCENTILE` 扩展 |
| Oracle | 不支持 | 支持 | `MEDIAN(col)` (10gR1+) |
| SQL Server | 不支持 | 不支持 | 需 `PERCENTILE_CONT(0.5)` |
| DB2 | 不支持 | 支持 | `MEDIAN(col)` (9.7+) |
| Snowflake | 支持 | 支持 | `MODE(col)`, `MEDIAN(col)` |
| BigQuery | 不支持 | 不支持 | 需 `PERCENTILE_CONT` 窗口函数 |
| Redshift | 不支持 | 支持 | `MEDIAN(col)` |
| DuckDB | 支持 | 支持 | `MODE(col)`, `MEDIAN(col)` |
| ClickHouse | 不支持 | 支持 | `median(col)` = `quantile(0.5)(col)` |
| Trino | 不支持 | 不支持 | 需 `approx_percentile` |
| Presto | 不支持 | 不支持 | 需 `approx_percentile` |
| Spark SQL | 支持 | 不支持 | `MODE(col)` (3.4+)，MEDIAN 需 `PERCENTILE_CONT(0.5)` |
| Hive | 不支持 | 不支持 | 需 `percentile(col, 0.5)` |
| Flink SQL | 不支持 | 不支持 | 需 UDF |
| Databricks | 支持 | 不支持 | 同 Spark SQL |
| Teradata | 不支持 | 支持 | `MEDIAN(col)` |
| Greenplum | 支持 | 支持 | `MEDIAN(col)`, 继承 PG |
| CockroachDB | 不支持 | 不支持 | 不支持 |
| TiDB | 不支持 | 不支持 | 不支持 |
| OceanBase | 不支持 | 支持 | Oracle 模式支持 `MEDIAN` |
| YugabyteDB | 支持 | 不支持 | 继承 PG |
| SingleStore | 不支持 | 支持 | `MEDIAN(col)` |
| Vertica | 不支持 | 支持 | `MEDIAN(col)` |
| Impala | 不支持 | 不支持 | `APPX_MEDIAN` 仅近似 |
| StarRocks | 不支持 | 不支持 | 需模拟 |
| Doris | 不支持 | 不支持 | 需模拟 |
| MonetDB | 不支持 | 支持 | `MEDIAN(col)` |
| CrateDB | 不支持 | 不支持 | 不支持 |
| TimescaleDB | 支持 | 不支持 | 继承 PG |
| QuestDB | 不支持 | 不支持 | 不支持 |
| Exasol | 不支持 | 支持 | `MEDIAN(col)` |
| SAP HANA | 不支持 | 支持 | `MEDIAN(col)` |
| Informix | 不支持 | 不支持 | 不支持 |
| Firebird | 不支持 | 不支持 | 不支持 |
| H2 | 支持 | 支持 | `MODE() WITHIN GROUP (...)`, `MEDIAN(col)` |
| HSQLDB | 支持 | 支持 | `WITHIN GROUP` 语法 |
| Derby | 不支持 | 不支持 | 不支持 |
| Amazon Athena | 不支持 | 不支持 | 继承 Trino |
| Azure Synapse | 不支持 | 不支持 | 需 `PERCENTILE_CONT(0.5)` |
| Google Spanner | 不支持 | 不支持 | 不支持 |
| Materialize | 不支持 | 不支持 | 不支持 |
| RisingWave | 不支持 | 不支持 | 不支持 |
| InfluxDB | 不支持 | 支持 | `MEDIAN(col)` |
| DatabendDB | 不支持 | 支持 | `MEDIAN(col)` |
| Yellowbrick | 不支持 | 不支持 | 需 `PERCENTILE_CONT` |
| Firebolt | 不支持 | 支持 | `MEDIAN(col)` |

### 回归/相关性函数：CORR / COVAR_POP / COVAR_SAMP / REGR_*

SQL:2003 标准定义了一组完整的回归分析聚合函数。以下矩阵检查 `CORR`、`COVAR_POP`/`COVAR_SAMP` 以及 `REGR_SLOPE`/`REGR_INTERCEPT`/`REGR_COUNT`/`REGR_R2`/`REGR_AVGX`/`REGR_AVGY`/`REGR_SXX`/`REGR_SXY`/`REGR_SYY` 这组函数的支持情况。

| 引擎 | CORR | COVAR_POP/SAMP | REGR_* (全部 9 个) | 版本 |
|------|:---:|:---:|:---:|------|
| PostgreSQL | 支持 | 支持 | 支持 | 8.2+ |
| MySQL | 不支持 | 不支持 | 不支持 | 不支持 |
| MariaDB | 不支持 | 不支持 | 不支持 | 不支持 |
| SQLite | 不支持 | 不支持 | 不支持 | 不支持 |
| Oracle | 支持 | 支持 | 支持 | 9i+ |
| SQL Server | 不支持 | 不支持 | 不支持 | 不支持（需手动计算） |
| DB2 | 支持 | 支持 | 支持 | 9.0+ |
| Snowflake | 支持 | 支持 | 支持 | GA |
| BigQuery | 支持 | 支持 | 不支持 | GA (仅 CORR/COVAR) |
| Redshift | 支持 | 支持 | 支持 | GA |
| DuckDB | 支持 | 支持 | 支持 | 0.7+ |
| ClickHouse | 支持 | 支持 | 不支持 | `corr`, `covarPop`, `covarSamp` |
| Trino | 支持 | 支持 | 支持 | 早期 |
| Presto | 支持 | 支持 | 支持 | 早期 |
| Spark SQL | 支持 | 支持 | 不支持 | `corr`, `covar_pop`, `covar_samp`; REGR 需手动 |
| Hive | 支持 | 支持 | 不支持 | `corr`, `covar_pop`, `covar_samp` |
| Flink SQL | 不支持 | 不支持 | 不支持 | 需 UDF |
| Databricks | 支持 | 支持 | 不支持 | 同 Spark SQL |
| Teradata | 支持 | 支持 | 支持 | 14+ |
| Greenplum | 支持 | 支持 | 支持 | 继承 PG |
| CockroachDB | 支持 | 支持 | 不支持 | 部分支持 |
| TiDB | 不支持 | 不支持 | 不支持 | 不支持 |
| OceanBase | 支持 | 支持 | 支持 | Oracle 模式 |
| YugabyteDB | 支持 | 支持 | 支持 | 继承 PG |
| SingleStore | 不支持 | 不支持 | 不支持 | 不支持 |
| Vertica | 支持 | 支持 | 支持 | 7.0+ |
| Impala | 不支持 | 不支持 | 不支持 | 不支持 |
| StarRocks | 支持 | 支持 | 不支持 | `corr`, `covar_pop`, `covar_samp` |
| Doris | 支持 | 支持 | 不支持 | `corr`, `covar_pop`, `covar_samp` |
| MonetDB | 支持 | 支持 | 支持 | 早期 |
| CrateDB | 不支持 | 不支持 | 不支持 | 不支持 |
| TimescaleDB | 支持 | 支持 | 支持 | 继承 PG |
| QuestDB | 不支持 | 不支持 | 不支持 | 不支持 |
| Exasol | 支持 | 支持 | 支持 | 6.0+ |
| SAP HANA | 支持 | 支持 | 支持 | 2.0+ |
| Informix | 不支持 | 不支持 | 不支持 | 不支持 |
| Firebird | 不支持 | 不支持 | 不支持 | 不支持 |
| H2 | 支持 | 支持 | 支持 | 2.0+ |
| HSQLDB | 支持 | 支持 | 支持 | 2.5+ |
| Derby | 不支持 | 不支持 | 不支持 | 不支持 |
| Amazon Athena | 支持 | 支持 | 支持 | 继承 Trino |
| Azure Synapse | 不支持 | 不支持 | 不支持 | 需手动计算 |
| Google Spanner | 不支持 | 不支持 | 不支持 | 不支持 |
| Materialize | 不支持 | 不支持 | 不支持 | 不支持 |
| RisingWave | 不支持 | 不支持 | 不支持 | 不支持 |
| InfluxDB | 不支持 | 不支持 | 不支持 | 不支持 |
| DatabendDB | 不支持 | 支持 | 不支持 | 部分支持 |
| Yellowbrick | 支持 | 支持 | 支持 | GA |
| Firebolt | 不支持 | 不支持 | 不支持 | 不支持 |

> **MySQL/SQL Server 的缺失**：MySQL 和 SQL Server 至今不支持任何回归/相关性聚合函数，这是 SQL:2003 合规性的显著缺口。在这些引擎中需用 `SUM`/`AVG`/`COUNT` 手动推导。

### GROUPING 函数

`GROUPING(col)` 函数用于区分 `GROUP BY GROUPING SETS`/`CUBE`/`ROLLUP` 中的真实 NULL 值和因分组产生的占位 NULL。详见 [grouping-sets-cube-rollup.md](grouping-sets-cube-rollup.md)。

| 引擎 | GROUPING() | GROUPING_ID() / GROUPING() 多参数 | 版本/备注 |
|------|:---:|:---:|------|
| PostgreSQL | 支持 | 支持 (多参数) | 9.5+ |
| MySQL | 支持 | 不支持 | 8.0.1+ |
| MariaDB | 不支持 | 不支持 | 仅支持 ROLLUP，无 GROUPING |
| SQLite | 不支持 | 不支持 | 不支持 GROUPING SETS |
| Oracle | 支持 | 支持 (`GROUPING_ID`) | 9i+ |
| SQL Server | 支持 | 支持 (`GROUPING_ID`) | 2008+ |
| DB2 | 支持 | 支持 (多参数) | 7.1+ |
| Snowflake | 支持 | 支持 (`GROUPING`) | GA |
| BigQuery | 支持 | 不支持 | GA |
| Redshift | 支持 | 不支持 | GA |
| DuckDB | 支持 | 支持 | 0.8.0+ |
| ClickHouse | 支持 | 不支持 | 19.13+ |
| Trino | 支持 | 支持 | 早期 |
| Presto | 支持 | 支持 | 0.98+ |
| Spark SQL | 支持 | 支持 (`GROUPING_ID`) | 2.0+ |
| Hive | 支持 | 支持 (`GROUPING__ID`) | 0.10+；注意双下划线 |
| Flink SQL | 支持 | 不支持 | 1.12+ |
| Databricks | 支持 | 支持 (`GROUPING_ID`) | GA |
| Teradata | 支持 | 支持 (`GROUPING`) | 14+ |
| Greenplum | 支持 | 支持 | 继承 PG |
| CockroachDB | 不支持 | 不支持 | 不支持 GROUPING SETS |
| TiDB | 不支持 | 不支持 | 仅 ROLLUP |
| OceanBase | 支持 | 支持 | Oracle 模式 3.x+ |
| YugabyteDB | 支持 | 支持 | 继承 PG |
| SingleStore | 不支持 | 不支持 | 不支持 |
| Vertica | 支持 | 支持 (`GROUPING_ID`) | 7.0+ |
| Impala | 不支持 | 不支持 | 不支持 GROUPING SETS |
| StarRocks | 支持 | 支持 (`GROUPING_ID`) | 2.0+ |
| Doris | 支持 | 支持 (`GROUPING_ID`) | 1.1+ |
| SAP HANA | 支持 | 支持 | 1.0+ |
| H2 | 支持 | 支持 | 1.4+ |
| Exasol | 支持 | 支持 | 6.0+ |

> **Hive 的命名异常**：Hive 使用 `GROUPING__ID`（双下划线），而非标准的 `GROUPING_ID`。这是一个历史遗留问题。

### FILTER 子句

详细的 FILTER 子句对比请参考 [filter-clause.md](filter-clause.md)，以下为完整引擎矩阵：

| 引擎 | FILTER (WHERE ...) | 替代方案 | 版本 |
|------|:---:|------|------|
| PostgreSQL | 支持 | -- | 9.4+ |
| MySQL | 不支持 | `CASE WHEN ... END` | - |
| MariaDB | 不支持 | `CASE WHEN ... END` | - |
| SQLite | 支持 | -- | 3.30+ |
| Oracle | 不支持 | `CASE WHEN ... END` | - |
| SQL Server | 不支持 | `CASE WHEN ... END` / `IIF` | - |
| DB2 | 不支持 | `CASE WHEN ... END` | - |
| Snowflake | 不支持 | `CASE WHEN ... END` / `IFF` | - |
| BigQuery | 不支持 | `COUNTIF` / `IF` | - |
| Redshift | 不支持 | `CASE WHEN ... END` | - |
| DuckDB | 支持 | -- | 0.3+ |
| ClickHouse | 不支持 | `-If` 后缀函数（`countIf`、`sumIf` 等） | - |
| Trino | 支持 | -- | 早期 |
| Presto | 支持 | -- | 0.142+ |
| Spark SQL | 支持 | -- | 3.0+ |
| Hive | 不支持 | `CASE WHEN ... END` | - |
| Flink SQL | 不支持 | `CASE WHEN ... END` | - |
| Databricks | 支持 | -- | 同 Spark SQL |
| Teradata | 不支持 | `CASE WHEN ... END` | - |
| Greenplum | 支持 | -- | 继承 PG |
| CockroachDB | 支持 | -- | 20.1+ |
| TiDB | 不支持 | `CASE WHEN ... END` | - |
| OceanBase | 不支持 | `CASE WHEN ... END` | - |
| YugabyteDB | 支持 | -- | 继承 PG |
| SingleStore | 不支持 | `CASE WHEN ... END` | - |
| Vertica | 不支持 | `CASE WHEN ... END` | - |
| Impala | 不支持 | `CASE WHEN ... END` | - |
| StarRocks | 不支持 | `CASE WHEN ... END` | - |
| Doris | 不支持 | `CASE WHEN ... END` | - |
| MonetDB | 不支持 | `CASE WHEN ... END` | - |
| CrateDB | 不支持 | `CASE WHEN ... END` | - |
| TimescaleDB | 支持 | -- | 继承 PG |
| QuestDB | 不支持 | `CASE WHEN ... END` | - |
| Exasol | 不支持 | `CASE WHEN ... END` | - |
| SAP HANA | 不支持 | `CASE WHEN ... END` | - |
| Informix | 不支持 | `CASE WHEN ... END` | - |
| Firebird | 不支持 | `CASE WHEN ... END` | - |
| H2 | 支持 | -- | 2.0+ |
| HSQLDB | 支持 | -- | 2.5+ |
| Derby | 不支持 | `CASE WHEN ... END` | - |
| Amazon Athena | 支持 | -- | 继承 Trino |
| Azure Synapse | 不支持 | `CASE WHEN ... END` | - |
| Google Spanner | 不支持 | `CASE WHEN ... END` | - |
| Materialize | 支持 | -- | 继承 PG |
| RisingWave | 支持 | -- | GA |
| InfluxDB | 不支持 | `WHERE` 子句 | - |
| DatabendDB | 不支持 | `CASE WHEN ... END` | - |
| Yellowbrick | 支持 | -- | GA |
| Firebolt | 不支持 | `CASE WHEN ... END` | - |

### DISTINCT 与 ORDER BY 在聚合内部的支持

| 引擎 | DISTINCT 内聚合 | ORDER BY 内聚合 | 版本/备注 |
|------|:---:|:---:|------|
| PostgreSQL | 支持 | 支持 | `STRING_AGG(DISTINCT col, ',' ORDER BY col)` |
| MySQL | 支持 | 支持 | `GROUP_CONCAT(DISTINCT col ORDER BY col)` |
| MariaDB | 支持 | 支持 | 同 MySQL |
| SQLite | 不支持 | 不支持 | `GROUP_CONCAT` 不支持 ORDER BY |
| Oracle | 支持 | 支持 | `LISTAGG(DISTINCT col, ',') WITHIN GROUP (ORDER BY col)` (19c+) |
| SQL Server | 支持 | 支持 | `STRING_AGG(col, ',') WITHIN GROUP (ORDER BY col)` |
| DB2 | 支持 | 支持 | `LISTAGG(DISTINCT col, ',') WITHIN GROUP (ORDER BY col)` |
| Snowflake | 支持 | 支持 | 通过 `WITHIN GROUP` 或函数内 ORDER BY |
| BigQuery | 支持 | 支持 | `STRING_AGG(DISTINCT col, ',' ORDER BY col)` |
| Redshift | 支持 | 支持 | `LISTAGG(DISTINCT col, ',') WITHIN GROUP (ORDER BY col)` |
| DuckDB | 支持 | 支持 | 多种语法均支持 |
| ClickHouse | 不支持 | 不支持 | 需 `groupArrayDistinct` + 排序 |
| Trino | 支持 | 支持 | `ARRAY_AGG(DISTINCT col ORDER BY col)` |
| Presto | 支持 | 支持 | 同 Trino |
| Spark SQL | 支持 | 不支持 | DISTINCT 支持；ORDER BY 内聚合有限 |
| Hive | 不支持 | 不支持 | `COLLECT_SET` 实现去重 |
| Flink SQL | 支持 | 不支持 | DISTINCT 支持；ORDER BY 不支持 |
| Databricks | 支持 | 不支持 | 同 Spark SQL |
| Teradata | 不支持 | 不支持 | 需子查询预处理 |
| Greenplum | 支持 | 支持 | 继承 PG |
| CockroachDB | 支持 | 支持 | 继承 PG |
| TiDB | 支持 | 支持 | 兼容 MySQL 的 GROUP_CONCAT 语法 |
| OceanBase | 支持 | 支持 | 模式依赖 |
| YugabyteDB | 支持 | 支持 | 继承 PG |
| SingleStore | 支持 | 支持 | 兼容 MySQL |
| Vertica | 不支持 | 支持 | `LISTAGG` 支持 ORDER BY |
| StarRocks | 支持 | 支持 | `GROUP_CONCAT` |
| Doris | 支持 | 支持 | `GROUP_CONCAT` |
| H2 | 支持 | 支持 | 多种函数均支持 |

## 各引擎语法示例

### PostgreSQL — 最完整的标准实现

```sql
-- 基础聚合
SELECT department,
       COUNT(*) AS cnt,
       SUM(salary) AS total,
       AVG(salary) AS avg_sal,
       MIN(salary) AS min_sal,
       MAX(salary) AS max_sal
FROM employees
GROUP BY department;

-- 统计聚合
SELECT department,
       STDDEV_POP(salary) AS stddev_pop,
       STDDEV_SAMP(salary) AS stddev_samp,
       VAR_POP(salary) AS var_pop,
       VAR_SAMP(salary) AS var_samp
FROM employees
GROUP BY department;

-- 布尔聚合
SELECT department,
       BOOL_AND(is_active) AS all_active,
       BOOL_OR(is_manager) AS has_manager,
       EVERY(salary > 0) AS all_positive_salary
FROM employees
GROUP BY department;

-- 字符串聚合 + ORDER BY
SELECT department,
       STRING_AGG(name, ', ' ORDER BY name) AS member_list,
       ARRAY_AGG(DISTINCT skill ORDER BY skill) AS skills
FROM employees
GROUP BY department;

-- 百分位数 (WITHIN GROUP 语法)
SELECT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median_salary,
       PERCENTILE_DISC(0.9) WITHIN GROUP (ORDER BY salary) AS p90_salary,
       MODE() WITHIN GROUP (ORDER BY title) AS most_common_title
FROM employees
GROUP BY department;

-- 回归函数
SELECT CORR(salary, experience_years) AS correlation,
       COVAR_POP(salary, experience_years) AS covar_p,
       REGR_SLOPE(salary, experience_years) AS slope,
       REGR_INTERCEPT(salary, experience_years) AS intercept,
       REGR_R2(salary, experience_years) AS r_squared
FROM employees;

-- FILTER 子句
SELECT department,
       COUNT(*) FILTER (WHERE status = 'active') AS active_count,
       SUM(salary) FILTER (WHERE hire_year >= 2020) AS recent_hire_salary,
       AVG(salary) FILTER (WHERE title LIKE '%Senior%') AS avg_senior_salary
FROM employees
GROUP BY department;

-- 位运算聚合
SELECT department,
       BIT_AND(permissions) AS common_permissions,
       BIT_OR(permissions) AS all_permissions,
       BIT_XOR(flags) AS xor_flags
FROM employees
GROUP BY department;
```

### MySQL — 常见陷阱

```sql
-- 基础聚合（同标准）
SELECT department, COUNT(*), SUM(salary), AVG(salary) FROM employees GROUP BY department;

-- ⚠️ AVG 陷阱：AVG(int_column) 在 MySQL 中可能返回 DECIMAL，但精度依赖列定义

-- 多列 COUNT DISTINCT（MySQL 独有）
SELECT COUNT(DISTINCT department, title) AS distinct_combos FROM employees;

-- GROUP_CONCAT（注意默认截断限制）
SET SESSION group_concat_max_len = 1000000;  -- 先提高限制
SELECT department,
       GROUP_CONCAT(name ORDER BY name SEPARATOR ', ') AS members,
       GROUP_CONCAT(DISTINCT title ORDER BY title SEPARATOR '; ') AS titles
FROM employees
GROUP BY department;

-- 统计函数
-- ⚠️ STDDEV() 和 VARIANCE() 在 MySQL 中是总体版本 (POP)，与 PostgreSQL 相反！
SELECT department,
       STDDEV(salary) AS stddev_pop,          -- 等价于 STDDEV_POP
       STDDEV_SAMP(salary) AS stddev_samp,    -- 样本标准差
       VARIANCE(salary) AS var_pop,           -- 等价于 VAR_POP
       VAR_SAMP(salary) AS var_samp           -- 样本方差
FROM employees
GROUP BY department;

-- 布尔聚合替代（MySQL 无布尔聚合）
SELECT department,
       MIN(is_active) = 1 AS all_active,     -- 模拟 BOOL_AND
       MAX(is_manager) = 1 AS has_manager    -- 模拟 BOOL_OR
FROM employees
GROUP BY department;

-- FILTER 子句替代
SELECT department,
       COUNT(CASE WHEN status = 'active' THEN 1 END) AS active_count,
       SUM(CASE WHEN hire_year >= 2020 THEN salary END) AS recent_salary
FROM employees
GROUP BY department;
```

### Oracle — LISTAGG 和回归函数

```sql
-- LISTAGG（Oracle 11gR2+）
SELECT department,
       LISTAGG(name, ', ') WITHIN GROUP (ORDER BY name) AS members
FROM employees
GROUP BY department;

-- LISTAGG 溢出处理（Oracle 12cR2+）
SELECT department,
       LISTAGG(name, ', ' ON OVERFLOW TRUNCATE '...' WITH COUNT)
         WITHIN GROUP (ORDER BY name) AS members
FROM employees
GROUP BY department;

-- LISTAGG DISTINCT（Oracle 19c+）
SELECT department,
       LISTAGG(DISTINCT title, ', ') WITHIN GROUP (ORDER BY title) AS titles
FROM employees
GROUP BY department;

-- 回归分析（完整支持）
SELECT
    CORR(salary, years_exp) AS correlation,
    COVAR_POP(salary, years_exp) AS cov_pop,
    COVAR_SAMP(salary, years_exp) AS cov_samp,
    REGR_SLOPE(salary, years_exp) AS slope,
    REGR_INTERCEPT(salary, years_exp) AS intercept,
    REGR_R2(salary, years_exp) AS r_squared,
    REGR_COUNT(salary, years_exp) AS n
FROM employees;

-- MEDIAN（Oracle 10g+，直接聚合函数）
SELECT department, MEDIAN(salary) AS median_salary
FROM employees
GROUP BY department;

-- 布尔聚合替代（Oracle 无布尔类型）
SELECT department,
       MIN(CASE WHEN is_active = 'Y' THEN 1 ELSE 0 END) AS all_active,
       MAX(CASE WHEN is_manager = 'Y' THEN 1 ELSE 0 END) AS has_manager
FROM employees
GROUP BY department;
```

### SQL Server — WITHIN GROUP 的特殊用法

```sql
-- STRING_AGG（SQL Server 2017+）
SELECT department,
       STRING_AGG(name, ', ') WITHIN GROUP (ORDER BY name) AS members
FROM employees
GROUP BY department;

-- ⚠️ PERCENTILE_CONT 只能作为窗口函数使用
SELECT DISTINCT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary)
         OVER (PARTITION BY department) AS median_salary
FROM employees;

-- 统计函数
-- STDDEV() = STDDEV_SAMP()（与 MySQL 相反！）
SELECT department,
       STDEV(salary) AS stddev_samp,         -- SQL Server 用 STDEV 而非 STDDEV
       STDEVP(salary) AS stddev_pop,         -- SQL Server 用 STDEVP
       VAR(salary) AS var_samp,              -- SQL Server 用 VAR
       VARP(salary) AS var_pop               -- SQL Server 用 VARP
FROM employees
GROUP BY department;

-- FILTER 替代
SELECT department,
       COUNT(CASE WHEN status = 'active' THEN 1 END) AS active_count,
       COUNT(IIF(status = 'pending', 1, NULL)) AS pending_count
FROM employees
GROUP BY department;
```

> **SQL Server 命名特殊性**：SQL Server 使用 `STDEV`/`STDEVP`/`VAR`/`VARP` 而非标准的 `STDDEV_SAMP`/`STDDEV_POP`/`VAR_SAMP`/`VAR_POP`。这是唯一一个不使用标准名称的主流引擎。

### ClickHouse — 独特的函数命名体系

```sql
-- ClickHouse 使用驼峰命名，且有丰富的变体后缀
SELECT department,
       count() AS cnt,                        -- count() 不带参数等价于 COUNT(*)
       sum(salary) AS total,
       avg(salary) AS avg_sal,
       stddevPop(salary) AS stddev_pop,
       stddevSamp(salary) AS stddev_samp,
       varPop(salary) AS var_pop,
       varSamp(salary) AS var_samp
FROM employees
GROUP BY department;

-- -If 后缀替代 FILTER 子句
SELECT department,
       countIf(status = 'active') AS active_count,
       sumIf(salary, hire_year >= 2020) AS recent_salary,
       avgIf(salary, title LIKE '%Senior%') AS avg_senior
FROM employees
GROUP BY department;

-- quantile 替代 PERCENTILE_CONT
SELECT department,
       quantile(0.5)(salary) AS median_salary,
       quantile(0.9)(salary) AS p90_salary,
       quantiles(0.25, 0.5, 0.75)(salary) AS quartiles  -- 一次计算多个分位数
FROM employees
GROUP BY department;

-- 字符串聚合
SELECT department,
       arrayStringConcat(groupArray(name), ', ') AS members,
       arrayStringConcat(arraySort(groupArray(name)), ', ') AS sorted_members
FROM employees
GROUP BY department;

-- 位运算聚合
SELECT department,
       groupBitAnd(permissions) AS common_perms,
       groupBitOr(permissions) AS all_perms,
       groupBitXor(flags) AS xor_flags
FROM employees
GROUP BY department;

-- 近似去重计数
SELECT
       uniq(user_id) AS approx_distinct,           -- HyperLogLog
       uniqExact(user_id) AS exact_distinct,        -- 精确
       uniqHLL12(user_id) AS hll_distinct            -- HLL 12-bit
FROM events;
```

### DuckDB — 多别名与现代语法

```sql
-- DuckDB 支持多种语法风格，兼容性极强
SELECT department,
       STRING_AGG(name, ', ' ORDER BY name) AS members_pg,     -- PostgreSQL 风格
       GROUP_CONCAT(name, ', ') AS members_mysql,              -- MySQL 风格
       LISTAGG(name, ', ') WITHIN GROUP (ORDER BY name) AS members_oracle  -- Oracle 风格
FROM employees
GROUP BY department;

-- FILTER 子句（完整支持）
SELECT department,
       COUNT(*) FILTER (WHERE status = 'active') AS active_count,
       SUM(salary) FILTER (WHERE hire_year >= 2020) AS recent_salary
FROM employees
GROUP BY department;

-- 百分位数（多种语法）
SELECT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median_standard,
       MEDIAN(salary) AS median_shortcut,                      -- 简写
       MODE(title) AS most_common_title                        -- 直接调用
FROM employees
GROUP BY department;

-- ARRAY_AGG + LIST（DuckDB 也使用 LIST 作为 ARRAY_AGG 别名）
SELECT department,
       LIST(name ORDER BY name) AS name_list,
       LIST(DISTINCT skill) AS unique_skills
FROM employees
GROUP BY department;
```

### Snowflake — LISTAGG + APPROX 函数

```sql
-- LISTAGG（标准 Oracle 风格）
SELECT department,
       LISTAGG(name, ', ') WITHIN GROUP (ORDER BY name) AS members
FROM employees
GROUP BY department;

-- ARRAY_AGG
SELECT department,
       ARRAY_AGG(name) WITHIN GROUP (ORDER BY name) AS name_array,
       ARRAY_AGG(DISTINCT title) AS unique_titles
FROM employees
GROUP BY department;

-- 近似函数
SELECT APPROX_COUNT_DISTINCT(user_id) AS approx_users,
       HLL(user_id) AS hll_users,
       APPROX_PERCENTILE(salary, 0.5) AS approx_median
FROM events;

-- 百分位数（标准 WITHIN GROUP 语法）
SELECT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median,
       PERCENTILE_DISC(0.9) WITHIN GROUP (ORDER BY salary) AS p90,
       MEDIAN(salary) AS median_shortcut
FROM employees
GROUP BY department;

-- 布尔聚合
SELECT department,
       BOOLAND_AGG(is_active) AS all_active,    -- Snowflake 用 BOOLAND_AGG
       BOOLOR_AGG(is_manager) AS has_manager    -- 和 BOOLOR_AGG
FROM employees
GROUP BY department;
```

### BigQuery — 特殊函数命名

```sql
-- 布尔聚合（BigQuery 用 LOGICAL_AND / LOGICAL_OR）
SELECT department,
       LOGICAL_AND(is_active) AS all_active,
       LOGICAL_OR(is_manager) AS has_manager
FROM employees
GROUP BY department;

-- COUNTIF（BigQuery 内置的 FILTER 替代）
SELECT department,
       COUNTIF(status = 'active') AS active_count,
       SUM(IF(hire_year >= 2020, salary, 0)) AS recent_salary
FROM employees
GROUP BY department;

-- STRING_AGG
SELECT department,
       STRING_AGG(name, ', ' ORDER BY name) AS members,
       STRING_AGG(DISTINCT title, '; ' ORDER BY title) AS titles
FROM employees
GROUP BY department;

-- ⚠️ PERCENTILE_CONT 必须作为窗口函数
SELECT DISTINCT department,
       PERCENTILE_CONT(salary, 0.5) OVER (PARTITION BY department) AS median
FROM employees;

-- APPROX 函数族
SELECT APPROX_COUNT_DISTINCT(user_id) AS approx_distinct,
       APPROX_QUANTILES(salary, 100)[OFFSET(50)] AS approx_median,
       APPROX_TOP_COUNT(browser, 10) AS top_browsers
FROM events;
```

### Spark SQL / Databricks

```sql
-- 布尔聚合（Spark 3.0+）
SELECT department,
       EVERY(salary > 0) AS all_positive,         -- SQL 标准名称
       BOOL_AND(is_active) AS all_active,          -- PostgreSQL 风格
       SOME(is_manager) AS has_manager,            -- SQL 标准
       BOOL_OR(is_vip) AS has_vip                  -- PostgreSQL 风格
FROM employees
GROUP BY department;

-- FILTER 子句（Spark 3.0+）
SELECT department,
       COUNT(*) FILTER (WHERE status = 'active') AS active_count,
       SUM(salary) FILTER (WHERE hire_year >= 2020) AS recent_salary
FROM employees
GROUP BY department;

-- 字符串聚合（需组合函数）
SELECT department,
       CONCAT_WS(', ', COLLECT_LIST(name)) AS members,            -- 保留重复
       CONCAT_WS(', ', COLLECT_SET(title)) AS unique_titles,      -- 去重
       CONCAT_WS(', ', SORT_ARRAY(COLLECT_LIST(name))) AS sorted  -- 排序
FROM employees
GROUP BY department;

-- PERCENTILE_CONT（Spark 3.1+）
SELECT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median
FROM employees
GROUP BY department;

-- MODE（Spark 3.4+）
SELECT department, MODE(title) AS most_common_title
FROM employees
GROUP BY department;

-- 近似函数
SELECT APPROX_COUNT_DISTINCT(user_id) AS approx_distinct,
       PERCENTILE_APPROX(salary, 0.5) AS approx_median
FROM events;
```

### Flink SQL — 流式聚合的限制

```sql
-- 基础聚合（完整支持）
SELECT department,
       COUNT(*) AS cnt,
       SUM(salary) AS total,
       AVG(salary) AS avg_sal
FROM employees
GROUP BY department;

-- LISTAGG（Flink 1.12+）
SELECT department,
       LISTAGG(name, ', ') AS members
FROM employees
GROUP BY department;
-- ⚠️ Flink 的 LISTAGG 不支持 ORDER BY 和 DISTINCT

-- ARRAY_AGG（Flink 1.15+）
SELECT department, ARRAY_AGG(name) AS names FROM employees GROUP BY department;

-- 统计函数
SELECT department,
       STDDEV_POP(salary) AS sp,
       STDDEV_SAMP(salary) AS ss,
       VAR_POP(salary) AS vp,
       VAR_SAMP(salary) AS vs
FROM employees
GROUP BY department;

-- ⚠️ FILTER 子句不支持，需用 CASE WHEN
SELECT department,
       COUNT(CASE WHEN status = 'active' THEN 1 END) AS active_count
FROM employees
GROUP BY department;

-- ⚠️ Flink 不支持 PERCENTILE_CONT/PERCENTILE_DISC、回归函数、布尔聚合
```

## FILTER 子句深入分析

### 标准语法

SQL:2003 标准定义的 `FILTER` 子句语法：

```sql
aggregate_function(...) FILTER (WHERE search_condition)
```

`FILTER` 子句可以附加到任何聚合函数之后，在聚合前对输入行进行过滤。逻辑上等价于在聚合函数内部使用 `CASE WHEN`，但语义更清晰且对优化器更友好。

### 支持引擎的详细行为

**完整支持 FILTER 的引擎**（约 16 个）：PostgreSQL (9.4+)、SQLite (3.30+)、DuckDB (0.3+)、Trino、Presto (0.142+)、Spark SQL (3.0+)、Databricks、CockroachDB (20.1+)、Greenplum、YugabyteDB、TimescaleDB、H2 (2.0+)、HSQLDB (2.5+)、Amazon Athena、Materialize、RisingWave、Yellowbrick。

### 不支持引擎的替代写法

#### 通用替代：CASE WHEN

```sql
-- FILTER 原始写法
COUNT(*) FILTER (WHERE status = 'active')

-- CASE WHEN 替代（适用所有引擎）
COUNT(CASE WHEN status = 'active' THEN 1 END)
-- 或
SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END)
```

注意：`COUNT(*)` 配合 FILTER 和 `COUNT(CASE WHEN)` 有细微语义差异——前者统计满足条件的行数，后者统计非 NULL 值的个数。但 `CASE WHEN ... THEN 1 END` 在条件不满足时返回 NULL，被 `COUNT` 忽略，因此效果相同。

#### BigQuery 专用：COUNTIF / IF

```sql
-- BigQuery 原生支持 COUNTIF
COUNTIF(status = 'active')

-- 其他聚合用 IF
SUM(IF(status = 'active', amount, 0))
AVG(IF(status = 'active', salary, NULL))
```

#### ClickHouse 专用：-If 后缀

```sql
-- ClickHouse 为每个聚合函数提供 -If 后缀版本
countIf(status = 'active')
sumIf(amount, status = 'active')
avgIf(salary, status = 'active')
minIf(price, category = 'electronics')

-- 也可以组合 -Distinct 和 -If
countDistinctIf(user_id, event_type = 'purchase')
-- 等价于: COUNT(DISTINCT user_id) FILTER (WHERE event_type = 'purchase')
```

### FILTER 与窗口函数的组合

在支持 FILTER 的引擎中，FILTER 也可以与窗口函数一起使用：

```sql
-- PostgreSQL / DuckDB
SELECT name, department, salary,
       SUM(salary) FILTER (WHERE hire_year >= 2020) 
         OVER (PARTITION BY department) AS recent_dept_total,
       COUNT(*) FILTER (WHERE is_manager)
         OVER () AS total_managers
FROM employees;
```

这在不支持 FILTER 的引擎中需要组合 CASE WHEN 和窗口函数：

```sql
-- MySQL / Oracle / SQL Server
SELECT name, department, salary,
       SUM(CASE WHEN hire_year >= 2020 THEN salary ELSE 0 END)
         OVER (PARTITION BY department) AS recent_dept_total,
       SUM(CASE WHEN is_manager = 1 THEN 1 ELSE 0 END)
         OVER () AS total_managers
FROM employees;
```

## NULL 处理的关键差异

### 标准 NULL 行为

SQL 标准规定了聚合函数的 NULL 处理规则：

| 场景 | 行为 | 示例 |
|------|------|------|
| `COUNT(*)` | 计数所有行（包括 NULL 行） | `COUNT(*)` 返回表总行数 |
| `COUNT(col)` | 忽略 col 为 NULL 的行 | 仅计数非 NULL 值 |
| `SUM/AVG/MIN/MAX(col)` | 忽略 NULL 值 | `SUM(NULL, 1, 2)` = 3 |
| 全 NULL 输入 | 除 COUNT 外返回 NULL | `SUM` 在空集上返回 NULL，非 0 |
| `COUNT` 空集 | 返回 0 | `COUNT(*)` 在空表上返回 0 |

### 引擎差异

```sql
-- 常见陷阱：SUM 在空集上返回 NULL，不是 0
SELECT SUM(amount) FROM orders WHERE 1 = 0;
-- 所有引擎：返回 NULL（不是 0）

-- 安全写法
SELECT COALESCE(SUM(amount), 0) FROM orders WHERE 1 = 0;
-- 返回 0
```

```sql
-- COUNT(DISTINCT) 对 NULL 的处理
-- 标准行为：NULL 不参与 DISTINCT 计数
SELECT COUNT(DISTINCT col) FROM (VALUES (1), (2), (NULL), (NULL), (1)) t(col);
-- 所有引擎：返回 2（只有 1 和 2）
```

```sql
-- BOOL_AND / EVERY 对 NULL 的处理
-- 标准：忽略 NULL，仅基于非 NULL 值判断
-- 全 NULL 输入返回 NULL（不是 TRUE）
SELECT BOOL_AND(col) FROM (VALUES (NULL), (NULL)) t(col);
-- PostgreSQL / DuckDB：返回 NULL
```

```sql
-- STDDEV / VARIANCE 单行输入
-- 标准：STDDEV_SAMP(x) 在只有一行时返回 NULL（除以 N-1 = 0）
-- 标准：STDDEV_POP(x) 在只有一行时返回 0
SELECT STDDEV_SAMP(salary) FROM (VALUES (100)) t(salary);
-- 所有引擎：返回 NULL
SELECT STDDEV_POP(salary) FROM (VALUES (100)) t(salary);
-- 所有引擎：返回 0
```

## 关键发现

1. **基础聚合是唯一的共同点**：`COUNT`/`SUM`/`AVG`/`MIN`/`MAX` 是所有 49 个引擎都支持的唯一一组函数，但即便如此，`AVG` 的返回类型和 `SUM` 的溢出行为仍有显著差异。

2. **STDDEV/VARIANCE 的命名陷阱是最危险的跨引擎问题**：`STDDEV()` 在 MySQL/Oracle/ClickHouse 中等于 `STDDEV_POP`（总体），在 PostgreSQL/SQL Server/BigQuery 中等于 `STDDEV_SAMP`（样本）。这种差异可能导致统计结果的系统性偏差。**迁移时务必使用带后缀的完整名称。**

3. **SQL Server 的命名完全独立**：SQL Server 是唯一不遵循标准命名的主流引擎——`STDEV`/`STDEVP`/`VAR`/`VARP` 而非 `STDDEV_SAMP`/`STDDEV_POP`/`VAR_SAMP`/`VAR_POP`。

4. **字符串聚合碎片化最严重**：四种主流函数名（`STRING_AGG`、`GROUP_CONCAT`、`LISTAGG`、`ARRAY_AGG`+拼接）在不同引擎中各自为政。DuckDB 通过支持所有别名成为兼容性最好的选择。

5. **FILTER 子句的采纳率仍然很低**：仅约 16/49 个引擎支持标准的 `FILTER (WHERE ...)` 语法。ClickHouse 的 `-If` 后缀和 BigQuery 的 `COUNTIF` 是两种有趣的替代设计。

6. **回归/相关性函数的分水岭**：OLAP 引擎（PostgreSQL、Oracle、Snowflake、Trino、Vertica 等）普遍支持完整的 `REGR_*` 函数族，而 OLTP 引擎（MySQL、SQL Server、TiDB）和流式引擎（Flink、RisingWave）普遍不支持。

7. **布尔聚合的支持依赖布尔类型**：Oracle 和 SQL Server 由于缺乏原生布尔类型，不支持 `BOOL_AND`/`BOOL_OR`/`EVERY`。这是类型系统设计影响函数可用性的典型案例。

8. **MySQL 的多列 COUNT DISTINCT 几乎独一无二**：`COUNT(DISTINCT col1, col2)` 语法仅 MySQL 族（MySQL/MariaDB/TiDB/OceanBase MySQL 模式）支持，其他所有引擎需要子查询改写。

9. **百分位数函数的语法分裂**：标准的 `WITHIN GROUP (ORDER BY ...)` 语法约一半引擎支持，BigQuery/SQL Server 要求窗口函数形式，ClickHouse 使用 `quantile()` 私有语法，StarRocks/Doris 使用 `PERCENTILE_CONT(col, pct)` 两参数形式。

10. **DuckDB 是聚合函数兼容性最好的引擎**：DuckDB 几乎支持所有分类的聚合函数，且为字符串聚合提供多别名兼容（STRING_AGG/GROUP_CONCAT/LISTAGG），并支持 FILTER 子句、WITHIN GROUP、布尔聚合、位运算聚合、回归函数等全部特性。
