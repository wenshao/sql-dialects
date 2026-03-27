# 存储过程 (STORED PROCEDURES)

各数据库存储过程语法对比，包括创建、参数、变量、游标、异常处理等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 链接 |
|---|---|
| MySQL | [mysql.sql](mysql.sql) |
| PostgreSQL | [postgres.sql](postgres.sql) |
| SQLite | [sqlite.sql](sqlite.sql) |
| Oracle | [oracle.sql](oracle.sql) |
| SQL Server | [sqlserver.sql](sqlserver.sql) |
| MariaDB | [mariadb.sql](mariadb.sql) |
| Firebird | [firebird.sql](firebird.sql) |
| IBM Db2 | [db2.sql](db2.sql) |
| SAP HANA | [saphana.sql](saphana.sql) |

### 大数据 / 分析型引擎
| 方言 | 链接 |
|---|---|
| BigQuery | [bigquery.sql](bigquery.sql) |
| Snowflake | [snowflake.sql](snowflake.sql) |
| ClickHouse | [clickhouse.sql](clickhouse.sql) |
| Hive | [hive.sql](hive.sql) |
| Spark SQL | [spark.sql](spark.sql) |
| Flink SQL | [flink.sql](flink.sql) |
| StarRocks | [starrocks.sql](starrocks.sql) |
| Doris | [doris.sql](doris.sql) |
| Trino | [trino.sql](trino.sql) |
| DuckDB | [duckdb.sql](duckdb.sql) |
| MaxCompute | [maxcompute.sql](maxcompute.sql) |
| Hologres | [hologres.sql](hologres.sql) |

### 云数仓
| 方言 | 链接 |
|---|---|
| Redshift | [redshift.sql](redshift.sql) |
| Azure Synapse | [synapse.sql](synapse.sql) |
| Databricks SQL | [databricks.sql](databricks.sql) |
| Greenplum | [greenplum.sql](greenplum.sql) |
| Impala | [impala.sql](impala.sql) |
| Vertica | [vertica.sql](vertica.sql) |
| Teradata | [teradata.sql](teradata.sql) |

### 分布式 / NewSQL
| 方言 | 链接 |
|---|---|
| TiDB | [tidb.sql](tidb.sql) |
| OceanBase | [oceanbase.sql](oceanbase.sql) |
| CockroachDB | [cockroachdb.sql](cockroachdb.sql) |
| Spanner | [spanner.sql](spanner.sql) |
| YugabyteDB | [yugabytedb.sql](yugabytedb.sql) |
| PolarDB | [polardb.sql](polardb.sql) |
| openGauss | [opengauss.sql](opengauss.sql) |
| TDSQL | [tdsql.sql](tdsql.sql) |

### 国产数据库
| 方言 | 链接 |
|---|---|
| DamengDB | [dameng.sql](dameng.sql) |
| KingbaseES | [kingbase.sql](kingbase.sql) |

### 时序数据库
| 方言 | 链接 |
|---|---|
| TimescaleDB | [timescaledb.sql](timescaledb.sql) |
| TDengine | [tdengine.sql](tdengine.sql) |

### 流处理
| 方言 | 链接 |
|---|---|
| ksqlDB | [ksqldb.sql](ksqldb.sql) |
| Materialize | [materialize.sql](materialize.sql) |

### 嵌入式 / 轻量
| 方言 | 链接 |
|---|---|
| H2 | [h2.sql](h2.sql) |
| Derby | [derby.sql](derby.sql) |

### SQL 标准
| 方言 | 链接 |
|---|---|
| SQL Standard | [sql-standard.sql](sql-standard.sql) |

## 核心差异

1. **过程式语言**：MySQL 用 SQL/PSM（BEGIN...END），PostgreSQL 用 PL/pgSQL（DECLARE...BEGIN...END），Oracle 用 PL/SQL，SQL Server 用 T-SQL，四种语法几乎完全不同
2. **CREATE PROCEDURE vs FUNCTION**：PostgreSQL 11 之前只有 FUNCTION（用 RETURNS VOID 模拟 PROCEDURE），11+ 才支持真正的 PROCEDURE 和事务控制
3. **返回结果集**：MySQL 过程可直接执行 SELECT 返回结果集，PostgreSQL 需要 RETURNS TABLE 或 REFCURSOR，Oracle 用 SYS_REFCURSOR
4. **分析型引擎支持**：BigQuery 支持 Scripting（过程式 SQL），Snowflake 支持 JavaScript/Python 存储过程，ClickHouse/Hive 不支持存储过程

## 选型建议

现代架构趋势是将业务逻辑从存储过程移到应用层，存储过程主要用于：DBA 的维护脚本、数据迁移/ETL、性能关键的批处理。新项目不建议重度依赖存储过程（可移植性差、版本控制困难、调试不便）。

## 版本演进

- PostgreSQL 11+：引入 CREATE PROCEDURE（支持事务控制 COMMIT/ROLLBACK）
- BigQuery 2019+：引入 Scripting 和存储过程支持
- Snowflake：支持 JavaScript/SQL/Python/Scala 编写存储过程，多语言支持是独特优势

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **存储过程** | 不支持存储过程（无过程式语言） | 不支持存储过程 | 支持 Scripting 和 CREATE PROCEDURE | MySQL/PG/Oracle/SQL Server 各有独立过程式语言 |
| **替代方案** | 应用层（Python/Java 等）实现逻辑 | 用物化视图 + 定时任务实现 ETL 逻辑 | EXECUTE IMMEDIATE + Scripting 实现动态逻辑 | 存储过程 + 触发器 |
| **UDF 支持** | 可通过 C API 注册自定义函数 | 支持 UDF（C++/SQL） | 支持 UDF（SQL/JavaScript） | 各方言支持 UDF |
| **事务控制** | 应用层管理事务 | 无事务控制 | Scripting 中无显式事务控制 | PG 11+ PROCEDURE 支持事务控制 |
| **调试能力** | 无数据库端调试 | 无存储过程调试 | 有限的错误信息 | 各方言有不同的调试工具 |
