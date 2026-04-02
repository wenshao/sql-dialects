# 条件表达式 (Conditional Expressions)

条件表达式是 SQL 中最基础也最频繁使用的逻辑构件。从 SQL:1992 标准引入的 `CASE` 表达式，到各引擎自行扩展的 `IF()`、`IIF()`、`DECODE()`、`NVL()` 等函数，不同方言在语法、语义和优化策略上的差异远比大多数开发者想象的大。对于引擎开发者而言，理解这些差异是实现兼容层、编写查询转换器以及进行跨引擎迁移的关键前提。本文以横向对比矩阵的形式，系统梳理 49 个 SQL 方言在条件表达式方面的异同。

## SQL 标准定义

### CASE 表达式 (SQL:1992)

SQL:1992 标准（ISO/IEC 9075, Section 6.9）正式定义了 `CASE` 表达式，分为两种形式：

```sql
-- 简单 CASE (Simple CASE)
<case_expression> ::=
    CASE <operand>
        WHEN <value1> THEN <result1>
      [ WHEN <value2> THEN <result2> ... ]
      [ ELSE <default_result> ]
    END

-- 搜索 CASE (Searched CASE)
<case_expression> ::=
    CASE
        WHEN <condition1> THEN <result1>
      [ WHEN <condition2> THEN <result2> ... ]
      [ ELSE <default_result> ]
    END
```

标准的关键语义：

1. **短路求值**：从上到下依次匹配 WHEN 子句，找到第一个匹配后立即返回对应 THEN 结果，不再继续求值后续 WHEN
2. **ELSE 缺省为 NULL**：未指定 ELSE 且无 WHEN 匹配时，返回 NULL
3. **类型推导**：所有 THEN/ELSE 分支的类型必须兼容，结果类型按隐式转换规则确定
4. **可出现在任意表达式位置**：SELECT 列表、WHERE、ORDER BY、GROUP BY、HAVING 等

### NULLIF 和 COALESCE (SQL:1992)

SQL:1992 同时定义了 `NULLIF` 和 `COALESCE` 作为 CASE 的简写形式：

```sql
-- NULLIF: 等价于 CASE WHEN a = b THEN NULL ELSE a END
NULLIF(a, b)

-- COALESCE: 等价于 CASE WHEN a IS NOT NULL THEN a
--                       WHEN b IS NOT NULL THEN b ... END
COALESCE(a, b, c, ...)
```

### GREATEST / LEAST (非标准但广泛支持)

`GREATEST` 和 `LEAST` 未出现在 SQL 标准中，但从 Oracle 开始被广泛采纳。它们本质上是多值条件表达式：

```sql
GREATEST(a, b, c)  -- 返回最大值
LEAST(a, b, c)     -- 返回最小值
```

## 支持矩阵

### CASE WHEN ... THEN ... ELSE ... END

CASE 表达式是 SQL:1992 标准的核心部分，几乎所有 SQL 引擎都支持简单 CASE 和搜索 CASE 两种形式。

| 引擎 | 简单 CASE | 搜索 CASE | 嵌套 CASE | CASE 在 DDL 中 | 版本 |
|------|----------|----------|----------|---------------|------|
| PostgreSQL | 是 | 是 | 是 | CHECK/DEFAULT | 6.3+ |
| MySQL | 是 | 是 | 是 | 受限 | 3.23+ |
| MariaDB | 是 | 是 | 是 | 受限 | 5.1+ |
| SQLite | 是 | 是 | 是 | CHECK/DEFAULT | 3.0+ |
| Oracle | 是 | 是 | 是 | 虚拟列 | 8i+ |
| SQL Server | 是 | 是 | 是 (限 10 层) | 计算列 | 6.0+ |
| DB2 | 是 | 是 | 是 | 受限 | 7.1+ |
| Snowflake | 是 | 是 | 是 | -- | GA |
| BigQuery | 是 | 是 | 是 | -- | GA |
| Redshift | 是 | 是 | 是 | -- | GA |
| DuckDB | 是 | 是 | 是 | -- | 0.1+ |
| ClickHouse | 是 | 是 | 是 | -- | 18.1+ |
| Trino | 是 | 是 | 是 | -- | 早期 |
| Presto | 是 | 是 | 是 | -- | 0.69+ |
| Spark SQL | 是 | 是 | 是 | -- | 1.0+ |
| Hive | 是 | 是 | 是 | -- | 0.7+ |
| Flink SQL | 是 | 是 | 是 | -- | 1.0+ |
| Databricks | 是 | 是 | 是 | -- | GA |
| Teradata | 是 | 是 | 是 | -- | V2R5+ |
| Greenplum | 是 | 是 | 是 | CHECK/DEFAULT | 4.0+ |
| CockroachDB | 是 | 是 | 是 | 计算列 | 1.0+ |
| TiDB | 是 | 是 | 是 | 受限 | 1.0+ |
| OceanBase | 是 | 是 | 是 | 受限 | 1.0+ |
| YugabyteDB | 是 | 是 | 是 | CHECK/DEFAULT | 2.0+ |
| SingleStore | 是 | 是 | 是 | 受限 | 5.0+ |
| Vertica | 是 | 是 | 是 | -- | 7.0+ |
| Impala | 是 | 是 | 是 | -- | 1.0+ |
| StarRocks | 是 | 是 | 是 | -- | 1.0+ |
| Doris | 是 | 是 | 是 | -- | 0.12+ |
| MonetDB | 是 | 是 | 是 | -- | Jun2020+ |
| CrateDB | 是 | 是 | 是 | 生成列 | 3.0+ |
| TimescaleDB | 是 | 是 | 是 | CHECK/DEFAULT | 继承 PG |
| QuestDB | 是 | 是 | 是 | -- | 6.0+ |
| Exasol | 是 | 是 | 是 | -- | 6.0+ |
| SAP HANA | 是 | 是 | 是 | -- | 1.0+ |
| Informix | 是 | 是 | 是 | -- | 9.2+ |
| Firebird | 是 | 是 | 是 | 计算列 | 1.5+ |
| H2 | 是 | 是 | 是 | 计算列 | 1.0+ |
| HSQLDB | 是 | 是 | 是 | -- | 2.0+ |
| Derby | 是 | 是 | 是 | -- | 10.1+ |
| Amazon Athena | 是 | 是 | 是 | -- | 继承 Trino |
| Azure Synapse | 是 | 是 | 是 | -- | GA |
| Google Spanner | 是 | 是 | 是 | -- | GA |
| Materialize | 是 | 是 | 是 | -- | GA |
| RisingWave | 是 | 是 | 是 | -- | 0.1+ |
| InfluxDB (SQL) | 是 | 是 | 是 | -- | 3.0 (IOx) |
| DatabendDB | 是 | 是 | 是 | -- | 0.7+ |
| Yellowbrick | 是 | 是 | 是 | -- | GA |
| Firebolt | 是 | 是 | 是 | -- | GA |

> 结论：CASE 表达式是 SQL 方言中**兼容性最好**的条件表达式——所有列出的 49 个引擎均完整支持简单 CASE 和搜索 CASE。

### IF(condition, true_val, false_val) 函数

IF 函数是非标准但常用的三元条件函数。它并非 SQL 标准的一部分，源自 MySQL 的早期扩展。

