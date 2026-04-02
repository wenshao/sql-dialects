# 数据类型映射 (Data Type Mapping)

数据类型是 SQL 引擎的基石——一个 `INT` 在 MySQL 中是 4 字节有符号整数，在 Oracle 中是 NUMBER(38) 的别名，在 SQLite 中只是一个"亲和性提示"。跨数据库迁移、联邦查询、ETL 管道中，类型映射差异是最常见的沉默错误来源。本文系统梳理 45+ SQL 方言的核心数据类型映射关系，为引擎开发者提供可验证的对照参考。

## SQL 标准类型体系

SQL 标准（SQL:1999 ISO/IEC 9075、SQL:2003、SQL:2016）定义了以下类型分类：

| 标准分类 | 标准类型 | 引入版本 |
|---------|---------|---------|
| 精确数值 | `SMALLINT`, `INTEGER`, `BIGINT`, `NUMERIC(p,s)`, `DECIMAL(p,s)` | SQL:1992 / SQL:2003 (BIGINT) |
| 近似数值 | `REAL`, `DOUBLE PRECISION`, `FLOAT(p)` | SQL:1992 |
| 字符串 | `CHARACTER(n)`, `CHARACTER VARYING(n)`, `CLOB` | SQL:1992 / SQL:1999 (CLOB) |
| 国际化字符串 | `NATIONAL CHARACTER(n)`, `NATIONAL CHARACTER VARYING(n)`, `NCLOB` | SQL:1992 |
| 二进制 | `BINARY(n)`, `BINARY VARYING(n)`, `BLOB` | SQL:1999 |
| 布尔 | `BOOLEAN` | SQL:1999 |
| 日期时间 | `DATE`, `TIME`, `TIMESTAMP`, `TIME WITH TIME ZONE`, `TIMESTAMP WITH TIME ZONE` | SQL:1992 |
| 间隔 | `INTERVAL YEAR TO MONTH`, `INTERVAL DAY TO SECOND` | SQL:1992 |
| XML | `XML` | SQL:2003 |
| JSON | `JSON` | SQL:2016 |
| 集合 | `ARRAY`, `MULTISET` | SQL:1999 / SQL:2003 |
| 行 | `ROW` | SQL:1999 |

> 注：SQL 标准不包含 `TINYINT`、`HUGEINT`、`TEXT`、`STRING`、`UUID`、`MAP`、`STRUCT` 等类型——这些均为各引擎的扩展。`BIGINT` 在 SQL:2003 中正式引入，但 SQL:1992 仅定义了 `SMALLINT` 和 `INTEGER`。

---

## 1. 整数类型 (Integer Types)

### 支持矩阵

| 引擎 | TINYINT | SMALLINT | INT / INTEGER | BIGINT | HUGEINT | INT128 | UNSIGNED 变体 | 版本说明 |
|------|---------|----------|--------------|--------|---------|--------|--------------|---------|
| PostgreSQL | ❌ | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |
| MySQL | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ✅ `UNSIGNED` | 全版本 |
| MariaDB | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ✅ `UNSIGNED` | 全版本 |
| SQLite | ❌ (存为 INTEGER) | ❌ (存为 INTEGER) | ✅ 动态 1-8B | ❌ (存为 INTEGER) | ❌ | ❌ | ❌ | 类型亲和性 |
| Oracle | ❌ | ❌ | ❌ (NUMBER 别名) | ❌ (NUMBER 别名) | ❌ | ❌ | ❌ | `NUMBER(38)` |
| SQL Server | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |
| DB2 | ❌ | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |
| Snowflake | ✅ 别名 | ✅ 别名 | ✅ 别名 | ✅ 别名 | ❌ | ❌ | ❌ | 全部映射到 NUMBER(38,0) |
| BigQuery | ❌ | ❌ | ✅ `INT64` | ✅ `INT64` | ❌ | ❌ | ❌ | INT 是 INT64 别名 |
| Redshift | ✅ 别名 | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |
| DuckDB | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ✅ 16B | ❌ | ✅ `UTINYINT` 等 | 0.3+ |
| ClickHouse | ✅ `Int8` | ✅ `Int16` | ✅ `Int32` | ✅ `Int64` | ❌ | ✅ `Int128`/`Int256` | ✅ `UInt8` 等 | 全版本 |
| Trino | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |
| Presto | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |
| Spark SQL | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |
| Hive | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | 0.11+ |
| Flink SQL | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |
| Databricks | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |
| Teradata | ✅ `BYTEINT` 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | BYTEINT 是专有名 |
| Greenplum | ❌ | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | 继承 PG |
| CockroachDB | ❌ | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | 兼容 PG |
| TiDB | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ✅ `UNSIGNED` | 兼容 MySQL |
| OceanBase | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ✅ `UNSIGNED`(MySQL模式) | 双模式 |
| YugabyteDB | ❌ | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | 兼容 PG |
| SingleStore | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ✅ `UNSIGNED` | 兼容 MySQL |
| Vertica | ✅ 别名 | ✅ 别名 | ✅ 8B | ✅ 8B | ❌ | ❌ | ❌ | INT 实际为 8 字节 |
| Impala | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |
| StarRocks | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ✅ `LARGEINT` 16B | ❌ | ❌ | -- |
| Doris | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ✅ `LARGEINT` 16B | ❌ | ❌ | -- |
| MonetDB | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ✅ 16B | ❌ | ❌ | -- |
| CrateDB | ❌ | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |
| TimescaleDB | ❌ | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | 继承 PG |
| QuestDB | ❌ | ✅ `short` 2B | ✅ 4B | ✅ `long` 8B | ❌ | ❌ | ❌ | 专有名 |
| Exasol | ❌ | ✅ 别名 | ✅ 别名 | ✅ 别名 | ❌ | ❌ | ❌ | 映射到 DECIMAL |
| SAP HANA | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |
| Informix | ❌ | ✅ 2B | ✅ 4B | ✅ `INT8` 8B | ❌ | ❌ | ❌ | INT8 是专有名 |
| Firebird | ❌ | ✅ 2B | ✅ 4B | ✅ 8B | ✅ `INT128` 16B | ❌ | ❌ | 4.0+ (INT128) |
| H2 | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |
| HSQLDB | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |
| Derby | ❌ | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |
| Amazon Athena | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | 继承 Trino |
| Azure Synapse | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | 继承 SQL Server |
| Google Spanner | ❌ | ❌ | ❌ | ✅ `INT64` | ❌ | ❌ | ❌ | 仅 INT64 |
| Materialize | ❌ | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | 兼容 PG |
| RisingWave | ❌ | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | 兼容 PG |
| InfluxDB (SQL) | ❌ | ❌ | ❌ | ✅ `i64` | ❌ | ❌ | ✅ `u64` | IOx 引擎 |
| DatabendDB | ✅ 1B | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ✅ `UInt8` 等 | -- |
| Yellowbrick | ❌ | ✅ 2B | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |
| Firebolt | ❌ | ❌ | ✅ 4B | ✅ 8B | ❌ | ❌ | ❌ | -- |

> **关键差异**：
> - **Oracle** 没有原生整数类型，`INT` / `INTEGER` / `SMALLINT` 均为 `NUMBER(38)` 的别名，实际存储为变长十进制。
> - **SQLite** 使用动态类型，`INTEGER` 根据值大小自动使用 1-8 字节存储，声明为 `TINYINT` 或 `BIGINT` 的列实际使用 `INTEGER` 亲和性。
> - **Snowflake** 的所有整数类型（TINYINT 到 BIGINT）均映射到 `NUMBER(38,0)`，物理存储根据实际值自动压缩。
> - **Vertica** 的 `INT` 实际占 8 字节（等同于多数引擎的 BIGINT），这在迁移时容易遗漏。
> - **ClickHouse** 和 **DatabendDB** 使用 Rust/C++ 风格的命名（`Int8`, `UInt64`），并提供 `Int128` / `Int256` 超宽整数。
> - **UNSIGNED** 仅 MySQL 系（MySQL、MariaDB、TiDB、SingleStore、OceanBase MySQL 模式）和部分列式引擎（ClickHouse、DuckDB、DatabendDB、InfluxDB）支持。

---

## 2. 精确小数类型 (Decimal / Numeric)

### 支持矩阵

