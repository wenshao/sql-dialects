# 表分区 (Partitioning) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| RANGE 分区 | ✅ | ✅ 10+ | ❌ | ✅ | ✅ 分区函数 | ✅ | ❌ | ✅ | ✅ |
| LIST 分区 | ✅ | ✅ 10+ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| HASH 分区 | ✅ | ✅ 11+ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| KEY 分区 | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| RANGE COLUMNS | ✅ 5.5+ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| LIST COLUMNS | ✅ 5.5+ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| 复合分区（子分区） | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| INTERVAL 分区 | ❌ | ❌ | ❌ | ✅ 11g+ | ❌ | ❌ | ❌ | ❌ | ❌ |
| REFERENCE 分区 | ❌ | ❌ | ❌ | ✅ 11g+ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 声明式分区 | ❌ | ✅ 10+ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 分区函数/方案 | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| ALTER TABLE 添加分区 | ✅ | ✅ ATTACH | ❌ | ✅ | ✅ SPLIT/MERGE | ✅ | ❌ | ✅ | ✅ |
| ALTER TABLE 删除分区 | ✅ | ✅ DETACH | ❌ | ✅ | ✅ MERGE | ✅ | ❌ | ✅ | ✅ |
| 自动分区 | ❌ | ❌ | ❌ | ✅ INTERVAL | ❌ | ❌ | ❌ | ❌ | ❌ |
| 分区裁剪 | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| 全局索引 | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| 局部索引 | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| 分区交换 | ✅ EXCHANGE | ✅ ATTACH/DETACH | ❌ | ✅ EXCHANGE | ✅ SWITCH | ✅ EXCHANGE | ❌ | ❌ | ❌ |
| DEFAULT 分区 | ❌ MAXVALUE | ✅ | ❌ | ✅ | ❌ | ❌ MAXVALUE | ❌ | ❌ | ❌ |
| 分区键必须在主键中 | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 分区表 | ✅ | ❌ 自动聚集 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ Hive 风格 | ✅ | ✅ |
| RANGE 分区 | ✅ 时间/整数 | ❌ | ❌ | ❌ | ✅ | ✅ | ⚠️ | ❌ | ✅ | ❌ | ❌ | ❌ |
| LIST 分区 | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ⚠️ | ✅ | ✅ | ❌ | ✅ | ✅ |
| HASH 分区 | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ⚠️ | ✅ | ❌ | ❌ | ✅ | ✅ |
| 动态分区 | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ⚠️ | ❌ | ✅ | ❌ | ✅ | ❌ |
| 分区裁剪 | ✅ | ✅ 自动 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Clustering/Bucketing | ✅ | ✅ 自动 | ❌ | ✅ BUCKET | ❌ | ✅ BUCKET | ❌ | ❌ | ✅ BUCKET | ❌ | ✅ BUCKET | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| 分区表 | ❌ 排序键 | ✅ | ✅ | ✅ | ✅ | ✅ Projection | ✅ PPI |
| RANGE 分区 | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ |
| LIST 分区 | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| HASH 分区 | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ SEGMENTED | ✅ |
| 分区裁剪 | ✅ Zone Map | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 分布键/分布方式 | ✅ DISTKEY | ✅ DISTRIBUTION | ❌ | ✅ DISTRIBUTED BY | ❌ | ✅ SEGMENTED BY | ✅ PRIMARY INDEX |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| RANGE 分区 | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| LIST 分区 | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| HASH 分区 | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| KEY 分区 | ✅ | ✅ MySQL 模式 | ❌ | ❌ | ❌ | ✅ MySQL 模式 | ❌ | ✅ | ❌ | ❌ |
| 分区裁剪 | ✅ | ✅ | ✅ Range 扫描 | ✅ Key Range | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| 分区支持 | ✅ 超表自动 | ✅ 子表/超级表 | ❌ | ❌ | ❌ | ❌ |
| 时间分区 | ✅ chunk | ✅ 自动 | ❌ | ❌ | ❌ | ❌ |
| 分区裁剪 | ✅ chunk 裁剪 | ✅ 时间裁剪 | ❌ | ❌ | ❌ | ❌ |

## 关键差异

- **MySQL/MariaDB** 要求分区键必须包含在主键或唯一键中
- **PostgreSQL 10+** 引入声明式分区，11+ 支持 HASH 分区
- **Oracle** 分区功能最丰富：INTERVAL 自动分区、REFERENCE 分区、复合分区
- **SQL Server** 使用独特的分区函数 + 分区方案机制
- **SQLite** 不支持任何分区功能
- **BigQuery** 支持时间和整数 RANGE 分区，配合聚集（Clustering）使用
- **Snowflake** 不使用传统分区，依靠自动微分区（Micro-Partition）和聚集键
- **Redshift** 不支持传统分区，使用分布键（DISTKEY）和排序键（SORTKEY）
- **TimescaleDB** 自动按时间分区创建 chunk，无需手动管理
- **TDengine** 使用超级表/子表模型，按标签（Tag）自动分表
- **CockroachDB** 不支持传统分区，使用 Range 分片自动管理
