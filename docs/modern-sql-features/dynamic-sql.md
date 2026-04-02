# 动态 SQL (Dynamic SQL)

在存储过程和管理脚本中，SQL 语句往往不能在编译期完全确定——表名、列名、过滤条件甚至整条语句可能需要在运行时动态构建。动态 SQL 正是解决这一需求的核心机制。它广泛用于通用管理工具、多租户系统中的动态 DDL、数据迁移脚本、以及基于用户输入的动态查询构建。然而，动态 SQL 也是 SQL 注入攻击的主要入口，各引擎在提供灵活性的同时也必须兼顾安全性。

本文从引擎开发者视角，逐方言对比动态 SQL 的语法差异、参数绑定机制和安全防护手段。

## SQL 标准

### SQL:1999 动态 SQL (ISO/IEC 9075-5)

SQL:1999 标准在 Part 5 (CLI) 和 Part 4 (PSM) 中正式定义了动态 SQL 的核心语法：

```sql
-- EXECUTE IMMEDIATE: 构建并立即执行 SQL 字符串
EXECUTE IMMEDIATE <sql_string>;

-- PREPARE / EXECUTE: 先准备再执行，可带参数
PREPARE <statement_name> FROM <sql_string>;
EXECUTE <statement_name> [USING <variable_list>];
DEALLOCATE PREPARE <statement_name>;

-- DESCRIBE: 获取预处理语句的结果集元数据
DESCRIBE <statement_name> INTO <descriptor>;

-- 动态游标
DECLARE <cursor_name> CURSOR FOR <statement_name>;
OPEN <cursor_name> [USING <variable_list>];
FETCH <cursor_name> INTO <variable_list>;
CLOSE <cursor_name>;
```

标准的关键语义要点：

1. **EXECUTE IMMEDIATE** 是"一次性"执行，无法复用预处理计划
2. **PREPARE / EXECUTE** 分离了编译和执行，允许多次执行同一预处理语句
3. **USING 子句** 提供了参数绑定能力，是防止 SQL 注入的标准手段
4. **参数标记** 使用 `?` 作为位置参数占位符（SQL 标准定义）
5. **DEALLOCATE PREPARE** 释放预处理语句占用的资源

## 支持矩阵

### EXECUTE IMMEDIATE 支持

| 引擎 | 支持 | 语法 | 上下文 | 版本 |
|------|:---:|------|--------|------|
| PostgreSQL | ✅ | `EXECUTE <string>` | PL/pgSQL | 7.0+ |
| MySQL | ❌ | — | 使用 PREPARE/EXECUTE | — |
| MariaDB | ✅ | `EXECUTE IMMEDIATE <string>` | 存储过程/匿名块 | 10.2.3+ |
| SQLite | ❌ | — | 无过程化语言 | — |
| Oracle | ✅ | `EXECUTE IMMEDIATE <string>` | PL/SQL | 8i+ |
| SQL Server | ❌ | — | 使用 EXEC() / sp_executesql | — |
| DB2 | ✅ | `EXECUTE IMMEDIATE <string>` | SQL PL | 7.0+ |
| Snowflake | ✅ | `EXECUTE IMMEDIATE <string>` | Snowflake Scripting | GA |
| BigQuery | ✅ | `EXECUTE IMMEDIATE <string>` | BigQuery 脚本 | 2020+ |
| Redshift | ✅ | `EXECUTE <string>` | PL/pgSQL | GA |
| DuckDB | ❌ | — | 无过程化语言 | — |
| ClickHouse | ❌ | — | 无过程化语言 | — |
| Trino | ❌ | — | 无过程化语言 | — |
| Presto | ❌ | — | 无过程化语言 | — |
| Spark SQL | ❌ | — | 无过程化语言 | — |
| Hive | ❌ | — | 无过程化语言 | — |
| Flink SQL | ❌ | — | 无过程化语言 | — |
| Databricks | ✅ | `EXECUTE IMMEDIATE <string>` | SQL 脚本 | Runtime 14.1+ |
| Teradata | ❌ | — | 使用 CALL DBC.SysExecSQL | — |
| Greenplum | ✅ | `EXECUTE <string>` | PL/pgSQL | 4.0+ |
| CockroachDB | ✅ | `EXECUTE <string>` | PL/pgSQL (23.1+) | 23.1+ |
| TiDB | ❌ | — | 使用 PREPARE/EXECUTE | — |
| OceanBase | ✅ | `EXECUTE IMMEDIATE <string>` | Oracle 模式 PL | 3.0+ |
| YugabyteDB | ✅ | `EXECUTE <string>` | PL/pgSQL | 2.0+ |
| SingleStore | ❌ | — | 使用 PREPARE/EXECUTE | — |
| Vertica | ✅ | `EXECUTE <string>` | PL/vSQL | 9.0+ |
| Impala | ❌ | — | 无过程化语言 | — |
| StarRocks | ❌ | — | 无过程化语言 | — |
| Doris | ❌ | — | 无过程化语言 | — |
| MonetDB | ✅ | `EXECUTE IMMEDIATE <string>` | SQL/PSM | 11.19+ |
| CrateDB | ❌ | — | 无过程化语言 | — |
| TimescaleDB | ✅ | `EXECUTE <string>` | PL/pgSQL (继承 PG) | 继承 PG |
| QuestDB | ❌ | — | 无过程化语言 | — |
| Exasol | ✅ | `EXECUTE IMMEDIATE <string>` | Exasol 脚本 | 6.0+ |
| SAP HANA | ✅ | `EXECUTE IMMEDIATE <string>` / `EXEC <string>` | SQLScript | 1.0+ |
| Informix | ✅ | `EXECUTE IMMEDIATE <string>` | SPL | 7.20+ |
| Firebird | ✅ | `EXECUTE STATEMENT <string>` | PSQL | 2.0+ |
| H2 | ❌ | — | 无 EXECUTE IMMEDIATE | — |
| HSQLDB | ✅ | `EXECUTE IMMEDIATE <string>` | SQL/PSM | 2.0+ |
| Derby | ✅ | `EXECUTE IMMEDIATE <string>` | SQL/PSM (有限) | 10.0+ |
| Amazon Athena | ❌ | — | 无过程化语言 | — |
| Azure Synapse | ❌ | — | 使用 EXEC() / sp_executesql | — |
| Google Spanner | ❌ | — | 无动态 SQL | — |
| Materialize | ❌ | — | 无过程化语言 | — |
| RisingWave | ❌ | — | 无过程化语言 | — |
| InfluxDB | ❌ | — | 无 SQL 过程化 | — |
| DatabendDB | ❌ | — | 无过程化语言 | — |
| Yellowbrick | ✅ | `EXECUTE <string>` | PL/pgSQL 兼容 | GA |
| Firebolt | ❌ | — | 无过程化语言 | — |

### PREPARE / EXECUTE（客户端与存储过程内）

