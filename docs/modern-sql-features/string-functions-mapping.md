# 字符串函数映射 (String Functions Mapping)

> 参考资料:
> - [SQL:1992 标准 (ISO/IEC 9075:1992)](https://www.iso.org/standard/16663.html)
> - [SQL:2003 标准 (ISO/IEC 9075-2:2003)](https://www.iso.org/standard/34133.html)
> - [PostgreSQL - String Functions](https://www.postgresql.org/docs/current/functions-string.html)
> - [MySQL 8.0 - String Functions](https://dev.mysql.com/doc/refman/8.0/en/string-functions.html)
> - [SQL Server - String Functions](https://learn.microsoft.com/en-us/sql/t-sql/functions/string-functions-transact-sql)
> - [Oracle - Character Functions](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Single-Row-Functions.html)
> - [Snowflake - String & Binary Functions](https://docs.snowflake.com/en/sql-reference/functions-string)
> - [BigQuery - String Functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/string_functions)

字符串处理是 SQL 跨引擎迁移中最高频的兼容性问题来源。与日期函数不同，字符串函数的差异不仅体现在**函数名称**上（`LENGTH` vs `LEN` vs `CHAR_LENGTH`），还体现在**语义细节**上——同名的 `SUBSTRING` 在某些引擎中基于 1 的索引，在另一些中基于 0；`CONCAT` 对 NULL 的处理在不同引擎中可能返回 NULL 或忽略 NULL。这些差异使得"看起来正确"的迁移往往在生产环境中产生静默错误。

本文覆盖 49 个 SQL 引擎的 14 类字符串函数，提供完整的名称映射和语义差异对照。

---

## SQL 标准中的字符串函数

SQL:1992 标准（ISO/IEC 9075）定义了以下核心字符串操作：

| 标准函数 | 语法 | 语义 |
|---------|------|------|
| `CHARACTER_LENGTH` | `CHARACTER_LENGTH(string)` | 返回字符数（非字节数） |
| `OCTET_LENGTH` | `OCTET_LENGTH(string)` | 返回字节数 |
| `SUBSTRING` | `SUBSTRING(string FROM start [FOR length])` | 提取子串，基于 1 的索引 |
| `\|\|` | `string1 \|\| string2` | 连接运算符 |
| `UPPER` | `UPPER(string)` | 转大写 |
| `LOWER` | `LOWER(string)` | 转小写 |
| `TRIM` | `TRIM([LEADING\|TRAILING\|BOTH] char FROM string)` | 去除指定字符 |
| `POSITION` | `POSITION(substring IN string)` | 查找子串位置，基于 1 |
| `OVERLAY` | `OVERLAY(string PLACING new FROM start [FOR length])` | 替换子串 |

SQL:2003 标准新增：

| 标准函数 | 语法 | 语义 |
|---------|------|------|
| `CHAR_LENGTH` | `CHAR_LENGTH(string)` | `CHARACTER_LENGTH` 的简写 |
| `NORMALIZE` | `NORMALIZE(string)` | Unicode 正规化 |

值得注意的是，许多常用函数如 `REPLACE`、`LPAD`、`RPAD`、`LEFT`、`RIGHT`、`CONCAT` 等并**不在 SQL 标准中**，而是各引擎自行实现的扩展，这也是差异产生的根源。

---

## 1. 字符串长度 (LENGTH / LEN / CHAR_LENGTH)

> **迁移陷阱**: `LENGTH` 在 Oracle 中返回字符数，在某些引擎中返回字节数；SQL Server 使用 `LEN` 且会忽略尾部空格。

### 支持矩阵

| 引擎 | LENGTH | LEN | CHAR_LENGTH | CHARACTER_LENGTH | OCTET_LENGTH | DATALENGTH | 版本 |
|------|--------|-----|-------------|-----------------|-------------|------------|------|
| PostgreSQL | 是(字符) | -- | 是 | 是 | 是(字节) | -- | 7.1+ |
| MySQL | 是(字节) | -- | 是(字符) | 是(字符) | 是(字节) | -- | 3.23+ |
| MariaDB | 是(字节) | -- | 是(字符) | 是(字符) | 是(字节) | -- | 5.1+ |
| SQLite | 是(字符) | -- | -- | -- | -- | -- | 3.0+ |
| Oracle | 是(字符) | -- | -- | -- | -- | -- | 7+ |
| SQL Server | -- | 是 | -- | -- | -- | 是(字节) | 2000+ |
| DB2 | 是(字符) | -- | 是 | 是 | 是 | -- | 9.1+ |
| Snowflake | 是(字符) | 是 | 是 | 是 | -- | -- | GA |
| BigQuery | 是(字符) | -- | 是 | 是 | 是(字节) | -- | GA |
| Redshift | 是(字符) | 是 | 是 | 是 | 是(字节) | -- | GA |
| DuckDB | 是(字符) | -- | 是 | 是 | 是(字节) | -- | 0.3+ |
| ClickHouse | 是(字节) | -- | 是(字符) | 是(字符) | -- | -- | 18.1+ |
| Trino | 是(字符) | -- | 是 | 是 | -- | -- | 早期 |
| Presto | 是(字符) | -- | 是 | 是 | -- | -- | 0.57+ |
| Spark SQL | 是(字符) | -- | 是 | 是 | 是(字节) | -- | 1.5+ |
| Hive | 是(字符) | -- | 是 | 是 | -- | -- | 0.7+ |
| Flink SQL | 是(字符) | -- | 是 | 是 | -- | -- | 1.12+ |
| Databricks | 是(字符) | 是 | 是 | 是 | 是(字节) | -- | GA |
| Teradata | -- | -- | 是 | 是 | -- | -- | V2R5+ |
| Greenplum | 是(字符) | -- | 是 | 是 | 是(字节) | -- | 继承 PG |
| CockroachDB | 是(字符) | -- | 是 | 是 | 是(字节) | -- | 1.0+ |
| TiDB | 是(字节) | -- | 是(字符) | 是(字符) | 是(字节) | -- | 2.0+ |
| OceanBase | 是 | -- | 是 | 是 | 是 | -- | 1.0+ |
| YugabyteDB | 是(字符) | -- | 是 | 是 | 是(字节) | -- | 2.0+ |
| SingleStore | 是(字节) | -- | 是(字符) | 是(字符) | 是(字节) | -- | 7.0+ |
| Vertica | 是(字节) | -- | 是(字符) | 是(字符) | 是(字节) | -- | 9.0+ |
| Impala | 是(字符) | -- | 是 | 是 | -- | -- | 2.0+ |
| StarRocks | 是(字节) | -- | 是(字符) | 是(字符) | -- | -- | 1.0+ |
| Doris | 是(字节) | -- | 是(字符) | 是(字符) | -- | -- | 0.15+ |
| MonetDB | 是(字符) | -- | 是 | 是 | 是 | -- | Jun2020+ |
| CrateDB | 是(字符) | -- | 是 | 是 | -- | -- | 3.0+ |
| TimescaleDB | 是(字符) | -- | 是 | 是 | 是(字节) | -- | 继承 PG |
| QuestDB | 是(字符) | -- | -- | -- | -- | -- | 6.0+ |
| Exasol | 是(字符) | -- | 是 | 是 | 是(字节) | -- | 6.0+ |
| SAP HANA | 是(字符) | -- | 是 | 是 | 是(字节) | -- | 1.0+ |
| Informix | 是(字符) | -- | 是 | 是 | -- | -- | 11.50+ |
| Firebird | 是(字符) | -- | 是 | 是 | 是(字节) | -- | 2.0+ |
| H2 | 是(字符) | -- | 是 | 是 | 是(字节) | -- | 1.0+ |
| HSQLDB | 是(字符) | -- | 是 | 是 | 是(字节) | -- | 2.0+ |
| Derby | -- | -- | -- | -- | -- | -- | LENGTH 函数不同 |
| Amazon Athena | 是(字符) | -- | 是 | 是 | -- | -- | 继承 Trino |
| Azure Synapse | -- | 是 | -- | -- | -- | 是(字节) | GA |
| Google Spanner | 是(字符) | -- | 是 | 是 | -- | -- | GA |
| Materialize | 是(字符) | -- | 是 | 是 | 是(字节) | -- | 继承 PG |
| RisingWave | 是(字符) | -- | 是 | 是 | 是(字节) | -- | 1.0+ |
| InfluxDB (SQL) | 是(字符) | -- | -- | -- | -- | -- | 3.0+ |
| DatabendDB | 是(字符) | -- | 是 | 是 | 是(字节) | -- | GA |
| Yellowbrick | 是(字符) | -- | 是 | 是 | 是(字节) | -- | GA |
| Firebolt | 是(字符) | -- | 是 | 是 | 是(字节) | -- | GA |

> **关键差异**: MySQL/MariaDB/TiDB/SingleStore/StarRocks/Doris/ClickHouse/Vertica 中 `LENGTH()` 返回**字节数**而非字符数。多字节字符（如中文 UTF-8）会导致结果不同。要获取字符数需使用 `CHAR_LENGTH()`。SQL Server/Azure Synapse 不支持 `LENGTH`，需使用 `LEN`，且 `LEN` 会忽略尾部空格。

### 等价语法速查

```sql
-- 获取字符数（所有引擎通用写法）
-- PostgreSQL / SQLite / Oracle / DuckDB / Trino / BigQuery
SELECT LENGTH('Hello世界');          -- 7

-- MySQL / MariaDB / TiDB / ClickHouse（LENGTH 返回字节数！）
SELECT CHAR_LENGTH('Hello世界');     -- 7（正确）
SELECT LENGTH('Hello世界');          -- 11（UTF-8 字节数，非字符数！）

-- SQL Server / Azure Synapse
SELECT LEN('Hello世界');             -- 7

-- Derby
SELECT LENGTH(CAST('Hello' AS VARCHAR(100)));
```

---

## 2. 子串提取 (SUBSTRING / SUBSTR / MID)

> **迁移陷阱**: SQL 标准 `SUBSTRING` 使用 `FROM ... FOR` 语法，但多数引擎同时支持逗号分隔参数。Oracle 的 `SUBSTR` 当 start 为负数时从末尾计算。

### 支持矩阵

| 引擎 | SUBSTRING(s,pos,len) | SUBSTRING(s FROM pos FOR len) | SUBSTR | MID | 版本 |
|------|---------------------|------------------------------|--------|-----|------|
| PostgreSQL | 是 | 是 | 是 | -- | 7.1+ |
| MySQL | 是 | 是 | 是 | 是 | 3.23+ |
| MariaDB | 是 | 是 | 是 | 是 | 5.1+ |
| SQLite | 是 | -- | 是 | -- | 3.0+ |
| Oracle | -- | -- | 是 | -- | 7+ |
| SQL Server | 是 | -- | -- | -- | 2000+ |
| DB2 | 是 | 是 | 是 | -- | 9.1+ |
| Snowflake | 是 | -- | 是 | -- | GA |
| BigQuery | 是 | -- | 是 | -- | GA |
| Redshift | 是 | 是 | 是 | -- | GA |
| DuckDB | 是 | 是 | 是 | -- | 0.3+ |
| ClickHouse | 是 | -- | 是 | -- | 18.1+ |
| Trino | 是 | 是 | 是 | -- | 早期 |
| Presto | 是 | 是 | 是 | -- | 0.57+ |
| Spark SQL | 是 | -- | 是 | -- | 1.0+ |
| Hive | 是 | -- | 是 | -- | 0.7+ |
| Flink SQL | 是 | 是 | -- | -- | 1.12+ |
| Databricks | 是 | -- | 是 | -- | GA |
| Teradata | 是 | -- | 是 | -- | V2R5+ |
| Greenplum | 是 | 是 | 是 | -- | 继承 PG |
| CockroachDB | 是 | 是 | 是 | -- | 1.0+ |
| TiDB | 是 | 是 | 是 | 是 | 2.0+ |
| OceanBase | 是 | -- | 是 | -- | 1.0+ |
| YugabyteDB | 是 | 是 | 是 | -- | 2.0+ |
| SingleStore | 是 | 是 | 是 | 是 | 7.0+ |
| Vertica | 是 | -- | 是 | -- | 9.0+ |
| Impala | 是 | -- | 是 | -- | 2.0+ |
| StarRocks | 是 | -- | 是 | -- | 1.0+ |
| Doris | 是 | -- | 是 | -- | 0.15+ |
| MonetDB | 是 | 是 | 是 | -- | Jun2020+ |
| CrateDB | 是 | 是 | 是 | -- | 3.0+ |
| TimescaleDB | 是 | 是 | 是 | -- | 继承 PG |
| QuestDB | 是 | -- | -- | -- | 6.0+ |
| Exasol | 是 | -- | 是 | -- | 6.0+ |
| SAP HANA | 是 | -- | 是 | -- | 1.0+ |
| Informix | 是 | -- | 是 | -- | 11.50+ |
| Firebird | 是 | 是 | -- | -- | 2.0+ |
| H2 | 是 | 是 | 是 | -- | 1.0+ |
| HSQLDB | 是 | 是 | 是 | -- | 2.0+ |
| Derby | 是 | -- | -- | -- | 10.0+ |
| Amazon Athena | 是 | 是 | 是 | -- | 继承 Trino |
| Azure Synapse | 是 | -- | -- | -- | GA |
| Google Spanner | 是 | -- | 是 | -- | GA |
| Materialize | 是 | 是 | 是 | -- | 继承 PG |
| RisingWave | 是 | 是 | 是 | -- | 1.0+ |
| InfluxDB (SQL) | 是 | -- | -- | -- | 3.0+ |
| DatabendDB | 是 | -- | 是 | -- | GA |
| Yellowbrick | 是 | 是 | 是 | -- | GA |
| Firebolt | 是 | -- | 是 | -- | GA |

### Oracle SUBSTR 负索引行为

```sql
-- Oracle: 负数 start 从末尾计算
SELECT SUBSTR('Hello World', -5, 5) FROM DUAL;  -- 'World'

-- 等价于其他引擎:
-- PostgreSQL / MySQL / Snowflake / BigQuery
SELECT RIGHT('Hello World', 5);                  -- 'World'
SELECT SUBSTRING('Hello World', LENGTH('Hello World') - 4, 5);  -- 'World'

-- SQL Server
SELECT RIGHT('Hello World', 5);                  -- 'World'
```

---

## 3. 字符串连接 (|| / CONCAT / + / CONCAT_WS)

> **迁移陷阱**: `||` 是 SQL 标准运算符，但 SQL Server/MySQL 默认不支持（MySQL 需 `SET sql_mode='PIPES_AS_CONCAT'`）。`CONCAT` 对 NULL 的处理在各引擎间有本质差异。

### 支持矩阵

| 引擎 | `\|\|` 运算符 | CONCAT(a,b,...) | `+` 运算符 | CONCAT_WS | 版本 |
|------|-------------|----------------|-----------|-----------|------|
| PostgreSQL | 是 | 是 | -- | 是 | 7.1+ |
| MySQL | 可选(PIPES_AS_CONCAT) | 是(忽略NULL) | -- | 是 | 4.0+ |
| MariaDB | 可选(PIPES_AS_CONCAT) | 是(忽略NULL) | -- | 是 | 5.1+ |
| SQLite | 是 | -- | -- | -- | 3.0+ |
| Oracle | 是 | 是(仅2参) | -- | -- | 7+ |
| SQL Server | -- | 是 | 是 | 是 | 2012+(CONCAT) |
| DB2 | 是 | 是 | -- | -- | 9.1+ |
| Snowflake | 是 | 是 | -- | 是 | GA |
| BigQuery | 是 | 是 | -- | -- | GA |
| Redshift | 是 | 是 | -- | -- | GA |
| DuckDB | 是 | 是 | -- | 是 | 0.3+ |
| ClickHouse | 是 | 是 | -- | -- | 18.1+ |
| Trino | 是 | 是 | -- | -- | 早期 |
| Presto | 是 | 是 | -- | -- | 0.57+ |
| Spark SQL | 是 | 是 | -- | 是 | 1.0+ |
| Hive | 是 | 是 | -- | 是 | 0.7+ |
| Flink SQL | 是 | 是 | -- | 是 | 1.12+ |
| Databricks | 是 | 是 | -- | 是 | GA |
| Teradata | 是 | -- | -- | -- | V2R5+ |
| Greenplum | 是 | 是 | -- | 是 | 继承 PG |
| CockroachDB | 是 | 是 | -- | 是 | 1.0+ |
| TiDB | 可选 | 是(忽略NULL) | -- | 是 | 2.0+ |
| OceanBase | 是 | 是 | -- | 是 | 1.0+ |
| YugabyteDB | 是 | 是 | -- | 是 | 2.0+ |
| SingleStore | 可选 | 是(忽略NULL) | -- | 是 | 7.0+ |
| Vertica | 是 | 是 | -- | -- | 9.0+ |
| Impala | 是 | 是 | -- | 是 | 2.0+ |
| StarRocks | 是 | 是 | -- | 是 | 1.0+ |
| Doris | 是 | 是 | -- | 是 | 0.15+ |
| MonetDB | 是 | 是 | -- | -- | Jun2020+ |
| CrateDB | 是 | 是 | -- | -- | 3.0+ |
| TimescaleDB | 是 | 是 | -- | 是 | 继承 PG |
| QuestDB | 是 | 是 | -- | -- | 6.0+ |
| Exasol | 是 | 是 | -- | -- | 6.0+ |
| SAP HANA | 是 | 是 | -- | 是 | 1.0+ |
| Informix | 是 | -- | -- | -- | 11.50+ |
| Firebird | 是 | -- | -- | -- | 2.0+ |
| H2 | 是 | 是 | -- | 是 | 1.0+ |
| HSQLDB | 是 | 是 | -- | -- | 2.0+ |
| Derby | 是 | -- | -- | -- | 10.0+ |
| Amazon Athena | 是 | 是 | -- | -- | 继承 Trino |
| Azure Synapse | -- | 是 | 是 | 是 | GA |
| Google Spanner | 是 | 是 | -- | -- | GA |
| Materialize | 是 | 是 | -- | 是 | 继承 PG |
| RisingWave | 是 | 是 | -- | 是 | 1.0+ |
| InfluxDB (SQL) | 是 | -- | -- | -- | 3.0+ |
| DatabendDB | 是 | 是 | -- | 是 | GA |
| Yellowbrick | 是 | 是 | -- | 是 | GA |
| Firebolt | 是 | 是 | -- | 是 | GA |

### NULL 处理差异（关键！）

```sql
-- PostgreSQL / Oracle / DB2 / SQLite: || 遇 NULL 结果为 NULL
SELECT 'Hello' || NULL || 'World';      -- NULL

-- MySQL / MariaDB / TiDB: CONCAT 遇 NULL 结果为 NULL
SELECT CONCAT('Hello', NULL, 'World');   -- NULL

-- SQL Server: + 遇 NULL 结果为 NULL（默认）
SELECT 'Hello' + NULL + 'World';         -- NULL

-- SQL Server / PostgreSQL: CONCAT 忽略 NULL
SELECT CONCAT('Hello', NULL, 'World');   -- 'HelloWorld'

-- MySQL 的 CONCAT_WS 忽略 NULL 参数（但不忽略分隔符）
SELECT CONCAT_WS(',', 'a', NULL, 'b');  -- 'a,b'

-- Snowflake: || 和 CONCAT 遇 NULL 结果为 NULL
SELECT 'Hello' || NULL;                  -- NULL
SELECT CONCAT('Hello', NULL);            -- NULL
```

> **最佳实践**: 跨引擎迁移时，使用 `COALESCE` 显式处理 NULL 以确保一致行为：`CONCAT(COALESCE(col1,''), COALESCE(col2,''))`。

---

## 4. 大小写转换 (UPPER / LOWER / UCASE / LCASE)

### 支持矩阵

| 引擎 | UPPER | LOWER | UCASE | LCASE | INITCAP | 版本 |
|------|-------|-------|-------|-------|---------|------|
| PostgreSQL | 是 | 是 | -- | -- | 是 | 7.1+ |
| MySQL | 是 | 是 | 是 | 是 | -- | 3.23+ |
| MariaDB | 是 | 是 | 是 | 是 | -- | 5.1+ |
| SQLite | 是 | 是 | -- | -- | -- | 3.0+ |
| Oracle | 是 | 是 | -- | -- | 是 | 7+ |
| SQL Server | 是 | 是 | -- | -- | -- | 2000+ |
| DB2 | 是 | 是 | 是 | 是 | 是 | 9.1+ |
| Snowflake | 是 | 是 | -- | -- | 是 | GA |
| BigQuery | 是 | 是 | -- | -- | 是 | GA |
| Redshift | 是 | 是 | -- | -- | 是 | GA |
| DuckDB | 是 | 是 | 是 | 是 | -- | 0.3+ |
| ClickHouse | 是 | 是 | -- | -- | -- | 18.1+ |
| Trino | 是 | 是 | -- | -- | -- | 早期 |
| Presto | 是 | 是 | -- | -- | -- | 0.57+ |
| Spark SQL | 是 | 是 | 是 | 是 | 是 | 1.0+ |
| Hive | 是 | 是 | 是 | 是 | 是 | 0.7+ |
| Flink SQL | 是 | 是 | -- | -- | 是 | 1.12+ |
| Databricks | 是 | 是 | 是 | 是 | 是 | GA |
| Teradata | 是 | 是 | -- | -- | -- | V2R5+ |
| Greenplum | 是 | 是 | -- | -- | 是 | 继承 PG |
| CockroachDB | 是 | 是 | -- | -- | 是 | 1.0+ |
| TiDB | 是 | 是 | 是 | 是 | -- | 2.0+ |
| OceanBase | 是 | 是 | -- | -- | 是 | 1.0+ |
| YugabyteDB | 是 | 是 | -- | -- | 是 | 2.0+ |
| SingleStore | 是 | 是 | 是 | 是 | -- | 7.0+ |
| Vertica | 是 | 是 | -- | -- | 是 | 9.0+ |
| Impala | 是 | 是 | -- | -- | 是 | 2.0+ |
| StarRocks | 是 | 是 | -- | -- | -- | 1.0+ |
| Doris | 是 | 是 | -- | -- | -- | 0.15+ |
| MonetDB | 是 | 是 | -- | -- | -- | Jun2020+ |
| CrateDB | 是 | 是 | -- | -- | -- | 3.0+ |
| TimescaleDB | 是 | 是 | -- | -- | 是 | 继承 PG |
| QuestDB | 是 | 是 | -- | -- | -- | 6.0+ |
| Exasol | 是 | 是 | -- | -- | 是 | 6.0+ |
| SAP HANA | 是 | 是 | 是 | 是 | 是 | 1.0+ |
| Informix | 是 | 是 | -- | -- | 是 | 11.50+ |
| Firebird | 是 | 是 | -- | -- | -- | 2.0+ |
| H2 | 是 | 是 | -- | -- | -- | 1.0+ |
| HSQLDB | 是 | 是 | 是 | 是 | -- | 2.0+ |
| Derby | 是 | 是 | -- | -- | -- | 10.0+ |
| Amazon Athena | 是 | 是 | -- | -- | -- | 继承 Trino |
| Azure Synapse | 是 | 是 | -- | -- | -- | GA |
| Google Spanner | 是 | 是 | -- | -- | 是 | GA |
| Materialize | 是 | 是 | -- | -- | 是 | 继承 PG |
| RisingWave | 是 | 是 | -- | -- | 是 | 1.0+ |
| InfluxDB (SQL) | 是 | 是 | -- | -- | -- | 3.0+ |
| DatabendDB | 是 | 是 | -- | -- | -- | GA |
| Yellowbrick | 是 | 是 | -- | -- | 是 | GA |
| Firebolt | 是 | 是 | -- | -- | -- | GA |

> `UPPER` 和 `LOWER` 是所有引擎均支持的函数，兼容性最好。`UCASE`/`LCASE` 是 MySQL 系别名，在 MySQL/MariaDB/TiDB/SingleStore/DB2/Spark SQL/Hive/DuckDB/SAP HANA/HSQLDB 中可用。`INITCAP`（首字母大写）是 PostgreSQL 系和部分分析型引擎的扩展。

---

## 5. 空白/字符修剪 (TRIM / LTRIM / RTRIM / BTRIM)

> **迁移陷阱**: SQL 标准 `TRIM` 语法使用 `TRIM(LEADING 'x' FROM string)`，但大多数引擎也支持简写 `TRIM(string)`。`BTRIM` 是 PostgreSQL 方言。

### 支持矩阵

| 引擎 | TRIM(s) | TRIM(LEADING/TRAILING/BOTH x FROM s) | LTRIM | RTRIM | BTRIM | 版本 |
|------|---------|-------------------------------------|-------|-------|-------|------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 | 7.1+ |
| MySQL | 是 | 是 | 是 | 是 | -- | 3.23+ |
| MariaDB | 是 | 是 | 是 | 是 | -- | 5.1+ |
| SQLite | 是 | -- | 是 | 是 | -- | 3.0+ |
| Oracle | 是 | 是 | 是 | 是 | -- | 9i+ |
| SQL Server | 是(2017+) | -- | 是 | 是 | -- | 2000+ |
| DB2 | 是 | 是 | 是 | 是 | -- | 9.1+ |
| Snowflake | 是 | 是 | 是 | 是 | -- | GA |
| BigQuery | 是 | 是 | 是 | 是 | -- | GA |
| Redshift | 是 | 是 | 是 | 是 | 是 | GA |
| DuckDB | 是 | 是 | 是 | 是 | -- | 0.3+ |
| ClickHouse | 是 | -- | -- | -- | -- | 18.1+ |
| Trino | 是 | 是 | 是 | 是 | -- | 早期 |
| Presto | 是 | 是 | 是 | 是 | -- | 0.57+ |
| Spark SQL | 是 | 是 | 是 | 是 | -- | 1.0+ |
| Hive | 是 | -- | 是 | 是 | -- | 0.7+ |
| Flink SQL | 是 | 是 | 是 | 是 | -- | 1.12+ |
| Databricks | 是 | 是 | 是 | 是 | -- | GA |
| Teradata | 是 | 是 | -- | -- | -- | V2R5+ |
| Greenplum | 是 | 是 | 是 | 是 | 是 | 继承 PG |
| CockroachDB | 是 | 是 | 是 | 是 | 是 | 1.0+ |
| TiDB | 是 | 是 | 是 | 是 | -- | 2.0+ |
| OceanBase | 是 | 是 | 是 | 是 | -- | 1.0+ |
| YugabyteDB | 是 | 是 | 是 | 是 | 是 | 2.0+ |
| SingleStore | 是 | 是 | 是 | 是 | -- | 7.0+ |
| Vertica | 是 | 是 | 是 | 是 | 是 | 9.0+ |
| Impala | 是 | -- | 是 | 是 | -- | 2.0+ |
| StarRocks | 是 | -- | 是 | 是 | -- | 1.0+ |
| Doris | 是 | -- | 是 | 是 | -- | 0.15+ |
| MonetDB | 是 | 是 | 是 | 是 | -- | Jun2020+ |
| CrateDB | 是 | 是 | 是 | 是 | -- | 3.0+ |
| TimescaleDB | 是 | 是 | 是 | 是 | 是 | 继承 PG |
| QuestDB | 是 | -- | -- | -- | -- | 6.0+ |
| Exasol | 是 | 是 | 是 | 是 | -- | 6.0+ |
| SAP HANA | 是 | 是 | 是 | 是 | -- | 1.0+ |
| Informix | 是 | 是 | -- | -- | -- | 11.50+ |
| Firebird | 是 | 是 | -- | -- | -- | 2.0+ |
| H2 | 是 | 是 | 是 | 是 | -- | 1.0+ |
| HSQLDB | 是 | 是 | 是 | 是 | -- | 2.0+ |
| Derby | 是 | 是 | 是 | 是 | -- | 10.0+ |
| Amazon Athena | 是 | 是 | 是 | 是 | -- | 继承 Trino |
| Azure Synapse | 是 | -- | 是 | 是 | -- | GA |
| Google Spanner | 是 | 是 | 是 | 是 | -- | GA |
| Materialize | 是 | 是 | 是 | 是 | 是 | 继承 PG |
| RisingWave | 是 | 是 | 是 | 是 | 是 | 1.0+ |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | 不支持 |
| DatabendDB | 是 | -- | 是 | 是 | -- | GA |
| Yellowbrick | 是 | 是 | 是 | 是 | 是 | GA |
| Firebolt | 是 | -- | 是 | 是 | -- | GA |

### LTRIM/RTRIM 指定字符集

```sql
-- PostgreSQL / Redshift: LTRIM/RTRIM 支持指定字符集
SELECT LTRIM('xxxHello', 'x');          -- 'Hello'
SELECT RTRIM('Helloyyy', 'y');          -- 'Hello'
SELECT BTRIM('xxHelloxx', 'x');         -- 'Hello'

-- Oracle: LTRIM/RTRIM 支持指定字符集
SELECT LTRIM('xxxHello', 'x') FROM DUAL;  -- 'Hello'

-- SQL Server: LTRIM/RTRIM 仅去空格（2022 前）
SELECT LTRIM('   Hello');               -- 'Hello'
-- SQL Server 2022+ 支持指定字符
SELECT LTRIM('xxxHello', 'x');          -- 'Hello'

-- 标准语法方式
SELECT TRIM(LEADING 'x' FROM 'xxxHello');  -- 'Hello'
SELECT TRIM(TRAILING 'y' FROM 'Helloyyy'); -- 'Hello'
SELECT TRIM(BOTH 'x' FROM 'xxHelloxx');    -- 'Hello'
```

---

## 6. 字符串填充 (LPAD / RPAD)

### 支持矩阵

| 引擎 | LPAD | RPAD | 版本 |
|------|------|------|------|
| PostgreSQL | 是 | 是 | 7.1+ |
| MySQL | 是 | 是 | 3.23+ |
| MariaDB | 是 | 是 | 5.1+ |
| SQLite | -- | -- | 不支持 |
| Oracle | 是 | 是 | 7+ |
| SQL Server | -- | -- | 不支持（需模拟） |
| DB2 | 是 | 是 | 9.1+ |
| Snowflake | 是 | 是 | GA |
| BigQuery | 是 | 是 | GA |
| Redshift | 是 | 是 | GA |
| DuckDB | 是 | 是 | 0.3+ |
| ClickHouse | 是 | 是 | 20.1+ |
| Trino | 是 | 是 | 早期 |
| Presto | 是 | 是 | 0.57+ |
| Spark SQL | 是 | 是 | 1.5+ |
| Hive | 是 | 是 | 1.2+ |
| Flink SQL | 是 | 是 | 1.12+ |
| Databricks | 是 | 是 | GA |
| Teradata | -- | -- | 不支持（需模拟） |
| Greenplum | 是 | 是 | 继承 PG |
| CockroachDB | 是 | 是 | 1.0+ |
| TiDB | 是 | 是 | 2.0+ |
| OceanBase | 是 | 是 | 1.0+ |
| YugabyteDB | 是 | 是 | 2.0+ |
| SingleStore | 是 | 是 | 7.0+ |
| Vertica | 是 | 是 | 9.0+ |
| Impala | 是 | 是 | 2.0+ |
| StarRocks | 是 | 是 | 1.0+ |
| Doris | 是 | 是 | 0.15+ |
| MonetDB | 是 | 是 | Jun2020+ |
| CrateDB | -- | -- | 不支持 |
| TimescaleDB | 是 | 是 | 继承 PG |
| QuestDB | -- | -- | 不支持 |
| Exasol | 是 | 是 | 6.0+ |
| SAP HANA | 是 | 是 | 1.0+ |
| Informix | 是 | 是 | 11.50+ |
| Firebird | 是 | 是 | 2.5+ |
| H2 | 是 | 是 | 1.0+ |
| HSQLDB | 是 | 是 | 2.0+ |
| Derby | -- | -- | 不支持 |
| Amazon Athena | 是 | 是 | 继承 Trino |
| Azure Synapse | -- | -- | 不支持（需模拟） |
| Google Spanner | 是 | 是 | GA |
| Materialize | 是 | 是 | 继承 PG |
| RisingWave | 是 | 是 | 1.0+ |
| InfluxDB (SQL) | -- | -- | 不支持 |
| DatabendDB | 是 | 是 | GA |
| Yellowbrick | 是 | 是 | GA |
| Firebolt | 是 | 是 | GA |

### SQL Server / Azure Synapse 模拟 LPAD

```sql
-- SQL Server / Azure Synapse: 模拟 LPAD(string, length, pad_char)
-- LPAD('42', 5, '0') => '00042'
SELECT RIGHT(REPLICATE('0', 5) + '42', 5);  -- '00042'

-- SQLite: 模拟 LPAD
SELECT SUBSTR('00000' || '42', -5, 5);       -- '00042'

-- Teradata: 模拟 LPAD
SELECT SUBSTRING('00000' || '42' FROM CHARACTER_LENGTH('00000' || '42') - 4 FOR 5);
```

---

## 7. 子串位置查找 (POSITION / LOCATE / INSTR / CHARINDEX / STRPOS)

> **迁移陷阱**: 各引擎的参数顺序完全不同——`LOCATE(sub, str)` vs `INSTR(str, sub)` vs `CHARINDEX(sub, str)` vs `POSITION(sub IN str)`。

### 支持矩阵

| 引擎 | POSITION(sub IN s) | LOCATE(sub,s[,pos]) | INSTR(s,sub) | CHARINDEX(sub,s) | STRPOS(s,sub) | 版本 |
|------|-------------------|--------------------|--------------|-----------------|--------------|----|
| PostgreSQL | 是 | -- | -- | -- | 是 | 7.1+ |
| MySQL | 是 | 是 | 是 | -- | -- | 3.23+ |
| MariaDB | 是 | 是 | 是 | -- | -- | 5.1+ |
| SQLite | -- | -- | 是 | -- | -- | 3.0+ |
| Oracle | -- | -- | 是 | -- | -- | 7+ |
| SQL Server | -- | -- | -- | 是 | -- | 2000+ |
| DB2 | 是 | 是 | 是 | -- | -- | 9.1+ |
| Snowflake | 是 | -- | -- | 是 | -- | GA |
| BigQuery | -- | -- | 是 | -- | 是 | GA |
| Redshift | 是 | -- | -- | 是 | 是 | GA |
| DuckDB | 是 | -- | 是 | -- | 是 | 0.3+ |
| ClickHouse | 是 | 是 | -- | -- | -- | 18.1+ |
| Trino | 是 | -- | -- | -- | 是 | 早期 |
| Presto | 是 | -- | -- | -- | 是 | 0.57+ |
| Spark SQL | 是 | 是 | 是 | -- | -- | 1.0+ |
| Hive | -- | 是 | 是 | -- | -- | 0.7+ |
| Flink SQL | 是 | 是 | -- | -- | -- | 1.12+ |
| Databricks | 是 | 是 | 是 | -- | -- | GA |
| Teradata | 是 | -- | 是 | -- | -- | V2R5+ |
| Greenplum | 是 | -- | -- | -- | 是 | 继承 PG |
| CockroachDB | 是 | -- | -- | -- | 是 | 1.0+ |
| TiDB | 是 | 是 | 是 | -- | -- | 2.0+ |
| OceanBase | 是 | 是 | 是 | -- | -- | 1.0+ |
| YugabyteDB | 是 | -- | -- | -- | 是 | 2.0+ |
| SingleStore | 是 | 是 | 是 | -- | -- | 7.0+ |
| Vertica | 是 | -- | 是 | -- | 是 | 9.0+ |
| Impala | -- | 是 | 是 | -- | -- | 2.0+ |
| StarRocks | 是 | 是 | 是 | -- | -- | 1.0+ |
| Doris | 是 | 是 | 是 | -- | -- | 0.15+ |
| MonetDB | 是 | 是 | -- | -- | -- | Jun2020+ |
| CrateDB | -- | -- | -- | -- | -- | 不支持（用 regexp_matches） |
| TimescaleDB | 是 | -- | -- | -- | 是 | 继承 PG |
| QuestDB | -- | -- | -- | -- | 是 | 6.0+ |
| Exasol | 是 | 是 | 是 | -- | -- | 6.0+ |
| SAP HANA | -- | 是 | 是 | -- | -- | 1.0+ |
| Informix | -- | -- | 是 | -- | -- | 11.50+ |
| Firebird | 是 | -- | -- | -- | -- | 2.0+ |
| H2 | 是 | 是 | 是 | -- | -- | 1.0+ |
| HSQLDB | 是 | 是 | 是 | -- | -- | 2.0+ |
| Derby | -- | 是 | -- | -- | -- | 10.0+ |
| Amazon Athena | 是 | -- | -- | -- | 是 | 继承 Trino |
| Azure Synapse | -- | -- | -- | 是 | -- | GA |
| Google Spanner | -- | -- | 是 | -- | 是 | GA |
| Materialize | 是 | -- | -- | -- | 是 | 继承 PG |
| RisingWave | 是 | -- | -- | -- | 是 | 1.0+ |
| InfluxDB (SQL) | 是 | -- | -- | -- | 是 | 3.0+ |
| DatabendDB | 是 | 是 | 是 | -- | -- | GA |
| Yellowbrick | 是 | -- | -- | -- | 是 | GA |
| Firebolt | -- | -- | -- | -- | 是 | GA |

### 参数顺序速查表

```sql
-- 查找 'World' 在 'Hello World' 中的位置（期望返回 7）

-- 模式 A: POSITION(sub IN string) —— SQL 标准
-- PostgreSQL / MySQL / DB2 / Snowflake / Trino / DuckDB / Flink SQL
SELECT POSITION('World' IN 'Hello World');   -- 7

-- 模式 B: LOCATE(sub, string[, start_pos]) —— sub 在前
-- MySQL / MariaDB / DB2 / Spark SQL / Hive / SAP HANA
SELECT LOCATE('World', 'Hello World');       -- 7
SELECT LOCATE('l', 'Hello World', 5);        -- 找第 5 位之后的 'l'

-- 模式 C: INSTR(string, sub) —— string 在前
-- Oracle / SQLite / MySQL / Spark SQL / BigQuery / DuckDB
SELECT INSTR('Hello World', 'World');        -- 7

-- 模式 D: CHARINDEX(sub, string[, start_pos]) —— sub 在前
-- SQL Server / Snowflake / Redshift / Azure Synapse
SELECT CHARINDEX('World', 'Hello World');    -- 7

-- 模式 E: STRPOS(string, sub) —— string 在前
-- PostgreSQL / BigQuery / Trino / DuckDB / Redshift
SELECT STRPOS('Hello World', 'World');       -- 7
```

> **注意**: `LOCATE` 和 `CHARINDEX` 参数顺序相同（sub 在前），而 `INSTR` 和 `STRPOS` 参数顺序相同（string 在前）但函数名不同。迁移时务必注意参数顺序。

---

## 8. 字符串替换 (REPLACE / TRANSLATE)

### 支持矩阵

| 引擎 | REPLACE(s,from,to) | TRANSLATE(s,from,to) | 版本 |
|------|--------------------|--------------------|------|
| PostgreSQL | 是 | 是 | 7.1+ |
| MySQL | 是 | -- | 3.23+ |
| MariaDB | 是 | -- | 5.1+ |
| SQLite | 是 | -- | 3.0+ |
| Oracle | 是 | 是 | 7+ |
| SQL Server | 是 | 是(2017+) | 2000+(REPLACE) |
| DB2 | 是 | 是 | 9.1+ |
| Snowflake | 是 | 是 | GA |
| BigQuery | 是 | 是 | GA |
| Redshift | 是 | 是 | GA |
| DuckDB | 是 | 是 | 0.3+ |
| ClickHouse | 是 | -- | 18.1+ |
| Trino | 是 | 是 | 早期 |
| Presto | 是 | 是 | 0.57+ |
| Spark SQL | 是 | 是 | 1.5+ |
| Hive | 是 | -- | 0.7+ |
| Flink SQL | 是 | -- | 1.12+ |
| Databricks | 是 | 是 | GA |
| Teradata | -- | 是 | V2R5+ |
| Greenplum | 是 | 是 | 继承 PG |
| CockroachDB | 是 | 是 | 1.0+ |
| TiDB | 是 | -- | 2.0+ |
| OceanBase | 是 | 是 | 1.0+ |
| YugabyteDB | 是 | 是 | 2.0+ |
| SingleStore | 是 | -- | 7.0+ |
| Vertica | 是 | 是 | 9.0+ |
| Impala | 是 | 是 | 2.0+ |
| StarRocks | 是 | -- | 1.0+ |
| Doris | 是 | -- | 0.15+ |
| MonetDB | 是 | -- | Jun2020+ |
| CrateDB | 是 | -- | 3.0+ |
| TimescaleDB | 是 | 是 | 继承 PG |
| QuestDB | 是 | -- | 6.0+ |
| Exasol | 是 | 是 | 6.0+ |
| SAP HANA | 是 | -- | 1.0+ |
| Informix | 是 | -- | 11.50+ |
| Firebird | 是 | -- | 2.0+ |
| H2 | 是 | 是 | 1.0+ |
| HSQLDB | 是 | 是 | 2.0+ |
| Derby | -- | -- | 不支持 |
| Amazon Athena | 是 | 是 | 继承 Trino |
| Azure Synapse | 是 | 是(继承 SQL Server 2017) | GA |
| Google Spanner | 是 | -- | GA |
| Materialize | 是 | 是 | 继承 PG |
| RisingWave | 是 | 是 | 1.0+ |
| InfluxDB (SQL) | 是 | -- | 3.0+ |
| DatabendDB | 是 | -- | GA |
| Yellowbrick | 是 | 是 | GA |
| Firebolt | 是 | -- | GA |

### REPLACE vs TRANSLATE 语义差异

```sql
-- REPLACE: 替换整个子串
SELECT REPLACE('Hello World', 'World', 'SQL');  -- 'Hello SQL'

-- TRANSLATE: 逐字符替换（字符映射）
-- Oracle / PostgreSQL / Snowflake / Trino / SQL Server 2017+
SELECT TRANSLATE('Hello 123', '123', 'abc');     -- 'Hello abc'
-- '1'->'a', '2'->'b', '3'->'c'

-- Oracle 特殊行为: TRANSLATE 的 to 参数不能为空字符串
-- 删除字符的技巧:
SELECT TRANSLATE('Hello123', 'x0123456789', 'x') FROM DUAL;  -- 'Hello'
-- 先用 'x'->'x' 占位，然后 '0'->'', '1'->'', ...

-- Teradata: 仅支持 TRANSLATE，不支持 REPLACE（需用 OREPLACE）
SELECT OREPLACE('Hello World', 'World', 'SQL');  -- 'Hello SQL'
```

---

## 9. 字符串拆分 (SPLIT / SPLIT_PART / STRING_SPLIT / STRING_TO_ARRAY)

> **迁移陷阱**: 字符串拆分函数在引擎间差异极大。有的返回数组，有的返回表，有的返回指定位置的元素。

### 支持矩阵

| 引擎 | SPLIT_PART(s,d,n) | STRING_SPLIT(s,d) | STRING_TO_ARRAY(s,d) | SPLIT(s,d) | STRTOK | 版本 |
|------|-------------------|--------------------|---------------------|-----------|--------|------|
| PostgreSQL | 是 | -- | 是 | -- | -- | 7.4+(SPLIT_PART), 9.1+(STRING_TO_ARRAY) |
| MySQL | -- | -- | -- | -- | -- | 不支持（需模拟） |
| MariaDB | -- | -- | -- | -- | -- | 不支持（需模拟） |
| SQLite | -- | -- | -- | -- | -- | 不支持 |
| Oracle | -- | -- | -- | -- | -- | 不支持（需 REGEXP_SUBSTR） |
| SQL Server | -- | 是(2016+) | -- | -- | -- | 2016+ |
| DB2 | -- | -- | -- | -- | 是 | 9.7+ |
| Snowflake | 是 | -- | -- | 是(返回数组) | 是 | GA |
| BigQuery | -- | -- | -- | 是(返回数组) | -- | GA |
| Redshift | 是 | -- | 是 | -- | 是 | GA |
| DuckDB | 是 | -- | 是 | 是(返回列表) | -- | 0.3+ |
| ClickHouse | -- | -- | -- | splitByChar / splitByString | -- | 18.1+ |
| Trino | -- | -- | -- | 是(返回数组) | -- | 早期 |
| Presto | -- | -- | -- | 是(返回数组) | -- | 0.57+ |
| Spark SQL | -- | -- | -- | 是(返回数组) | -- | 1.5+ |
| Hive | -- | -- | -- | 是(返回数组) | -- | 0.7+ |
| Flink SQL | -- | -- | -- | -- | -- | 不支持 |
| Databricks | -- | -- | -- | 是(返回数组) | -- | GA |
| Teradata | -- | -- | -- | -- | 是 | V2R5+ |
| Greenplum | 是 | -- | 是 | -- | -- | 继承 PG |
| CockroachDB | 是 | -- | 是 | -- | -- | 1.0+ |
| TiDB | -- | -- | -- | -- | -- | 不支持（需模拟） |
| OceanBase | -- | -- | -- | -- | -- | 不支持 |
| YugabyteDB | 是 | -- | 是 | -- | -- | 2.0+ |
| SingleStore | -- | -- | -- | -- | -- | 不支持（需模拟） |
| Vertica | -- | -- | -- | -- | 是 | 9.0+ |
| Impala | -- | -- | -- | 是(返回数组) | -- | 2.0+ |
| StarRocks | 是 | -- | -- | 是(返回数组) | -- | 2.0+ |
| Doris | 是 | -- | -- | 是(返回数组) | -- | 1.0+ |
| MonetDB | -- | -- | -- | -- | -- | 不支持 |
| CrateDB | -- | -- | -- | -- | -- | 不支持 |
| TimescaleDB | 是 | -- | 是 | -- | -- | 继承 PG |
| QuestDB | -- | -- | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | -- | -- | 不支持（需模拟） |
| SAP HANA | -- | -- | -- | -- | -- | 不支持（需模拟） |
| Informix | -- | -- | -- | -- | -- | 不支持 |
| Firebird | -- | -- | -- | -- | -- | 不支持 |
| H2 | -- | -- | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | -- | -- | 不支持 |
| Amazon Athena | -- | -- | -- | 是(返回数组) | -- | 继承 Trino |
| Azure Synapse | -- | 是 | -- | -- | -- | GA |
| Google Spanner | -- | -- | -- | 是(返回数组) | -- | GA |
| Materialize | 是 | -- | 是 | -- | -- | 继承 PG |
| RisingWave | 是 | -- | 是 | -- | -- | 1.0+ |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | 不支持 |
| DatabendDB | 是 | -- | -- | -- | -- | GA |
| Yellowbrick | 是 | -- | 是 | -- | -- | GA |
| Firebolt | 是 | -- | -- | -- | -- | GA |

### 跨引擎拆分等价语法

```sql
-- 任务: 获取 'a,b,c' 的第 2 个元素（期望 'b'）

-- PostgreSQL / Redshift / DuckDB / CockroachDB / Greenplum
SELECT SPLIT_PART('a,b,c', ',', 2);              -- 'b'

-- SQL Server 2016+ / Azure Synapse
SELECT value FROM STRING_SPLIT('a,b,c', ',')
    ORDER BY (SELECT NULL) OFFSET 1 ROW FETCH NEXT 1 ROW ONLY;
-- SQL Server 2022+ 支持 ordinal:
SELECT value FROM STRING_SPLIT('a,b,c', ',', 1) WHERE ordinal = 2;

-- Snowflake
SELECT SPLIT_PART('a,b,c', ',', 2);              -- 'b'

-- BigQuery / Trino / Spark SQL / Hive / Databricks
SELECT SPLIT('a,b,c', ',')[OFFSET(1)];           -- BigQuery (0-based)
SELECT SPLIT('a,b,c', ',')[2];                    -- Trino/Spark/Hive (1-based)

-- ClickHouse
SELECT splitByChar(',', 'a,b,c')[2];             -- 'b' (1-based)

-- Oracle（无内置函数，使用 REGEXP_SUBSTR）
SELECT REGEXP_SUBSTR('a,b,c', '[^,]+', 1, 2) FROM DUAL;  -- 'b'

-- MySQL / MariaDB（无内置函数，使用 SUBSTRING_INDEX）
SELECT SUBSTRING_INDEX(SUBSTRING_INDEX('a,b,c', ',', 2), ',', -1);  -- 'b'
```

---

## 10. 字符串重复 (REPEAT / REPLICATE)

### 支持矩阵

| 引擎 | REPEAT(s,n) | REPLICATE(s,n) | 版本 |
|------|------------|---------------|------|
| PostgreSQL | 是 | -- | 7.1+ |
| MySQL | 是 | -- | 3.23+ |
| MariaDB | 是 | -- | 5.1+ |
| SQLite | -- | -- | 不支持（需模拟） |
| Oracle | -- | -- | 不支持（用 RPAD 模拟） |
| SQL Server | -- | 是 | 2000+ |
| DB2 | 是 | -- | 9.1+ |
| Snowflake | 是 | -- | GA |
| BigQuery | 是 | -- | GA |
| Redshift | 是 | 是 | GA |
| DuckDB | 是 | -- | 0.3+ |
| ClickHouse | 是 | -- | 18.1+ |
| Trino | -- | -- | 不支持（需模拟） |
| Presto | -- | -- | 不支持（需模拟） |
| Spark SQL | 是 | -- | 1.5+ |
| Hive | 是 | -- | 1.2+ |
| Flink SQL | -- | -- | 不支持 |
| Databricks | 是 | -- | GA |
| Teradata | -- | -- | 不支持（需模拟） |
| Greenplum | 是 | -- | 继承 PG |
| CockroachDB | 是 | -- | 1.0+ |
| TiDB | 是 | -- | 2.0+ |
| OceanBase | 是 | -- | 1.0+ |
| YugabyteDB | 是 | -- | 2.0+ |
| SingleStore | 是 | -- | 7.0+ |
| Vertica | 是 | -- | 9.0+ |
| Impala | 是 | -- | 2.0+ |
| StarRocks | 是 | -- | 1.0+ |
| Doris | 是 | -- | 0.15+ |
| MonetDB | 是 | -- | Jun2020+ |
| CrateDB | -- | -- | 不支持 |
| TimescaleDB | 是 | -- | 继承 PG |
| QuestDB | -- | -- | 不支持 |
| Exasol | 是 | -- | 6.0+ |
| SAP HANA | -- | -- | 不支持（用 LPAD 模拟） |
| Informix | -- | -- | 不支持 |
| Firebird | -- | -- | 不支持 |
| H2 | 是 | -- | 1.0+ |
| HSQLDB | 是 | -- | 2.0+ |
| Derby | -- | -- | 不支持 |
| Amazon Athena | -- | -- | 不支持（需模拟） |
| Azure Synapse | -- | 是 | GA |
| Google Spanner | 是 | -- | GA |
| Materialize | 是 | -- | 继承 PG |
| RisingWave | 是 | -- | 1.0+ |
| InfluxDB (SQL) | -- | -- | 不支持 |
| DatabendDB | 是 | -- | GA |
| Yellowbrick | 是 | -- | GA |
| Firebolt | -- | -- | 不支持 |

### 不支持引擎的模拟

```sql
-- Oracle: 用 RPAD 模拟 REPEAT
SELECT RPAD('ab', LENGTH('ab') * 3, 'ab') FROM DUAL;  -- 'ababab'

-- SQL Server: REPLICATE 是原生函数
SELECT REPLICATE('ab', 3);                              -- 'ababab'

-- Trino / Presto / Amazon Athena: 用 ARRAY 模拟
SELECT ARRAY_JOIN(REPEAT('ab', 3), '');                 -- 'ababab'

-- SQLite: 用 REPLACE + ZEROBLOB 模拟
SELECT REPLACE(HEX(ZEROBLOB(3)), '00', 'ab');           -- 'ababab'
```

---

## 11. 字符串反转 (REVERSE)

### 支持矩阵

| 引擎 | REVERSE | 版本 |
|------|---------|------|
| PostgreSQL | 是 | 9.1+ |
| MySQL | 是 | 3.23+ |
| MariaDB | 是 | 5.1+ |
| SQLite | -- | 不支持 |
| Oracle | 是 | 10g+ |
| SQL Server | 是 | 2000+ |
| DB2 | -- | 不支持 |
| Snowflake | 是 | GA |
| BigQuery | 是 | GA |
| Redshift | 是 | GA |
| DuckDB | 是 | 0.3+ |
| ClickHouse | 是 | 18.1+ |
| Trino | 是 | 早期 |
| Presto | 是 | 0.57+ |
| Spark SQL | 是 | 1.5+ |
| Hive | 是 | 1.2+ |
| Flink SQL | -- | 不支持 |
| Databricks | 是 | GA |
| Teradata | -- | 不支持 |
| Greenplum | 是 | 继承 PG |
| CockroachDB | 是 | 1.0+ |
| TiDB | 是 | 2.0+ |
| OceanBase | 是 | 1.0+ |
| YugabyteDB | 是 | 2.0+ |
| SingleStore | 是 | 7.0+ |
| Vertica | -- | 不支持 |
| Impala | 是 | 2.0+ |
| StarRocks | 是 | 1.0+ |
| Doris | 是 | 0.15+ |
| MonetDB | -- | 不支持 |
| CrateDB | -- | 不支持 |
| TimescaleDB | 是 | 继承 PG |
| QuestDB | -- | 不支持 |
| Exasol | 是 | 6.0+ |
| SAP HANA | -- | 不支持 |
| Informix | -- | 不支持 |
| Firebird | 是 | 2.0+ |
| H2 | -- | 不支持 |
| HSQLDB | 是 | 2.0+ |
| Derby | -- | 不支持 |
| Amazon Athena | 是 | 继承 Trino |
| Azure Synapse | 是 | GA |
| Google Spanner | 是 | GA |
| Materialize | 是 | 继承 PG |
| RisingWave | 是 | 1.0+ |
| InfluxDB (SQL) | -- | 不支持 |
| DatabendDB | 是 | GA |
| Yellowbrick | 是 | GA |
| Firebolt | -- | 不支持 |

---

## 12. 左/右截取 (LEFT / RIGHT)

### 支持矩阵

| 引擎 | LEFT(s,n) | RIGHT(s,n) | 版本 |
|------|-----------|-----------|------|
| PostgreSQL | 是 | 是 | 9.1+ |
| MySQL | 是 | 是 | 3.23+ |
| MariaDB | 是 | 是 | 5.1+ |
| SQLite | -- | -- | 不支持（用 SUBSTR 模拟） |
| Oracle | -- | -- | 不支持（用 SUBSTR 模拟） |
| SQL Server | 是 | 是 | 2000+ |
| DB2 | 是 | 是 | 9.1+ |
| Snowflake | 是 | 是 | GA |
| BigQuery | 是 | 是 | GA |
| Redshift | 是 | 是 | GA |
| DuckDB | 是 | 是 | 0.3+ |
| ClickHouse | -- | -- | 不支持（用 substring 模拟） |
| Trino | -- | -- | 不支持（用 SUBSTR 模拟） |
| Presto | -- | -- | 不支持（用 SUBSTR 模拟） |
| Spark SQL | 是 | 是 | 3.4+(LEFT), 3.4+(RIGHT) |
| Hive | -- | -- | 不支持（用 SUBSTR 模拟） |
| Flink SQL | -- | -- | 不支持 |
| Databricks | 是 | 是 | GA |
| Teradata | -- | -- | 不支持 |
| Greenplum | 是 | 是 | 继承 PG |
| CockroachDB | 是 | 是 | 1.0+ |
| TiDB | 是 | 是 | 2.0+ |
| OceanBase | 是 | 是 | 1.0+ |
| YugabyteDB | 是 | 是 | 2.0+ |
| SingleStore | 是 | 是 | 7.0+ |
| Vertica | -- | -- | 不支持（用 SUBSTR 模拟） |
| Impala | 是 | 是 | 4.0+ |
| StarRocks | 是 | 是 | 1.0+ |
| Doris | 是 | 是 | 0.15+ |
| MonetDB | -- | -- | 不支持 |
| CrateDB | 是 | 是 | 4.0+ |
| TimescaleDB | 是 | 是 | 继承 PG |
| QuestDB | 是 | 是 | 6.0+ |
| Exasol | 是 | 是 | 6.0+ |
| SAP HANA | 是 | 是 | 1.0+ |
| Informix | -- | -- | 不支持 |
| Firebird | 是 | 是 | 2.0+ |
| H2 | 是 | 是 | 1.0+ |
| HSQLDB | 是 | 是 | 2.0+ |
| Derby | -- | -- | 不支持 |
| Amazon Athena | -- | -- | 不支持（用 SUBSTR 模拟） |
| Azure Synapse | 是 | 是 | GA |
| Google Spanner | 是 | 是 | GA |
| Materialize | 是 | 是 | 继承 PG |
| RisingWave | 是 | 是 | 1.0+ |
| InfluxDB (SQL) | -- | -- | 不支持 |
| DatabendDB | 是 | 是 | GA |
| Yellowbrick | 是 | 是 | GA |
| Firebolt | -- | -- | 不支持（用 SUBSTR 模拟） |

### 不支持引擎的模拟

```sql
-- LEFT('Hello World', 5) => 'Hello'
-- RIGHT('Hello World', 5) => 'World'

-- Oracle / SQLite（用 SUBSTR）
SELECT SUBSTR('Hello World', 1, 5);                          -- 'Hello'（LEFT）
SELECT SUBSTR('Hello World', LENGTH('Hello World') - 4);     -- 'World'（RIGHT）

-- Trino / Presto / Amazon Athena / Hive（用 SUBSTR）
SELECT SUBSTR('Hello World', 1, 5);                          -- 'Hello'（LEFT）
SELECT SUBSTR('Hello World', -5);                            -- 'World'（RIGHT, 负索引）

-- ClickHouse（用 substring）
SELECT substring('Hello World', 1, 5);                       -- 'Hello'
SELECT substring('Hello World', -5);                         -- 'World'

-- Vertica
SELECT SUBSTR('Hello World', 1, 5);                          -- 'Hello'
SELECT SUBSTR('Hello World', LENGTH('Hello World') - 4, 5);  -- 'World'
```

---

## 13. 格式化 (FORMAT / TO_CHAR / PRINTF)

### 支持矩阵

| 引擎 | FORMAT | TO_CHAR | PRINTF | 版本 |
|------|--------|---------|--------|------|
| PostgreSQL | -- | 是 | -- | 7.1+ |
| MySQL | 是(数字格式化) | -- | -- | 5.0+ |
| MariaDB | 是(数字格式化) | -- | -- | 5.1+ |
| SQLite | -- | -- | 是 | 3.8.3+ |
| Oracle | -- | 是 | -- | 7+ |
| SQL Server | 是(通用格式化) | -- | -- | 2012+ |
| DB2 | -- | 是 | -- | 9.7+ |
| Snowflake | -- | 是 | -- | GA |
| BigQuery | 是 | -- | -- | GA |
| Redshift | -- | 是 | -- | GA |
| DuckDB | 是 | -- | 是 | 0.3+ |
| ClickHouse | 是(formatRow) | -- | -- | 20.1+ |
| Trino | 是 | -- | -- | 早期 |
| Presto | 是 | -- | -- | 0.57+ |
| Spark SQL | 是 | -- | -- | 1.5+ |
| Hive | 是(format_number) | -- | 是 | 0.7+ |
| Flink SQL | -- | -- | -- | 不支持 |
| Databricks | 是 | -- | -- | GA |
| Teradata | -- | 是(FORMAT修饰符) | -- | V2R5+ |
| Greenplum | -- | 是 | -- | 继承 PG |
| CockroachDB | -- | 是 | -- | 1.0+ |
| TiDB | 是(数字格式化) | -- | -- | 2.0+ |
| OceanBase | 是 | 是 | -- | 1.0+ |
| YugabyteDB | -- | 是 | -- | 2.0+ |
| SingleStore | 是(数字格式化) | -- | -- | 7.0+ |
| Vertica | -- | 是 | -- | 9.0+ |
| Impala | -- | -- | -- | 不支持 |
| StarRocks | -- | -- | -- | 不支持 |
| Doris | -- | -- | -- | 不支持 |
| MonetDB | -- | -- | -- | 不支持 |
| CrateDB | 是 | 是 | -- | 4.0+ |
| TimescaleDB | -- | 是 | -- | 继承 PG |
| QuestDB | -- | 是 | -- | 6.0+ |
| Exasol | -- | 是 | -- | 6.0+ |
| SAP HANA | -- | 是 | -- | 1.0+ |
| Informix | -- | 是 | -- | 11.50+ |
| Firebird | -- | -- | -- | 不支持 |
| H2 | 是 | -- | -- | 1.0+ |
| HSQLDB | -- | 是 | -- | 2.0+ |
| Derby | -- | -- | -- | 不支持 |
| Amazon Athena | 是 | -- | -- | 继承 Trino |
| Azure Synapse | 是 | -- | -- | GA |
| Google Spanner | 是 | -- | -- | GA |
| Materialize | -- | 是 | -- | 继承 PG |
| RisingWave | -- | 是 | -- | 1.0+ |
| InfluxDB (SQL) | -- | -- | -- | 不支持 |
| DatabendDB | -- | 是 | -- | GA |
| Yellowbrick | -- | 是 | -- | GA |
| Firebolt | -- | 是 | -- | GA |

### FORMAT vs TO_CHAR 语义差异

```sql
-- MySQL FORMAT: 数字格式化（加千分位）
SELECT FORMAT(1234567.891, 2);           -- '1,234,567.89'

-- SQL Server FORMAT: .NET 格式字符串
SELECT FORMAT(1234567.891, 'N2');        -- '1,234,567.89'
SELECT FORMAT(GETDATE(), 'yyyy-MM-dd'); -- '2024-01-15'

-- PostgreSQL / Oracle TO_CHAR: 格式模板
SELECT TO_CHAR(1234567.891, '9,999,999.99');  -- ' 1,234,567.89'
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD');          -- '2024-01-15'

-- SQLite PRINTF: C 风格格式
SELECT PRINTF('%010.2f', 1234.5);        -- '0001234.50'
SELECT PRINTF('%s has %d items', 'cart', 5);  -- 'cart has 5 items'

-- BigQuery FORMAT: 使用 %d / %s 风格
SELECT FORMAT('%s has %d items', 'cart', 5);  -- 'cart has 5 items'

-- Trino FORMAT: Java String.format 语法
SELECT FORMAT('%s has %d items', 'cart', 5);  -- 'cart has 5 items'
```

---

## 14. Base64 编解码 (BASE64_ENCODE / BASE64_DECODE / TO_BASE64 / FROM_BASE64)

### 支持矩阵

| 引擎 | 编码函数 | 解码函数 | 版本 |
|------|---------|---------|------|
| PostgreSQL | `ENCODE(bytes, 'base64')` | `DECODE(string, 'base64')` | 8.1+ |
| MySQL | `TO_BASE64(s)` | `FROM_BASE64(s)` | 5.6+ |
| MariaDB | `TO_BASE64(s)` | `FROM_BASE64(s)` | 10.0+ |
| SQLite | -- | -- | 不支持 |
| Oracle | `UTL_ENCODE.BASE64_ENCODE()` | `UTL_ENCODE.BASE64_DECODE()` | 10g+ |
| SQL Server | 需用 XML 或 CAST(... AS XML) | 需用 XML | 2005+ |
| DB2 | `BASE64_ENCODE(s)` | `BASE64_DECODE(s)` | 11.1+ |
| Snowflake | `BASE64_ENCODE(s)` | `BASE64_DECODE_STRING(s)` | GA |
| BigQuery | `TO_BASE64(s)` | `FROM_BASE64(s)` | GA |
| Redshift | -- | -- | 不支持 |
| DuckDB | `BASE64(s)` | `FROM_BASE64(s)` | 0.8+ |
| ClickHouse | `base64Encode(s)` | `base64Decode(s)` | 20.1+ |
| Trino | `TO_BASE64(s)` | `FROM_BASE64(s)` | 早期 |
| Presto | `TO_BASE64(s)` | `FROM_BASE64(s)` | 0.57+ |
| Spark SQL | `BASE64(s)` | `UNBASE64(s)` | 1.5+ |
| Hive | `BASE64(s)` | `UNBASE64(s)` | 0.12+ |
| Flink SQL | `TO_BASE64(s)` | `FROM_BASE64(s)` | 1.13+ |
| Databricks | `BASE64(s)` | `UNBASE64(s)` | GA |
| Teradata | -- | -- | 不支持 |
| Greenplum | `ENCODE(bytes, 'base64')` | `DECODE(string, 'base64')` | 继承 PG |
| CockroachDB | `ENCODE(bytes, 'base64')` | `DECODE(string, 'base64')` | 1.0+ |
| TiDB | `TO_BASE64(s)` | `FROM_BASE64(s)` | 4.0+ |
| OceanBase | `TO_BASE64(s)` | `FROM_BASE64(s)` | 2.0+ |
| YugabyteDB | `ENCODE(bytes, 'base64')` | `DECODE(string, 'base64')` | 2.0+ |
| SingleStore | `TO_BASE64(s)` | `FROM_BASE64(s)` | 7.0+ |
| Vertica | -- | -- | 不支持 |
| Impala | `BASE64ENCODE(s)` | `BASE64DECODE(s)` | 3.0+ |
| StarRocks | `TO_BASE64(s)` | `FROM_BASE64(s)` | 2.0+ |
| Doris | `TO_BASE64(s)` | `FROM_BASE64(s)` | 1.0+ |
| MonetDB | -- | -- | 不支持 |
| CrateDB | -- | -- | 不支持 |
| TimescaleDB | `ENCODE(bytes, 'base64')` | `DECODE(string, 'base64')` | 继承 PG |
| QuestDB | -- | -- | 不支持 |
| Exasol | -- | -- | 不支持 |
| SAP HANA | `TO_BASE64(s)` | `FROM_BASE64(s)` | 2.0+ |
| Informix | -- | -- | 不支持 |
| Firebird | -- | -- | 不支持 |
| H2 | -- | -- | 不支持 |
| HSQLDB | -- | -- | 不支持 |
| Derby | -- | -- | 不支持 |
| Amazon Athena | `TO_BASE64(s)` | `FROM_BASE64(s)` | 继承 Trino |
| Azure Synapse | 需用 CAST 和 XML | 需用 CAST 和 XML | GA |
| Google Spanner | `TO_BASE64(s)` | `FROM_BASE64(s)` | GA |
| Materialize | `ENCODE(bytes, 'base64')` | `DECODE(string, 'base64')` | 继承 PG |
| RisingWave | `ENCODE(bytes, 'base64')` | `DECODE(string, 'base64')` | 1.0+ |
| InfluxDB (SQL) | -- | -- | 不支持 |
| DatabendDB | -- | -- | 不支持 |
| Yellowbrick | -- | -- | 不支持 |
| Firebolt | -- | -- | 不支持 |

### 跨引擎 Base64 示例

```sql
-- PostgreSQL / CockroachDB / YugabyteDB / Greenplum
SELECT ENCODE('Hello World'::bytea, 'base64');    -- 'SGVsbG8gV29ybGQ='
SELECT CONVERT_FROM(DECODE('SGVsbG8gV29ybGQ=', 'base64'), 'UTF-8');  -- 'Hello World'

-- MySQL / MariaDB / TiDB / SingleStore
SELECT TO_BASE64('Hello World');                   -- 'SGVsbG8gV29ybGQ='
SELECT FROM_BASE64('SGVsbG8gV29ybGQ=');            -- 'Hello World' (binary)

-- Snowflake
SELECT BASE64_ENCODE('Hello World');               -- 'SGVsbG8gV29ybGQ='
SELECT BASE64_DECODE_STRING('SGVsbG8gV29ybGQ=');   -- 'Hello World'

-- Spark SQL / Hive / Databricks
SELECT BASE64(CAST('Hello World' AS BINARY));      -- 'SGVsbG8gV29ybGQ='
SELECT CAST(UNBASE64('SGVsbG8gV29ybGQ=') AS STRING);  -- 'Hello World'

-- ClickHouse
SELECT base64Encode('Hello World');                -- 'SGVsbG8gV29ybGQ='
SELECT base64Decode('SGVsbG8gV29ybGQ=');           -- 'Hello World'

-- SQL Server（较复杂，使用 XML 方式）
SELECT CAST('' AS XML).value('xs:base64Binary(sql:column("bin"))', 'VARCHAR(MAX)')
FROM (SELECT CAST('Hello World' AS VARBINARY(MAX)) AS bin) t;
```

---

## 关键发现

### 1. 高度兼容的函数（所有引擎均支持）

| 函数 | 兼容性 | 备注 |
|------|-------|------|
| `UPPER` / `LOWER` | 49/49 引擎 | 最安全的跨引擎函数 |
| `SUBSTRING(s, pos, len)` | 48/49 引擎 | Oracle 使用 `SUBSTR`，但语义一致 |
| `TRIM(s)` | 47/49 引擎 | 仅去除空格的简写形式，几乎通用 |
| `REPLACE(s, from, to)` | 47/49 引擎 | Derby/Teradata 不支持或使用别名 |

### 2. 分裂最严重的函数（命名/语义差异大）

| 功能 | 函数名变体数 | 主要分歧 |
|------|-----------|---------|
| 字符串长度 | 6 种（LENGTH/LEN/CHAR_LENGTH/CHARACTER_LENGTH/OCTET_LENGTH/DATALENGTH） | LENGTH 返回字符还是字节 |
| 子串位置 | 5 种（POSITION/LOCATE/INSTR/CHARINDEX/STRPOS） | 参数顺序完全不同 |
| 字符串拆分 | 5 种（SPLIT_PART/STRING_SPLIT/STRING_TO_ARRAY/SPLIT/STRTOK） | 返回类型不同（标量 vs 数组 vs 表） |
| 重复 | 2 种（REPEAT/REPLICATE） | 约 10 个引擎不支持 |
| Base64 | 8+ 种函数名 | 各引擎命名完全不同 |

### 3. NULL 行为差异汇总

| 操作 | NULL 传播（标准行为） | NULL 忽略 |
|------|-------------------|----------|
| `\|\|`（连接） | PostgreSQL, Oracle, SQLite, DB2 | -- |
| `CONCAT()` | Oracle(2参数版) | SQL Server 2012+, PostgreSQL, MySQL* |
| `CONCAT_WS()` | -- | 几乎所有支持引擎 |
| `LENGTH(NULL)` | 所有引擎 | -- |
| `REPLACE(NULL,...)` | 所有引擎 | -- |

> *MySQL 的 `CONCAT()` 任一参数为 NULL 则返回 NULL；但 `CONCAT_WS()` 会跳过 NULL 参数。

### 4. 迁移优先级建议

对于需要跨引擎兼容的 SQL，推荐优先使用以下函数：

| 优先级 | 推荐函数 | 覆盖范围 | 避免使用 |
|-------|---------|---------|---------|
| 最高 | `UPPER`, `LOWER` | 所有引擎 | `UCASE`, `LCASE` |
| 最高 | `SUBSTRING(s, pos, len)` | 几乎所有引擎 | `MID`, `SUBSTR`(部分引擎不支持) |
| 高 | `TRIM(s)` | 几乎所有引擎 | `BTRIM` |
| 高 | `REPLACE(s, from, to)` | 几乎所有引擎 | -- |
| 中 | `CHAR_LENGTH(s)` | 大多数引擎 | `LENGTH`(字节/字符语义不一致) |
| 中 | `POSITION(sub IN s)` | 大多数引擎 | `LOCATE`/`INSTR`/`CHARINDEX`(参数顺序差异) |
| 低 | `LPAD(s,n,pad)` | 大多数引擎 | SQL Server/SQLite 需模拟 |
| 低 | `CONCAT(a,b)` | 大多数引擎 | `\|\|`(SQL Server 不支持), `+`(仅 SQL Server) |

### 5. SQL Server 与其他引擎的函数名映射速查

SQL Server 使用了大量与 SQL 标准和其他引擎不同的函数名，是迁移中最需要注意的引擎之一：

| 通用函数 | SQL Server 等价 |
|---------|----------------|
| `LENGTH(s)` | `LEN(s)` |
| `POSITION(sub IN s)` / `INSTR(s, sub)` | `CHARINDEX(sub, s)` |
| `SUBSTR(s, pos, len)` | `SUBSTRING(s, pos, len)` |
| `REPEAT(s, n)` | `REPLICATE(s, n)` |
| `LPAD(s, n, pad)` | `RIGHT(REPLICATE(pad, n) + s, n)` |
| `TO_CHAR(num, fmt)` | `FORMAT(num, fmt)` |
| `\|\|` 连接 | `+` 或 `CONCAT()` |
| `SPLIT_PART(s, d, n)` | `STRING_SPLIT(s, d)` (2016+, 返回表) |
| `TO_BASE64(s)` | XML CAST 方式 |