| 引擎 | DECIMAL(p,s) | NUMERIC(p,s) | NUMBER(p,s) | 最大精度 | 默认精度 | 版本说明 |
|------|-------------|-------------|-------------|---------|---------|---------|
| PostgreSQL | ✅ | ✅ (同义) | ❌ | 1000 位 | 无限制 | `NUMERIC` 无参数=任意精度 |
| MySQL | ✅ | ✅ (同义) | ❌ | 65,30 | (10,0) | -- |
| MariaDB | ✅ | ✅ (同义) | ❌ | 65,30 | (10,0) | -- |
| SQLite | ❌ (存为 REAL/TEXT) | ❌ | ❌ | N/A | N/A | 类型亲和性 NUMERIC |
| Oracle | ❌ (别名) | ❌ (别名) | ✅ | 38 | NUMBER=浮点 | `NUMBER` 是原生类型 |
| SQL Server | ✅ | ✅ (同义) | ❌ | 38 | (18,0) | -- |
| DB2 | ✅ | ✅ (同义) | ❌ | 31 | (5,0) | -- |
| Snowflake | ✅ | ✅ (同义) | ✅ (同义) | 38 | (38,0) | 三者同义 |
| BigQuery | ✅ `NUMERIC` | ✅ | ✅ `BIGNUMERIC` | 76,38 | NUMERIC=(29,9) | BIGNUMERIC=(76,38) |
| Redshift | ✅ | ✅ (同义) | ❌ | 38 | (18,0) | -- |
| DuckDB | ✅ | ✅ (同义) | ❌ | 38 | (18,3) | -- |
| ClickHouse | ✅ | ❌ | ❌ | 76 | 必须指定 | `Decimal32/64/128/256` |
| Trino | ✅ | ❌ | ❌ | 38 | 必须指定 | -- |
| Presto | ✅ | ❌ | ❌ | 38 | 必须指定 | -- |
| Spark SQL | ✅ | ❌ | ❌ | 38 | (10,0) | -- |
| Hive | ✅ | ❌ | ❌ | 38 | (10,0) | 0.11+ |
| Flink SQL | ✅ | ❌ | ❌ | 38 | (10,0) | -- |
| Databricks | ✅ | ❌ | ❌ | 38 | (10,0) | -- |
| Teradata | ✅ | ✅ (同义) | ✅ `NUMBER` | 38 | (5,0) | NUMBER 是独立类型 |
| Greenplum | ✅ | ✅ (同义) | ❌ | 1000 位 | 无限制 | 继承 PG |
| CockroachDB | ✅ | ✅ (同义) | ❌ | 无限制 | 无限制 | 兼容 PG |
| TiDB | ✅ | ✅ (同义) | ❌ | 65,30 | (10,0) | 兼容 MySQL |
| OceanBase | ✅ | ✅ (同义) | ✅ (Oracle模式) | 65(M)/38(O) | 取决于模式 | 双模式 |
| YugabyteDB | ✅ | ✅ (同义) | ❌ | 1000 位 | 无限制 | 兼容 PG |
| SingleStore | ✅ | ✅ (同义) | ❌ | 65,30 | (10,0) | 兼容 MySQL |
| Vertica | ✅ | ✅ (同义) | ✅ (别名) | 1024 位 | (37,15) | NUMBER 是别名 |
| Impala | ✅ | ❌ | ❌ | 38 | (9,0) | -- |
| StarRocks | ✅ | ❌ | ❌ | 38,18 | (10,0) | DECIMAL V3 |
| Doris | ✅ | ❌ | ❌ | 38,18 | (10,0) | DECIMAL V3 |
| MonetDB | ✅ | ✅ (同义) | ❌ | 38 | (18,3) | -- |
| CrateDB | ❌ | ✅ | ❌ | N/A | 无精度控制 | 实际为 DOUBLE |
| TimescaleDB | ✅ | ✅ (同义) | ❌ | 1000 位 | 无限制 | 继承 PG |
| QuestDB | ❌ | ❌ | ❌ | N/A | N/A | 无精确小数类型 |
| Exasol | ✅ | ✅ (同义) | ❌ | 36 | (18,0) | -- |
| SAP HANA | ✅ | ✅ (同义) | ❌ | 38 | (34,0) | SMALLDECIMAL 也可用 |
| Informix | ✅ | ✅ (同义) | ❌ | 32 | (16,0) | -- |
| Firebird | ✅ | ✅ (同义) | ❌ | 38 | (9,0) | 4.0+ `DECFLOAT` |
| H2 | ✅ | ✅ (同义) | ❌ | 无限制 | 无限制 | Java BigDecimal |
| HSQLDB | ✅ | ✅ (同义) | ❌ | 无限制 | 无限制 | Java BigDecimal |
| Derby | ✅ | ✅ (同义) | ❌ | 31 | (5,0) | -- |
| Amazon Athena | ✅ | ❌ | ❌ | 38 | 必须指定 | 继承 Trino |
| Azure Synapse | ✅ | ✅ (同义) | ❌ | 38 | (18,0) | 继承 SQL Server |
| Google Spanner | ✅ `NUMERIC` | ✅ | ❌ | 29,9 | 固定 (29,9) | PostgreSQL 接口支持 PG NUMERIC |
| Materialize | ✅ | ✅ (同义) | ❌ | 38 | 无限制 | 兼容 PG |
| RisingWave | ✅ | ✅ (同义) | ❌ | 无限制 | 无限制 | 兼容 PG |
| InfluxDB (SQL) | ❌ | ❌ | ❌ | N/A | N/A | 仅浮点 |
| DatabendDB | ✅ | ❌ | ❌ | 76 | (10,0) | -- |
| Yellowbrick | ✅ | ✅ (同义) | ❌ | 38 | (18,0) | -- |
| Firebolt | ✅ `NUMERIC` | ✅ | ❌ | 38 | (38,0) | -- |

> **关键差异**：
> - **Oracle** 的原生类型是 `NUMBER(p,s)`，`DECIMAL` 和 `NUMERIC` 仅是别名。`NUMBER` 不带参数时是浮点十进制。
> - **ClickHouse** 使用分级类型：`Decimal32(s)` (精度 1-9)、`Decimal64(s)` (10-18)、`Decimal128(s)` (19-38)、`Decimal256(s)` (39-76)。
> - **PostgreSQL** 及其生态（Greenplum、TimescaleDB、CockroachDB、YugabyteDB）的 `NUMERIC` 不指定精度时支持任意精度，这在金融场景中是优势。
> - **QuestDB** 和 **InfluxDB** 作为时序数据库不提供精确小数类型。

---

## 3. 浮点类型 (Floating Point)

### 支持矩阵

| 引擎 | REAL / FLOAT4 | FLOAT | DOUBLE / FLOAT8 | FLOAT(n) 语义 | 版本说明 |
|------|--------------|-------|----------------|--------------|---------|
| PostgreSQL | ✅ `real` 4B | ✅ = `float8` | ✅ `double precision` 8B | FLOAT(1-24)=real, FLOAT(25-53)=double | -- |
| MySQL | ✅ `FLOAT` 4B | ✅ 4B (无参数) | ✅ `DOUBLE` 8B | FLOAT(p): p≤24→4B, p≥25→8B | -- |
| MariaDB | ✅ `FLOAT` 4B | ✅ 4B | ✅ `DOUBLE` 8B | 同 MySQL | -- |
| SQLite | ✅ (REAL 亲和性) | ✅ (REAL 亲和性) | ✅ (REAL 亲和性) | 全部为 8B 浮点 | 类型亲和性 |
| Oracle | ❌ | ✅ `BINARY_FLOAT` 4B | ✅ `BINARY_DOUBLE` 8B | FLOAT(p) = NUMBER 近似 | FLOAT(p) 中 p 是二进制位 |
| SQL Server | ✅ 4B | ✅ = `float(53)` | ✅ `float(53)` 8B | FLOAT(1-24)=4B, FLOAT(25-53)=8B | -- |
| DB2 | ✅ 4B | ✅ = `double` | ✅ `DOUBLE` 8B | 同 SQL 标准 | `DECFLOAT` 也可用 |
| Snowflake | ❌ | ✅ = `double` | ✅ `DOUBLE` 8B | 全部映射到 DOUBLE 8B | 无 4B 浮点 |
| BigQuery | ❌ | ✅ `FLOAT64` | ✅ `FLOAT64` 8B | 仅 FLOAT64 | 无 4B 浮点 |
| Redshift | ✅ `REAL` 4B | ✅ = `float8` | ✅ `DOUBLE PRECISION` 8B | 同 PG | -- |
| DuckDB | ✅ `REAL` 4B | ✅ = `float` | ✅ `DOUBLE` 8B | -- | -- |
| ClickHouse | ✅ `Float32` | ✅ = `Float64` | ✅ `Float64` | -- | -- |
| Trino | ✅ `REAL` 4B | ❌ (不接受 FLOAT) | ✅ `DOUBLE` 8B | -- | 必须使用 REAL / DOUBLE |
| Presto | ✅ `REAL` 4B | ❌ | ✅ `DOUBLE` 8B | -- | 同 Trino |
| Spark SQL | ✅ `FLOAT` 4B | ✅ 4B | ✅ `DOUBLE` 8B | -- | -- |
| Hive | ✅ `FLOAT` 4B | ✅ 4B | ✅ `DOUBLE` 8B | -- | -- |
| Flink SQL | ✅ `FLOAT` 4B | ✅ 4B | ✅ `DOUBLE` 8B | -- | -- |
| Databricks | ✅ `FLOAT` 4B | ✅ 4B | ✅ `DOUBLE` 8B | -- | -- |
| Teradata | ✅ `REAL` 4B | ✅ = `float` | ✅ `DOUBLE PRECISION` 8B | FLOAT(p) 同 SQL 标准 | -- |
| Greenplum | ✅ `real` 4B | ✅ = `float8` | ✅ `double precision` 8B | 同 PG | -- |
| CockroachDB | ✅ `REAL` 4B | ✅ = `float8` | ✅ `DOUBLE PRECISION` 8B | FLOAT(1-24)=4B, FLOAT(25-53)=8B | -- |
| TiDB | ✅ `FLOAT` 4B | ✅ 4B | ✅ `DOUBLE` 8B | 同 MySQL | -- |
| OceanBase | ✅ | ✅ | ✅ | 取决于模式 | 双模式 |
| YugabyteDB | ✅ `real` 4B | ✅ = `float8` | ✅ `double precision` 8B | 同 PG | -- |
| SingleStore | ✅ `FLOAT` 4B | ✅ 4B | ✅ `DOUBLE` 8B | 同 MySQL | -- |
| Vertica | ✅ = `double` | ✅ = `double` | ✅ `DOUBLE PRECISION` 8B | 全部为 8B | 无 4B 浮点 |
| Impala | ✅ `FLOAT` 4B | ✅ 4B | ✅ `DOUBLE` 8B | -- | -- |
| StarRocks | ✅ `FLOAT` 4B | ✅ 4B | ✅ `DOUBLE` 8B | -- | -- |
| Doris | ✅ `FLOAT` 4B | ✅ 4B | ✅ `DOUBLE` 8B | -- | -- |
| MonetDB | ✅ `REAL` 4B | ✅ | ✅ `DOUBLE` 8B | 同 SQL 标准 | -- |
| CrateDB | ✅ `REAL` 4B | ✅ = `double` | ✅ `DOUBLE PRECISION` 8B | -- | -- |
| TimescaleDB | ✅ `real` 4B | ✅ = `float8` | ✅ `double precision` 8B | 同 PG | -- |
| QuestDB | ✅ `float` 4B | ✅ 4B | ✅ `double` 8B | -- | -- |
| Exasol | ❌ | ✅ = `double` | ✅ `DOUBLE PRECISION` 8B | 全部为 8B | 无 4B 浮点 |
| SAP HANA | ✅ `REAL` 4B | ✅ = `double` | ✅ `DOUBLE` 8B | -- | -- |
| Informix | ✅ `SMALLFLOAT` 4B | ✅ 8B | ✅ `DOUBLE PRECISION` 8B | -- | SMALLFLOAT 是专有名 |
| Firebird | ✅ `FLOAT` 4B | ✅ | ✅ `DOUBLE PRECISION` 8B | FLOAT(1-7)=4B, FLOAT(8+)=8B | -- |
| H2 | ✅ `REAL` 4B | ✅ = `double` | ✅ `DOUBLE PRECISION` 8B | 同 SQL 标准 | -- |
| HSQLDB | ✅ `REAL` 4B | ✅ = `double` | ✅ `DOUBLE` 8B | 同 SQL 标准 | -- |
| Derby | ✅ `REAL` 4B | ✅ 8B | ✅ `DOUBLE` 8B | FLOAT = DOUBLE | -- |
| Amazon Athena | ✅ `REAL` 4B | ❌ | ✅ `DOUBLE` 8B | 同 Trino | -- |
| Azure Synapse | ✅ `REAL` 4B | ✅ = `float(53)` | ✅ `float(53)` 8B | 同 SQL Server | -- |
| Google Spanner | ❌ | ❌ | ✅ `FLOAT64` 8B | 仅 FLOAT64; FLOAT32 预览中 | -- |
| Materialize | ✅ `real` 4B | ✅ = `float8` | ✅ `double precision` 8B | 同 PG | -- |
| RisingWave | ✅ `real` 4B | ✅ = `float8` | ✅ `double precision` 8B | 同 PG | -- |
| InfluxDB (SQL) | ❌ | ❌ | ✅ `f64` 8B | 仅 64 位浮点 | -- |
| DatabendDB | ✅ `Float32` | ✅ = `Float64` | ✅ `Float64` | -- | -- |
| Yellowbrick | ✅ `REAL` 4B | ✅ = `double` | ✅ `DOUBLE PRECISION` 8B | -- | -- |
| Firebolt | ✅ `REAL` 4B | ✅ = `double` | ✅ `DOUBLE PRECISION` 8B | -- | -- |