| 引擎 | 客户端 PREPARE | 过程内 PREPARE | DEALLOCATE | 参数标记风格 | 版本 |
|------|:---:|:---:|:---:|------|------|
| PostgreSQL | ✅ | ✅ | ✅ | `$1, $2` | 7.0+ |
| MySQL | ✅ | ✅ | ✅ | `?` | 4.1+ |
| MariaDB | ✅ | ✅ | ✅ | `?` | 5.0+ |
| SQLite | ✅ (API) | — | ✅ (API) | `?`, `?NNN`, `:name`, `@name`, `$name` | 3.0+ |
| Oracle | ✅ (API) | ✅ (`DBMS_SQL`) | ✅ | `:name` | 7.0+ |
| SQL Server | ✅ (API) | ✅ (`sp_executesql`) | ✅ | `@name` | 6.0+ |
| DB2 | ✅ | ✅ | ✅ | `?` | 7.0+ |
| Snowflake | ✅ (API) | ✅ | — | `?`, `:name` | GA |
| BigQuery | ✅ (API) | ✅ | — | `@name` | GA |
| Redshift | ✅ | ✅ | ✅ | `$1, $2` | GA |
| DuckDB | ✅ | — | ✅ | `$1, $2`, `?` | 0.2+ |
| ClickHouse | ✅ (API) | — | — | `{name:type}` | 21.1+ |
| Trino | ✅ | — | ✅ | `?` (JDBC) | 早期 |
| Presto | ✅ | — | ✅ | `?` (JDBC) | 0.100+ |
| Spark SQL | ✅ (API) | — | — | `?` (JDBC) | 1.0+ |
| Hive | ✅ (API) | — | — | `?` (JDBC) | 0.14+ |
| Flink SQL | ✅ (API) | — | — | `?` (JDBC) | 1.0+ |
| Databricks | ✅ (API) | ✅ | — | `?`, `:name` | Runtime 14.1+ |
| Teradata | ✅ | ✅ | ✅ | `?` | V2R5+ |
| Greenplum | ✅ | ✅ | ✅ | `$1, $2` | 4.0+ |
| CockroachDB | ✅ | ✅ | ✅ | `$1, $2` | 1.0+ |
| TiDB | ✅ | ✅ | ✅ | `?` | 2.1+ |
| OceanBase | ✅ | ✅ | ✅ | `?`, `:name` (Oracle 模式) | 3.0+ |
| YugabyteDB | ✅ | ✅ | ✅ | `$1, $2` | 2.0+ |
| SingleStore | ✅ | ✅ | ✅ | `?` | 6.0+ |
| Vertica | ✅ | ✅ | ✅ | `?` | 7.0+ |
| Impala | ✅ (API) | — | — | `?` (JDBC) | 2.0+ |
| StarRocks | ✅ (API) | — | — | `?` (JDBC) | 2.0+ |
| Doris | ✅ (API) | — | — | `?` (JDBC) | 1.0+ |
| MonetDB | ✅ | ✅ | ✅ | `?` | 11.19+ |
| CrateDB | ✅ | — | — | `$1, $2` | 0.57+ |
| TimescaleDB | ✅ | ✅ | ✅ | `$1, $2` | 继承 PG |
| QuestDB | ✅ (API) | — | — | `$1, $2` | 6.0+ |
| Exasol | ✅ | ✅ | ✅ | `?` | 6.0+ |
| SAP HANA | ✅ | ✅ | ✅ | `?` | 1.0+ |
| Informix | ✅ | ✅ | ✅ | `?` | 7.20+ |
| Firebird | ✅ | ✅ | ✅ | `?` | 1.0+ |
| H2 | ✅ | — | ✅ | `?` | 1.0+ |
| HSQLDB | ✅ | ✅ | ✅ | `?` | 2.0+ |
| Derby | ✅ | — | ✅ | `?` | 10.0+ |
| Amazon Athena | ✅ | — | ✅ | `?` | 继承 Trino |
| Azure Synapse | ✅ | ✅ (`sp_executesql`) | — | `@name` | GA |
| Google Spanner | ✅ (API) | — | — | `@name` | GA |
| Materialize | ✅ | — | ✅ | `$1, $2` | 继承 PG 协议 |
| RisingWave | ✅ | — | ✅ | `$1, $2` | 继承 PG 协议 |
| InfluxDB | ✅ (API) | — | — | `$name` (Flight SQL) | 3.0+ |
| DatabendDB | ✅ (API) | — | — | `?` | GA |
| Yellowbrick | ✅ | ✅ | ✅ | `$1, $2` | GA |
| Firebolt | ✅ (API) | — | — | `?` | GA |

### EXECUTE ('string') / EXEC 语法

| 引擎 | EXEC('string') | EXEC sp_executesql | 上下文 | 版本 |
|------|:---:|:---:|------|------|
| SQL Server | ✅ | ✅ | T-SQL 批处理/过程 | 6.0+ |
| Azure Synapse | ✅ | ✅ | T-SQL 兼容 | GA |
| SAP HANA | ✅ `EXEC` | ❌ | SQLScript | 1.0+ |
| MySQL | ❌ | ❌ | — | — |
| MariaDB | ❌ | ❌ | — | — |
| PostgreSQL | ❌ | ❌ | — | — |
| Oracle | ❌ | ❌ | — | — |
| DB2 | ❌ | ❌ | — | — |
| 其他引擎 | ❌ | ❌ | T-SQL 风格仅限 SQL Server 家族 | — |

> `EXEC('string')` / `EXECUTE('string')` 是 T-SQL 独有的动态 SQL 形式。注意：此形式不支持参数化，存在 SQL 注入风险，微软推荐使用 `sp_executesql` 替代。

### DBMS_SQL 包（Oracle 风格）

| 引擎 | DBMS_SQL | 等价机制 | 说明 | 版本 |
|------|:---:|------|------|------|
| Oracle | ✅ | — | 完整的动态 SQL API：OPEN_CURSOR, PARSE, BIND_VARIABLE, EXECUTE, FETCH_ROWS | 7.1+ |
| DB2 | ❌ | `PREPARE / EXECUTE` | SQL/PSM 标准方式 | — |
| PostgreSQL | ❌ | `EXECUTE` in PL/pgSQL | PL/pgSQL 原生 EXECUTE 更简洁 | — |
| OceanBase | ✅ | — | Oracle 模式兼容 DBMS_SQL | 3.0+ |
| Exasol | ❌ | `EXECUTE IMMEDIATE` | 脚本语言内执行 | — |
| SAP HANA | ❌ | `EXECUTE IMMEDIATE` / `EXEC` | SQLScript 方式 | — |
| Informix | ❌ | `EXECUTE IMMEDIATE` / `PREPARE` | SPL 方式 | — |

> `DBMS_SQL` 是 Oracle 的底层动态 SQL 包，提供逐步构建和执行 SQL 的能力。对于大多数场景，Oracle 推荐使用更简洁的 `EXECUTE IMMEDIATE`（即原生动态 SQL, NDS）。`DBMS_SQL` 主要用于列数/类型在编译期未知的场景（如通用报表生成器）。

### 动态游标 (Dynamic Cursor)

