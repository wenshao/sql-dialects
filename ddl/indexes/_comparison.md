# 索引 (Indexes) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| B-tree | ✅ 默认 | ✅ 默认 | ✅ 唯一 | ✅ 默认 | ✅ | ✅ 默认 | ✅ 唯一 | ✅ 默认 | ✅ 行存 |
| Hash | ✅ Memory | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| GIN | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| GiST | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| BRIN | ❌ | ✅ 9.5+ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Bitmap | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| FULLTEXT | ✅ | ❌ | ❌ | ✅ CONTEXT | ✅ | ✅ | ❌ | ✅ | ✅ |
| SPATIAL | ✅ | ✅ GiST | ✅ R-tree | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| 部分索引 | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ 5.0+ | ❌ | ❌ |
| 表达式索引 | ✅ 8.0+ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ 3.0+ | ❌ | ❌ |
| INCLUDE 列 | ❌ | ✅ 11+ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ |
| CONCURRENTLY | ❌ | ✅ | ❌ | ✅ ONLINE | ✅ ONLINE | ❌ | ❌ | ❌ | ❌ |
| 聚集索引 | ✅ InnoDB PK | ❌ | ❌ | ✅ IOT | ✅ CLUSTERED | ✅ InnoDB PK | ❌ | ✅ CLUSTER | ❌ |
| Columnstore | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ 默认列存 |
| 反向索引 | ❌ | ❌ | ❌ | ✅ REVERSE | ❌ | ❌ | ❌ | ❌ | ❌ |
| 前缀索引 | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 传统索引 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ⚠️ | ❌ | ✅ ART | ❌ | ❌ |
| Bloom Filter | ❌ | ❌ | ❌ | ✅ ORC | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ Delta | ❌ |
| Bitmap | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| 倒排索引 | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| SEARCH 索引 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 分桶 | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| Z-ORDER | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ Delta | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| 传统索引 | ❌ | ❌ | ❌ | ✅ B-tree/GIN/GiST | ❌ | ❌ | ✅ |
| 排序键 | ✅ SORTKEY | ✅ ORDER CCI | ✅ Z-ORDER/Liquid | ❌ | ❌ | ✅ ORDER BY | ✅ PI |
| Columnstore | ✅ 默认 | ✅ CCI 默认 | ✅ 默认 | ✅ AOCO | ✅ Parquet | ✅ 默认 | ✅ COLUMN |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| B-tree | ✅ | ✅ | ✅ | ✅ | ✅ LSM | ✅ | ✅ | ✅ | ✅ | ✅ |
| Hash 分片索引 | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 表达式索引 | ✅ 5.0+ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 部分索引 | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ |
| STORING/INCLUDE | ❌ | ❌ | ✅ | ✅ STORING | ✅ INCLUDE | ❌ | ✅ | ❌ | ❌ | ✅ |
| FULLTEXT | ❌ | ✅ 4.0+ | ❌ | ✅ SEARCH | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ GIN |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| B-tree | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ 唯一 |
| Hash | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| GIN/GiST | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 增量维护索引 | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| 标签索引 | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| SMA 索引 | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |

## 关键差异

- **BigQuery/Snowflake/Redshift** 完全不支持传统索引，依赖自动优化和分区/排序键
- **PostgreSQL** 索引类型最丰富：B-tree, Hash, GIN, GiST, BRIN, SP-GiST
- **Oracle** 独有 Bitmap 索引（低基数列）和 REVERSE 索引（避免索引热点）
- **SQL Server** 独有 COLUMNSTORE INDEX（列式存储索引）
- **ClickHouse** 使用稀疏索引 + Bloom Filter + 倒排索引体系
- **TDengine** 仅支持标签索引和 SMA（小型物化聚合）索引
- **Materialize** 索引用于增量维护物化视图，不是传统查询加速
- **Flink/Trino** 作为查询引擎不支持创建索引
- **YugabyteDB** 使用 LSM-tree 而非 B-tree 实现分布式索引
