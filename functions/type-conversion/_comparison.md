# 类型转换 (Type Conversion) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| CAST(x AS type) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CONVERT(x, type) | ✅ MySQL 语法 | ❌ | ❌ | ❌ | ✅ SQL Server 语法 | ✅ | ❌ | ❌ | ✅ |
| :: 操作符 | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| TRY_CAST | ❌ | ❌ | ❌ | ❌ | ✅ 2012+ | ❌ | ❌ | ❌ | ❌ |
| TRY_CONVERT | ❌ | ❌ | ❌ | ❌ | ✅ 2012+ | ❌ | ❌ | ❌ | ❌ |
| SAFE_CAST | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| TO_CHAR | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| TO_NUMBER | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| TO_DATE | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| TO_TIMESTAMP | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| FORMAT | ❌ | ❌ | ❌ | ❌ | ✅ 2012+ | ❌ | ❌ | ❌ | ❌ |
| STR_TO_DATE | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| DATE_FORMAT | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| CONVERT(USING charset) | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| 隐式类型转换 | ✅ 宽松 | ⚠️ 较严格 | ✅ 非常宽松 | ⚠️ 中等 | ✅ 宽松 | ✅ 宽松 | ⚠️ 较严格 | ⚠️ 较严格 | ⚠️ 较严格 |
| CAST 到 JSON | ✅ 8.0+ | ✅ ::json | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| CAST 到 BOOLEAN | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ |
| 二进制转换 | ✅ BINARY | ✅ ::bytea | ✅ CAST BLOB | ✅ UTL_RAW | ✅ VARBINARY | ✅ BINARY | ✅ | ✅ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CAST | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| SAFE_CAST | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| TRY_CAST | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ |
| :: 操作符 | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| TO_CHAR / TO_NUMBER | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| toXxx 函数 | ❌ | ❌ | ❌ | ❌ | ✅ toInt32 等 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 隐式转换 | ⚠️ 较严格 | ✅ 宽松 | ✅ 宽松 | ✅ 宽松 | ⚠️ 较严格 | ✅ 宽松 | ⚠️ 较严格 | ⚠️ 较严格 | ✅ 宽松 | ⚠️ 较严格 | ✅ 宽松 | ⚠️ 较严格 |
| FORMAT_DATE/TIME | ✅ | ✅ | ❌ | ❌ | ✅ formatDateTime | ❌ | ✅ format_datetime | ❌ | ❌ | ✅ strftime | ❌ | ✅ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| CAST | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| :: 操作符 | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |
| TRY_CAST | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| TO_CHAR / TO_NUMBER | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |
| FORMAT | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| CONVERT | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| CAST | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| :: 操作符 | ❌ | ❌ | ✅ | ❌ | ✅ | ⚠️ PG 模式 | ✅ | ❌ | ❌ | ✅ |
| CONVERT | ✅ MySQL 语法 | ✅ MySQL 模式 | ❌ | ❌ | ❌ | ✅ MySQL 模式 | ❌ | ✅ | ❌ | ❌ |
| TO_CHAR / TO_NUMBER | ❌ | ⚠️ Oracle 模式 | ❌ | ❌ | ✅ | ⚠️ PG 模式 | ✅ | ❌ | ✅ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| CAST | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| :: 操作符 | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |
| TO_CHAR / TO_NUMBER | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |

## 关键差异

- **CAST** 是 SQL 标准语法，所有数据库都支持
- **PostgreSQL** 的 :: 操作符最简洁（如 '42'::integer），被多个 PG 兼容数据库继承
- **MySQL** 的 CONVERT 语法独特：CONVERT(expr, type) 和 CONVERT(expr USING charset)
- **SQL Server** 的 CONVERT 语法不同：CONVERT(type, expr [, style])，style 参数控制日期格式
- **Oracle** 使用 TO_CHAR/TO_NUMBER/TO_DATE 系列函数，格式字符串语法独特
- **SQL Server 2012+** 引入 TRY_CAST/TRY_CONVERT（转换失败返回 NULL）
- **BigQuery** 使用 SAFE_CAST（等价于 TRY_CAST）
- **ClickHouse** 使用独有的 toInt32/toFloat64/toString 等类型化函数
- **SQLite** 类型系统最灵活（动态类型），隐式转换非常宽松
- **PostgreSQL** 类型转换最严格，通常需要显式 CAST 或 ::