| 引擎 | OPEN cursor FOR string | REF CURSOR | SYS_REFCURSOR | 版本 |
|------|:---:|:---:|:---:|------|
| PostgreSQL | ✅ `OPEN cur FOR EXECUTE <string>` | ✅ `REFCURSOR` | ❌ | 7.1+ |
| MySQL | ❌ | ❌ | ❌ | — |
| MariaDB | ❌ | ❌ | ❌ | — |
| Oracle | ✅ `OPEN cur FOR <string>` | ✅ | ✅ | 7.3+ |
| SQL Server | ❌ (通过 sp_executesql 间接) | ❌ | ❌ | — |
| DB2 | ✅ `DECLARE cur CURSOR FOR <stmt>` | ❌ | ❌ | 7.0+ |
| Snowflake | ✅ `OPEN cur FOR <string>` | ✅ `RESULTSET` | ❌ | GA |
| BigQuery | ❌ | ❌ | ❌ | — |
| Redshift | ✅ `OPEN cur FOR EXECUTE <string>` | ✅ `REFCURSOR` | ❌ | GA |
| Greenplum | ✅ `OPEN cur FOR EXECUTE <string>` | ✅ `REFCURSOR` | ❌ | 4.0+ |
| CockroachDB | ✅ (23.2+) | ❌ | ❌ | 23.2+ |
| YugabyteDB | ✅ `OPEN cur FOR EXECUTE <string>` | ✅ `REFCURSOR` | ❌ | 2.0+ |
| OceanBase | ✅ (Oracle 模式) | ✅ (Oracle 模式) | ✅ (Oracle 模式) | 3.0+ |
| Vertica | ✅ `FOR row IN EXECUTE <string>` | ❌ | ❌ | 9.0+ |
| SAP HANA | ✅ `OPEN cur FOR <string>` | ❌ | ❌ | 1.0+ |
| Informix | ✅ `DECLARE cur CURSOR FOR <stmt>` | ❌ | ❌ | 7.20+ |
| Firebird | ✅ `FOR EXECUTE STATEMENT <string> INTO` | ❌ | ❌ | 2.0+ |
| Exasol | ✅ `OPEN cur FOR <string>` | ❌ | ❌ | 6.0+ |
| TimescaleDB | ✅ (继承 PG) | ✅ (继承 PG) | ❌ | 继承 PG |
| Yellowbrick | ✅ (PL/pgSQL 兼容) | ✅ | ❌ | GA |
| HSQLDB | ✅ `DECLARE cur CURSOR FOR <stmt>` | ❌ | ❌ | 2.0+ |
| MonetDB | ✅ `DECLARE cur CURSOR FOR <stmt>` | ❌ | ❌ | 11.19+ |
| Teradata | ✅ `DECLARE cur CURSOR FOR <stmt>` | ❌ | ❌ | V14+ |

> 注：MySQL 和 MariaDB 的游标只能用于静态 SQL，不支持 `OPEN cursor FOR <dynamic_string>`。动态查询结果只能通过 `PREPARE / EXECUTE` 在存储过程中间接处理。

### EXECUTE ... INTO (捕获结果)

| 引擎 | INTO 变量 | INTO 记录 | 语法 | 版本 |
|------|:---:|:---:|------|------|
| PostgreSQL | ✅ | ✅ | `EXECUTE <string> INTO [STRICT] <var>` | 7.0+ |
| Oracle | ✅ | ✅ | `EXECUTE IMMEDIATE <string> INTO <var>` | 8i+ |
| MariaDB | ✅ | ❌ | `EXECUTE IMMEDIATE <string> INTO <var>` | 10.2.3+ |
| DB2 | ✅ | ✅ | `EXECUTE <stmt> INTO <var>` | 7.0+ |
| Snowflake | ✅ | ❌ | `EXECUTE IMMEDIATE <string> INTO :<var>` | GA |
| BigQuery | ✅ | ❌ | `EXECUTE IMMEDIATE <string> INTO <var>` | 2020+ |
| Redshift | ✅ | ✅ | `EXECUTE <string> INTO <var>` | GA |
| Greenplum | ✅ | ✅ | `EXECUTE <string> INTO <var>` | 4.0+ |
| CockroachDB | ✅ | ❌ | `EXECUTE <string> INTO <var>` | 23.1+ |
| YugabyteDB | ✅ | ✅ | `EXECUTE <string> INTO <var>` | 2.0+ |
| OceanBase | ✅ | ✅ | `EXECUTE IMMEDIATE <string> INTO <var>` | 3.0+ |
| Vertica | ✅ | ❌ | `EXECUTE <string> INTO <var>` | 9.0+ |
| SAP HANA | ✅ | ❌ | `EXECUTE IMMEDIATE <string> INTO <var>` | 2.0+ |
| Informix | ✅ | ✅ | `EXECUTE <stmt> INTO <var>` | 7.20+ |
| Firebird | ✅ | ❌ | `EXECUTE STATEMENT <string> INTO <var>` | 2.0+ |
| Exasol | ✅ | ❌ | `EXECUTE IMMEDIATE <string> INTO <var>` | 6.0+ |
| HSQLDB | ✅ | ❌ | `EXECUTE <stmt> INTO <var>` | 2.0+ |
| Databricks | ✅ | ❌ | `EXECUTE IMMEDIATE <string> INTO <var>` | Runtime 14.1+ |
| TimescaleDB | ✅ | ✅ | 继承 PG | 继承 PG |
| Yellowbrick | ✅ | ✅ | `EXECUTE <string> INTO <var>` | GA |
| MonetDB | ✅ | ❌ | `EXECUTE <stmt> INTO <var>` | 11.19+ |
| MySQL | ❌ | ❌ | 使用 PREPARE + `SELECT ... INTO` 间接实现 | — |
| SQL Server | ❌ | ❌ | 通过 sp_executesql OUTPUT 参数间接实现 | — |

### EXECUTE ... USING (参数传递)

| 引擎 | USING 位置参数 | USING 命名参数 | 语法 | 版本 |
|------|:---:|:---:|------|------|
| PostgreSQL | ✅ | ❌ | `EXECUTE <string> USING <val1>, <val2>` | 8.4+ |
| Oracle | ✅ | ❌ | `EXECUTE IMMEDIATE <string> USING [IN\|OUT\|IN OUT] <val>` | 8i+ |
| MariaDB | ✅ | ❌ | `EXECUTE IMMEDIATE <string> USING <val>` | 10.2.3+ |
| DB2 | ✅ | ❌ | `EXECUTE <stmt> USING <val>` | 7.0+ |
| MySQL | ✅ | ❌ | `EXECUTE <stmt> USING @var1, @var2` | 4.1+ |
| Snowflake | ✅ | ✅ | `EXECUTE IMMEDIATE <string> USING (<val>)` | GA |
| BigQuery | ✅ | ✅ | `EXECUTE IMMEDIATE <string> USING <val> AS name` | 2020+ |
| Redshift | ✅ | ❌ | `EXECUTE <string> USING <val>` | GA |
| Greenplum | ✅ | ❌ | `EXECUTE <string> USING <val>` | 5.0+ |
| CockroachDB | ✅ | ❌ | `EXECUTE <string> USING <val>` | 23.1+ |
| YugabyteDB | ✅ | ❌ | `EXECUTE <string> USING <val>` | 2.0+ |
| OceanBase | ✅ | ❌ | `EXECUTE IMMEDIATE <string> USING <val>` | 3.0+ |
| Vertica | ✅ | ❌ | `EXECUTE <string> USING <val>` | 9.0+ |
| SAP HANA | ✅ | ❌ | `EXECUTE IMMEDIATE <string> USING <val>` | 2.0+ |
| Informix | ✅ | ❌ | `EXECUTE <stmt> USING <val>` | 7.20+ |
| Firebird | ✅ | ❌ | `EXECUTE STATEMENT (<string>) (<val>)` | 2.0+ |
| Exasol | ✅ | ❌ | `EXECUTE IMMEDIATE <string> USING <val>` | 6.0+ |
| HSQLDB | ✅ | ❌ | `EXECUTE <stmt> USING <val>` | 2.0+ |
| Databricks | ✅ | ✅ | `EXECUTE IMMEDIATE <string> USING <val>` | Runtime 14.1+ |
| Teradata | ✅ | ❌ | `EXECUTE <stmt> USING <val>` | V14+ |
| TimescaleDB | ✅ | ❌ | 继承 PG | 继承 PG |
| Yellowbrick | ✅ | ❌ | `EXECUTE <string> USING <val>` | GA |
| MonetDB | ✅ | ❌ | `EXECUTE <stmt> USING <val>` | 11.19+ |
| SQL Server | ❌ | ✅ | `sp_executesql N'...', N'@p1 int', @p1 = <val>` | 6.5+ |
| SingleStore | ✅ | ❌ | `EXECUTE <stmt> USING @var1, @var2` | 6.0+ |
| TiDB | ✅ | ❌ | `EXECUTE <stmt> USING @var1, @var2` | 2.1+ |