> **注意**：`FLOAT` 在不同引擎中含义不同——在 PostgreSQL / Redshift 中等于 `DOUBLE`（8B），在 MySQL / Spark SQL 中等于 4B 浮点。迁移时务必确认。

---

## 4. 字符串类型 (String Types)

### 支持矩阵

| 引擎 | CHAR(n) | VARCHAR(n) | TEXT / CLOB | NCHAR/NVARCHAR | STRING | 最大 VARCHAR 长度 |
|------|---------|-----------|------------|---------------|--------|----------------|
| PostgreSQL | ✅ | ✅ | ✅ `TEXT` | ❌ (但支持) | ❌ | 1 GB |
| MySQL | ✅ (255) | ✅ | ✅ `TEXT`/`LONGTEXT` | ✅ | ❌ | 65,535 B (行级) |
| MariaDB | ✅ (255) | ✅ | ✅ `TEXT`/`LONGTEXT` | ✅ | ❌ | 65,535 B (行级) |
| SQLite | ❌ (TEXT 亲和性) | ❌ (TEXT 亲和性) | ✅ `TEXT` | ❌ | ❌ | 无限制 |
| Oracle | ✅ (2000) | ✅ `VARCHAR2` (4000/32767) | ✅ `CLOB` | ✅ `NVARCHAR2` | ❌ | 4000 B (标准)，32767 B (扩展) |
| SQL Server | ✅ (8000) | ✅ (8000) | ❌ (用 `VARCHAR(MAX)`) | ✅ `NVARCHAR` | ❌ | 8000 / MAX=2 GB |
| DB2 | ✅ (254) | ✅ | ✅ `CLOB` | ❌ | ❌ | 32,672 B |
| Snowflake | ✅ (= VARCHAR) | ✅ | ✅ `TEXT` (= VARCHAR) | ❌ | ✅ (= VARCHAR) | 16 MB |
| BigQuery | ❌ | ❌ | ✅ `STRING` | ❌ | ✅ `STRING` | 无限制 |
| Redshift | ✅ | ✅ | ❌ (VARCHAR(MAX)) | ❌ | ❌ | 65,535 B |
| DuckDB | ✅ (= VARCHAR) | ✅ | ✅ `TEXT` (= VARCHAR) | ❌ | ❌ | 无限制 |
| ClickHouse | ❌ | ❌ | ❌ | ❌ | ✅ `String` | 无限制 |
| Trino | ✅ | ✅ | ❌ | ❌ | ❌ | 无限制 (无需指定长度) |
| Presto | ✅ | ✅ | ❌ | ❌ | ❌ | 无限制 |
| Spark SQL | ✅ | ✅ | ❌ | ❌ | ✅ `STRING` | 无限制 |
| Hive | ✅ | ✅ | ❌ | ❌ | ✅ `STRING` | 无限制 |
| Flink SQL | ✅ | ✅ | ❌ | ❌ | ✅ `STRING` | 无限制 |
| Databricks | ✅ | ✅ | ❌ | ❌ | ✅ `STRING` | 无限制 |
| Teradata | ✅ (64000) | ✅ (64000) | ✅ `CLOB` | ❌ | ❌ | 64,000 字符 |
| Greenplum | ✅ | ✅ | ✅ `TEXT` | ❌ | ❌ | 1 GB |
| CockroachDB | ✅ | ✅ | ✅ `TEXT` | ❌ | ✅ `STRING` | 无限制 |
| TiDB | ✅ (255) | ✅ | ✅ `TEXT`/`LONGTEXT` | ✅ | ❌ | 65,535 B |
| OceanBase | ✅ | ✅ | ✅ `TEXT`(M)/`CLOB`(O) | ✅ (Oracle模式) | ❌ | 取决于模式 |
| YugabyteDB | ✅ | ✅ | ✅ `TEXT` | ❌ | ❌ | 1 GB |
| SingleStore | ✅ (255) | ✅ | ✅ `TEXT`/`LONGTEXT` | ❌ | ❌ | 65,535 B |
| Vertica | ✅ | ✅ | ❌ (VARCHAR(65000)) | ❌ | ❌ | 65,000 B |
| Impala | ✅ | ✅ | ❌ | ❌ | ✅ `STRING` | 无限制 |
| StarRocks | ✅ | ✅ | ❌ | ❌ | ✅ `STRING` | 默认 65,535 B; STRING=最大 2 GB |
| Doris | ✅ | ✅ | ❌ | ❌ | ✅ `STRING` | 默认 65,535 B; STRING=最大 2 GB |
| MonetDB | ✅ | ✅ | ✅ `TEXT` / `CLOB` | ❌ | ❌ | 无限制 |
| CrateDB | ❌ | ❌ | ✅ `TEXT` | ❌ | ❌ | 无限制 |
| TimescaleDB | ✅ | ✅ | ✅ `TEXT` | ❌ | ❌ | 1 GB |
| QuestDB | ❌ | ✅ `varchar` | ✅ `string` (定长符号) | ❌ | ✅ `string` | varchar=无限制 |
| Exasol | ✅ | ✅ | ❌ | ❌ | ❌ | 2,000,000 字符 |
| SAP HANA | ✅ | ✅ `VARCHAR` / `NVARCHAR` | ✅ `CLOB`/`NCLOB` | ✅ | ❌ | 5000 B(VARCHAR) |
| Informix | ✅ (32767) | ✅ (255) | ✅ `TEXT` / `CLOB` | ❌ | ❌ | VARCHAR 限 255 B |
| Firebird | ✅ (32767) | ✅ (32767) | ✅ `BLOB SUB_TYPE TEXT` | ❌ | ❌ | 32,767 B |
| H2 | ✅ | ✅ | ✅ `CLOB` | ❌ | ❌ | 无限制 |
| HSQLDB | ✅ | ✅ | ✅ `CLOB` | ❌ | ❌ | 无限制 |
| Derby | ✅ (254) | ✅ (32672) | ✅ `CLOB` | ❌ | ❌ | 32,672 B |
| Amazon Athena | ✅ | ✅ | ❌ | ❌ | ❌ | 无限制 |
| Azure Synapse | ✅ (8000) | ✅ (8000) | ❌ (`VARCHAR(MAX)`) | ✅ `NVARCHAR` | ❌ | 8000 / MAX |
| Google Spanner | ❌ | ❌ | ✅ `STRING(MAX)` | ❌ | ✅ `STRING(n)` | 10 MB |
| Materialize | ✅ | ✅ | ✅ `TEXT` | ❌ | ❌ | 无限制 |
| RisingWave | ✅ | ✅ | ✅ `TEXT` | ❌ | ❌ | 无限制 |
| InfluxDB (SQL) | ❌ | ❌ | ❌ | ❌ | ✅ `string` | 无限制 |
| DatabendDB | ❌ | ✅ | ❌ | ❌ | ✅ `STRING` | 无限制 |
| Yellowbrick | ✅ | ✅ | ❌ | ❌ | ❌ | 64,000 B |
| Firebolt | ❌ | ❌ | ✅ `TEXT` | ❌ | ❌ | 无限制 |

> **关键差异**：
> - **Oracle** 使用 `VARCHAR2` 而非 `VARCHAR`（Oracle 保留 `VARCHAR` 用于将来的 SQL 标准对齐，但强烈建议使用 `VARCHAR2`）。
> - **BigQuery** 和 **Google Spanner** 仅使用 `STRING` 类型，不支持 `CHAR`/`VARCHAR`。
> - **ClickHouse** 只有 `String`（无长度限制）和 `FixedString(n)`（定长字节串），无 `VARCHAR`。
> - **Snowflake** 中 `CHAR`, `VARCHAR`, `STRING`, `TEXT` 全部等价，CHAR 不做补空格处理。
> - **SQL Server** 使用 `VARCHAR(MAX)` 替代 `TEXT`/`CLOB`，`TEXT` 类型已废弃。

---

## 5. 二进制类型 (Binary Types)

### 支持矩阵

