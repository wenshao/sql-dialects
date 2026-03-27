# 建表 (CREATE TABLE)

各数据库 CREATE TABLE 语法对比。

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

1. **自增主键**：MySQL 用 `AUTO_INCREMENT`，PostgreSQL 用 `SERIAL`/`GENERATED AS IDENTITY`（推荐后者），Oracle 12c+ 才支持 IDENTITY，之前必须用 SEQUENCE + TRIGGER
2. **IF NOT EXISTS**：MySQL/PostgreSQL/SQLite 支持，Oracle/SQL Server 不直接支持，需要用过程式代码或条件判断
3. **存储引擎指定**：ClickHouse 必须指定引擎（MergeTree 等），Hive 必须指定行列格式和存储位置，传统 RDBMS 通常有默认引擎
4. **排序键/分区键**：ClickHouse 的 ORDER BY 是表级的（排序键），BigQuery 可指定 clustering，Hive 用 PARTITIONED BY，这些概念在传统 RDBMS 中不存在
5. **临时表语法**：`CREATE TEMPORARY TABLE` vs `CREATE GLOBAL TEMPORARY TABLE` vs `#table_name`（SQL Server）

## 选型建议

传统业务系统选 MySQL/PostgreSQL 的标准 CREATE TABLE 语法即可。需要分析场景时，重点掌握 ClickHouse 的引擎选择和 Hive/Spark 的分区分桶策略。云数仓（BigQuery/Snowflake）的建表语法最简洁，大部分存储细节由平台自动管理。

## 版本演进

- PostgreSQL 10+：引入 `GENERATED AS IDENTITY`（替代 SERIAL），这是 SQL 标准语法
- MySQL 8.0：支持 `CHECK` 约束（之前只解析不执行）、支持降序索引
- Oracle 12c：引入 IDENTITY 列，不再强制依赖 SEQUENCE
- SQL Server 2016+：支持 `DROP IF EXISTS` 语法简化 DDL 脚本

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **类型系统** | 动态类型，声明类型仅为亲和性提示，任意列可存任意类型 | 严格类型，有丰富的数值类型（UInt8~256、Decimal32~256） | 严格类型，INT64/FLOAT64/STRING 等有限类型集 | 严格类型，丰富的类型选择 |
| **存储引擎** | 单一文件存储，无引擎选择 | 必须指定引擎（MergeTree/Log/Memory 等），引擎决定数据组织方式 | 无需指定，Serverless 自动管理存储 | 可选引擎（MySQL InnoDB/MyISAM），多数有默认引擎 |
| **自增主键** | ROWID 自动生成，INTEGER PRIMARY KEY 即为 ROWID 别名 | 无传统自增，分布式环境不适用单调递增 ID | 无自增列，通常用 GENERATE_UUID() 或应用层生成 | AUTO_INCREMENT / SERIAL / IDENTITY / SEQUENCE |
| **约束执行** | 支持但外键默认关闭（需 PRAGMA foreign_keys=ON） | 不支持外键，PRIMARY KEY 影响排序但不强制唯一 | 约束为信息性（NOT ENFORCED），不实际执行 | 完整约束执行（PK/FK/UNIQUE/CHECK） |
| **分区/分桶** | 不支持 | 通过 PARTITION BY 表达式分区，ORDER BY 定义排序键 | PARTITION BY（仅支持日期/整数等）+ CLUSTER BY 代替索引 | 支持 RANGE/LIST/HASH 分区 |
| **并发架构** | 文件级锁，单写多读（WAL 模式下允许并发读） | 多节点分布式写入，列式存储优化批量写入 | Serverless 无限扩展，按查询量计费 | 客户端-服务器架构，行级锁支持高并发读写 |

## 引擎开发者视角

**核心设计决策**：建表语法是引擎的第一印象。需要决定：是否支持 ENGINE 子句（可插拔存储）？约束是强制执行还是信息性的？自增用列属性还是独立 SEQUENCE 对象？

**实现建议**：
- IF NOT EXISTS 必须从第一天就支持——DDL 脚本的幂等性依赖此特性，缺失会导致部署脚本无法重复执行
- 分布式引擎不推荐全局自增（实现成本高、热点问题），推荐 UUID 或 AUTO_RANDOM（TiDB 的做法是好范例）
- CREATE TABLE AS SELECT（CTAS）实现简单但价值大，应尽早支持——它是 ETL 和数据探索的核心操作
- 存储引擎子句（ENGINE=xxx）如果走 MySQL 兼容路线可以保留但默认只支持一种存储引擎。ClickHouse 的强制指定引擎（MergeTree/Log/Memory）面向不同场景是好设计
- 列式引擎需要额外的建表参数：排序键（ORDER BY）、分区表达式（PARTITION BY）、TTL 设置等。这些参数的语法设计要尽量声明式而非过程式
- 常见错误：TEMPORARY TABLE 和普通表共享命名空间导致意外冲突。临时表应在独立的命名空间中，并且临时表始终优先于同名永久表被解析