### DDL 在动态 SQL 中的执行

| 引擎 | 支持动态 DDL | 限制 | 版本 |
|------|:---:|------|------|
| PostgreSQL | ✅ | 无限制 | 7.0+ |
| MySQL | ✅ | 无限制 | 4.1+ |
| MariaDB | ✅ | 无限制 | 5.0+ |
| Oracle | ✅ | PL/SQL 中的 DDL 必须通过 EXECUTE IMMEDIATE | 8i+ |
| SQL Server | ✅ | 无限制 | 6.0+ |
| DB2 | ✅ | 大部分 DDL 支持，部分需 EXECUTE IMMEDIATE | 7.0+ |
| Snowflake | ✅ | 无限制 | GA |
| BigQuery | ✅ | 无限制 | 2020+ |
| Redshift | ✅ | 无限制 | GA |
| Greenplum | ✅ | 无限制 | 4.0+ |
| CockroachDB | ✅ | 无限制 | 23.1+ |
| YugabyteDB | ✅ | 无限制 | 2.0+ |
| OceanBase | ✅ | Oracle 模式 PL 中 DDL 必须通过 EXECUTE IMMEDIATE | 3.0+ |
| Vertica | ✅ | 无限制 | 9.0+ |
| SAP HANA | ✅ | 无限制 | 1.0+ |
| Informix | ✅ | 无限制 | 7.20+ |
| Firebird | ✅ | 无限制 | 2.0+ |
| Exasol | ✅ | 无限制 | 6.0+ |
| Teradata | ✅ | 通过 CALL DBC.SysExecSQL 或 PREPARE | V14+ |
| TimescaleDB | ✅ | 继承 PG | 继承 PG |
| Yellowbrick | ✅ | 无限制 | GA |
| Databricks | ✅ | 无限制 | Runtime 14.1+ |
| MonetDB | ✅ | 无限制 | 11.19+ |
| HSQLDB | ✅ | 无限制 | 2.0+ |
| SingleStore | ✅ | 无限制 | 6.0+ |
| TiDB | ✅ | 无限制 | 2.1+ |
| MariaDB | ✅ | 无限制 | 5.0+ |

> 关键差异：Oracle 和 OceanBase（Oracle 模式）在 PL/SQL 块中不允许直接写静态 DDL（如 `CREATE TABLE`），必须通过 `EXECUTE IMMEDIATE` 执行。这是 PL/SQL 的设计约束——编译器无法在编译期验证 DDL 语句的语义。

### SQL 注入防护机制

| 引擎 | 参数绑定 | DBMS_ASSERT/QUOTENAME | 白名单校验函数 | FORMAT/quote_ident | 版本 |
|------|:---:|:---:|:---:|:---:|------|
| PostgreSQL | ✅ `USING $1` | ❌ | ❌ | ✅ `quote_ident()`, `quote_literal()`, `format('%I', ...)` | 7.0+ |
| MySQL | ✅ `USING ?` | ❌ | ❌ | ❌ | 4.1+ |
| MariaDB | ✅ `USING ?` | ❌ | ❌ | ❌ | 5.0+ |
| Oracle | ✅ `USING :name` | ✅ `DBMS_ASSERT` | ✅ | ❌ | 10gR2+ |
| SQL Server | ✅ `sp_executesql @name` | ✅ `QUOTENAME()` | ❌ | ❌ | 6.5+ |
| DB2 | ✅ `USING ?` | ❌ | ❌ | ❌ | 7.0+ |
| Snowflake | ✅ `USING ?/:name` | ❌ | ❌ | ❌ | GA |
| BigQuery | ✅ `USING @name` | ❌ | ❌ | ❌ | 2020+ |
| Redshift | ✅ `USING $1` | ❌ | ❌ | ✅ `quote_ident()`, `quote_literal()` | GA |
| Greenplum | ✅ `USING $1` | ❌ | ❌ | ✅ `quote_ident()`, `quote_literal()` | 4.0+ |
| CockroachDB | ✅ `USING $1` | ❌ | ❌ | ✅ `quote_ident()` | 23.1+ |
| YugabyteDB | ✅ `USING $1` | ❌ | ❌ | ✅ `quote_ident()`, `quote_literal()` | 2.0+ |
| OceanBase | ✅ `USING` | ✅ (Oracle 模式) | ✅ (Oracle 模式) | ❌ | 3.0+ |
| SAP HANA | ✅ `USING ?` | ❌ | ❌ | ✅ `ESCAPE_SINGLE_QUOTES()` | 1.0+ |
| Firebird | ✅ | ❌ | ❌ | ❌ | 2.0+ |
| Exasol | ✅ `USING ?` | ❌ | ❌ | ❌ | 6.0+ |
| Vertica | ✅ `USING` | ❌ | ❌ | ✅ `QUOTE_IDENT()` | 9.0+ |
| Informix | ✅ `USING` | ❌ | ❌ | ❌ | 7.20+ |
| TimescaleDB | ✅ | ❌ | ❌ | ✅ (继承 PG) | 继承 PG |
| Yellowbrick | ✅ | ❌ | ❌ | ✅ (PG 兼容) | GA |
| SQL Server (Azure Synapse) | ✅ | ✅ `QUOTENAME()` | ❌ | ❌ | GA |
| Teradata | ✅ `USING ?` | ❌ | ❌ | ❌ | V14+ |

## 各引擎详细语法与示例

### PostgreSQL — EXECUTE in PL/pgSQL

PostgreSQL 的动态 SQL 通过 PL/pgSQL 中的 `EXECUTE` 命令实现，不使用 `EXECUTE IMMEDIATE` 关键字：

```sql
-- 基本动态 SQL
DO $$
DECLARE
    v_table TEXT := 'users';
    v_count INT;
BEGIN
    EXECUTE 'SELECT count(*) FROM ' || quote_ident(v_table)
    INTO v_count;
    RAISE NOTICE 'Count: %', v_count;
END;
$$;

-- 带参数绑定的动态 SQL (8.4+)
DO $$
DECLARE
    v_min_age INT := 18;
    v_count INT;
BEGIN
    EXECUTE 'SELECT count(*) FROM users WHERE age > $1'
    INTO v_count
    USING v_min_age;
    RAISE NOTICE 'Count: %', v_count;
END;
$$;

-- format() 安全构建动态标识符 (9.1+)
DO $$
DECLARE
    v_schema TEXT := 'public';
    v_table TEXT := 'users';
    v_col TEXT := 'email';
BEGIN
    EXECUTE format('ALTER TABLE %I.%I ADD COLUMN %I TEXT', v_schema, v_table, v_col);
END;
$$;

-- 动态游标
DO $$
DECLARE
    v_cur REFCURSOR;
    v_rec RECORD;
BEGIN
    OPEN v_cur FOR EXECUTE 'SELECT * FROM users WHERE active = $1' USING true;
    LOOP
        FETCH v_cur INTO v_rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'User: %', v_rec.name;
    END LOOP;
    CLOSE v_cur;
END;
$$;
```

> 关键点：PostgreSQL 的 `format('%I', name)` 是最安全的标识符引用机制——`%I` 自动加双引号（仅在必要时），`%L` 自动加单引号并转义，`%s` 无转义（慎用）。

### MySQL — PREPARE / EXECUTE