| 引擎 | 支持 | 语法 | 备注 | 版本 |
|------|------|------|------|------|
| PostgreSQL | -- | -- | 不支持函数形式，仅 PL/pgSQL 中有 IF 语句 | -- |
| MySQL | 是 | `IF(cond, a, b)` | 表达式级别，非控制流 | 3.23+ |
| MariaDB | 是 | `IF(cond, a, b)` | 同 MySQL | 5.1+ |
| SQLite | -- | -- | 仅支持 IIF | 3.32+ |
| Oracle | -- | -- | 不支持；PL/SQL 中有 IF 语句 | -- |
| SQL Server | -- | -- | 不支持 IF 函数；T-SQL 中有 IF 语句和 IIF 函数 | -- |
| DB2 | -- | -- | 不支持 | -- |
| Snowflake | 是 | `IF(cond, a, b)` | 同 MySQL 语法 | GA |
| BigQuery | 是 | `IF(cond, a, b)` | 原生支持 | GA |
| Redshift | -- | -- | 不支持 | -- |
| DuckDB | 是 | `IF(cond, a, b)` | 兼容 MySQL | 0.3+ |
| ClickHouse | 是 | `if(cond, a, b)` | 同时支持 `multiIf()` | 18.1+ |
| Trino | 是 | `IF(cond, a, b)` | 也支持 `IF(cond, a)` (省略 false 返回 NULL) | 早期 |
| Presto | 是 | `IF(cond, a, b)` | 同 Trino | 0.69+ |
| Spark SQL | 是 | `IF(cond, a, b)` | Hive 兼容 | 1.0+ |
| Hive | 是 | `IF(cond, a, b)` | 原生支持 | 0.7+ |
| Flink SQL | 是 | `IF(cond, a, b)` | 同时支持 `IF(cond, a)` | 1.12+ |
| Databricks | 是 | `IF(cond, a, b)` | 同 Spark SQL | GA |
| Teradata | -- | -- | 不支持 | -- |
| Greenplum | -- | -- | 不支持；继承 PG | -- |
| CockroachDB | 是 | `IF(cond, a, b)` | 扩展函数 | 2.0+ |
| TiDB | 是 | `IF(cond, a, b)` | MySQL 兼容 | 1.0+ |
| OceanBase | 是 | `IF(cond, a, b)` | MySQL 模式支持 | 1.0+ |
| YugabyteDB | -- | -- | 不支持；继承 PG | -- |
| SingleStore | 是 | `IF(cond, a, b)` | MySQL 兼容 | 5.0+ |
| Vertica | -- | -- | 不支持 | -- |
| Impala | 是 | `IF(cond, a, b)` | Hive 兼容 | 1.0+ |
| StarRocks | 是 | `IF(cond, a, b)` | MySQL 兼容 | 1.0+ |
| Doris | 是 | `IF(cond, a, b)` | MySQL 兼容 | 0.12+ |
| MonetDB | 是 | `IF(cond, a, b)` | 别名 `ifthenelse()` | Jun2020+ |
| CrateDB | 是 | `IF(cond, a, b)` | 扩展函数 | 4.0+ |
| TimescaleDB | -- | -- | 不支持；继承 PG | -- |
| QuestDB | -- | -- | 不支持 | -- |
| Exasol | -- | -- | 不支持 | -- |
| SAP HANA | 是 | `IF(cond, a, b)` | SQL 表达式级别 | 2.0+ |
| Informix | -- | -- | 不支持 | -- |
| Firebird | -- | -- | 不支持 | -- |
| H2 | -- | -- | 不支持 | -- |
| HSQLDB | -- | -- | 不支持 | -- |
| Derby | -- | -- | 不支持 | -- |
| Amazon Athena | 是 | `IF(cond, a, b)` | 继承 Trino | GA |
| Azure Synapse | -- | -- | 不支持 IF 函数；支持 IIF | -- |
| Google Spanner | 是 | `IF(cond, a, b)` | 原生支持 | GA |
| Materialize | -- | -- | 不支持；继承 PG | -- |
| RisingWave | -- | -- | 不支持；继承 PG | -- |
| InfluxDB (SQL) | -- | -- | 不支持 | -- |
| DatabendDB | 是 | `IF(cond, a, b)` | MySQL 兼容 | 0.7+ |
| Yellowbrick | -- | -- | 不支持 | -- |
| Firebolt | 是 | `IF(cond, a, b)` | 原生支持 | GA |

> 统计：约 27 个引擎支持 IF 函数，约 22 个不支持。支持的引擎主要是 MySQL 兼容系和大数据/分析引擎。

### IIF(condition, true_val, false_val) 函数

IIF 源自 Microsoft Access 和 Visual Basic，后被 SQL Server 2012 正式引入。

| 引擎 | 支持 | 备注 | 版本 |
|------|------|------|------|
| PostgreSQL | -- | 不支持 | -- |
| MySQL | -- | 不支持（使用 IF） | -- |
| MariaDB | -- | 不支持（使用 IF） | -- |
| SQLite | 是 | 作为内建函数引入 | 3.32+ (2021) |
| Oracle | -- | 不支持 | -- |
| SQL Server | 是 | 等价于 CASE WHEN | 2012+ |
| DB2 | -- | 不支持 | -- |
| Snowflake | -- | 不支持（使用 IF） | -- |
| BigQuery | -- | 不支持（使用 IF） | -- |
| Redshift | -- | 不支持 | -- |
| DuckDB | 是 | 兼容 SQLite/SQL Server | 0.5+ |
| ClickHouse | -- | 不支持（使用 if） | -- |
| Trino | -- | 不支持（使用 IF） | -- |
| Presto | -- | 不支持（使用 IF） | -- |
| Spark SQL | -- | 不支持（使用 IF） | -- |
| Hive | -- | 不支持（使用 IF） | -- |
| Flink SQL | -- | 不支持（使用 IF） | -- |
| Databricks | -- | 不支持（使用 IF） | -- |
| Teradata | -- | 不支持 | -- |
| Greenplum | -- | 不支持 | -- |
| CockroachDB | -- | 不支持 | -- |
| TiDB | -- | 不支持（使用 IF） | -- |
| OceanBase | -- | 不支持 | -- |
| YugabyteDB | -- | 不支持 | -- |
| SingleStore | -- | 不支持（使用 IF） | -- |
| Vertica | -- | 不支持 | -- |
| Impala | -- | 不支持（使用 IF） | -- |
| StarRocks | -- | 不支持（使用 IF） | -- |
| Doris | -- | 不支持（使用 IF） | -- |
| MonetDB | -- | 不支持 | -- |
| CrateDB | -- | 不支持 | -- |
| TimescaleDB | -- | 不支持 | -- |
| QuestDB | -- | 不支持 | -- |
| Exasol | -- | 不支持 | -- |
| SAP HANA | -- | 不支持 | -- |
| Informix | -- | 不支持 | -- |
| Firebird | 是 | 作为内建函数 | 3.0+ |
| H2 | -- | 不支持 | -- |
| HSQLDB | -- | 不支持 | -- |
| Derby | -- | 不支持 | -- |
| Amazon Athena | -- | 不支持（使用 IF） | -- |
| Azure Synapse | 是 | 继承 SQL Server | GA |
| Google Spanner | -- | 不支持（使用 IF） | -- |
| Materialize | -- | 不支持 | -- |
| RisingWave | -- | 不支持 | -- |
| InfluxDB (SQL) | -- | 不支持 | -- |
| DatabendDB | -- | 不支持（使用 IF） | -- |
| Yellowbrick | -- | 不支持 | -- |
| Firebolt | -- | 不支持（使用 IF） | -- |

> 统计：仅 5 个引擎支持 IIF——SQL Server、Azure Synapse、SQLite、DuckDB、Firebird。IIF 的覆盖面远小于 IF 函数。

### DECODE(expr, search, result, ..., default) — Oracle 风格

DECODE 是 Oracle 在 SQL 标准 CASE 出现之前的条件表达式。其语义为：依次比较 expr 与每个 search 值，匹配则返回对应 result，均不匹配则返回 default（未指定则为 NULL）。

| 引擎 | 支持 | NULL 匹配 | 备注 | 版本 |
|------|------|----------|------|------|
| PostgreSQL | -- | -- | 不支持（可用扩展 orafce） | -- |
| MySQL | -- | -- | 不支持 | -- |
| MariaDB | -- | -- | 不支持 | -- |
| SQLite | -- | -- | 不支持 | -- |
| Oracle | 是 | 是 (NULL=NULL) | 原创者；DECODE 视 NULL 为相等 | 6.0+ |
| SQL Server | -- | -- | 不支持 | -- |
| DB2 | 是 | 否 | Oracle 兼容模式 | 9.7+ |
| Snowflake | 是 | 是 | Oracle 兼容 | GA |
| BigQuery | -- | -- | 不支持 | -- |
| Redshift | 是 | 是 | Oracle 兼容 | GA |
| DuckDB | -- | -- | 不支持 | -- |
| ClickHouse | -- | -- | 不支持（有 transform 函数） | -- |
| Trino | -- | -- | 不支持 | -- |
| Presto | -- | -- | 不支持 | -- |
| Spark SQL | 是 | 是 | Oracle 兼容 | 2.0+ |
| Hive | -- | -- | 不支持 | -- |
| Flink SQL | -- | -- | 不支持 | -- |
| Databricks | 是 | 是 | 同 Spark SQL | GA |
| Teradata | 是 | 否 | Oracle 兼容模式 | 14.0+ |
| Greenplum | -- | -- | 不支持（可用 orafce） | -- |
| CockroachDB | -- | -- | 不支持 | -- |
| TiDB | -- | -- | 不支持 | -- |
| OceanBase | 是 | 是 | Oracle 模式支持 | 1.0+ |
| YugabyteDB | -- | -- | 不支持 | -- |
| SingleStore | -- | -- | 不支持 | -- |
| Vertica | 是 | 是 | Oracle 兼容 | 7.0+ |
| Impala | 是 | 否 | 与 Oracle 行为不完全一致 | 1.0+ |
| StarRocks | -- | -- | 不支持 | -- |
| Doris | -- | -- | 不支持 | -- |
| MonetDB | -- | -- | 不支持 | -- |
| CrateDB | -- | -- | 不支持 | -- |
| TimescaleDB | -- | -- | 不支持 | -- |
| QuestDB | -- | -- | 不支持 | -- |
| Exasol | 是 | 是 | Oracle 兼容 | 6.0+ |
| SAP HANA | 是 | 是 | Oracle 兼容 | 1.0+ |
| Informix | 是 | 否 | 有限支持 | 12.10+ |
| Firebird | -- | -- | 不支持 (DECODE 仅为 PSQL 过程语言内部函数，非 SQL 表达式) | -- |
| H2 | 是 | 否 | Oracle 兼容模式 | 1.0+ |
| HSQLDB | 是 | 否 | Oracle 兼容模式 | 2.3+ |
| Derby | -- | -- | 不支持 | -- |
| Amazon Athena | -- | -- | 不支持 | -- |
| Azure Synapse | -- | -- | 不支持 | -- |
| Google Spanner | -- | -- | 不支持 | -- |
| Materialize | -- | -- | 不支持 | -- |
| RisingWave | -- | -- | 不支持 | -- |
| InfluxDB (SQL) | -- | -- | 不支持 | -- |
| DatabendDB | -- | -- | 不支持 | -- |
| Yellowbrick | -- | -- | 不支持 | -- |
| Firebolt | -- | -- | 不支持 | -- |