| 引擎 | BINARY(n) | VARBINARY(n) | BLOB | BYTEA / BYTES | 版本说明 |
|------|----------|-------------|------|-------------|---------|
| PostgreSQL | ❌ | ❌ | ❌ | ✅ `BYTEA` | -- |
| MySQL | ✅ | ✅ | ✅ `BLOB`/`LONGBLOB` | ❌ | -- |
| MariaDB | ✅ | ✅ | ✅ `BLOB`/`LONGBLOB` | ❌ | -- |
| SQLite | ❌ | ❌ | ✅ `BLOB` | ❌ | BLOB 亲和性 |
| Oracle | ❌ | ❌ (用 `RAW`) | ✅ `BLOB` | ❌ | `RAW(n)` 最大 2000/32767 B |
| SQL Server | ✅ (8000) | ✅ (8000) | ❌ | ❌ | `VARBINARY(MAX)` 替代 BLOB |
| DB2 | ✅ | ✅ | ✅ `BLOB` | ❌ | -- |
| Snowflake | ✅ `BINARY` | ✅ `VARBINARY` (= BINARY) | ❌ | ❌ | 最大 8 MB |
| BigQuery | ❌ | ❌ | ❌ | ✅ `BYTES` | -- |
| Redshift | ❌ | ✅ `VARBYTE` | ❌ | ❌ | `VARBYTE` 最大 1 MB |
| DuckDB | ❌ | ❌ | ✅ `BLOB` | ❌ | -- |
| ClickHouse | ❌ | ❌ | ❌ | ❌ | 用 `String` 存储二进制 |
| Trino | ❌ | ✅ `VARBINARY` | ❌ | ❌ | -- |
| Presto | ❌ | ✅ `VARBINARY` | ❌ | ❌ | -- |
| Spark SQL | ❌ | ❌ | ❌ | ✅ `BINARY` | 不定长 |
| Hive | ❌ | ❌ | ❌ | ✅ `BINARY` | 不定长 |
| Flink SQL | ✅ | ✅ | ❌ | ✅ `BYTES` | -- |
| Databricks | ❌ | ❌ | ❌ | ✅ `BINARY` | 不定长 |
| Teradata | ✅ | ✅ | ✅ `BLOB` | ❌ | -- |
| Greenplum | ❌ | ❌ | ❌ | ✅ `BYTEA` | 继承 PG |
| CockroachDB | ❌ | ❌ | ❌ | ✅ `BYTEA` / `BYTES` | -- |
| TiDB | ✅ | ✅ | ✅ `BLOB` | ❌ | 兼容 MySQL |
| OceanBase | ✅ | ✅ | ✅ `BLOB` | ❌ | -- |
| YugabyteDB | ❌ | ❌ | ❌ | ✅ `BYTEA` | 继承 PG |
| SingleStore | ✅ | ✅ | ✅ `BLOB` | ❌ | 兼容 MySQL |
| Vertica | ✅ | ✅ `VARBINARY` | ❌ | ❌ | 最大 65,000 B |
| Impala | ❌ | ❌ | ❌ | ❌ | 用 STRING 存储 |
| StarRocks | ❌ | ❌ | ❌ | ❌ | 用 VARCHAR 存储 |
| Doris | ❌ | ❌ | ❌ | ❌ | 用 VARCHAR 存储 |
| MonetDB | ❌ | ❌ | ✅ `BLOB` | ❌ | -- |
| CrateDB | ❌ | ❌ | ❌ | ❌ | 不支持原生二进制 |
| TimescaleDB | ❌ | ❌ | ❌ | ✅ `BYTEA` | 继承 PG |
| QuestDB | ❌ | ❌ | ❌ | ❌ | 不支持二进制类型 |
| Exasol | ❌ | ❌ | ❌ | ❌ | 不支持（用 VARCHAR 编码） |
| SAP HANA | ❌ | ✅ `VARBINARY` | ✅ `BLOB` | ❌ | -- |
| Informix | ❌ | ❌ | ✅ `BYTE` / `BLOB` | ❌ | BYTE 是简单二进制 |
| Firebird | ❌ | ❌ | ✅ `BLOB SUB_TYPE 0` | ❌ | 通过 BLOB 子类型区分 |
| H2 | ✅ | ✅ | ✅ `BLOB` | ❌ | -- |
| HSQLDB | ✅ | ✅ | ✅ `BLOB` | ❌ | -- |
| Derby | ❌ | ❌ (VARCHAR FOR BIT DATA) | ✅ `BLOB` | ❌ | 专有语法 |
| Amazon Athena | ❌ | ✅ `VARBINARY` | ❌ | ❌ | 继承 Trino |
| Azure Synapse | ✅ | ✅ | ❌ | ❌ | 同 SQL Server |
| Google Spanner | ❌ | ❌ | ❌ | ✅ `BYTES(n)` | -- |
| Materialize | ❌ | ❌ | ❌ | ✅ `BYTEA` | 兼容 PG |
| RisingWave | ❌ | ❌ | ❌ | ✅ `BYTEA` | 兼容 PG |
| InfluxDB (SQL) | ❌ | ❌ | ❌ | ❌ | 不支持 |
| DatabendDB | ❌ | ❌ | ❌ | ❌ | 用 STRING 存储 |
| Yellowbrick | ❌ | ✅ | ❌ | ✅ `BYTEA` | -- |
| Firebolt | ❌ | ❌ | ❌ | ✅ `BYTEA` | -- |

> **关键差异**：
> - **PostgreSQL** 生态统一使用 `BYTEA`（byte array），与 SQL 标准的 `BINARY`/`VARBINARY`/`BLOB` 体系不同。
> - **ClickHouse** 没有专门的二进制类型，使用通用的 `String` 类型存储二进制数据。
> - **Oracle** 使用 `RAW(n)` 对应 `VARBINARY`，`BLOB` 对应大对象。
> - 分析型引擎（StarRocks、Doris、Impala、QuestDB）普遍不提供原生二进制类型。

---

## 6. 布尔类型 (Boolean)

### 支持矩阵

| 引擎 | BOOLEAN 原生 | 存储方式 | TRUE/FALSE 字面量 | 替代实现 | 版本说明 |
|------|------------|---------|------------------|---------|---------|
| PostgreSQL | ✅ | 1 字节 | `TRUE`/`FALSE`, `'t'`/`'f'` | -- | 支持 `BOOL` 别名 |
| MySQL | ❌ (别名) | `TINYINT(1)` | `TRUE`=1, `FALSE`=0 | `TINYINT(1)` | `BOOLEAN` 是 TINYINT(1) 的别名 |
| MariaDB | ❌ (别名) | `TINYINT(1)` | `TRUE`=1, `FALSE`=0 | `TINYINT(1)` | 同 MySQL |
| SQLite | ❌ | INTEGER (0/1) | `TRUE`=1, `FALSE`=0 | 整数 0/1 | 3.23.0+ 识别 TRUE/FALSE |
| Oracle | ❌ | -- | ❌ | `NUMBER(1)` / `CHAR(1)` | PL/SQL 有 BOOLEAN，SQL 不支持 (23c 引入) |
| SQL Server | ✅ `BIT` | 1 位 | `1`/`0` | `BIT` | BIT 可存 0、1、NULL |
| DB2 | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | 9.7+ |
| Snowflake | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| BigQuery | ✅ `BOOL` | -- | `TRUE`/`FALSE` | -- | -- |
| Redshift | ✅ | 1 字节 | `TRUE`/`FALSE`, `'t'`/`'f'` | -- | -- |
| DuckDB | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| ClickHouse | ✅ `Bool` | `UInt8` | `true`/`false` | `UInt8` (0/1) | 21.12+ 原生 Bool |
| Trino | ✅ | -- | `TRUE`/`FALSE` | -- | -- |
| Presto | ✅ | -- | `TRUE`/`FALSE` | -- | -- |
| Spark SQL | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| Hive | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| Flink SQL | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| Databricks | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| Teradata | ❌ | -- | ❌ | `BYTEINT` (0/1) | 无 BOOLEAN 类型 |
| Greenplum | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | 继承 PG |
| CockroachDB | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | 兼容 PG |
| TiDB | ❌ (别名) | `TINYINT(1)` | `TRUE`=1, `FALSE`=0 | `TINYINT(1)` | 兼容 MySQL |
| OceanBase | ❌ (别名/模式) | `TINYINT(1)` / -- | 取决于模式 | 取决于模式 | MySQL 模式同 MySQL |
| YugabyteDB | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | 继承 PG |
| SingleStore | ❌ (别名) | `TINYINT(1)` | `TRUE`=1, `FALSE`=0 | `TINYINT(1)` | 兼容 MySQL |
| Vertica | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| Impala | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| StarRocks | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| Doris | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| MonetDB | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| CrateDB | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| TimescaleDB | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | 继承 PG |
| QuestDB | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| Exasol | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| SAP HANA | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | 2.0 SPS04+ |
| Informix | ✅ | 1 字节 | `'t'`/`'f'` | -- | -- |
| Firebird | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | 3.0+ |
| H2 | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| HSQLDB | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| Derby | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | 10.7+ |
| Amazon Athena | ✅ | -- | `TRUE`/`FALSE` | -- | 继承 Trino |
| Azure Synapse | ✅ `BIT` | 1 位 | `1`/`0` | `BIT` | 同 SQL Server |
| Google Spanner | ✅ `BOOL` | -- | `TRUE`/`FALSE` | -- | -- |
| Materialize | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | 兼容 PG |
| RisingWave | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | 兼容 PG |
| InfluxDB (SQL) | ✅ `bool` | 1 字节 | `true`/`false` | -- | -- |
| DatabendDB | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| Yellowbrick | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |
| Firebolt | ✅ | 1 字节 | `TRUE`/`FALSE` | -- | -- |

> **关键差异**：
> - **MySQL 系**（MySQL、MariaDB、TiDB、SingleStore）中 `BOOLEAN` 是 `TINYINT(1)` 的语法糖，因此 `SELECT col = 2` 在 BOOLEAN 列上不会报错（列可以存储 0-255 的任何整数）。
> - **Oracle** 直到 23c 才在 SQL 层面引入 `BOOLEAN`，之前只有 PL/SQL 支持。
> - **SQL Server / Azure Synapse** 使用 `BIT` 而非 `BOOLEAN`，只能存储 0、1、NULL。
> - **Teradata** 没有布尔类型，通常用 `BYTEINT` 列存储 0/1。

---

## 7. 日期与时间类型 (Date / Time Types)

### 支持矩阵

