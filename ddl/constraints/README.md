# 约束 (CONSTRAINTS)

各数据库约束管理语法对比，包括主键、外键、唯一、检查、非空约束。

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

1. **CHECK 约束**：MySQL 8.0.16+ 才真正执行 CHECK 约束（之前只解析不执行），PostgreSQL/Oracle/SQL Server 一直支持
2. **外键支持**：分析型引擎（BigQuery/Snowflake/ClickHouse/Hive）的外键是信息性的不强制执行，TiDB 6.6 之前不支持外键
3. **DEFERRABLE 约束**：PostgreSQL/Oracle 支持延迟约束检查（事务提交时检查），MySQL/SQL Server 不支持
4. **UNIQUE 约束与 NULL**：SQL 标准允许 UNIQUE 列有多个 NULL，PostgreSQL/Oracle 遵循标准，SQL Server 默认只允许一个 NULL
5. **约束命名**：PostgreSQL/Oracle 严格管理约束名，MySQL 约束名可选但推荐命名以便后续管理

## 选型建议

OLTP 数据库应充分利用约束保证数据完整性，外键约束对数据一致性非常有价值但会影响写入性能。OLAP/大数据场景通常在应用层或 ETL 管道中保证数据质量，数据库层的约束往往是信息性的。

## 版本演进

- MySQL 8.0.16：CHECK 约束从"仅解析"变为真正强制执行
- TiDB 6.6：首次支持外键约束
- PostgreSQL 15+：支持 NULLS NOT DISTINCT 使 UNIQUE 约束完全排除 NULL 重复

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **主键约束** | 支持且强制执行，INTEGER PRIMARY KEY 特殊处理为 ROWID | 定义 PRIMARY KEY 影响排序键（ORDER BY），但不强制唯一性 | 支持声明但不强制执行（NOT ENFORCED） | 完整支持且强制执行 |
| **外键约束** | 支持但默认关闭（PRAGMA foreign_keys=ON 启用） | 不支持外键 | 支持声明但不强制执行（信息性约束） | 完整支持且强制执行，影响写入性能 |
| **CHECK 约束** | 完整支持 | 不支持 CHECK 约束 | 不支持 | MySQL 8.0.16+ 才真正执行，PG/Oracle 一直支持 |
| **UNIQUE 约束** | 支持且强制执行 | 不强制执行唯一性（MergeTree 最终合并可能去重） | 不强制执行 | 完整支持且强制执行 |
| **约束命名** | 支持但通常省略 | 无约束命名概念 | 约束名可选 | PG/Oracle 严格管理约束名 |
| **事务保证** | 单写场景下约束检查在事务内即时生效 | 无传统事务，约束不在写入时检查 | DML 有配额限制，约束仅用于查询优化器提示 | 约束在事务中即时检查（可 DEFERRABLE 延迟到提交） |