> 注意：Oracle DECODE 的一个重要特殊行为是**视 NULL 为相等**（即 `DECODE(NULL, NULL, 'match')` 返回 `'match'`），这与标准 CASE（`NULL = NULL` 返回 UNKNOWN）不同。Snowflake、Redshift、Spark SQL 等保持了此行为以兼容 Oracle 迁移。

### NULLIF(a, b)

NULLIF 是 SQL:1992 标准定义的条件表达式，语义为：若 `a = b` 则返回 NULL，否则返回 a。常用于避免除零错误。

| 引擎 | 支持 | 版本 |
|------|------|------|
| PostgreSQL | 是 | 7.0+ |
| MySQL | 是 | 4.0+ |
| MariaDB | 是 | 5.1+ |
| SQLite | 是 | 3.0+ |
| Oracle | 是 | 9i+ |
| SQL Server | 是 | 2000+ |
| DB2 | 是 | 7.1+ |
| Snowflake | 是 | GA |
| BigQuery | 是 | GA |
| Redshift | 是 | GA |
| DuckDB | 是 | 0.1+ |
| ClickHouse | 是 | 18.1+ |
| Trino | 是 | 早期 |
| Presto | 是 | 0.69+ |
| Spark SQL | 是 | 1.0+ |
| Hive | 是 | 2.0+ |
| Flink SQL | 是 | 1.12+ |
| Databricks | 是 | GA |
| Teradata | 是 | V2R5+ |
| Greenplum | 是 | 4.0+ |
| CockroachDB | 是 | 1.0+ |
| TiDB | 是 | 1.0+ |
| OceanBase | 是 | 1.0+ |
| YugabyteDB | 是 | 2.0+ |
| SingleStore | 是 | 5.0+ |
| Vertica | 是 | 7.0+ |
| Impala | 是 | 1.0+ |
| StarRocks | 是 | 1.0+ |
| Doris | 是 | 0.12+ |
| MonetDB | 是 | Jun2020+ |
| CrateDB | 是 | 3.0+ |
| TimescaleDB | 是 | 继承 PG |
| QuestDB | 是 | 6.0+ |
| Exasol | 是 | 6.0+ |
| SAP HANA | 是 | 1.0+ |
| Informix | 是 | 9.2+ |
| Firebird | 是 | 1.5+ |
| H2 | 是 | 1.0+ |
| HSQLDB | 是 | 2.0+ |
| Derby | 是 | 10.1+ |
| Amazon Athena | 是 | 继承 Trino |
| Azure Synapse | 是 | GA |
| Google Spanner | 是 | GA |
| Materialize | 是 | GA |
| RisingWave | 是 | 0.1+ |
| InfluxDB (SQL) | 是 | 3.0 (IOx) |
| DatabendDB | 是 | 0.7+ |
| Yellowbrick | 是 | GA |
| Firebolt | 是 | GA |

> 结论：NULLIF 的兼容性与 CASE 相当——全部 49 个引擎均支持。

### COALESCE(a, b, c, ...)

COALESCE 是 SQL:1992 标准定义的函数，返回参数列表中第一个非 NULL 值。

| 引擎 | 支持 | 参数数量上限 | 备注 | 版本 |
|------|------|------------|------|------|
| PostgreSQL | 是 | 无限制 | 标准实现 | 7.0+ |
| MySQL | 是 | 无限制 | 标准实现 | 4.0+ |
| MariaDB | 是 | 无限制 | 标准实现 | 5.1+ |
| SQLite | 是 | 无限制 | 标准实现 | 3.0+ |
| Oracle | 是 | 无限制 | 标准实现 | 9i+ |
| SQL Server | 是 | 无限制 | 标准实现 | 2000+ |
| DB2 | 是 | 无限制 | 标准实现 | 7.1+ |
| Snowflake | 是 | 无限制 | 标准实现 | GA |
| BigQuery | 是 | 无限制 | 标准实现 | GA |
| Redshift | 是 | 无限制 | 标准实现 | GA |
| DuckDB | 是 | 无限制 | 标准实现 | 0.1+ |
| ClickHouse | 是 | 无限制 | 使用 `coalesce()` 小写 | 18.1+ |
| Trino | 是 | 无限制 | 标准实现 | 早期 |
| Presto | 是 | 无限制 | 标准实现 | 0.69+ |
| Spark SQL | 是 | 无限制 | 标准实现 | 1.0+ |
| Hive | 是 | 无限制 | 标准实现 | 0.7+ |
| Flink SQL | 是 | 无限制 | 标准实现 | 1.0+ |
| Databricks | 是 | 无限制 | 标准实现 | GA |
| Teradata | 是 | 无限制 | 标准实现 | V2R5+ |
| Greenplum | 是 | 无限制 | 标准实现 | 4.0+ |
| CockroachDB | 是 | 无限制 | 标准实现 | 1.0+ |
| TiDB | 是 | 无限制 | 标准实现 | 1.0+ |
| OceanBase | 是 | 无限制 | 标准实现 | 1.0+ |
| YugabyteDB | 是 | 无限制 | 标准实现 | 2.0+ |
| SingleStore | 是 | 无限制 | 标准实现 | 5.0+ |
| Vertica | 是 | 无限制 | 标准实现 | 7.0+ |
| Impala | 是 | 无限制 | 标准实现 | 1.0+ |
| StarRocks | 是 | 无限制 | 标准实现 | 1.0+ |
| Doris | 是 | 无限制 | 标准实现 | 0.12+ |
| MonetDB | 是 | 无限制 | 标准实现 | Jun2020+ |
| CrateDB | 是 | 无限制 | 标准实现 | 3.0+ |
| TimescaleDB | 是 | 无限制 | 继承 PG | 继承 PG |
| QuestDB | 是 | 无限制 | 标准实现 | 6.0+ |
| Exasol | 是 | 无限制 | 标准实现 | 6.0+ |
| SAP HANA | 是 | 无限制 | 标准实现 | 1.0+ |
| Informix | 是 | 无限制 | 标准实现 | 9.2+ |
| Firebird | 是 | 无限制 | 标准实现 | 1.5+ |
| H2 | 是 | 无限制 | 标准实现 | 1.0+ |
| HSQLDB | 是 | 无限制 | 标准实现 | 2.0+ |
| Derby | 是 | 无限制 | 标准实现 | 10.1+ |
| Amazon Athena | 是 | 无限制 | 继承 Trino | GA |
| Azure Synapse | 是 | 无限制 | 标准实现 | GA |
| Google Spanner | 是 | 无限制 | 标准实现 | GA |
| Materialize | 是 | 无限制 | 标准实现 | GA |
| RisingWave | 是 | 无限制 | 标准实现 | 0.1+ |
| InfluxDB (SQL) | 是 | 无限制 | 标准实现 | 3.0 (IOx) |
| DatabendDB | 是 | 无限制 | 标准实现 | 0.7+ |
| Yellowbrick | 是 | 无限制 | 标准实现 | GA |
| Firebolt | 是 | 无限制 | 标准实现 | GA |

> 结论：COALESCE 同样是**全引擎支持**的标准函数。

### NVL / NVL2 — Oracle 风格

NVL 是 Oracle 对 COALESCE 的两参数简化版本。NVL2 增加了一个"非 NULL 时的替代值"参数。

```sql
NVL(expr, default_val)              -- 等价于 COALESCE(expr, default_val)
NVL2(expr, val_if_not_null, val_if_null) -- 无标准等价
```

