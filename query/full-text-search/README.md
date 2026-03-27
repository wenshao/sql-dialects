# 全文搜索 (FULL-TEXT SEARCH)

各数据库全文搜索语法对比，包括全文索引创建与查询。

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

1. **实现方式**：MySQL 用 FULLTEXT INDEX + MATCH AGAINST，PostgreSQL 用 tsvector/tsquery + GIN 索引，Oracle 用 Oracle Text（CONTAINS），SQL Server 用 Full-Text Catalog
2. **中文支持**：MySQL 5.7+ 内置 ngram 分词器，PostgreSQL 需要安装 zhparser/pg_jieba 扩展，Oracle Text 内置多语言分词
3. **相关性排序**：各方言返回相关性分数的方式不同——MySQL 的 MATCH 返回相关性，PostgreSQL 用 ts_rank()，Oracle 用 SCORE()
4. **分析型引擎**：大多数分析型引擎没有原生全文索引，依赖 LIKE '%keyword%' 或正则表达式（ClickHouse 有 tokenbf_v1 索引支持简单全文查找）

## 选型建议

轻量级全文搜索可以用数据库内置功能。对搜索质量要求高的场景（电商搜索、内容平台）应使用 Elasticsearch/Solr 等专业搜索引擎。PostgreSQL 的全文搜索功能最丰富，支持词典、同义词、权重等高级特性。

## 版本演进

- MySQL 5.6+：InnoDB 引擎支持 FULLTEXT INDEX（之前仅 MyISAM 支持）
- MySQL 5.7+：内置 ngram 和 MeCab 分词器支持 CJK 语言
- PostgreSQL 12+：引入 websearch_to_tsquery() 支持类似 Google 的搜索语法
