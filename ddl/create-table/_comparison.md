# 建表 (CREATE TABLE) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| IF NOT EXISTS | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| CREATE OR REPLACE | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ 10.0.24+ | ❌ | ✅ | ❌ |
| CTAS | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| 自增列 | AUTO_INCREMENT | SERIAL/IDENTITY | AUTOINCREMENT | IDENTITY 12c+ | IDENTITY | AUTO_INCREMENT | IDENTITY | IDENTITY | IDENTITY |
| 分区表 | ✅ | ✅ 10+ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| 临时表 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ 3.0+ | ✅ | ✅ |
| 计算列 | ⚠️ 5.7+ | ✅ 12+ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| 表注释 | ✅ | ✅ | ❌ | ✅ | ⚠️ | ✅ | ❌ | ✅ | ✅ |
| 存储引擎选择 | ✅ ENGINE= | ❌ | ❌ | ❌ | ❌ | ✅ ENGINE= | ❌ | ❌ | ✅ ROW/COLUMN |
| 外部表 | ❌ | ✅ FDW | ❌ | ✅ | ✅ | ❌ | ✅ 4.0+ | ❌ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| IF NOT EXISTS | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CREATE OR REPLACE | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |
| CTAS | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| 分区表 | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| 分桶/聚集 | ✅ CLUSTER BY | ✅ CLUSTER BY | ✅ | ✅ CLUSTERED BY | ✅ ORDER BY | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ |
| 外部表 | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| 引擎指定 | ❌ | ❌ | ❌ | ❌ | ✅ ENGINE= | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ connector |
| ARRAY/STRUCT 类型 | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| CTAS | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 分区表 | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 分布策略 | DISTKEY/DISTSTYLE | DISTRIBUTION | ❌ | DISTRIBUTED BY | ❌ | SEGMENTED BY | PRIMARY INDEX |
| 列式存储 | ✅ 默认 | ✅ CCI | ✅ Delta | ✅ AOCO | ✅ Parquet | ✅ 默认 | ✅ COLUMN |
| 自增列 | IDENTITY | IDENTITY | IDENTITY | SERIAL | ❌ | AUTO_INCREMENT | ❌ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| 自增列 | AUTO_INCREMENT/AUTO_RANDOM | AUTO_INCREMENT | SERIAL | SEQUENCE | SERIAL | AUTO_INCREMENT | SERIAL | AUTO_INCREMENT | IDENTITY | SERIAL/IDENTITY |
| 分区表 | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 分布键 | ❌ | ✅ | ❌ | PRIMARY KEY | ❌ | ✅ shardkey | ❌ | ✅ shardkey | ❌ | ❌ |
| INTERLEAVE | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| 自增列 | SERIAL | ❌ | ❌ | ❌ | AUTO_INCREMENT/IDENTITY | IDENTITY |
| 超级表/子表 | ✅ hypertable | ✅ STable | ❌ | ❌ | ❌ | ❌ |
| STREAM/TABLE | ❌ | ❌ | ✅ | ✅ SOURCE | ❌ | ❌ |
| IF NOT EXISTS | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |

## 关键差异

- **ClickHouse** 需要指定 ENGINE（MergeTree 家族），其他数据库大多有默认引擎
- **Spanner** 使用 INTERLEAVE IN PARENT 实现父子表共存储，其他引擎无此概念
- **TiDB** 独有 AUTO_RANDOM 替代 AUTO_INCREMENT 避免分布式热点
- **TDengine** 使用超级表(STable) + 子表模式，完全不同于关系型建表
- **ksqlDB** 区分 STREAM（只追加）和 TABLE（可更新），而非传统 CREATE TABLE
- **Flink** 建表需指定 connector 属性连接外部系统
- **Redshift/Synapse/Greenplum/Vertica** 建表需要考虑数据分布策略
- **BigQuery/Snowflake** 虽不分区但自动管理存储，CLUSTER BY 优化查询性能