| 引擎 | NVL | NVL2 | 备注 | 版本 |
|------|-----|------|------|------|
| PostgreSQL | -- | -- | 不支持（可用 orafce 扩展） | -- |
| MySQL | -- | -- | 不支持（使用 IFNULL） | -- |
| MariaDB | -- | -- | 不支持（使用 IFNULL） | -- |
| SQLite | -- | -- | 不支持（使用 IFNULL） | -- |
| Oracle | 是 | 是 | 原创者 | 6.0+ |
| SQL Server | -- | -- | 不支持（使用 ISNULL） | -- |
| DB2 | 是 | 是 | Oracle 兼容模式 | 9.7+ |
| Snowflake | 是 | 是 | Oracle 兼容 | GA |
| BigQuery | -- | -- | 不支持（使用 IFNULL） | -- |
| Redshift | 是 | 是 | Oracle 兼容 | GA |
| DuckDB | -- | -- | 不支持 | -- |
| ClickHouse | -- | -- | 不支持 | -- |
| Trino | -- | -- | 不支持 | -- |
| Presto | -- | -- | 不支持 | -- |
| Spark SQL | 是 | 是 | Oracle 兼容 | 1.0+ |
| Hive | 是 | -- | 仅 NVL | 0.11+ |
| Flink SQL | -- | -- | 不支持 | -- |
| Databricks | 是 | 是 | 同 Spark SQL | GA |
| Teradata | 是 | -- | 仅 NVL | V2R5+ |
| Greenplum | -- | -- | 不支持（可用 orafce） | -- |
| CockroachDB | -- | -- | 不支持 | -- |
| TiDB | -- | -- | 不支持（使用 IFNULL） | -- |
| OceanBase | 是 | 是 | Oracle 模式支持 | 1.0+ |
| YugabyteDB | -- | -- | 不支持 | -- |
| SingleStore | -- | -- | 不支持（使用 IFNULL） | -- |
| Vertica | 是 | 是 | Oracle 兼容 | 7.0+ |
| Impala | 是 | 是 | Oracle 兼容 | 1.0+ |
| StarRocks | 是 | 是 | Oracle 兼容 | 2.0+ |
| Doris | 是 | 是 | Oracle 兼容 | 0.14+ |
| MonetDB | -- | -- | 不支持 | -- |
| CrateDB | -- | -- | 不支持 | -- |
| TimescaleDB | -- | -- | 不支持 | -- |
| QuestDB | -- | -- | 不支持 | -- |
| Exasol | 是 | 是 | Oracle 兼容 | 6.0+ |
| SAP HANA | 是 | 是 | Oracle 兼容 | 1.0+ |
| Informix | 是 | -- | 仅 NVL | 12.10+ |
| Firebird | -- | -- | 不支持 | -- |
| H2 | 是 | 是 | Oracle 兼容模式 | 1.0+ |
| HSQLDB | 是 | 是 | Oracle 兼容模式 | 2.3+ |
| Derby | -- | -- | 不支持 | -- |
| Amazon Athena | -- | -- | 不支持 | -- |
| Azure Synapse | -- | -- | 不支持（使用 ISNULL） | -- |
| Google Spanner | -- | -- | 不支持（使用 IFNULL） | -- |
| Materialize | -- | -- | 不支持 | -- |
| RisingWave | -- | -- | 不支持 | -- |
| InfluxDB (SQL) | -- | -- | 不支持 | -- |
| DatabendDB | -- | -- | 不支持 | -- |
| Yellowbrick | -- | -- | 不支持 | -- |
| Firebolt | -- | -- | 不支持 | -- |

> 统计：约 20 个引擎支持 NVL，约 15 个同时支持 NVL2。支持的引擎主要是 Oracle 兼容系。

### IFNULL / ISNULL 函数

IFNULL 和 ISNULL 都是 COALESCE 的两参数简化版本，但来源不同：IFNULL 源自 MySQL，ISNULL 源自 SQL Server。

| 引擎 | IFNULL | ISNULL (替换型) | 备注 | 版本 |
|------|--------|----------------|------|------|
| PostgreSQL | -- | -- | 不支持（ISNULL 仅为判断函数） | -- |
| MySQL | 是 | -- | IFNULL 原创 | 3.23+ |
| MariaDB | 是 | -- | 同 MySQL | 5.1+ |
| SQLite | 是 | -- | 同 MySQL 语法 | 3.0+ |
| Oracle | -- | -- | 不支持（使用 NVL） | -- |
| SQL Server | -- | 是 | `ISNULL(expr, replacement)` | 6.0+ |
| DB2 | -- | -- | 不支持（使用 NVL 或 COALESCE） | -- |
| Snowflake | 是 | -- | MySQL 兼容 | GA |
| BigQuery | 是 | -- | 原生支持 | GA |
| Redshift | -- | -- | 不支持（使用 NVL 或 COALESCE） | -- |
| DuckDB | 是 | -- | 多兼容 | 0.1+ |
| ClickHouse | 是 | -- | 函数名 `ifNull` | 18.1+ |
| Trino | -- | -- | 不支持（使用 COALESCE） | -- |
| Presto | -- | -- | 不支持（使用 COALESCE） | -- |
| Spark SQL | -- | -- | 不支持（使用 NVL 或 COALESCE） | -- |
| Hive | -- | -- | 不支持（使用 NVL 或 COALESCE） | -- |
| Flink SQL | 是 | -- | 内建函数 | 1.12+ |
| Databricks | -- | -- | 不支持（使用 NVL 或 COALESCE） | -- |
| Teradata | -- | -- | 不支持 | -- |
| Greenplum | -- | -- | 不支持 | -- |
| CockroachDB | 是 | -- | MySQL 兼容 | 2.0+ |
| TiDB | 是 | -- | MySQL 兼容 | 1.0+ |
| OceanBase | 是 | -- | MySQL 模式支持 | 1.0+ |
| YugabyteDB | -- | -- | 不支持 | -- |
| SingleStore | 是 | -- | MySQL 兼容 | 5.0+ |
| Vertica | -- | -- | 不支持 | -- |
| Impala | -- | -- | 不支持 | -- |
| StarRocks | 是 | -- | MySQL 兼容 | 1.0+ |
| Doris | 是 | -- | MySQL 兼容 | 0.12+ |
| MonetDB | 是 | -- | 内建函数 | Jun2020+ |
| CrateDB | 是 | -- | 内建函数 | 3.0+ |
| TimescaleDB | -- | -- | 不支持；继承 PG | -- |
| QuestDB | -- | -- | 不支持 | -- |
| Exasol | -- | -- | 不支持 | -- |
| SAP HANA | 是 | -- | 内建函数 | 1.0+ |
| Informix | -- | -- | 不支持 | -- |
| Firebird | -- | -- | 不支持 | -- |
| H2 | 是 | -- | MySQL 兼容 | 1.0+ |
| HSQLDB | 是 | -- | MySQL 兼容 | 2.0+ |
| Derby | -- | -- | 不支持 | -- |
| Amazon Athena | -- | -- | 不支持 | -- |
| Azure Synapse | -- | 是 | 继承 SQL Server | GA |
| Google Spanner | 是 | -- | 原生支持 | GA |
| Materialize | -- | -- | 不支持 | -- |
| RisingWave | -- | -- | 不支持 | -- |
| InfluxDB (SQL) | -- | -- | 不支持 | -- |
| DatabendDB | 是 | -- | MySQL 兼容 | 0.7+ |
| Yellowbrick | -- | -- | 不支持 | -- |
| Firebolt | 是 | -- | 内建函数 | GA |

> 注意 ISNULL 在不同引擎中的歧义：SQL Server 的 `ISNULL(expr, replacement)` 是**替换函数**，而 PostgreSQL/MySQL 的 `ISNULL(expr)` 是**判断函数**（返回布尔值）。迁移时必须注意这个语义差异。

### GREATEST / LEAST

GREATEST 和 LEAST 返回参数列表中的最大值/最小值。非 SQL 标准，但被广泛支持。关键差异在于含 NULL 参数时的行为。