| 引擎 | DATE | TIME | TIMESTAMP | DATETIME | TIMESTAMP WITH TZ | INTERVAL | 版本说明 |
|------|------|------|-----------|----------|-------------------|----------|---------|
| PostgreSQL | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMPTZ` | ✅ | -- |
| MySQL | ✅ | ✅ | ✅ (带时区转换) | ✅ | ❌ (TIMESTAMP 隐含时区) | ❌ | DATETIME: 无时区; TIMESTAMP: UTC 存储 |
| MariaDB | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | 同 MySQL |
| SQLite | ❌ (TEXT/REAL/INT) | ❌ | ❌ | ❌ | ❌ | ❌ | 日期函数操作字符串 |
| Oracle | ✅ (含时间) | ❌ | ✅ | ❌ | ✅ `TIMESTAMP WITH TIME ZONE` | ✅ | DATE 包含时分秒 |
| SQL Server | ✅ | ✅ | ❌ (用 `datetime2`) | ✅ `DATETIME`/`DATETIME2` | ✅ `DATETIMEOFFSET` | ❌ | DATETIME: 3.33ms 精度; DATETIME2: 100ns |
| DB2 | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | -- |
| Snowflake | ✅ | ✅ | ✅ | ❌ (别名) | ✅ `TIMESTAMP_TZ` | ❌ | `TIMESTAMP_LTZ`/`_NTZ`/`_TZ` 三种 |
| BigQuery | ✅ | ✅ | ✅ (无时区) | ✅ `DATETIME` (无时区) | ✅ `TIMESTAMP` (UTC) | ✅ | BigQuery 的 TIMESTAMP 含时区 |
| Redshift | ✅ | ❌ | ✅ | ❌ | ✅ `TIMESTAMPTZ` | ✅ `INTERVAL` 仅字面量 | -- |
| DuckDB | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMPTZ` | ✅ | `TIMESTAMP_S/_MS/_NS` 多精度 |
| ClickHouse | ✅ `Date` / `Date32` | ❌ | ✅ `DateTime` | ✅ `DateTime` | ✅ `DateTime64(p, tz)` | ❌ | DateTime 秒级; DateTime64 亚秒级 |
| Trino | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMP WITH TIME ZONE` | ✅ | -- |
| Presto | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | -- |
| Spark SQL | ✅ | ❌ | ✅ | ❌ | ✅ `TIMESTAMP_NTZ` (3.4+) | ✅ | TIMESTAMP 默认含时区 (3.4 前) |
| Hive | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | 3.0+ (DATE改进) |
| Flink SQL | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMP_LTZ` | ✅ | -- |
| Databricks | ✅ | ❌ | ✅ | ❌ | ✅ `TIMESTAMP_NTZ` | ✅ | -- |
| Teradata | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMP WITH TIME ZONE` | ✅ | -- |
| Greenplum | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMPTZ` | ✅ | 继承 PG |
| CockroachDB | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMPTZ` | ✅ | 兼容 PG |
| TiDB | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | 兼容 MySQL |
| OceanBase | ✅ | ✅ | ✅ | ✅ (MySQL模式) | ✅ (Oracle模式) | ✅ (Oracle模式) | 双模式 |
| YugabyteDB | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMPTZ` | ✅ | 继承 PG |
| SingleStore | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | 兼容 MySQL |
| Vertica | ✅ | ✅ | ✅ | ❌ (别名) | ✅ `TIMESTAMPTZ` | ✅ | `DATETIME` 是 TIMESTAMP 别名 |
| Impala | ❌ (内嵌于 TIMESTAMP) | ❌ | ✅ | ❌ | ❌ | ❌ | TIMESTAMP 含日期和时间 |
| StarRocks | ✅ | ❌ | ❌ | ✅ `DATETIME` | ❌ | ❌ | DATETIME 秒/微秒级 |
| Doris | ✅ | ❌ | ❌ | ✅ `DATETIME` | ❌ | ❌ | 同 StarRocks |
| MonetDB | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMPTZ` | ✅ | -- |
| CrateDB | ❌ | ❌ | ✅ `TIMESTAMP` | ❌ | ✅ `TIMESTAMP WITH TIME ZONE` | ❌ | 内部为 BIGINT 毫秒 |
| TimescaleDB | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMPTZ` | ✅ | 继承 PG |
| QuestDB | ✅ `date` | ❌ | ✅ `timestamp` | ❌ | ❌ | ❌ | timestamp 为微秒精度 |
| Exasol | ✅ | ❌ | ✅ | ❌ | ✅ `TIMESTAMP WITH LOCAL TIME ZONE` | ✅ | -- |
| SAP HANA | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMP` 含时区 | ❌ | `SECONDDATE` 也可用 |
| Informix | ✅ | ❌ (DATETIME HOUR TO SECOND) | ❌ (用 DATETIME) | ✅ `DATETIME` | ❌ | ✅ | `DATETIME YEAR TO SECOND` |
| Firebird | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMP WITH TIME ZONE` | ❌ | 4.0+ (WITH TIME ZONE) |
| H2 | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMP WITH TIME ZONE` | ✅ | -- |
| HSQLDB | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMP WITH TIME ZONE` | ✅ | -- |
| Derby | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | -- |
| Amazon Athena | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | 继承 Trino |
| Azure Synapse | ✅ | ✅ | ❌ | ✅ `DATETIME2` | ✅ `DATETIMEOFFSET` | ❌ | 同 SQL Server |
| Google Spanner | ✅ | ❌ | ✅ `TIMESTAMP` (UTC) | ❌ | ✅ (TIMESTAMP 含时区) | ❌ | -- |
| Materialize | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMPTZ` | ✅ | 兼容 PG |
| RisingWave | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMPTZ` | ✅ | 兼容 PG |
| InfluxDB (SQL) | ❌ | ❌ | ✅ `timestamp` (纳秒) | ❌ | ❌ | ✅ `duration` | 纳秒级时间戳 |
| DatabendDB | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | -- |
| Yellowbrick | ✅ | ✅ | ✅ | ❌ | ✅ `TIMESTAMPTZ` | ✅ | -- |
| Firebolt | ✅ | ❌ | ✅ | ❌ | ✅ `TIMESTAMPTZ` | ❌ | -- |

> **关键差异**：
> - **Oracle** 的 `DATE` 类型包含时分秒（精度到秒），与 SQL 标准的纯日期不同——这是最常见的跨库陷阱之一。
> - **MySQL** 的 `TIMESTAMP` 自动做 UTC 转换（存入时转 UTC，读出时转回会话时区），`DATETIME` 不做转换。两者范围不同：TIMESTAMP='1970-01-01'~'2038-01-19'，DATETIME='1000-01-01'~'9999-12-31'。
> - **BigQuery** 的命名与多数引擎相反：`TIMESTAMP` 含时区（UTC），`DATETIME` 不含时区。
> - **Snowflake** 提供三种 TIMESTAMP 变体：`TIMESTAMP_NTZ`（无时区）、`TIMESTAMP_LTZ`（本地时区）、`TIMESTAMP_TZ`（带时区偏移），默认行为通过 `TIMESTAMP_TYPE_MAPPING` 参数控制。
> - **SQLite** 没有专用的日期时间类型，使用 `TEXT`（ISO 8601 字符串）、`REAL`（Julian day）或 `INTEGER`（Unix 时间戳）存储。
> - **INTERVAL** 支持差异巨大：PostgreSQL 生态和 SQL 标准引擎完整支持，MySQL 系和部分分析引擎不支持。

---

## 8. UUID 类型

### 支持矩阵

| 引擎 | 原生 UUID 类型 | 存储大小 | 生成函数 | 版本说明 |
|------|-------------|---------|---------|---------|
| PostgreSQL | ✅ `UUID` | 16 字节 | `gen_random_uuid()` (13+) / `uuid_generate_v4()` (扩展) | 8.3+ 类型, 13+ 内置函数 |
| MySQL | ❌ | -- | `UUID()` 返回 `CHAR(36)` | 存为字符串 |
| MariaDB | ✅ `UUID` | 16 字节 | `UUID()` / `SYS_GUID()` | 10.7+ |
| SQLite | ❌ | -- | 无内置 | 存为 TEXT / BLOB |
| Oracle | ❌ | -- | `SYS_GUID()` 返回 `RAW(16)` | 存为 RAW(16) |
| SQL Server | ✅ `UNIQUEIDENTIFIER` | 16 字节 | `NEWID()` / `NEWSEQUENTIALID()` | 全版本 |
| DB2 | ❌ | -- | 无内置 | 存为 CHAR(36) |
| Snowflake | ❌ | -- | `UUID_STRING()` | 返回 VARCHAR |
| BigQuery | ❌ | -- | `GENERATE_UUID()` | 返回 STRING |
| Redshift | ❌ | -- | 无内置 | 存为 VARCHAR(36) |
| DuckDB | ✅ `UUID` | 16 字节 | `uuid()` | -- |
| ClickHouse | ✅ `UUID` | 16 字节 | `generateUUIDv4()` | -- |
| Trino | ✅ `UUID` | 16 字节 | `uuid()` | -- |
| Presto | ✅ `UUID` | 16 字节 | `uuid()` | -- |
| Spark SQL | ❌ | -- | `uuid()` 返回 `STRING` | -- |
| Hive | ❌ | -- | `reflect("java.util.UUID","randomUUID")` | -- |
| Flink SQL | ❌ | -- | `UUID()` 返回 `STRING` | -- |
| Databricks | ❌ | -- | `uuid()` 返回 `STRING` | -- |
| Teradata | ❌ | -- | 无内置 | 存为 CHAR(36) |
| Greenplum | ✅ `UUID` | 16 字节 | `gen_random_uuid()` | 继承 PG |
| CockroachDB | ✅ `UUID` | 16 字节 | `gen_random_uuid()` | 兼容 PG |
| TiDB | ❌ | -- | `UUID()` 返回 VARCHAR | 兼容 MySQL |
| OceanBase | ❌ | -- | `UUID()` / `SYS_GUID()` | 取决于模式 |
| YugabyteDB | ✅ `UUID` | 16 字节 | `gen_random_uuid()` | 继承 PG |
| SingleStore | ❌ | -- | `UUID()` 返回 CHAR(36) | -- |
| Vertica | ✅ `UUID` | 16 字节 | `UUID_GENERATE()` | 9.0+ |
| Impala | ❌ | -- | `uuid()` 返回 STRING | -- |
| StarRocks | ❌ | -- | `uuid()` 返回 VARCHAR | -- |
| Doris | ❌ | -- | `uuid()` 返回 VARCHAR | -- |
| MonetDB | ✅ `UUID` | 16 字节 | `uuid()` | -- |
| CrateDB | ❌ | -- | 无内置 | 存为 TEXT |
| TimescaleDB | ✅ `UUID` | 16 字节 | `gen_random_uuid()` | 继承 PG |
| QuestDB | ✅ `uuid` | 16 字节 | `rnd_uuid4()` | -- |
| Exasol | ❌ | -- | 无内置 | 存为 CHAR(36) |
| SAP HANA | ❌ | -- | `SYSUUID` | 返回 VARBINARY |
| Informix | ❌ | -- | 无内置 | 存为 CHAR(36) |
| Firebird | ✅ (CHAR(16) OCTETS) | 16 字节 | `GEN_UUID()` | 2.1+ 函数, 4.0+ 优化 |
| H2 | ✅ `UUID` | 16 字节 | `RANDOM_UUID()` | -- |
| HSQLDB | ✅ `UUID` | 16 字节 | `UUID()` | 2.4+ |
| Derby | ❌ | -- | 无内置 | 存为 CHAR(36) |
| Amazon Athena | ✅ `UUID` | 16 字节 | `uuid()` | 继承 Trino |
| Azure Synapse | ✅ `UNIQUEIDENTIFIER` | 16 字节 | `NEWID()` | 同 SQL Server |
| Google Spanner | ❌ | -- | `GENERATE_UUID()` | 返回 STRING |
| Materialize | ✅ `UUID` | 16 字节 | `gen_random_uuid()` | 兼容 PG |
| RisingWave | ❌ | -- | 无内置 | 存为 VARCHAR |
| InfluxDB (SQL) | ❌ | -- | 无内置 | 不支持 |
| DatabendDB | ❌ | -- | 无内置 | 存为 VARCHAR |
| Yellowbrick | ✅ `UUID` | 16 字节 | `gen_random_uuid()` | -- |
| Firebolt | ❌ | -- | 无内置 | 存为 TEXT |

