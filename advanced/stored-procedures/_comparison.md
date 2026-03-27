# 存储过程 (Stored Procedures) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| CREATE PROCEDURE | ✅ | ✅ 11+ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CREATE FUNCTION | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CREATE OR REPLACE | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ 10.1.3+ | ✅ | ✅ | ✅ |
| 过程式语言 | SQL/PSM | PL/pgSQL | ❌ | PL/SQL | T-SQL | SQL/PSM | PSQL | SQL PL | SQLScript |
| IN/OUT/INOUT 参数 | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 游标 | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 异常处理 | ✅ HANDLER | ✅ EXCEPTION | ❌ | ✅ EXCEPTION | ✅ TRY/CATCH | ✅ HANDLER | ✅ EXCEPTION | ✅ HANDLER | ✅ EXCEPTION |
| 表值函数 | ❌ | ✅ RETURNS TABLE | ❌ | ✅ 管道 | ✅ | ❌ | ✅ Selectable | ✅ | ✅ |
| 外部语言 | ❌ | ✅ Python/C/Java | ✅ App UDF | ✅ Java | ✅ CLR | ❌ | ❌ | ✅ Java | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 存储过程 | ⚠️ Scripting | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ PL/pgSQL | ❌ | ❌ | ❌ | ❌ |
| UDF (SQL) | ✅ | ✅ | ✅ | ❌ | ✅ Lambda | ❌ | ✅ 420+ | ✅ | ❌ | ✅ MACRO | ✅ | ❌ |
| UDF (Java) | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| UDF (Python) | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ API | ✅ API | ✅ |
| UDF (JavaScript) | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| 存储过程 | ✅ PL/pgSQL | ✅ T-SQL | ❌ | ✅ PL/pgSQL | ❌ | ✅ PLvSQL | ✅ SPL |
| UDF (SQL) | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| UDF (外部语言) | ✅ Python | ✅ | ✅ Python | ✅ Python/C | ✅ C++/Java | ✅ C++/Java/R | ✅ C/Java |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| 存储过程 | ⚠️ 有限 | ✅ | ✅ PL/pgSQL | ❌ | ✅ PL/pgSQL | ✅ | ✅ PL/pgSQL | ✅ | ✅ PL/SQL | ✅ PL/pgSQL |
| 游标 | ⚠️ 有限 | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 异常处理 | ⚠️ 有限 | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| 存储过程 | ✅ PL/pgSQL | ❌ | ❌ | ❌ | ⚠️ Java | ✅ Java |
| UDF | ✅ | ✅ C 3.0+ | ✅ Java | ❌ | ✅ Java | ✅ Java |

## 关键差异

- **SQLite** 完全不支持存储过程，需通过宿主语言（Python/C）实现
- **大数据引擎**（Hive/ClickHouse/Spark/Flink/Doris/StarRocks）大多不支持存储过程，通过 UDF 扩展
- **Snowflake** 存储过程支持最多语言：SQL, JavaScript, Python, Java, Scala
- **BigQuery** 通过 Scripting（脚本模式）和 SQL UDF 替代存储过程
- **ClickHouse** UDF 使用 Lambda 风格（CREATE FUNCTION ... AS (x) -> ...）
- **DuckDB** 使用 MACRO 替代 UDF/函数
- **PostgreSQL** 支持多种过程式语言（PL/pgSQL, PL/Python, PL/Perl 等）
- **TiDB** 存储过程支持有限，复杂逻辑建议在应用层实现
- **Spanner** 完全不支持存储过程和 UDF
- **Oracle PL/SQL** vs **SQL Server T-SQL** 是两大最成熟的过程式语言