| 引擎 | 支持 | NULL 行为 | 备注 | 版本 |
|------|------|----------|------|------|
| PostgreSQL | 是 | 跳过 NULL | 所有参数为 NULL 时返回 NULL | 8.1+ |
| MySQL | 是 | 含 NULL 返回 NULL | 任一参数为 NULL 则结果为 NULL | 3.23+ |
| MariaDB | 是 | 含 NULL 返回 NULL | 同 MySQL | 5.1+ |
| SQLite | 是 | 跳过 NULL | 同 PostgreSQL | 3.34+ (2020) |
| Oracle | 是 | 跳过 NULL | 所有参数为 NULL 时返回 NULL | 8i+ |
| SQL Server | 是 | 含 NULL 返回 NULL | 2022 新增；之前不支持 | 2022+ |
| DB2 | 是 | 跳过 NULL | Oracle 兼容模式 | 9.7+ |
| Snowflake | 是 | 跳过 NULL | 同 Oracle 行为 | GA |
| BigQuery | 是 | 含 NULL 返回 NULL | 需用 IGNORE NULLS 变通 | GA |
| Redshift | 是 | 跳过 NULL | 同 PostgreSQL | GA |
| DuckDB | 是 | 跳过 NULL | 同 PostgreSQL | 0.1+ |
| ClickHouse | 是 | 含 NULL 返回 NULL | `greatest()`/`least()` | 18.1+ |
| Trino | 是 | 含 NULL 返回 NULL | -- | 早期 |
| Presto | 是 | 含 NULL 返回 NULL | -- | 0.69+ |
| Spark SQL | 是 | 跳过 NULL | 同 Oracle/PostgreSQL | 1.0+ |
| Hive | 是 | 含 NULL 返回 NULL | -- | 0.7+ |
| Flink SQL | 是 | 含 NULL 返回 NULL | -- | 1.12+ |
| Databricks | 是 | 跳过 NULL | 同 Spark SQL | GA |
| Teradata | 是 | 含 NULL 返回 NULL | -- | 14.0+ |
| Greenplum | 是 | 跳过 NULL | 继承 PG | 4.0+ |
| CockroachDB | 是 | 跳过 NULL | 继承 PG | 1.0+ |
| TiDB | 是 | 含 NULL 返回 NULL | 同 MySQL | 1.0+ |
| OceanBase | 是 | 取决于模式 | MySQL 模式同 MySQL；Oracle 模式同 Oracle | 1.0+ |
| YugabyteDB | 是 | 跳过 NULL | 继承 PG | 2.0+ |
| SingleStore | 是 | 含 NULL 返回 NULL | 同 MySQL | 5.0+ |
| Vertica | 是 | 跳过 NULL | 同 Oracle | 7.0+ |
| Impala | 是 | 含 NULL 返回 NULL | -- | 1.0+ |
| StarRocks | 是 | 含 NULL 返回 NULL | 同 MySQL | 1.0+ |
| Doris | 是 | 含 NULL 返回 NULL | 同 MySQL | 0.12+ |
| MonetDB | 是 | 跳过 NULL | -- | Jun2020+ |
| CrateDB | 是 | 含 NULL 返回 NULL | -- | 3.0+ |
| TimescaleDB | 是 | 跳过 NULL | 继承 PG | 继承 PG |
| QuestDB | -- | -- | 不支持 | -- |
| Exasol | 是 | 跳过 NULL | Oracle 兼容 | 6.0+ |
| SAP HANA | 是 | 跳过 NULL | Oracle 兼容 | 1.0+ |
| Informix | -- | -- | 不支持 | -- |
| Firebird | 是 | 跳过 NULL | -- | 3.0+ |
| H2 | 是 | 含 NULL 返回 NULL | -- | 1.0+ |
| HSQLDB | 是 | 含 NULL 返回 NULL | -- | 2.0+ |
| Derby | -- | -- | 不支持 | -- |
| Amazon Athena | 是 | 含 NULL 返回 NULL | 继承 Trino | GA |
| Azure Synapse | 是 | 含 NULL 返回 NULL | 继承 SQL Server 2022 行为 | GA |
| Google Spanner | 是 | 含 NULL 返回 NULL | -- | GA |
| Materialize | 是 | 跳过 NULL | 继承 PG | GA |
| RisingWave | 是 | 跳过 NULL | 继承 PG | 0.1+ |
| InfluxDB (SQL) | -- | -- | 不支持 | -- |
| DatabendDB | 是 | 含 NULL 返回 NULL | -- | 0.7+ |
| Yellowbrick | 是 | 跳过 NULL | 继承 PG 行为 | GA |
| Firebolt | 是 | 含 NULL 返回 NULL | -- | GA |

> **关键分裂**：GREATEST/LEAST 的 NULL 行为是跨引擎迁移的最大陷阱之一。PostgreSQL/Oracle/Snowflake 系跳过 NULL，MySQL/Trino/ClickHouse 系含 NULL 则返回 NULL。OceanBase 的行为取决于运行模式。约 45 个引擎支持，但 NULL 行为分为两派。

### CHOOSE(index, val1, val2, ...) 函数

CHOOSE 函数按索引位置返回值，源自 SQL Server / Visual Basic。

| 引擎 | 支持 | 备注 | 版本 |
|------|------|------|------|
| SQL Server | 是 | `CHOOSE(index, v1, v2, ...)`, 1-based | 2012+ |
| Azure Synapse | 是 | 继承 SQL Server | GA |
| DuckDB | 是 | 兼容 SQL Server | 0.8+ |
| 其他所有引擎 | -- | 不支持 | -- |

> CHOOSE 覆盖面极窄，仅 3 个引擎支持。可用 `CASE index WHEN 1 THEN v1 WHEN 2 THEN v2 ... END` 替代。

### ClickHouse 特有条件函数

ClickHouse 提供了几个独特的条件表达式函数：

| 函数 | 语法 | 说明 |
|------|------|------|
| `multiIf` | `multiIf(cond1, val1, cond2, val2, ..., default)` | 多条件 IF，等价于链式 CASE WHEN |
| `transform` | `transform(x, [from1, from2], [to1, to2], default)` | 数组映射替换，类似 DECODE |

## 各引擎语法详解

### PostgreSQL

```sql
-- 简单 CASE
SELECT product_name,
       CASE category
           WHEN 'electronics' THEN '电子产品'
           WHEN 'clothing'    THEN '服装'
           WHEN 'food'        THEN '食品'
           ELSE '其他'
       END AS category_cn
FROM products;

-- 搜索 CASE
SELECT order_id, amount,
       CASE
           WHEN amount >= 10000 THEN '大额'
           WHEN amount >= 1000  THEN '中额'
           ELSE '小额'
       END AS order_level
FROM orders;

-- COALESCE 替代缺失值
SELECT COALESCE(nickname, first_name, email, 'anonymous') AS display_name
FROM users;

-- NULLIF 避免除零错误
SELECT revenue / NULLIF(cost, 0) AS profit_ratio
FROM financials;

-- GREATEST / LEAST (跳过 NULL)
SELECT GREATEST(score_a, score_b, score_c) AS max_score,
       LEAST(price_online, price_store)    AS best_price
FROM products;

-- PostgreSQL 无 IF 函数，可用 CASE 替代
-- 如果需要在 PL/pgSQL 中使用条件逻辑，则有 IF 语句：
-- IF condition THEN ... ELSIF ... ELSE ... END IF;
```

### MySQL / MariaDB

```sql
-- IF 函数（MySQL 特有，最常用的条件函数）
SELECT IF(score >= 60, '及格', '不及格') AS result
FROM students;

-- 嵌套 IF
SELECT IF(age >= 18,
          IF(age >= 65, '老年', '成年'),
          '未成年') AS age_group
FROM users;

-- IFNULL（两参数 COALESCE）
SELECT IFNULL(phone, '未提供') AS contact_phone
FROM customers;

-- CASE（完全标准兼容）
SELECT CASE status
           WHEN 0 THEN '待处理'
           WHEN 1 THEN '处理中'
           WHEN 2 THEN '已完成'
           ELSE '未知'
       END AS status_text
FROM orders;

-- GREATEST / LEAST（任一参数为 NULL 则返回 NULL）
SELECT GREATEST(10, 20, NULL);  -- 返回 NULL
-- 安全用法：
SELECT GREATEST(COALESCE(a, 0), COALESCE(b, 0), COALESCE(c, 0)) AS max_val
FROM scores;
```

### Oracle

```sql
-- DECODE（Oracle 经典条件表达式，支持 NULL 匹配）
SELECT DECODE(status, 'A', '活跃',
                      'I', '不活跃',
                      'D', '已删除',
                           '未知') AS status_text
FROM accounts;

-- DECODE 中 NULL 可匹配 NULL
SELECT DECODE(commission, NULL, '无佣金', '有佣金') AS comm_status
FROM employees;  -- commission 为 NULL 时返回 '无佣金'

-- 等价的 CASE 写法（注意 CASE 中 NULL 无法用 = 匹配）
SELECT CASE WHEN commission IS NULL THEN '无佣金'
            ELSE '有佣金'
       END AS comm_status
FROM employees;

-- NVL / NVL2
SELECT NVL(phone, '未提供')                              AS contact,
       NVL2(bonus, salary + bonus, salary)               AS total_pay
FROM employees;

-- GREATEST / LEAST（跳过 NULL）
SELECT GREATEST(10, 20, NULL)  AS result  -- 返回 20
FROM dual;

-- COALESCE（Oracle 9i+ 支持标准语法）
SELECT COALESCE(mobile, home_phone, office_phone, '无电话')
FROM contacts;
```

### SQL Server

```sql
-- IIF（SQL Server 2012+，来自 Access/VB）
SELECT IIF(quantity > 0, '有库存', '缺货') AS stock_status
FROM products;

-- 嵌套 IIF
SELECT IIF(score >= 90, 'A',
       IIF(score >= 80, 'B',
       IIF(score >= 70, 'C', 'D'))) AS grade
FROM exams;

-- ISNULL（两参数，替换 NULL）
SELECT ISNULL(middle_name, '') AS middle_name
FROM employees;
-- 注意：ISNULL 的返回类型取决于第一个参数的类型（与 COALESCE 不同）

-- CHOOSE（按索引选值，1-based）
SELECT CHOOSE(month_num, 'Jan','Feb','Mar','Apr','May','Jun',
                         'Jul','Aug','Sep','Oct','Nov','Dec') AS month_name
FROM sales;

-- COALESCE vs ISNULL 的类型差异
DECLARE @x VARCHAR(3) = NULL;
SELECT ISNULL(@x, 'hello');    -- 返回 'hel' (截断为 VARCHAR(3))
SELECT COALESCE(@x, 'hello');  -- 返回 'hello' (VARCHAR(5))

-- GREATEST / LEAST (SQL Server 2022+ 新增)
SELECT GREATEST(price_a, price_b, price_c) AS max_price  -- 2022+
FROM products;
```

