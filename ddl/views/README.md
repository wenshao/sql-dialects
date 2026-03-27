# 视图 (VIEWS)

各数据库视图语法对比，包括普通视图和物化视图的创建与管理。

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

1. **物化视图**：PostgreSQL/Oracle/SQL Server 支持完整的物化视图，MySQL 不原生支持（需要手动维护），BigQuery/Snowflake 支持自动刷新的物化视图
2. **可更新视图**：MySQL/PostgreSQL/Oracle 支持对简单视图执行 INSERT/UPDATE/DELETE，但条件严格（不能有 JOIN、GROUP BY 等）
3. **WITH CHECK OPTION**：防止通过视图插入不满足视图 WHERE 条件的数据，多数 RDBMS 支持但语义有细微差异
4. **递归视图**：SQL 标准定义了 `CREATE RECURSIVE VIEW`，但大多数方言用视图 + 递归 CTE 实现
5. **物化视图刷新**：Oracle 支持增量刷新（FAST REFRESH），PostgreSQL 只支持全量刷新（REFRESH MATERIALIZED VIEW），BigQuery 自动增量刷新

## 选型建议

普通视图适合封装复杂查询、实现权限隔离。物化视图适合加速慢查询，但需要考虑数据新鲜度和刷新成本。在 MySQL 中可以用定时任务 + 物理表模拟物化视图。在分析型引擎中物化视图常用于预聚合加速。

## 版本演进

- PostgreSQL 9.3+：引入物化视图，9.4+ 支持 CONCURRENTLY 刷新不阻塞查询
- MySQL 8.0：视图功能与 5.7 基本一致，仍无原生物化视图
- ClickHouse：物化视图是触发式的，INSERT 时自动增量更新到目标表

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **普通视图** | 支持 CREATE VIEW | 支持 CREATE VIEW | 支持 CREATE VIEW | 均支持 |
| **物化视图** | 不支持 | 支持且独特：INSERT 触发式增量更新到目标表 | 支持自动增量刷新的物化视图 | PG/Oracle 支持，MySQL 不原生支持 |
| **可更新视图** | 简单视图支持 INSERT/UPDATE/DELETE | 视图只读 | 视图只读 | MySQL/PG/Oracle 简单视图可更新 |
| **WITH CHECK OPTION** | 不支持 | 不支持 | 不支持 | MySQL/PG/Oracle/SQL Server 支持 |
| **视图性能** | 视图展开为子查询执行，无额外优化 | 物化视图用于预聚合加速，普通视图无特殊优化 | 物化视图可显著降低查询成本和延迟 | PG 物化视图可手动 REFRESH |
| **权限控制** | 无权限系统，视图不提供安全隔离 | 可通过 GRANT 控制视图访问 | 通过 IAM 控制视图的 dataset 级访问 | 视图是实现列级/行级安全的常用手段 |
