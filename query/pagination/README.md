# 分页 (PAGINATION)

各数据库分页语法对比，包括 LIMIT/OFFSET、FETCH FIRST、ROWNUM 等。

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

1. **LIMIT/OFFSET**：MySQL/PostgreSQL/SQLite/MariaDB 使用，最直观但 OFFSET 大时性能差
2. **FETCH FIRST**：SQL 标准语法 `FETCH FIRST n ROWS ONLY`，Oracle 12c+/SQL Server 2012+/Db2/PostgreSQL 都支持
3. **ROWNUM**：Oracle 12c 之前的经典分页方式（三层嵌套 SELECT），代码冗长但无替代方案
4. **TOP**：SQL Server 特有的 `SELECT TOP n`，不支持 OFFSET（需要配合 OFFSET FETCH 或 ROW_NUMBER）
5. **Teradata 独特语法**：`SELECT TOP n` 或 `QUALIFY ROW_NUMBER() OVER (...) BETWEEN m AND n`

## 选型建议

前几页用 LIMIT/OFFSET 即可，深分页（OFFSET > 10000）必须用键集分页（WHERE id > last_id ORDER BY id LIMIT n）。API 分页推荐用游标分页（cursor-based），比 OFFSET 更稳定且性能一致。报表场景的分页通常在应用层处理。

## 版本演进

- Oracle 12c+：引入 `OFFSET n ROWS FETCH FIRST m ROWS ONLY`，告别 ROWNUM 三层嵌套
- SQL Server 2012+：引入 `OFFSET ... FETCH NEXT ...` 语法
- MySQL 8.0：引入窗口函数，可用 ROW_NUMBER() 实现更灵活的分页逻辑

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **分页语法** | LIMIT/OFFSET（与 MySQL/PG 相同） | LIMIT/OFFSET | LIMIT/OFFSET | MySQL/PG LIMIT / Oracle FETCH FIRST / SQL Server TOP+OFFSET |
| **OFFSET 性能** | 大 OFFSET 性能差（需跳过行），但单文件操作开销有限 | 大 OFFSET 分布式扫描成本高 | 大 OFFSET 按扫描量计费，成本高 | 大 OFFSET 普遍性能差 |
| **键集分页** | 支持 WHERE id > last_id 键集分页 | 支持且推荐，避免大 OFFSET | 支持但更推荐利用分区裁剪 | 均支持且推荐 |
| **FETCH FIRST** | 不支持 SQL 标准 FETCH FIRST 语法 | 不支持 | 不支持 | PG/Oracle 12c+/SQL Server 2012+ 支持 |
| **计费影响** | 无计费概念 | 无直接计费影响 | OFFSET 不减少扫描量，分页仍按全量扫描计费 | 无计费概念 |