### Snowflake

```sql
-- IF 函数
SELECT IF(temperature < 0, '冰点以下', '冰点以上') AS temp_status
FROM weather;

-- DECODE（Oracle 兼容，含 NULL 匹配）
SELECT DECODE(region, 'US', '美国',
                      'EU', '欧洲',
                      'APAC', '亚太',
                      NULL, '未指定',
                             '其他') AS region_name
FROM customers;

-- IFF（Snowflake 特有别名，等价于 IF）
SELECT IFF(is_active, '活跃', '不活跃') AS status
FROM users;

-- NVL / NVL2
SELECT NVL(email, '无邮箱') AS email,
       NVL2(phone, '有电话', '无电话') AS phone_status
FROM contacts;

-- IFNULL（MySQL 兼容）
SELECT IFNULL(department, '未分配') AS dept
FROM employees;

-- COALESCE + GREATEST/LEAST（跳过 NULL）
SELECT COALESCE(preferred_name, full_name) AS display_name,
       GREATEST(start_date, hire_date)     AS effective_date
FROM employees;
```

### BigQuery

```sql
-- IF 函数
SELECT IF(total > 1000, 'high_value', 'regular') AS customer_type
FROM orders;

-- IFNULL
SELECT IFNULL(country, 'Unknown') AS country
FROM users;

-- COALESCE
SELECT COALESCE(mobile, home_phone, work_phone) AS best_phone
FROM contacts;

-- GREATEST / LEAST（含 NULL 返回 NULL）
SELECT GREATEST(score_1, score_2, score_3) AS max_score  -- 含 NULL 则返回 NULL
FROM results;

-- 安全替代方案：使用 ARRAY + IGNORE NULLS
SELECT (SELECT MAX(x) FROM UNNEST([score_1, score_2, score_3]) AS x) AS max_score
FROM results;

-- NULLIF
SELECT revenue / NULLIF(users_count, 0) AS arpu
FROM metrics;
```

### ClickHouse

```sql
-- if 函数（小写）
SELECT if(status = 1, '活跃', '不活跃') AS status_text
FROM users;

-- multiIf（多条件分支，ClickHouse 特有）
SELECT multiIf(
    age < 13, '儿童',
    age < 18, '青少年',
    age < 60, '成年',
    '老年'
) AS age_group
FROM users;

-- transform（数组映射，类似 DECODE）
SELECT transform(status,
    ['A', 'B', 'C'],
    ['活跃', '冻结', '注销'],
    '未知'
) AS status_text
FROM accounts;

-- ifNull（注意大小写：camelCase）
SELECT ifNull(email, 'unknown@example.com') AS email
FROM users;

-- COALESCE
SELECT coalesce(phone_1, phone_2, phone_3) AS phone
FROM contacts;

-- GREATEST / LEAST（含 NULL 返回 NULL）
SELECT greatest(score_a, score_b) AS max_score
FROM results;  -- 任一为 NULL 则返回 NULL
```

### Trino / Presto / Amazon Athena

```sql
-- IF 函数（支持两参数和三参数形式）
SELECT IF(condition, true_value, false_value) FROM t;
SELECT IF(condition, true_value) FROM t;  -- false 时返回 NULL

-- CASE
SELECT CASE
           WHEN revenue > 1000000 THEN 'enterprise'
           WHEN revenue > 100000  THEN 'mid-market'
           ELSE 'smb'
       END AS segment
FROM companies;

-- COALESCE
SELECT COALESCE(address_line_2, '') AS address_line_2
FROM addresses;

-- NULLIF
SELECT NULLIF(status, 'UNKNOWN') AS clean_status
FROM records;

-- GREATEST / LEAST（含 NULL 返回 NULL）
SELECT GREATEST(val_a, val_b, val_c) AS max_val
FROM measurements;

-- 注意：Trino 不支持 DECODE、NVL、IFNULL、IIF
-- 对于 DECODE 迁移，使用 CASE 替代
```

### Spark SQL / Databricks

```sql
-- IF 函数
SELECT IF(quantity > 0, 'in_stock', 'out_of_stock') AS availability
FROM inventory;

-- CASE
SELECT CASE priority
           WHEN 1 THEN '紧急'
           WHEN 2 THEN '高'
           WHEN 3 THEN '中'
           ELSE '低'
       END AS priority_text
FROM tickets;

-- DECODE（Oracle 兼容）
SELECT DECODE(day_of_week, 1, 'Mon', 2, 'Tue', 3, 'Wed',
              4, 'Thu', 5, 'Fri', 6, 'Sat', 7, 'Sun', 'Unknown') AS day_name
FROM calendar;

-- NVL / NVL2
SELECT NVL(email, 'no-email@example.com') AS email,
       NVL2(manager_id, '有上级', '顶级管理者') AS mgr_status
FROM employees;

-- COALESCE + NULLIF
SELECT COALESCE(NULLIF(trim(name), ''), 'Anonymous') AS clean_name
FROM users;

-- GREATEST / LEAST（跳过 NULL）
SELECT GREATEST(temp_morning, temp_noon, temp_evening) AS max_temp
FROM weather;  -- NULL 被忽略
```

### Flink SQL

```sql
-- IF 函数
SELECT IF(amount > 100, 'large', 'small') AS order_size
FROM orders;

-- CASE
SELECT CASE event_type
           WHEN 'click'      THEN 1
           WHEN 'impression' THEN 0
           ELSE -1
       END AS event_value
FROM events;

-- IFNULL
SELECT IFNULL(user_name, 'anonymous') AS display_name
FROM sessions;

-- COALESCE
SELECT COALESCE(last_login, registration_date) AS reference_date
FROM users;

-- NULLIF
SELECT NULLIF(error_code, 0) AS meaningful_error
FROM logs;

-- 注意：Flink SQL 不支持 DECODE、NVL、IIF
```

### DuckDB

```sql
-- IF 函数
SELECT IF(price > 100, 'premium', 'standard') AS tier
FROM products;

-- IIF 函数（同时兼容 SQLite 和 SQL Server）
SELECT IIF(is_active, '活跃', '休眠') AS status
FROM accounts;

-- CASE
SELECT CASE
           WHEN score >= 90 THEN 'A'
           WHEN score >= 80 THEN 'B'
           WHEN score >= 70 THEN 'C'
           ELSE 'F'
       END AS grade
FROM students;

-- COALESCE / IFNULL / NULLIF（全部支持）
SELECT COALESCE(a, b, c)  AS first_non_null,
       IFNULL(x, 0)       AS x_or_zero,
       NULLIF(status, '')  AS null_if_empty
FROM data;

-- GREATEST / LEAST（跳过 NULL，同 PostgreSQL）
SELECT GREATEST(1, 2, NULL, 3)  AS result;  -- 返回 3

-- CHOOSE（SQL Server 兼容，0.8+）
SELECT CHOOSE(quarter, 'Q1', 'Q2', 'Q3', 'Q4') AS quarter_name
FROM sales;
```

### SQLite

```sql
-- IIF 函数（3.32+ 新增，唯一的内建条件函数）
SELECT IIF(age >= 18, 'adult', 'minor') AS age_class
FROM persons;

-- CASE（一直支持）
SELECT CASE
           WHEN typeof(value) = 'integer' THEN 'int'
           WHEN typeof(value) = 'real'    THEN 'float'
           WHEN typeof(value) = 'text'    THEN 'string'
           ELSE 'other'
       END AS value_type
FROM data;

-- COALESCE / NULLIF / IFNULL（全部支持）
SELECT COALESCE(nickname, username, 'user_' || id) AS display_name,
       NULLIF(trim(bio), '')                       AS bio_or_null,
       IFNULL(score, 0)                            AS score
FROM users;

-- GREATEST / LEAST（3.34+ 新增）
SELECT MAX(a, b, c) AS greatest_val,  -- SQLite 的 MAX 可作标量函数
       MIN(a, b, c) AS least_val      -- SQLite 的 MIN 可作标量函数
FROM t;
-- 注意：SQLite 同时支持 GREATEST/LEAST（3.34+）和 标量 MAX/MIN
```

### Teradata

```sql
-- CASE（标准语法）
SELECT CASE
           WHEN sales > 100000 THEN 'Top'
           WHEN sales > 50000  THEN 'Mid'
           ELSE 'Low'
       END AS sales_tier
FROM accounts;

-- DECODE（Oracle 兼容模式，14.0+）
SELECT DECODE(status_code, 1, 'Active', 2, 'Suspended', 'Unknown')
FROM users;

-- NVL（两参数 NULL 替换）
SELECT NVL(department_name, 'Unassigned') AS dept
FROM employees;

-- NULLIF / COALESCE（标准兼容）
SELECT revenue / NULLIF(headcount, 0) AS revenue_per_head,
       COALESCE(override_price, list_price, 0) AS effective_price
FROM products;

-- GREATEST / LEAST（含 NULL 返回 NULL）
SELECT GREATEST(q1_sales, q2_sales, q3_sales, q4_sales) AS max_quarterly
FROM annual_sales;
```

