# 动态 SQL (Dynamic SQL) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| PREPARE / EXECUTE | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| EXECUTE IMMEDIATE | ❌ | ✅ PL/pgSQL | ❌ | ✅ PL/SQL | ❌ | ❌ | ✅ PSQL | ✅ | ✅ |
| sp_executesql | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| EXEC() | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| DBMS_SQL 包 | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 参数化查询 | ✅ ? 占位符 | ✅ $1, $2 | ❌ | ✅ :name | ✅ @param | ✅ ? 占位符 | ✅ ? 占位符 | ✅ ? 占位符 | ✅ ? 占位符 |
| 动态游标 | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
| INTO 变量 | ✅ | ✅ | ❌ | ✅ INTO | ❌ | ✅ | ✅ | ✅ | ✅ |
| USING 参数绑定 | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| DEALLOCATE PREPARE | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| 动态 DDL | ⚠️ PREPARE 内 | ✅ | ❌ | ✅ | ✅ | ⚠️ PREPARE 内 | ✅ | ✅ | ✅ |
| 动态 SQL 在存储过程内 | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| FORMAT / QUOTE 函数 | ❌ | ✅ format() | ❌ | ❌ | ✅ QUOTENAME() | ❌ | ❌ | ❌ | ❌ |
| SQL 注入防护函数 | ❌ | ✅ quote_ident/literal | ❌ | ✅ DBMS_ASSERT | ✅ QUOTENAME | ❌ | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| EXECUTE IMMEDIATE | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| 脚本内动态 SQL | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 参数化查询 | ✅ @param | ✅ :name/? | ❌ | ❌ | ✅ {param} | ❌ | ✅ ? | ✅ $1 | ❌ | ✅ $1 ? | ❌ | ❌ |
| 存储过程动态 SQL | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| EXECUTE IMMEDIATE | ❌ | ❌ | ❌ | ✅ PL/pgSQL | ❌ | ❌ | ❌ |
| sp_executesql | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 存储过程动态 SQL | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| PREPARE / EXECUTE | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| PREPARE / EXECUTE | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| EXECUTE IMMEDIATE | ❌ | ⚠️ Oracle 模式 | ❌ | ❌ | ✅ PL/pgSQL | ⚠️ PG 模式 | ✅ | ❌ | ✅ | ✅ |
| sp_executesql | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| PREPARE / EXECUTE | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| EXECUTE IMMEDIATE | ✅ PL/pgSQL | ❌ | ❌ | ❌ | ❌ | ❌ |
| 动态 SQL 支持 | ✅ | ❌ | ❌ | ⚠️ | ⚠️ | ⚠️ |

## 关键差异

- **MySQL/MariaDB** 使用 PREPARE/EXECUTE/DEALLOCATE，参数用 ? 占位符
- **PostgreSQL** 在 PL/pgSQL 中使用 EXECUTE ... USING，提供 format() 和 quote_ident/quote_literal 防注入
- **Oracle** 使用 EXECUTE IMMEDIATE ... USING 和 DBMS_SQL 包（更灵活但更复杂）
- **SQL Server** 推荐 sp_executesql（支持输出参数），EXEC() 不支持参数化
- **SQLite** 不支持服务端动态 SQL（需在应用层实现）
- **BigQuery/Snowflake** 在脚本（Scripting）中支持 EXECUTE IMMEDIATE
- **ClickHouse/Hive/Spark/Flink** 不支持动态 SQL，需在应用层或调度工具中实现
- **SQL 注入防护**：PostgreSQL 的 quote_ident/quote_literal、SQL Server 的 QUOTENAME、Oracle 的 DBMS_ASSERT 最完善