MySQL 不支持 `EXECUTE IMMEDIATE`，所有动态 SQL 都通过 `PREPARE / EXECUTE / DEALLOCATE PREPARE` 三步完成：

```sql
-- 基本用法（会话级别）
SET @sql = 'SELECT * FROM users WHERE id = ?';
SET @id = 42;
PREPARE stmt FROM @sql;
EXECUTE stmt USING @id;
DEALLOCATE PREPARE stmt;

-- 存储过程中的动态 SQL
DELIMITER //
CREATE PROCEDURE dynamic_query(IN p_table VARCHAR(64), IN p_limit INT)
BEGIN
    SET @sql = CONCAT('SELECT * FROM ', p_table, ' LIMIT ?');
    SET @lim = p_limit;
    PREPARE stmt FROM @sql;
    EXECUTE stmt USING @lim;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;

-- 动态 DDL
SET @sql = 'CREATE TABLE IF NOT EXISTS test_tbl (id INT PRIMARY KEY, name VARCHAR(100))';
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
```

> 注意：MySQL 的 `PREPARE` 只能使用用户变量（`@var`），不能使用局部变量。参数标记只有 `?`（位置参数），不支持命名参数。每个 `PREPARE` 只能包含一条 SQL 语句。

### MariaDB — EXECUTE IMMEDIATE (10.2.3+)

MariaDB 在 MySQL 兼容的基础上新增了 `EXECUTE IMMEDIATE`，简化了动态 SQL 的使用：

```sql
-- EXECUTE IMMEDIATE: 一步完成 (10.2.3+)
EXECUTE IMMEDIATE 'SELECT * FROM users WHERE id = ?' USING 42;

-- 带 INTO 的 EXECUTE IMMEDIATE
DECLARE v_name VARCHAR(100);
EXECUTE IMMEDIATE 'SELECT name FROM users WHERE id = ?' INTO v_name USING 42;

-- 也兼容 MySQL 的三步方式
PREPARE stmt FROM 'SELECT * FROM users WHERE age > ?';
EXECUTE stmt USING @min_age;
DEALLOCATE PREPARE stmt;

-- 匿名块中的使用 (10.1.1+)
BEGIN NOT ATOMIC
    DECLARE v_tbl VARCHAR(64) DEFAULT 'users';
    DECLARE v_cnt INT;
    EXECUTE IMMEDIATE CONCAT('SELECT COUNT(*) FROM ', v_tbl) INTO v_cnt;
    SELECT v_cnt;
END;
```

### Oracle — EXECUTE IMMEDIATE / DBMS_SQL

Oracle 提供两种动态 SQL 机制：原生动态 SQL（NDS，推荐）和 `DBMS_SQL`（底层 API）：

```sql
-- 原生动态 SQL (NDS) — EXECUTE IMMEDIATE
DECLARE
    v_count NUMBER;
    v_name  VARCHAR2(100);
BEGIN
    -- 简单动态查询
    EXECUTE IMMEDIATE 'SELECT count(*) FROM employees' INTO v_count;

    -- 带绑定变量
    EXECUTE IMMEDIATE 'SELECT name FROM employees WHERE id = :1'
    INTO v_name USING 1001;

    -- 动态 DDL
    EXECUTE IMMEDIATE 'CREATE TABLE temp_tbl (id NUMBER, val VARCHAR2(100))';

    -- 动态 DML，带 RETURNING
    EXECUTE IMMEDIATE 'UPDATE employees SET salary = salary * 1.1 WHERE id = :1
                        RETURNING name INTO :2'
    USING 1001
    RETURNING INTO v_name;
END;
/

-- 动态游标 (REF CURSOR)
DECLARE
    TYPE cur_type IS REF CURSOR;
    v_cur cur_type;
    v_name VARCHAR2(100);
BEGIN
    OPEN v_cur FOR 'SELECT name FROM employees WHERE dept_id = :1' USING 10;
    LOOP
        FETCH v_cur INTO v_name;
        EXIT WHEN v_cur%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE(v_name);
    END LOOP;
    CLOSE v_cur;
END;
/

-- DBMS_SQL — 列数在编译期未知时使用
DECLARE
    v_cursor  INTEGER;
    v_status  INTEGER;
    v_val     VARCHAR2(4000);
    v_col_cnt INTEGER;
    v_desc    DBMS_SQL.DESC_TAB;
BEGIN
    v_cursor := DBMS_SQL.OPEN_CURSOR;
    DBMS_SQL.PARSE(v_cursor, 'SELECT * FROM employees WHERE dept_id = :dept', DBMS_SQL.NATIVE);
    DBMS_SQL.BIND_VARIABLE(v_cursor, ':dept', 10);

    v_status := DBMS_SQL.EXECUTE(v_cursor);
    DBMS_SQL.DESCRIBE_COLUMNS(v_cursor, v_col_cnt, v_desc);

    FOR i IN 1..v_col_cnt LOOP
        DBMS_SQL.DEFINE_COLUMN(v_cursor, i, v_val, 4000);
    END LOOP;

    WHILE DBMS_SQL.FETCH_ROWS(v_cursor) > 0 LOOP
        FOR i IN 1..v_col_cnt LOOP
            DBMS_SQL.COLUMN_VALUE(v_cursor, i, v_val);
            DBMS_OUTPUT.PUT(v_val || ' | ');
        END LOOP;
        DBMS_OUTPUT.NEW_LINE;
    END LOOP;
    DBMS_SQL.CLOSE_CURSOR(v_cursor);
END;
/
```

> Oracle 安全提示：`DBMS_ASSERT` 包（10gR2+）提供了标识符验证函数——`SCHEMA_NAME()`、`SQL_OBJECT_NAME()`、`SIMPLE_SQL_NAME()` 和 `ENQUOTE_NAME()`，用于验证动态构建的标识符，防止 SQL 注入。

### SQL Server — EXEC() / sp_executesql

SQL Server 提供两种动态 SQL 机制，强烈推荐使用 `sp_executesql`：

```sql
-- EXEC() — 简单但不安全（不支持参数化）
DECLARE @sql NVARCHAR(MAX);
SET @sql = N'SELECT * FROM users WHERE id = ' + CAST(@id AS NVARCHAR(10));
EXEC(@sql);  -- 存在 SQL 注入风险!

-- sp_executesql — 参数化动态 SQL（推荐）
DECLARE @sql NVARCHAR(MAX);
DECLARE @params NVARCHAR(200);
DECLARE @count INT;

SET @sql = N'SELECT @cnt = COUNT(*) FROM users WHERE age > @min_age';
SET @params = N'@min_age INT, @cnt INT OUTPUT';
EXEC sp_executesql @sql, @params, @min_age = 18, @cnt = @count OUTPUT;
PRINT @count;

-- 动态 DDL
DECLARE @tbl NVARCHAR(128) = N'test_table';
DECLARE @sql2 NVARCHAR(MAX);
SET @sql2 = N'CREATE TABLE ' + QUOTENAME(@tbl) + N' (id INT PRIMARY KEY, name NVARCHAR(100))';
EXEC sp_executesql @sql2;

-- QUOTENAME() 防注入
DECLARE @col NVARCHAR(128) = N'user_name';
DECLARE @sql3 NVARCHAR(MAX);
SET @sql3 = N'SELECT ' + QUOTENAME(@col) + N' FROM users';
EXEC sp_executesql @sql3;
```

> 关键区别：`EXEC(@sql)` 在当前会话上下文执行，`sp_executesql` 创建独立参数化查询，可利用查询计划缓存。微软官方文档明确推荐始终使用 `sp_executesql`。