## CASE 表达式优化

### 短路求值 (Short-Circuit Evaluation)

所有主流 SQL 引擎都在 CASE 表达式中实现了短路求值：当某个 WHEN 条件匹配后，后续的 WHEN 分支不再求值。

```sql
-- 短路求值示例：除零不会发生
SELECT CASE
           WHEN denominator = 0 THEN 0
           WHEN numerator / denominator > 1 THEN 'high'
           ELSE 'low'
       END
FROM data;
-- 当 denominator = 0 时，第一个 WHEN 匹配，
-- 第二个 WHEN 中的 numerator / denominator 不会被执行
```

但需要注意以下引擎级别的差异：

| 引擎 | 短路求值保证 | 注意事项 |
|------|------------|---------|
| PostgreSQL | 是 | 文档明确保证 |
| MySQL | 是 | IF 函数同样短路 |
| Oracle | 是 | DECODE 也短路 |
| SQL Server | 是 | 但优化器可能重排（见下文） |
| Snowflake | 是 | 文档明确保证 |
| ClickHouse | 是 | `if`/`multiIf` 均短路 |
| Trino | 是 | IF 和 CASE 均短路 |
| Spark SQL | 是 | 代码生成保持短路语义 |
| BigQuery | 是 | 文档明确保证 |

### 索引使用

CASE 表达式在 WHERE 子句中通常**无法**利用索引。但部分引擎支持通过函数索引或计算列优化：

```sql
-- 直接在 WHERE 中使用 CASE — 通常无法使用索引
SELECT * FROM orders
WHERE CASE WHEN status = 'rush' THEN priority ELSE 0 END > 5;

-- PostgreSQL：表达式索引
CREATE INDEX idx_order_priority ON orders (
    (CASE WHEN status = 'rush' THEN priority ELSE 0 END)
);

-- SQL Server：计算列 + 索引
ALTER TABLE orders ADD rush_priority AS (
    CASE WHEN status = 'rush' THEN priority ELSE 0 END
);
CREATE INDEX idx_rush ON orders(rush_priority);

-- Oracle：函数索引
CREATE INDEX idx_order_case ON orders (
    CASE WHEN status = 'rush' THEN priority ELSE 0 END
);
```

### CASE 折叠和常量传播

成熟的查询优化器会对 CASE 表达式进行以下优化：

1. **常量折叠 (Constant Folding)**：当 CASE 的所有输入均为常量时，在编译期直接求值

```sql
-- 优化器将直接替换为 'weekday'
SELECT CASE WHEN 1 = 1 THEN 'weekday' ELSE 'weekend' END;
```

2. **CASE 消除 (CASE Elimination)**：当所有分支返回相同值时，消除 CASE

```sql
-- 优化器可能消除 CASE，直接返回 x
SELECT CASE WHEN a > 0 THEN x ELSE x END FROM t;
```

3. **CASE 到 COALESCE 转换**：部分引擎可识别 CASE WHEN x IS NOT NULL THEN x ELSE y END 模式

```sql
-- 以下两种写法，优化器可能统一为内部表示
CASE WHEN a IS NOT NULL THEN a ELSE b END
COALESCE(a, b)
```

4. **DECODE 到 CASE 转换**：支持 DECODE 的引擎内部通常将 DECODE 转换为 CASE 进行优化

| 引擎 | 常量折叠 | CASE 消除 | DECODE 转 CASE | CASE 谓词下推 |
|------|---------|----------|---------------|-------------|
| PostgreSQL | 是 | 是 | -- | 有限 |
| MySQL | 是 | 是 | -- | 有限 |
| Oracle | 是 | 是 | 是 | 是 |
| SQL Server | 是 | 是 | -- | 是 |
| Snowflake | 是 | 是 | 是 | 是 |
| ClickHouse | 是 | 是 | -- | 有限 |
| Trino | 是 | 是 | -- | 是 |
| DuckDB | 是 | 是 | -- | 是 |

### SQL Server 的优化器重排问题

SQL Server 优化器可能在特定条件下重排 CASE 表达式中的求值顺序。这在官方文档中有说明，可能导致看似安全的短路求值实际失败：

```sql
-- 可能出现问题的写法
SELECT CASE
           WHEN ISNUMERIC(col) = 1 THEN CAST(col AS INT)
           ELSE 0
       END
FROM mixed_data;
-- 优化器可能先执行 CAST，导致非数字字符串报错

-- 更安全的替代方案（SQL Server 2012+）
SELECT TRY_CAST(col AS INT)
FROM mixed_data;
```

## NULL 处理函数对比总览

以下矩阵汇总了各引擎的 NULL 处理函数支持情况：

| 引擎 | COALESCE | NVL | IFNULL | ISNULL(替换) | NVL2 |
|------|----------|-----|--------|-------------|------|
| PostgreSQL | 是 | -- | -- | -- | -- |
| MySQL | 是 | -- | 是 | -- | -- |
| MariaDB | 是 | -- | 是 | -- | -- |
| SQLite | 是 | -- | 是 | -- | -- |
| Oracle | 是 | 是 | -- | -- | 是 |
| SQL Server | 是 | -- | -- | 是 | -- |
| DB2 | 是 | 是 | -- | -- | 是 |
| Snowflake | 是 | 是 | 是 | -- | 是 |
| BigQuery | 是 | -- | 是 | -- | -- |
| Redshift | 是 | 是 | -- | -- | 是 |
| DuckDB | 是 | -- | 是 | -- | -- |
| ClickHouse | 是 | -- | 是 | -- | -- |
| Trino | 是 | -- | -- | -- | -- |
| Spark SQL | 是 | 是 | -- | -- | 是 |
| Hive | 是 | 是 | -- | -- | -- |
| Flink SQL | 是 | -- | 是 | -- | -- |
| Teradata | 是 | 是 | -- | -- | -- |
| CockroachDB | 是 | -- | 是 | -- | -- |
| TiDB | 是 | -- | 是 | -- | -- |
| OceanBase | 是 | 是 | 是 | -- | 是 |
| SingleStore | 是 | -- | 是 | -- | -- |
| Azure Synapse | 是 | -- | -- | 是 | -- |

> 选择建议：跨引擎兼容性最佳的 NULL 处理函数始终是 `COALESCE`——所有引擎均支持，且参数数量不受限。

## 条件表达式综合对比矩阵

下表汇总每个引擎对各类条件表达式的支持情况：

