# 动态 SQL (DYNAMIC SQL)

各数据库动态 SQL 语法对比，包括 EXECUTE IMMEDIATE、PREPARE、游标等。

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

1. **执行方式**：MySQL 用 PREPARE + EXECUTE + DEALLOCATE，PostgreSQL 用 EXECUTE（PL/pgSQL 中）或 PREPARE，Oracle 用 EXECUTE IMMEDIATE，SQL Server 用 sp_executesql 或 EXEC()
2. **参数绑定**：PostgreSQL/Oracle/SQL Server 支持参数化动态 SQL（防注入），MySQL 的 PREPARE 支持 `?` 占位符
3. **安全风险**：动态 SQL 是 SQL 注入的主要入口，必须使用参数绑定而非字符串拼接
4. **分析型引擎**：大多数分析型引擎不支持存储过程内的动态 SQL，BigQuery 的 EXECUTE IMMEDIATE 是例外

## 选型建议

动态 SQL 应作为最后手段使用：表名/列名动态时无法避免，但 WHERE 条件值应始终用参数绑定。生产环境的动态 SQL 必须做白名单校验（只允许预定义的表名/列名）。优先考虑用 ORM 或应用层生成 SQL 替代数据库内的动态 SQL。

## 版本演进

- BigQuery：引入 EXECUTE IMMEDIATE 支持脚本中的动态 SQL
- Snowflake：存储过程中支持 JavaScript 拼接和执行 SQL
- PostgreSQL：PL/pgSQL 的 EXECUTE 一直是动态 SQL 的标准方式，支持 USING 参数绑定

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **动态 SQL** | 不支持（无存储过程，应用层拼接 SQL） | 不支持数据库端动态 SQL | 支持 EXECUTE IMMEDIATE（Scripting 中） | MySQL PREPARE/EXECUTE / PG EXECUTE / Oracle EXECUTE IMMEDIATE |
| **参数绑定** | 应用层 API 支持参数化查询（防注入） | 应用层参数化 | EXECUTE IMMEDIATE 支持 USING 参数绑定 | 各方言均支持参数绑定 |
| **安全风险** | 应用层拼接 SQL 需防注入 | 应用层拼接 SQL 需防注入 | EXECUTE IMMEDIATE 需防注入 | 存储过程内动态 SQL 需防注入 |
| **适用场景** | 应用层动态生成查询是唯一方式 | 应用层动态生成查询 | 报表/ETL 脚本中的动态表名/列名 | 动态报表、通用查询接口、DDL 脚本 |