### DB2 — EXECUTE IMMEDIATE / PREPARE

DB2 遵循 SQL/PSM 标准，同时支持 `EXECUTE IMMEDIATE` 和 `PREPARE / EXECUTE`：

```sql
-- EXECUTE IMMEDIATE
CREATE PROCEDURE dynamic_ddl(IN p_table VARCHAR(128))
LANGUAGE SQL
BEGIN
    DECLARE v_sql VARCHAR(1000);
    SET v_sql = 'CREATE TABLE ' || p_table || ' (id INT, name VARCHAR(100))';
    EXECUTE IMMEDIATE v_sql;
END;

-- PREPARE / EXECUTE
CREATE PROCEDURE find_user(IN p_id INT, OUT p_name VARCHAR(100))
LANGUAGE SQL
BEGIN
    DECLARE v_sql VARCHAR(500);
    DECLARE v_stmt STATEMENT;
    SET v_sql = 'SELECT name FROM users WHERE id = ?';
    PREPARE v_stmt FROM v_sql;
    EXECUTE v_stmt INTO p_name USING p_id;
END;

-- 动态游标
CREATE PROCEDURE list_by_dept(IN p_dept INT)
LANGUAGE SQL
BEGIN
    DECLARE v_sql VARCHAR(500);
    DECLARE v_stmt STATEMENT;
    DECLARE v_cur CURSOR FOR v_stmt;
    DECLARE v_name VARCHAR(100);

    SET v_sql = 'SELECT name FROM employees WHERE dept_id = ?';
    PREPARE v_stmt FROM v_sql;
    OPEN v_cur USING p_dept;
    FETCH v_cur INTO v_name;
    WHILE SQLCODE = 0 DO
        -- 处理结果
        FETCH v_cur INTO v_name;
    END WHILE;
    CLOSE v_cur;
END;
```

### Snowflake — Snowflake Scripting

Snowflake 在 Snowflake Scripting（2021+ GA）中支持 `EXECUTE IMMEDIATE` 和 `RESULTSET`：

```sql
-- EXECUTE IMMEDIATE 基本用法
EXECUTE IMMEDIATE 'CREATE TABLE test_tbl (id INT, name STRING)';

-- Snowflake Scripting 块中的动态 SQL
DECLARE
    v_table STRING DEFAULT 'users';
    v_count NUMBER;
    v_sql STRING;
    res RESULTSET;
BEGIN
    -- 简单查询 INTO
    v_sql := 'SELECT COUNT(*) FROM ' || :v_table;
    EXECUTE IMMEDIATE :v_sql INTO :v_count;

    -- 带参数的动态 SQL
    EXECUTE IMMEDIATE 'SELECT * FROM users WHERE age > ?' USING (18);

    -- RESULTSET 捕获动态查询结果
    res := (EXECUTE IMMEDIATE 'SELECT * FROM users LIMIT 10');
    RETURN TABLE(res);
END;

-- 过程中使用
CREATE OR REPLACE PROCEDURE run_dynamic(sql_text STRING)
RETURNS TABLE()
LANGUAGE SQL
AS
DECLARE
    res RESULTSET;
BEGIN
    res := (EXECUTE IMMEDIATE :sql_text);
    RETURN TABLE(res);
END;
```

### BigQuery — 脚本中的 EXECUTE IMMEDIATE

BigQuery 在脚本模式（Scripting, 2020+）中支持 `EXECUTE IMMEDIATE`：

```sql
-- 基本 EXECUTE IMMEDIATE
EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM `project.dataset.table`';

-- 带参数
DECLARE count_val INT64;
EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM `project.dataset.users` WHERE age > @min_age'
INTO count_val
USING 18 AS min_age;

-- 动态 DDL
DECLARE table_name STRING DEFAULT 'new_table';
EXECUTE IMMEDIATE FORMAT('CREATE TABLE `project.dataset.%s` (id INT64, name STRING)', table_name);

-- 多参数绑定
DECLARE result STRING;
EXECUTE IMMEDIATE '''
    SELECT name FROM `project.dataset.users`
    WHERE age BETWEEN @lo AND @hi
    LIMIT 1
'''
INTO result
USING 18 AS lo, 30 AS hi;
```

> BigQuery 使用 `@name` 命名参数标记，在 `USING` 子句中通过 `AS name` 绑定。不支持位置参数 `?`。

### Redshift — PL/pgSQL 兼容

Redshift 的存储过程使用 PL/pgSQL 方言，动态 SQL 语法与 PostgreSQL 基本一致：

```sql
CREATE OR REPLACE PROCEDURE dynamic_count(p_table VARCHAR, INOUT p_count INT)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE 'SELECT COUNT(*) FROM ' || p_table INTO p_count;
END;
$$;

-- 带 USING 参数
CREATE OR REPLACE PROCEDURE find_user(p_id INT, INOUT p_name VARCHAR)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE 'SELECT name FROM users WHERE id = $1' INTO p_name USING p_id;
END;
$$;
```

### Firebird — EXECUTE STATEMENT

Firebird 使用独特的 `EXECUTE STATEMENT` 语法（而非标准的 `EXECUTE IMMEDIATE`）：

```sql
-- EXECUTE STATEMENT 基本用法
CREATE PROCEDURE dynamic_count(tbl_name VARCHAR(63))
RETURNS (cnt INTEGER)
AS
BEGIN
    EXECUTE STATEMENT ('SELECT COUNT(*) FROM ' || tbl_name) INTO :cnt;
    SUSPEND;
END;

-- 带参数绑定 (Firebird 2.5+)
EXECUTE STATEMENT ('SELECT name FROM users WHERE id = ?') (42) INTO :v_name;

-- FOR EXECUTE STATEMENT 遍历结果集
CREATE PROCEDURE list_all(tbl_name VARCHAR(63))
RETURNS (col_val VARCHAR(1000))
AS
BEGIN
    FOR EXECUTE STATEMENT ('SELECT name FROM ' || tbl_name)
    INTO :col_val
    DO SUSPEND;
END;

-- 命名参数 (Firebird 2.5+)
EXECUTE STATEMENT ('SELECT * FROM users WHERE id = :id AND active = :flag')
    (id := 42, flag := 1)
INTO :v_name;
```

### SAP HANA — SQLScript 动态 SQL

SAP HANA 在 SQLScript 中同时支持 `EXECUTE IMMEDIATE` 和 `EXEC`：

```sql
-- EXECUTE IMMEDIATE
CREATE PROCEDURE dynamic_query(IN p_table NVARCHAR(128), OUT p_count INTEGER)
LANGUAGE SQLSCRIPT
AS
BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) INTO p_count FROM ' || :p_table;
END;

-- EXEC 简写
DO BEGIN
    DECLARE v_sql NVARCHAR(1000);
    v_sql := 'CREATE TABLE test_tbl (id INT, name NVARCHAR(100))';
    EXEC :v_sql;
END;

-- EXECUTE IMMEDIATE ... INTO ... USING (HANA 2.0+)
DO BEGIN
    DECLARE v_count INT;
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM users WHERE age > ?' INTO v_count USING 18;
END;

-- 安全：ESCAPE_SINGLE_QUOTES
DO BEGIN
    DECLARE v_name NVARCHAR(100) := 'O''Brien';
    DECLARE v_sql NVARCHAR(1000);
    v_sql := 'SELECT * FROM users WHERE name = ''' || ESCAPE_SINGLE_QUOTES(:v_name) || '''';
    EXEC :v_sql;
END;
```

### Informix — SPL 动态 SQL

