# 全文搜索 (Full-Text Search) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| 原生全文搜索 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| 搜索语法 | MATCH AGAINST | tsvector/tsquery | FTS5 MATCH | CONTAINS | CONTAINS/FREETEXT | MATCH AGAINST | CONTAINING | CONTAINS | CONTAINS |
| 布尔搜索 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| 短语搜索 | ✅ | ✅ <-> | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| 相关度排序 | ✅ | ✅ ts_rank | ✅ bm25 | ✅ SCORE | ✅ RANK | ✅ | ❌ | ✅ | ✅ |
| 模糊搜索 | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| 全文索引 | FULLTEXT | GIN | 虚拟表 | CONTEXT | FULLTEXT | FULLTEXT | ❌ | 扩展 | FULLTEXT |
| 中文支持 | ✅ ngram | ✅ zhparser | ❌ | ✅ | ❌ | ✅ Mroonga | ❌ | ❌ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 原生全文搜索 | ❌ | ❌ | ❌ | ❌ | ⚠️ | ⚠️ | ❌ | ⚠️ | ✅ | ✅ | ❌ | ❌ |
| 搜索语法 | CONTAINS_SUBSTR | CONTAINS | LIKE/REGEXP | LIKE/REGEXP | multiSearch | LIKE | 依赖连接器 | tsvector | MATCH_ALL/ANY | FTS 扩展 | LIKE/RLIKE | LIKE |
| 倒排索引 | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| 相关度排序 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ bm25 | ❌ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| 原生全文搜索 | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| 搜索语法 | LIKE/REGEXP | LIKE | LIKE/REGEXP | tsvector/tsquery | RLIKE | Text Index | CONTAINS |
| 全文索引 | ❌ | ❌ | ❌ | GIN | ❌ | Text Index | FULLTEXT |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| 原生全文搜索 | ❌ | ✅ 4.0+ | ✅ | ✅ 2024+ | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ |
| 搜索语法 | LIKE/REGEXP | MATCH AGAINST | tsvector/tsquery | SEARCH | tsvector/tsquery | MATCH AGAINST | tsvector/tsquery | MATCH AGAINST | CONTAINS | tsvector/tsquery |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| 原生全文搜索 | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| 搜索语法 | tsvector/tsquery | MATCH (正则) | LIKE | LIKE | FT_SEARCH/Lucene | LIKE |

## 关键差异

- **PostgreSQL 系**（PostgreSQL, CockroachDB, YugabyteDB, Greenplum, TimescaleDB, openGauss, KingbaseES）使用 tsvector/tsquery + GIN 索引
- **MySQL 系**（MySQL, MariaDB, OceanBase, PolarDB, TDSQL）使用 MATCH ... AGAINST + FULLTEXT 索引
- **Oracle** 使用 Oracle Text (CONTAINS + CONTEXT 索引)
- **SQL Server** 使用 CONTAINS/FREETEXT + FULLTEXT CATALOG
- **SQLite** 使用 FTS5 虚拟表，轻量但功能完整
- **Spanner 2024+** 新增 SEARCH 函数和 TOKENLIST + SEARCH INDEX
- **Doris** 独有 MATCH_ALL/MATCH_ANY/MATCH_PHRASE 语法配合倒排索引
- **TiDB** 不支持 FULLTEXT 索引，需外部搜索引擎
- **大数据引擎**（BigQuery, Snowflake, Hive, Spark 等）大多无原生全文搜索，依赖 Elasticsearch 等外部引擎