> **关键差异**：
> - 约一半引擎有原生 `UUID` 类型（16 字节紧凑存储，支持索引优化），另一半使用 `CHAR(36)` / `VARCHAR` 存储文本格式（36 字节，性能较差）。
> - **SQL Server** 的 UUID 类型叫 `UNIQUEIDENTIFIER`，`NEWSEQUENTIALID()` 生成递增 UUID，对 B-Tree 索引友好。
> - **Oracle** 使用 `SYS_GUID()` 返回 `RAW(16)`（非标准 UUID 格式，而是全局唯一标识符）。

---

## 9. JSON 类型

### 支持矩阵

| 引擎 | 原生 JSON 类型 | 二进制 JSON | 存储方式 | 访问语法 | 版本说明 |
|------|-------------|-----------|---------|---------|---------|
| PostgreSQL | ✅ `JSON` | ✅ `JSONB` | 文本 / 二进制 | `->`, `->>`, `@>`, `#>` | 9.2+ (JSON), 9.4+ (JSONB) |
| MySQL | ✅ `JSON` | ✅ (内部二进制) | 二进制 | `->`, `->>`, `JSON_EXTRACT()` | 5.7.8+ |
| MariaDB | ✅ `JSON` | ❌ (TEXT 别名) | 文本 (TEXT) | `JSON_EXTRACT()` | JSON 是 LONGTEXT 别名 |
| SQLite | ❌ (TEXT) | ✅ `JSONB` 内部 | 文本 | `json_extract()`, `->`, `->>` | 3.38+ (-> 操作符), 3.45+ (JSONB) |
| Oracle | ✅ `JSON` | ✅ `OSON` | 二进制 | `json_value()`, `.` 点路径 | 12c+ (函数), 21c+ (原生类型) |
| SQL Server | ❌ (NVARCHAR) | ❌ | 文本 | `JSON_VALUE()`, `JSON_QUERY()`, `OPENJSON()` | 2016+ (函数), 2025+ (原生类型预览) |
| DB2 | ✅ `JSON` | ✅ `BSON` | 二进制 | `JSON_VALUE()`, `JSON_TABLE()` | 11.1+ |
| Snowflake | ✅ `VARIANT` | ✅ (内部) | 二进制 | `:` 冒号路径, `GET_PATH()` | GA |
| BigQuery | ✅ `JSON` | ✅ (内部) | 二进制 | `JSON_EXTRACT()`, `JSON_VALUE()` | GA |
| Redshift | ✅ `SUPER` | ✅ (内部) | 二进制 | `PartiQL` 语法, `JSON_EXTRACT_PATH_TEXT()` | 2021+ |
| DuckDB | ✅ `JSON` | ❌ | 文本 | `->`, `->>`, `json_extract()` | json 扩展 |
| ClickHouse | ✅ `JSON` | ❌ | 列式展开 | `JSONExtract*()`, 点路径 | 24.1+ (新 JSON), 旧版用 String |
| Trino | ✅ `JSON` | ❌ | 文本 | `json_extract()`, `json_value()` | -- |
| Presto | ✅ `JSON` | ❌ | 文本 | `json_extract()` | -- |
| Spark SQL | ❌ (STRING) | ❌ | 文本 | `get_json_object()`, `from_json()` | -- |
| Hive | ❌ (STRING) | ❌ | 文本 | `get_json_object()` | -- |
| Flink SQL | ❌ (STRING) | ❌ | 文本 | `JSON_VALUE()`, `JSON_QUERY()` | -- |
| Databricks | ❌ (STRING) | ❌ | 文本 | `get_json_object()`, `:` 点路径 | -- |
| Teradata | ✅ `JSON` | ✅ | 文本/二进制 | `JSONExtract*()` | 15.10+ |
| Greenplum | ✅ `JSON` / `JSONB` | ✅ | 同 PG | 同 PG | 继承 PG |
| CockroachDB | ✅ `JSON` / `JSONB` | ✅ | 二进制 | 同 PG | 兼容 PG |
| TiDB | ✅ `JSON` | ✅ (内部二进制) | 二进制 | `->`, `->>`, `JSON_EXTRACT()` | 兼容 MySQL |
| OceanBase | ✅ `JSON` | ✅ | 取决于模式 | 取决于模式 | 双模式 |
| YugabyteDB | ✅ `JSON` / `JSONB` | ✅ | 同 PG | 同 PG | 继承 PG |
| SingleStore | ✅ `JSON` | ✅ (内部二进制) | 二进制 | `::$` 路径, `JSON_EXTRACT_*()` | -- |
| Vertica | ❌ (LONG VARCHAR) | ❌ | 文本 | `MAPJSONEXTRACTOR()` | Flex 表支持 JSON |
| Impala | ❌ (STRING) | ❌ | 文本 | `get_json_object()` | -- |
| StarRocks | ✅ `JSON` | ✅ (内部二进制) | 二进制 | `->`, `json_query()` | 2.2+ |
| Doris | ✅ `JSON` | ✅ (内部二进制) | 二进制 | `json_extract()` | 1.2+ |
| MonetDB | ❌ (VARCHAR) | ❌ | 文本 | `json.text()` 等 | json 模块 |
| CrateDB | ✅ `OBJECT` | ✅ (内部) | 列式 | `['key']` 下标 | 原生对象类型 |
| TimescaleDB | ✅ `JSON`/`JSONB` | ✅ | 同 PG | 同 PG | 继承 PG |
| QuestDB | ❌ | ❌ | ❌ | ❌ | 不支持 |
| Exasol | ❌ (VARCHAR) | ❌ | 文本 | `JSON_VALUE()`, `JSON_EXTRACT()` | 函数支持 |
| SAP HANA | ❌ (NCLOB) | ❌ | 文本 | `JSON_VALUE()`, `JSON_QUERY()` | 函数支持 |
| Informix | ✅ `BSON` | ✅ | 二进制 | Wire Listener API | -- |
| Firebird | ❌ | ❌ | ❌ | ❌ | 不支持原生 JSON |
| H2 | ✅ `JSON` | ❌ | 文本 | `JSON_EXTRACT()` | 2.0+ |
| HSQLDB | ❌ | ❌ | ❌ | ❌ | 不支持 |
| Derby | ❌ | ❌ | ❌ | ❌ | 不支持 |
| Amazon Athena | ✅ `JSON` | ❌ | 文本 | `json_extract()` | 继承 Trino |
| Azure Synapse | ❌ (NVARCHAR) | ❌ | 文本 | `JSON_VALUE()`, `OPENJSON()` | 同 SQL Server |
| Google Spanner | ✅ `JSON` | ✅ (内部) | 二进制 | `JSON_VALUE()`, `JSON_QUERY()` | 2022+ |
| Materialize | ✅ `JSONB` | ✅ | 二进制 | 同 PG | 兼容 PG |
| RisingWave | ✅ `JSONB` | ✅ | 二进制 | 同 PG | 兼容 PG |
| InfluxDB (SQL) | ❌ | ❌ | ❌ | ❌ | 不支持 |
| DatabendDB | ✅ `VARIANT` | ✅ (内部) | 二进制 | `:` 冒号路径, `['key']` | -- |
| Yellowbrick | ❌ | ❌ | ❌ | ❌ | 有限 JSON 函数 |
| Firebolt | ❌ | ❌ | ❌ | ❌ | 使用 ARRAY/STRUCT |

> **关键差异**：
> - **PostgreSQL** 提供 `JSON`（文本存储，保留格式）和 `JSONB`（二进制存储，去重键，支持索引），推荐使用 `JSONB`。
> - **MariaDB** 的 `JSON` 只是 `LONGTEXT` 的别名，不做验证也不做二进制优化——与 MySQL 的原生 JSON 类型有本质区别。
> - **Snowflake** 和 **DatabendDB** 使用 `VARIANT` 类型处理半结构化数据（JSON 是其子集）。
> - **ClickHouse** 24.1+ 引入的新 `JSON` 类型会将 JSON 字段自动展开为独立列存储，与传统 JSON 类型的设计理念截然不同。
> - 详见 [json-in-sql-evolution.md](json-in-sql-evolution.md) 获取更多 JSON 处理细节。

---

## 10. ARRAY / MAP / STRUCT 类型（概要）

复合集合类型的支持差异巨大，此处仅列出概要。详细对比请参阅 [array-collection-types.md](array-collection-types.md)。