```sql
-- EXECUTE IMMEDIATE
CREATE PROCEDURE exec_ddl(p_sql VARCHAR(1000))
    EXECUTE IMMEDIATE p_sql;
END PROCEDURE;

-- PREPARE / EXECUTE
CREATE PROCEDURE find_user(p_id INT)
    DEFINE v_name VARCHAR(100);
    DEFINE v_stmt VARCHAR(500);

    LET v_stmt = 'SELECT name FROM users WHERE id = ?';
    PREPARE s1 FROM v_stmt;
    EXECUTE s1 INTO v_name USING p_id;
    FREE s1;
END PROCEDURE;

-- 动态游标
CREATE PROCEDURE list_by_dept(p_dept INT)
    DEFINE v_name VARCHAR(100);

    PREPARE s2 FROM 'SELECT name FROM employees WHERE dept_id = ?';
    DECLARE c2 CURSOR FOR s2;
    OPEN c2 USING p_dept;
    WHILE 1=1
        FETCH c2 INTO v_name;
        IF SQLCODE != 0 THEN EXIT WHILE; END IF;
    END WHILE;
    CLOSE c2;
    FREE s2;
END PROCEDURE;
```

### Vertica — PL/vSQL 动态 SQL (9.0+)

```sql
-- 基本 EXECUTE
CREATE PROCEDURE dynamic_count(p_table VARCHAR)
LANGUAGE PLvSQL
AS $$
DECLARE
    v_count INT;
BEGIN
    EXECUTE 'SELECT COUNT(*) FROM ' || quote_ident(p_table) INTO v_count;
    RAISE NOTICE 'Count: %', v_count;
END;
$$;

-- FOR 循环遍历动态结果
CREATE PROCEDURE list_tables(p_schema VARCHAR)
LANGUAGE PLvSQL
AS $$
DECLARE
    v_rec RECORD;
BEGIN
    FOR v_rec IN EXECUTE 'SELECT table_name FROM v_catalog.tables WHERE table_schema = '
                         || quote_literal(p_schema)
    LOOP
        RAISE NOTICE 'Table: %', v_rec.table_name;
    END LOOP;
END;
$$;
```

### Exasol — Scripting 语言动态 SQL

```sql
-- EXECUTE IMMEDIATE
CREATE OR REPLACE SCRIPT run_ddl(p_sql VARCHAR(10000)) AS
    query(p_sql);
/

-- Lua 脚本中的动态 SQL
CREATE OR REPLACE SCRIPT dynamic_count(schema_name, table_name) RETURNS ROWCOUNT AS
    local res = query([[SELECT COUNT(*) FROM ]] .. quote_ident(schema_name) .. '.' .. quote_ident(table_name))
    return res[1][1]
/

-- 存储过程中的 EXECUTE IMMEDIATE (Exasol 7+)
CREATE OR REPLACE PROCEDURE find_count(p_table VARCHAR(128), OUT p_count DECIMAL)
IS
BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || p_table INTO p_count;
END;
/
```

### Teradata — 动态 SQL

Teradata 的过程化 SQL 支持 `PREPARE / EXECUTE`，但不支持 `EXECUTE IMMEDIATE`：

```sql
-- 存储过程中的动态 SQL
CREATE PROCEDURE dynamic_query(IN p_col VARCHAR(30), IN p_val VARCHAR(100))
BEGIN
    DECLARE v_sql VARCHAR(1000);
    DECLARE v_stmt STATEMENT;
    DECLARE v_cur CURSOR FOR v_stmt;

    SET v_sql = 'SELECT * FROM employees WHERE ' || p_col || ' = ?';
    PREPARE v_stmt FROM v_sql;
    OPEN v_cur USING p_val;
    -- FETCH 循环处理结果...
    CLOSE v_cur;
END;

-- 系统过程 DBC.SysExecSQL 执行动态 DDL
CALL DBC.SysExecSQL('CREATE TABLE temp_test (id INTEGER, name VARCHAR(100))');
```

## 分析引擎中的动态 SQL

分析型引擎通常不提供完整的过程化编程能力，但部分引擎通过脚本功能支持有限的动态 SQL。

### Databricks — EXECUTE IMMEDIATE (Runtime 14.1+)

Databricks 在 Runtime 14.1 中引入了 `EXECUTE IMMEDIATE`，支持参数化和结果捕获：

```sql
-- 基本用法
EXECUTE IMMEDIATE 'SELECT current_date()';

-- 命名参数
DECLARE v_count INT;
EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM users WHERE age > :min_age'
INTO v_count
USING 18 AS min_age;

-- 动态表名（通过 IDENTIFIER 函数）
DECLARE v_table STRING DEFAULT 'default.users';
EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM IDENTIFIER(:tbl)' USING v_table AS tbl;
```

### DuckDB — 无内置动态 SQL

DuckDB 当前（1.x）没有过程化语言支持，不提供 `EXECUTE IMMEDIATE` 或等价机制。动态 SQL 只能通过宿主语言（Python、Java 等）的 API 参数化查询实现：

```python
# Python API 参数化查询
import duckdb
conn = duckdb.connect()
conn.execute("SELECT * FROM users WHERE age > ?", [18])
```

### ClickHouse — 无过程化动态 SQL

ClickHouse 没有存储过程或脚本化能力，不支持动态 SQL。参数化查询通过客户端 API 或 `{name:type}` 语法的查询参数实现：

```sql
-- 查询参数 (HTTP 接口)
SELECT * FROM users WHERE age > {min_age:UInt32}
-- 通过 HTTP 参数传入: min_age=18
```

### Trino / Presto — 无动态 SQL

Trino 和 Presto 不支持过程化 SQL，没有动态 SQL 机制。SQL Routine（Trino 419+）是静态定义的，不支持动态语句构建。客户端 PREPARE/EXECUTE 用于参数化查询：

```sql
-- 客户端 PREPARE/EXECUTE
PREPARE my_query FROM SELECT * FROM users WHERE age > ?;
EXECUTE my_query USING 18;
DEALLOCATE PREPARE my_query;
```

### Spark SQL / Hive / Flink SQL — 无 SQL 层动态 SQL

这三个引擎均不在 SQL 层提供动态 SQL 能力。动态查询构建在宿主语言层（Scala/Python/Java）完成：

```scala
// Spark SQL — Scala API
val tableName = "users"
val minAge = 18
spark.sql(s"SELECT * FROM $tableName WHERE age > $minAge")
```

### Amazon Athena — 继承 Trino

Athena 基于 Trino（原 Presto），支持 `PREPARE / EXECUTE` 用于参数化查询，但不支持过程化动态 SQL：

```sql
PREPARE my_stmt FROM SELECT * FROM users WHERE id = ?;
EXECUTE my_stmt USING 42;
DEALLOCATE PREPARE my_stmt;
```

### Google Spanner — 无动态 SQL

Spanner 不支持存储过程或动态 SQL。参数化查询在客户端 API 层实现，使用 `@name` 参数标记：

```sql
-- 客户端参数化查询
SELECT * FROM users WHERE id = @user_id
-- 参数通过 API 绑定
```

### Azure Synapse — T-SQL 兼容

Azure Synapse 的专用 SQL 池（Dedicated SQL Pool）支持 T-SQL 的 `EXEC()` 和 `sp_executesql`：

```sql
-- sp_executesql 参数化
DECLARE @sql NVARCHAR(MAX) = N'SELECT COUNT(*) FROM dbo.users WHERE age > @min';
EXEC sp_executesql @sql, N'@min INT', @min = 18;

-- 注意：Synapse 无服务器 SQL 池 (Serverless) 的 T-SQL 支持有限制
```