| 引擎 | CASE | IF | IIF | DECODE | NULLIF | COALESCE | NVL | IFNULL | GREATEST |
|------|------|----|-----|--------|--------|----------|-----|--------|----------|
| PostgreSQL | 是 | -- | -- | -- | 是 | 是 | -- | -- | 是 |
| MySQL | 是 | 是 | -- | -- | 是 | 是 | -- | 是 | 是 |
| MariaDB | 是 | 是 | -- | -- | 是 | 是 | -- | 是 | 是 |
| SQLite | 是 | -- | 是 | -- | 是 | 是 | -- | 是 | 是 |
| Oracle | 是 | -- | -- | 是 | 是 | 是 | 是 | -- | 是 |
| SQL Server | 是 | -- | 是 | -- | 是 | 是 | -- | -- | 是* |
| DB2 | 是 | -- | -- | 是 | 是 | 是 | 是 | -- | 是 |
| Snowflake | 是 | 是 | -- | 是 | 是 | 是 | 是 | 是 | 是 |
| BigQuery | 是 | 是 | -- | -- | 是 | 是 | -- | 是 | 是 |
| Redshift | 是 | -- | -- | 是 | 是 | 是 | 是 | -- | 是 |
| DuckDB | 是 | 是 | 是 | -- | 是 | 是 | -- | 是 | 是 |
| ClickHouse | 是 | 是 | -- | -- | 是 | 是 | -- | 是 | 是 |
| Trino | 是 | 是 | -- | -- | 是 | 是 | -- | -- | 是 |
| Presto | 是 | 是 | -- | -- | 是 | 是 | -- | -- | 是 |
| Spark SQL | 是 | 是 | -- | 是 | 是 | 是 | 是 | -- | 是 |
| Hive | 是 | 是 | -- | -- | 是 | 是 | 是 | -- | 是 |
| Flink SQL | 是 | 是 | -- | -- | 是 | 是 | -- | 是 | 是 |
| Databricks | 是 | 是 | -- | 是 | 是 | 是 | 是 | -- | 是 |
| Teradata | 是 | -- | -- | 是 | 是 | 是 | 是 | -- | 是 |
| Greenplum | 是 | -- | -- | -- | 是 | 是 | -- | -- | 是 |
| CockroachDB | 是 | 是 | -- | -- | 是 | 是 | -- | 是 | 是 |
| TiDB | 是 | 是 | -- | -- | 是 | 是 | -- | 是 | 是 |
| OceanBase | 是 | 是 | -- | 是 | 是 | 是 | 是 | 是 | 是 |
| YugabyteDB | 是 | -- | -- | -- | 是 | 是 | -- | -- | 是 |
| SingleStore | 是 | 是 | -- | -- | 是 | 是 | -- | 是 | 是 |
| Vertica | 是 | -- | -- | 是 | 是 | 是 | 是 | -- | 是 |
| Impala | 是 | 是 | -- | 是 | 是 | 是 | 是 | -- | 是 |
| StarRocks | 是 | 是 | -- | -- | 是 | 是 | 是 | 是 | 是 |
| Doris | 是 | 是 | -- | -- | 是 | 是 | 是 | 是 | 是 |
| MonetDB | 是 | 是 | -- | -- | 是 | 是 | -- | 是 | 是 |
| CrateDB | 是 | 是 | -- | -- | 是 | 是 | -- | 是 | 是 |
| TimescaleDB | 是 | -- | -- | -- | 是 | 是 | -- | -- | 是 |
| QuestDB | 是 | -- | -- | -- | 是 | 是 | -- | -- | -- |
| Exasol | 是 | -- | -- | 是 | 是 | 是 | 是 | -- | 是 |
| SAP HANA | 是 | 是 | -- | 是 | 是 | 是 | 是 | 是 | 是 |
| Informix | 是 | -- | -- | 是 | 是 | 是 | 是 | -- | -- |
| Firebird | 是 | -- | 是 | 是 | 是 | 是 | -- | -- | 是 |
| H2 | 是 | -- | -- | 是 | 是 | 是 | 是 | 是 | 是 |
| HSQLDB | 是 | -- | -- | 是 | 是 | 是 | 是 | 是 | 是 |
| Derby | 是 | -- | -- | -- | 是 | 是 | -- | -- | -- |
| Athena | 是 | 是 | -- | -- | 是 | 是 | -- | -- | 是 |
| Azure Synapse | 是 | -- | 是 | -- | 是 | 是 | -- | -- | 是 |
| Spanner | 是 | 是 | -- | -- | 是 | 是 | -- | 是 | 是 |
| Materialize | 是 | -- | -- | -- | 是 | 是 | -- | -- | 是 |
| RisingWave | 是 | -- | -- | -- | 是 | 是 | -- | -- | 是 |
| InfluxDB | 是 | -- | -- | -- | 是 | 是 | -- | -- | -- |
| DatabendDB | 是 | 是 | -- | -- | 是 | 是 | -- | 是 | 是 |
| Yellowbrick | 是 | -- | -- | -- | 是 | 是 | -- | -- | 是 |
| Firebolt | 是 | 是 | -- | -- | 是 | 是 | -- | 是 | 是 |

> 注：SQL Server 的 GREATEST 标记为 "是*"，表示仅 2022 及以上版本支持。

## 关键发现

### 1. 三级兼容性层次

条件表达式的跨引擎兼容性呈现清晰的三级结构：

- **全兼容**（49/49 引擎）：`CASE`、`NULLIF`、`COALESCE` — 这三个标准函数可在任何引擎中安全使用
- **广泛支持**（40-45/49）：`GREATEST`/`LEAST` — 绝大多数引擎支持，但 NULL 行为分裂为两派
- **分裂支持**（3-27/49）：`IF`、`IIF`、`DECODE`、`NVL`、`IFNULL`、`ISNULL` — 均为非标准扩展，覆盖面差异极大

### 2. GREATEST/LEAST 的 NULL 陷阱

这是跨引擎迁移中最容易被忽视的语义差异：

- **跳过 NULL 派**（约 22 个引擎）：PostgreSQL、Oracle、Snowflake、Spark SQL、DuckDB、Redshift、DB2、Vertica、SQLite、Greenplum、CockroachDB、YugabyteDB、Materialize、RisingWave、Yellowbrick、MonetDB、Exasol、SAP HANA、Firebird、TimescaleDB、Databricks
- **含 NULL 返回 NULL 派**（约 23 个引擎）：MySQL、MariaDB、BigQuery、ClickHouse、Trino、Presto、Hive、Flink SQL、Teradata、TiDB、SingleStore、Impala、StarRocks、Doris、CrateDB、H2、HSQLDB、Amazon Athena、Azure Synapse、Google Spanner、DatabendDB、Firebolt、SQL Server 2022+

安全的跨引擎写法：
```sql
-- 使用 COALESCE 包裹参数，确保行为一致
SELECT GREATEST(COALESCE(a, minimum_val), COALESCE(b, minimum_val)) AS result;
```

### 3. DECODE vs CASE 的 NULL 语义差异

Oracle 的 `DECODE` 将 `NULL = NULL` 视为 TRUE，而标准 `CASE` 遵循三值逻辑（`NULL = NULL` 为 UNKNOWN）。将 DECODE 迁移为 CASE 时，必须显式处理 NULL 分支：

```sql
-- Oracle DECODE（NULL 可匹配 NULL）
DECODE(col, NULL, 'is_null', 'not_null')

-- 正确的 CASE 等价写法
CASE WHEN col IS NULL THEN 'is_null' ELSE 'not_null' END

-- 错误的 CASE 写法（永远不会匹配 NULL）
CASE col WHEN NULL THEN 'is_null' ELSE 'not_null' END
```

### 4. SQL Server ISNULL vs COALESCE 的类型差异

SQL Server 的 `ISNULL` 和 `COALESCE` 在类型推导上行为不同：

- `ISNULL(expr, replacement)`：返回类型由**第一个参数**决定，可能截断
- `COALESCE(expr, replacement)`：返回类型取所有参数中**优先级最高**的类型

这个差异在处理不同长度的 VARCHAR 或混合数值类型时尤为显著。

### 5. 引擎家族特征

条件表达式的支持模式与引擎血缘高度相关：

| 家族 | 代表引擎 | 条件函数特征 |
|------|---------|------------|
| PostgreSQL 系 | PG, TimescaleDB, Greenplum, YugabyteDB, CockroachDB, Materialize, RisingWave | CASE + COALESCE + GREATEST（跳 NULL），无 IF/DECODE/NVL |
| MySQL 系 | MySQL, MariaDB, TiDB, SingleStore, StarRocks, Doris, OceanBase(MySQL 模式) | CASE + IF + IFNULL + GREATEST（含 NULL 返回 NULL） |
| Oracle 系 | Oracle, DB2, OceanBase(Oracle 模式), Exasol, SAP HANA | CASE + DECODE + NVL/NVL2 + GREATEST（跳 NULL） |
| 大数据系 | Trino, Presto, Spark SQL, Hive, Flink SQL, Impala, Athena | CASE + IF + COALESCE，部分支持 DECODE/NVL |
| SQL Server 系 | SQL Server, Azure Synapse | CASE + IIF + ISNULL + CHOOSE |

### 6. 迁移建议

- **最安全的跨引擎条件表达式**：`CASE WHEN ... THEN ... ELSE ... END`
- **最安全的 NULL 替换函数**：`COALESCE()`
- **避免在跨引擎代码中使用**：`IF()`、`IIF()`、`DECODE()`、`NVL()`、`IFNULL()`、`ISNULL()`
- **GREATEST/LEAST 跨引擎使用时**：始终用 `COALESCE` 预处理 NULL 参数

## 参考资料

- SQL:1992 标准: ISO/IEC 9075, Section 6.9 (case expression), Section 6.6 (NULLIF, COALESCE)
- PostgreSQL: [Conditional Expressions](https://www.postgresql.org/docs/current/functions-conditional.html)
- MySQL: [Control Flow Functions](https://dev.mysql.com/doc/refman/8.0/en/flow-control-functions.html)
- Oracle: [CASE / DECODE](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CASE-Expressions.html)
- SQL Server: [IIF / CHOOSE / COALESCE / ISNULL](https://learn.microsoft.com/en-us/sql/t-sql/functions/logical-functions-iif-transact-sql)
- Snowflake: [Conditional Expression Functions](https://docs.snowflake.com/en/sql-reference/functions/iff)
- BigQuery: [Conditional Expressions](https://cloud.google.com/bigquery/docs/reference/standard-sql/conditional_expressions)
- ClickHouse: [Conditional Functions](https://clickhouse.com/docs/en/sql-reference/functions/conditional-functions)
- Trino: [Conditional Expressions](https://trino.io/docs/current/functions/conditional.html)
- Spark SQL: [Built-in Functions](https://spark.apache.org/docs/latest/api/sql/#conditional-functions)
- DuckDB: [Functions - Conditional](https://duckdb.org/docs/sql/functions/conditional)
- Flink SQL: [System Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/)
- SQLite: [Core Functions](https://www.sqlite.org/lang_corefunc.html)
- Teradata: [DECODE Function](https://docs.teradata.com/r/Teradata-Database-SQL-Functions-Operators-Expressions-and-Predicates)