| 引擎 | ARRAY | MAP | STRUCT / ROW | 版本说明 |
|------|-------|-----|-------------|---------|
| PostgreSQL | ✅ | ❌ (hstore 扩展) | ✅ `ROW` / 复合类型 | -- |
| MySQL | ❌ | ❌ | ❌ | -- |
| MariaDB | ❌ | ❌ | ❌ | -- |
| SQLite | ❌ | ❌ | ❌ | json_each() 模拟 |
| Oracle | ✅ `VARRAY` / 嵌套表 | ❌ | ✅ `OBJECT TYPE` | -- |
| SQL Server | ❌ | ❌ | ❌ | -- |
| DB2 | ✅ | ❌ | ✅ `ROW` | -- |
| Snowflake | ✅ | ✅ `OBJECT` | ✅ `OBJECT` | 通过 VARIANT 体系 |
| BigQuery | ✅ | ❌ | ✅ `STRUCT` | -- |
| Redshift | ✅ `SUPER` | ✅ `SUPER` | ✅ `SUPER` | 通过 SUPER 半结构化类型 |
| DuckDB | ✅ `LIST` | ✅ `MAP` | ✅ `STRUCT` | -- |
| ClickHouse | ✅ `Array` | ✅ `Map` | ✅ `Tuple` / `Nested` | -- |
| Trino | ✅ | ✅ | ✅ `ROW` | -- |
| Presto | ✅ | ✅ | ✅ `ROW` | -- |
| Spark SQL | ✅ | ✅ | ✅ `STRUCT` | -- |
| Hive | ✅ | ✅ | ✅ `STRUCT` | -- |
| Flink SQL | ✅ | ✅ | ✅ `ROW` | -- |
| Databricks | ✅ | ✅ | ✅ `STRUCT` | -- |

> 传统 RDBMS（MySQL、MariaDB、SQL Server、SQLite）通常不支持 ARRAY / MAP / STRUCT，需要通过 JSON 或关联表模拟。分析型引擎和大数据引擎普遍提供原生支持。完整矩阵见 [array-collection-types.md](array-collection-types.md)。

---

## 11. 跨引擎类型等价映射

以下是常见类型在主要引擎间的等价关系。`→` 表示"在该引擎中应使用此类型"。

### 整数类型等价

| 标准概念 | PostgreSQL | MySQL | Oracle | SQL Server | BigQuery | Snowflake | ClickHouse | Spark SQL |
|---------|-----------|-------|--------|-----------|---------|-----------|-----------|----------|
| 1 字节整数 | `SMALLINT` | `TINYINT` | `NUMBER(3)` | `TINYINT` | `INT64` | `NUMBER(3,0)` | `Int8` | `TINYINT` |
| 2 字节整数 | `SMALLINT` | `SMALLINT` | `NUMBER(5)` | `SMALLINT` | `INT64` | `NUMBER(5,0)` | `Int16` | `SMALLINT` |
| 4 字节整数 | `INTEGER` | `INT` | `NUMBER(10)` | `INT` | `INT64` | `NUMBER(10,0)` | `Int32` | `INT` |
| 8 字节整数 | `BIGINT` | `BIGINT` | `NUMBER(19)` | `BIGINT` | `INT64` | `NUMBER(19,0)` | `Int64` | `BIGINT` |
| 自增主键 | `SERIAL`/`GENERATED` | `AUTO_INCREMENT` | `GENERATED AS IDENTITY` | `IDENTITY` | 无原生支持 | `AUTOINCREMENT` | 无原生支持 | 无原生支持 |

### 字符串类型等价

| 标准概念 | PostgreSQL | MySQL | Oracle | SQL Server | BigQuery | ClickHouse | Spark SQL |
|---------|-----------|-------|--------|-----------|---------|-----------|----------|
| 定长字符串 | `CHAR(n)` | `CHAR(n)` | `CHAR(n)` | `CHAR(n)` | `STRING` | `FixedString(n)` | `CHAR(n)` |
| 变长字符串 | `VARCHAR(n)` | `VARCHAR(n)` | `VARCHAR2(n)` | `VARCHAR(n)` | `STRING` | `String` | `VARCHAR(n)` |
| 无限长文本 | `TEXT` | `LONGTEXT` | `CLOB` | `VARCHAR(MAX)` | `STRING` | `String` | `STRING` |
| Unicode 字符串 | `TEXT` (原生 UTF-8) | `VARCHAR(n) CHARSET utf8mb4` | `NVARCHAR2(n)` | `NVARCHAR(n)` | `STRING` (原生 UTF-8) | `String` (原生 UTF-8) | `STRING` (原生 UTF-8) |

### 日期时间类型等价

| 标准概念 | PostgreSQL | MySQL | Oracle | SQL Server | BigQuery | Snowflake | ClickHouse |
|---------|-----------|-------|--------|-----------|---------|-----------|-----------|
| 纯日期 | `DATE` | `DATE` | `DATE` (含时间!) | `DATE` | `DATE` | `DATE` | `Date` / `Date32` |
| 纯时间 | `TIME` | `TIME` | ❌ | `TIME` | `TIME` | `TIME` | ❌ |
| 不含时区时间戳 | `TIMESTAMP` | `DATETIME` | `TIMESTAMP` | `DATETIME2` | `DATETIME` | `TIMESTAMP_NTZ` | `DateTime` |
| 含时区时间戳 | `TIMESTAMPTZ` | ❌ (TIMESTAMP 部分等价) | `TIMESTAMP WITH TIME ZONE` | `DATETIMEOFFSET` | `TIMESTAMP` | `TIMESTAMP_TZ` | `DateTime64(p, tz)` |

### 二进制/大对象等价

| 标准概念 | PostgreSQL | MySQL | Oracle | SQL Server | BigQuery | ClickHouse |
|---------|-----------|-------|--------|-----------|---------|-----------|
| 变长二进制 | `BYTEA` | `VARBINARY(n)` | `RAW(n)` | `VARBINARY(n)` | `BYTES` | `String` |
| 大二进制对象 | `BYTEA` | `LONGBLOB` | `BLOB` | `VARBINARY(MAX)` | `BYTES` | `String` |

---

## 12. 类型转换 / 类型强制 (Type Casting)

不同引擎提供不同的类型转换语法。

### 转换语法对比

| 语法形式 | 示例 | 支持引擎 |
|---------|------|---------|
| `CAST(expr AS type)` | `CAST('123' AS INT)` | 所有引擎（SQL 标准） |
| `::` 操作符 | `'123'::INT` | PostgreSQL, Redshift, DuckDB, CockroachDB, YugabyteDB, Greenplum, TimescaleDB, Materialize, RisingWave, Databricks (3.4+) |
| `CONVERT(type, expr)` | `CONVERT(INT, '123')` | SQL Server, Azure Synapse |
| `CONVERT(expr, type)` | `CONVERT('123', INT)` | MySQL, MariaDB, TiDB, SingleStore |
| `TRY_CAST(expr AS type)` | `TRY_CAST('abc' AS INT)` → NULL | SQL Server, Trino, Databricks, DuckDB, Snowflake, Azure Synapse |
| `SAFE_CAST(expr AS type)` | `SAFE_CAST('abc' AS INT64)` → NULL | BigQuery |
| `TRY_CONVERT(type, expr)` | `TRY_CONVERT(INT, 'abc')` → NULL | SQL Server, Azure Synapse |
| `type(expr)` 函数式 | `INT('123')`, `toInt32('123')` | ClickHouse, DatabendDB |
| `expr::type` + `TRY` | `TRY '123'::INT` | CockroachDB |

### CAST 语法示例

```sql
-- SQL 标准 CAST（所有引擎通用）
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST(price AS DECIMAL(10,2));

-- PostgreSQL / Redshift / DuckDB :: 语法
SELECT '2024-01-15'::DATE;
SELECT price::DECIMAL(10,2);
SELECT '{"a":1}'::JSONB;

-- SQL Server CONVERT（参数顺序：目标类型, 表达式 [, 样式]）
SELECT CONVERT(DATE, '2024-01-15');
SELECT CONVERT(VARCHAR, GETDATE(), 120);  -- 样式 120 = ODBC 标准格式

-- MySQL CONVERT（参数顺序：表达式, 目标类型）
SELECT CONVERT('123', SIGNED INTEGER);
SELECT CONVERT('2024-01-15', DATE);

-- ClickHouse 函数式转换
SELECT toInt32('123');
SELECT toDate('2024-01-15');
SELECT toDecimal64(price, 2);

-- BigQuery SAFE_CAST（失败返回 NULL，不报错）
SELECT SAFE_CAST('abc' AS INT64);      -- 返回 NULL
SELECT SAFE_CAST('123' AS INT64);      -- 返回 123

-- Trino / Databricks / DuckDB / Snowflake TRY_CAST
SELECT TRY_CAST('abc' AS INTEGER);     -- 返回 NULL
```

### 隐式转换严格度光谱

```
严格 ◄━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━► 宽松

Trino    PostgreSQL    BigQuery    Oracle    SQL Server    MySQL    SQLite
DuckDB   CockroachDB   Snowflake   DB2       Spark SQL     MariaDB
                                   Hive      ClickHouse    TiDB
```

> 详细的隐式/显式类型转换矩阵请参阅 [implicit-explicit-type-conversion.md](implicit-explicit-type-conversion.md)。

---

## 13. 关键发现 / 关键差异总结

### 类型系统设计哲学差异

1. **Oracle 无原生整数**：所有整数类型都是 `NUMBER(38)` 的别名。`INT` 列可以存入 `3.14`，不会报错。这在从 Oracle 迁移到严格类型引擎时是重大陷阱。

2. **SQLite 动态类型**：声明类型仅影响"亲和性"（affinity），不强制执行。`CREATE TABLE t(x INT)` 后执行 `INSERT INTO t VALUES('hello')` 完全合法。

3. **MySQL BOOLEAN 陷阱**：`BOOLEAN` 是 `TINYINT(1)` 的别名，因此布尔列可以存储 0-255 的任何整数。`WHERE bool_col = TRUE` 只匹配 `1`，不匹配 `2`、`3` 等非零值。正确写法是 `WHERE bool_col != 0` 或 `WHERE bool_col IS TRUE`（MySQL 8.0.16+）。

4. **FLOAT 含义歧义**：`FLOAT` 在 PostgreSQL / Redshift 中是 8 字节（=DOUBLE），在 MySQL / Spark SQL 中是 4 字节。跨库迁移时务必显式指定 `REAL`（4B）或 `DOUBLE PRECISION`（8B）。