## 参数标记风格汇总

不同引擎使用不同的参数占位符语法，这是跨引擎迁移时的常见摩擦点：

```
风格             引擎                                     示例
────────────     ──────────────────────────────────────── ─────────────────────────
? (位置)         MySQL, MariaDB, DB2, SAP HANA,           SELECT * FROM t WHERE id = ?
                 Firebird, Exasol, Informix, Teradata,
                 HSQLDB, Derby, H2, Snowflake,
                 SingleStore, Vertica, DuckDB,
                 Trino, Presto, Spark SQL, Hive,
                 Flink SQL, Impala, DatabendDB, Firebolt

$1, $2 (编号)    PostgreSQL, Redshift, Greenplum,          SELECT * FROM t WHERE id = $1
                 CockroachDB, YugabyteDB, TimescaleDB,      AND age > $2
                 CrateDB, QuestDB, Materialize,
                 RisingWave, Yellowbrick, DuckDB

:name (命名)     Oracle, OceanBase (Oracle 模式),           SELECT * FROM t WHERE id = :user_id
                 Snowflake, Databricks

@name (命名)     SQL Server, Azure Synapse, BigQuery,       SELECT * FROM t WHERE id = @user_id
                 Google Spanner

{name:type}      ClickHouse                                 SELECT * FROM t WHERE id = {uid:UInt32}

$name            SQLite, InfluxDB (Flight SQL)              SELECT * FROM t WHERE id = $user_id
```

> 注意：部分引擎（如 SQLite、DuckDB、Snowflake）同时支持多种参数标记风格，具体取决于使用的客户端接口。

## 安全最佳实践

动态 SQL 是 SQL 注入攻击的主要入口。以下是各引擎推荐的防护手段：

### 原则一：始终使用参数绑定

```sql
-- 危险 ❌
EXECUTE 'SELECT * FROM users WHERE name = ''' || user_input || '''';

-- 安全 ✅ (PostgreSQL)
EXECUTE 'SELECT * FROM users WHERE name = $1' USING user_input;

-- 安全 ✅ (Oracle)
EXECUTE IMMEDIATE 'SELECT * FROM users WHERE name = :1' USING user_input;

-- 安全 ✅ (SQL Server)
EXEC sp_executesql N'SELECT * FROM users WHERE name = @name', N'@name NVARCHAR(100)', @name = @user_input;
```

### 原则二：标识符使用专用引用函数

参数绑定只能用于值，不能用于标识符（表名、列名）。对于动态标识符，必须使用专用的引用/验证函数：

```sql
-- PostgreSQL: quote_ident() 或 format(%I)
EXECUTE format('SELECT * FROM %I.%I', schema_name, table_name);

-- SQL Server: QUOTENAME()
SET @sql = N'SELECT * FROM ' + QUOTENAME(@table_name);

-- Oracle: DBMS_ASSERT.SQL_OBJECT_NAME()
EXECUTE IMMEDIATE 'SELECT * FROM ' || DBMS_ASSERT.SQL_OBJECT_NAME(table_name);

-- Oracle: DBMS_ASSERT.ENQUOTE_NAME()
EXECUTE IMMEDIATE 'SELECT * FROM ' || DBMS_ASSERT.ENQUOTE_NAME(table_name);
```

### 原则三：最小权限

授予执行动态 SQL 的存储过程尽可能少的权限：

```sql
-- PostgreSQL: SECURITY DEFINER 控制执行权限
CREATE FUNCTION safe_count(p_table TEXT) RETURNS BIGINT
SECURITY DEFINER SET search_path = public
LANGUAGE plpgsql AS $$
BEGIN
    -- 白名单验证
    IF p_table NOT IN ('users', 'orders', 'products') THEN
        RAISE EXCEPTION 'Table not allowed: %', p_table;
    END IF;
    RETURN (EXECUTE format('SELECT count(*) FROM %I', p_table));
END;
$$;

-- Oracle: AUTHID CURRENT_USER vs AUTHID DEFINER
CREATE PROCEDURE safe_query(p_table VARCHAR2)
AUTHID CURRENT_USER  -- 使用调用者权限，而非定义者权限
AS ...
```

## 关键发现

1. **标准遵循度低**：SQL:1999 定义了 `EXECUTE IMMEDIATE` 和 `PREPARE/EXECUTE`，但各引擎实现差异巨大。MySQL 完全不支持 `EXECUTE IMMEDIATE`，SQL Server 使用独有的 `EXEC()` / `sp_executesql`，PostgreSQL 简化为 `EXECUTE`（省略 IMMEDIATE）。

2. **三大阵营**：
   - **EXECUTE IMMEDIATE 阵营**：Oracle、DB2、MariaDB、Snowflake、BigQuery、SAP HANA、Exasol、HSQLDB、Informix、OceanBase、MonetDB、Databricks——较接近 SQL 标准
   - **EXECUTE（简化）阵营**：PostgreSQL、Redshift、Greenplum、CockroachDB、YugabyteDB、Vertica、TimescaleDB、Yellowbrick——PL/pgSQL 系列
   - **EXEC / sp_executesql 阵营**：SQL Server、Azure Synapse——T-SQL 独有

3. **参数标记碎片化**：`?`（最广泛）、`$N`（PostgreSQL 系）、`:name`（Oracle 系）、`@name`（SQL Server/BigQuery/Spanner）四种风格互不兼容，是跨引擎迁移的主要障碍。

4. **分析引擎普遍缺失**：ClickHouse、Trino、Presto、Spark SQL、Hive、Flink SQL、DuckDB、Impala、StarRocks、Doris、QuestDB、InfluxDB、CrateDB、Materialize、RisingWave、Firebolt、DatabendDB 等分析/流式引擎不支持过程化动态 SQL，仅通过客户端 API 提供参数化查询。

5. **Firebird 语法独特**：Firebird 使用 `EXECUTE STATEMENT`（而非 `EXECUTE IMMEDIATE`），参数通过括号传递而非 `USING` 子句，在所有引擎中独树一帜。

6. **安全机制不对称**：PostgreSQL 的 `format('%I')`/`quote_ident()` 和 SQL Server 的 `QUOTENAME()` 是最完善的标识符安全引用机制。Oracle 的 `DBMS_ASSERT` 包提供了最全面的验证能力。大多数引擎缺乏内置的标识符安全函数。

7. **INTO 与 USING 的组合**：Oracle、BigQuery、Snowflake、Databricks 支持 `EXECUTE IMMEDIATE ... INTO ... USING` 完整语法链。PostgreSQL 系使用 `EXECUTE ... INTO ... USING`。MySQL 不支持 `INTO`，只能通过 `SELECT ... INTO @var` 间接实现。

8. **动态游标差距**：Oracle（REF CURSOR）、PostgreSQL（REFCURSOR）和 DB2（DECLARE CURSOR FOR statement）提供完善的动态游标支持。MySQL/MariaDB 的游标仅限静态 SQL，这是其过程化能力的显著短板。

9. **DDL 的特殊性**：Oracle/OceanBase 的 PL/SQL 中不允许直接写 DDL，必须通过 `EXECUTE IMMEDIATE`。这是编译型过程语言的设计限制——DDL 在编译期无法进行语义分析。大多数其他引擎允许在过程中直接使用 DDL。

10. **MariaDB 的演进**：MariaDB 10.2.3 引入 `EXECUTE IMMEDIATE` 是对 MySQL 动态 SQL 能力的重要增强，使其从三步式 `PREPARE/EXECUTE/DEALLOCATE` 简化为一步完成，缩小了与 Oracle/DB2 的差距。