### 迁移陷阱 Top 5

| 排名 | 陷阱 | 影响引擎 | 后果 |
|------|------|---------|------|
| 1 | Oracle `DATE` 含时间 | Oracle → PostgreSQL/MySQL | 时间信息丢失 |
| 2 | MySQL `TIMESTAMP` 范围限制 | MySQL → 其他引擎 | 2038 年溢出 |
| 3 | Snowflake 整数全为 NUMBER(38,0) | Snowflake → 严格类型引擎 | 精度/范围不匹配 |
| 4 | BigQuery TIMESTAMP vs DATETIME | BigQuery ↔ 多数引擎 | 时区语义反转 |
| 5 | VARCHAR 长度单位（字节 vs 字符） | Oracle/MySQL ↔ PostgreSQL | 多字节字符截断 |

### VARCHAR 长度：字节 vs 字符

不同引擎对 `VARCHAR(n)` 中 `n` 的含义不同，在多字节字符集（UTF-8、UTF-16）下影响巨大：

| 引擎 | `VARCHAR(n)` 的 n 含义 | 可选切换 | 示例 |
|------|----------------------|---------|------|
| PostgreSQL | **字符** | -- | `VARCHAR(10)` 可存 10 个中文字符 |
| MySQL | **字符** | -- | `VARCHAR(10)` 可存 10 个中文字符（但行总字节受限 65535） |
| Oracle | **字节**（默认） | `VARCHAR2(10 CHAR)` 切换为字符 | 默认 `VARCHAR2(10)` 仅存 3 个 UTF-8 中文字符 |
| SQL Server | **字符** (VARCHAR) / **字符** (NVARCHAR) | -- | `NVARCHAR` 用 UTF-16，每字符 2 字节 |
| Snowflake | **字符** | -- | `VARCHAR(10)` 可存 10 个任意字符 |
| BigQuery | N/A | -- | `STRING` 无长度限制 |
| ClickHouse | N/A | -- | `String` 无长度限制 |
| Redshift | **字节** | -- | `VARCHAR(10)` 仅存约 3 个 UTF-8 中文字符 |

```sql
-- Oracle: 字节与字符语义对比
CREATE TABLE t1 (name VARCHAR2(10));           -- 10 字节，最多 3 个 UTF-8 中文字符
CREATE TABLE t2 (name VARCHAR2(10 CHAR));      -- 10 字符，可存 10 个中文字符

-- 查看当前默认语义
SELECT value FROM nls_session_parameters WHERE parameter = 'NLS_LENGTH_SEMANTICS';

-- 全局设置字符语义（ALTER SYSTEM 级别）
ALTER SYSTEM SET NLS_LENGTH_SEMANTICS = 'CHAR';
```

### 特殊类型别名汇总

各引擎提供了大量非标准的类型别名。以下是主要引擎中容易混淆的别名关系：

| 引擎 | 别名 | 实际类型 | 说明 |
|------|------|---------|------|
| PostgreSQL | `SERIAL` | `INTEGER` + 序列 + `NOT NULL` | 不是真正的数据类型，是 DDL 宏 |
| PostgreSQL | `INT4` | `INTEGER` | 系统内部名 |
| PostgreSQL | `INT8` | `BIGINT` | 系统内部名 |
| PostgreSQL | `FLOAT4` | `REAL` | 系统内部名 |
| PostgreSQL | `FLOAT8` | `DOUBLE PRECISION` | 系统内部名 |
| PostgreSQL | `BOOL` | `BOOLEAN` | 标准别名 |
| MySQL | `BOOLEAN` / `BOOL` | `TINYINT(1)` | 不是真正的布尔类型 |
| MySQL | `INT` | `INTEGER` | 标准别名 |
| MySQL | `MEDIUMINT` | 3 字节整数 | MySQL 独有（范围 -8388608 ~ 8388607） |
| MySQL | `MEDIUMTEXT` | 16 MB 文本 | MySQL 独有（TEXT/MEDIUMTEXT/LONGTEXT 三级） |
| Oracle | `INT` / `INTEGER` | `NUMBER(38)` | 无原生整数 |
| Oracle | `FLOAT(p)` | `NUMBER` 子集 | p 是二进制位数，非十进制 |
| Oracle | `LONG` | 旧版大文本 | 已废弃，应使用 CLOB |
| SQL Server | `MONEY` | 8 字节定点 | 精度固定为 4 位小数 |
| SQL Server | `SMALLMONEY` | 4 字节定点 | 精度固定为 4 位小数 |
| SQL Server | `NTEXT` | Unicode 大文本 | 已废弃，使用 `NVARCHAR(MAX)` |
| SQL Server | `IMAGE` | 二进制大对象 | 已废弃，使用 `VARBINARY(MAX)` |
| Snowflake | `FLOAT` / `FLOAT4` / `FLOAT8` / `REAL` | `DOUBLE` (8B) | 全部映射到 DOUBLE |
| Snowflake | `INT` / `INTEGER` / `BIGINT` / `SMALLINT` / `TINYINT` | `NUMBER(38,0)` | 全部映射到 NUMBER |
| ClickHouse | `TINYINT` | `Int8` | 兼容别名 |
| ClickHouse | `INT` | `Int32` | 兼容别名 |
| ClickHouse | `BIGINT` | `Int64` | 兼容别名 |
| Teradata | `BYTEINT` | 1 字节整数 | Teradata 独有名称 |
| Informix | `INT8` | 8 字节整数 | Informix 独有名称（不是 PG 的 INT8） |
| Informix | `SMALLFLOAT` | 4 字节浮点 | Informix 独有名称 |
| DuckDB | `HUGEINT` | 16 字节整数 | DuckDB 独有名称 |
| DuckDB | `UTINYINT` / `USMALLINT` / `UINTEGER` / `UBIGINT` | 无符号整数 | DuckDB 独有的无符号整数 |
| StarRocks / Doris | `LARGEINT` | 16 字节整数 | StarRocks / Doris 独有名称 |
| Vertica | `INT` | 8 字节整数 | 注意：Vertica 的 INT 是 8 字节！ |

### 类型名称标准化建议

为最大化可移植性，建议使用以下类型名称：

```
推荐类型名称           避免使用                原因
──────────────────    ──────────────────     ──────────────────
INTEGER               INT                    INT 在部分引擎中非标准
BIGINT                INT8, Int64, long      引擎专有名称
DECIMAL(p,s)          NUMBER(p,s)            NUMBER 是 Oracle 专有
DOUBLE PRECISION      FLOAT8, Float64        FLOAT 含义歧义
VARCHAR(n)            STRING, TEXT           STRING/TEXT 不是标准类型
BOOLEAN               BOOL, BIT             BIT 语义不同
TIMESTAMP             DATETIME               DATETIME 语义因引擎而异
```

### 跨库迁移类型映射速查

从源引擎迁移到目标引擎时，以下类型需要特别注意转换：

```sql
-- MySQL → PostgreSQL
--   TINYINT          → SMALLINT (PG 无 TINYINT)
--   TINYINT(1)       → BOOLEAN
--   DATETIME         → TIMESTAMP
--   TIMESTAMP        → TIMESTAMPTZ
--   LONGTEXT         → TEXT
--   LONGBLOB         → BYTEA
--   ENUM('a','b')    → VARCHAR + CHECK 约束
--   SET('a','b')     → VARCHAR[] 或 TEXT + CHECK 约束
--   AUTO_INCREMENT   → GENERATED ALWAYS AS IDENTITY

-- Oracle → PostgreSQL
--   NUMBER(p,s)      → NUMERIC(p,s)
--   NUMBER (无参数)   → NUMERIC 或 DOUBLE PRECISION（视业务而定）
--   DATE             → TIMESTAMP（保留时间部分！）
--   VARCHAR2(n)      → VARCHAR(n)
--   CLOB             → TEXT
--   BLOB             → BYTEA
--   RAW(n)           → BYTEA

-- SQL Server → PostgreSQL
--   DATETIME         → TIMESTAMP（注意精度：DATETIME 是 3.33ms）
--   DATETIME2        → TIMESTAMP
--   DATETIMEOFFSET   → TIMESTAMPTZ
--   NVARCHAR(n)      → VARCHAR(n)（PG 原生 UTF-8）
--   NVARCHAR(MAX)    → TEXT
--   VARBINARY(MAX)   → BYTEA
--   BIT              → BOOLEAN
--   UNIQUEIDENTIFIER → UUID
--   MONEY            → NUMERIC(19,4)

-- BigQuery → PostgreSQL
--   INT64            → BIGINT
--   FLOAT64          → DOUBLE PRECISION
--   STRING           → TEXT
--   BYTES            → BYTEA
--   DATETIME         → TIMESTAMP (无时区)
--   TIMESTAMP        → TIMESTAMPTZ (含时区!)
--   BOOL             → BOOLEAN
--   STRUCT           → ROW / JSON
```

---

## 参考资料

- [SQL:2016 标准 (ISO/IEC 9075-2:2016)](https://www.iso.org/standard/63556.html) - SQL 标准类型系统定义
- [PostgreSQL Data Types](https://www.postgresql.org/docs/current/datatype.html) - PostgreSQL 17 类型文档
- [MySQL Data Types](https://dev.mysql.com/doc/refman/8.0/en/data-types.html) - MySQL 8.0 类型文档
- [Oracle Built-In Data Types](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Data-Types.html) - Oracle 23c 类型文档
- [SQL Server Data Types](https://learn.microsoft.com/en-us/sql/t-sql/data-types/data-types-transact-sql) - SQL Server 2022 类型文档
- [BigQuery Data Types](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types) - BigQuery 标准 SQL 类型
- [Snowflake Data Types](https://docs.snowflake.com/en/sql-reference/data-types) - Snowflake 类型文档
- [ClickHouse Data Types](https://clickhouse.com/docs/en/sql-reference/data-types) - ClickHouse 类型文档
- [Trino Data Types](https://trino.io/docs/current/language/types.html) - Trino 类型文档
- [DuckDB Data Types](https://duckdb.org/docs/sql/data_types/overview.html) - DuckDB 类型文档
- [Spark SQL Data Types](https://spark.apache.org/docs/latest/sql-ref-datatypes.html) - Spark SQL 类型文档
