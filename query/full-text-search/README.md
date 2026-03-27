# 全文搜索 (FULL-TEXT SEARCH)

各数据库全文搜索语法对比，包括全文索引创建与查询。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | InnoDB FULLTEXT(5.6+)，MATCH AGAINST |
| [PostgreSQL](postgres.sql) | tsvector/tsquery，GIN 索引，丰富排名 |
| [SQLite](sqlite.sql) | FTS5 扩展模块，轻量全文搜索 |
| [Oracle](oracle.sql) | Oracle Text(CONTAINS/CTXSYS) |
| [SQL Server](sqlserver.sql) | CONTAINS/FREETEXT，全文目录 |
| [MariaDB](mariadb.sql) | 兼容 MySQL FULLTEXT，Mroonga 引擎 |
| [Firebird](firebird.sql) | 无内建全文搜索 |
| [IBM Db2](db2.sql) | Text Search 扩展，需配置 |
| [SAP HANA](saphana.sql) | CONTAINS/FUZZY，内建全文搜索 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | SEARCH() 函数 + SEARCH INDEX |
| [Snowflake](snowflake.sql) | 无原生全文搜索，用 LIKE/REGEXP |
| [ClickHouse](clickhouse.sql) | tokenbf_v1/ngrambf 索引，近似搜索 |
| [Hive](hive.sql) | 无内建全文搜索 |
| [Spark SQL](spark.sql) | 无内建全文搜索，用 UDF |
| [Flink SQL](flink.sql) | 无内建全文搜索 |
| [StarRocks](starrocks.sql) | 无内建全文搜索，LIKE/REGEXP |
| [Doris](doris.sql) | 倒排索引(2.0+)，MATCH_ALL/MATCH_ANY |
| [Trino](trino.sql) | 无内建全文搜索 |
| [DuckDB](duckdb.sql) | 无内建全文搜索，fts 扩展 |
| [MaxCompute](maxcompute.sql) | 无内建全文搜索 |
| [Hologres](hologres.sql) | 无内建全文搜索 |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | 无原生全文搜索 |
| [Azure Synapse](synapse.sql) | 无内建全文搜索 |
| [Databricks SQL](databricks.sql) | 无原生全文搜索 |
| [Greenplum](greenplum.sql) | 继承 PG tsvector/tsquery |
| [Impala](impala.sql) | 无内建全文搜索 |
| [Vertica](vertica.sql) | Text Search 函数，v_txtindex |
| [Teradata](teradata.sql) | 无内建全文搜索 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 FULLTEXT(5.7+) |
| [OceanBase](oceanbase.sql) | MySQL 模式 FULLTEXT 支持 |
| [CockroachDB](cockroachdb.sql) | PG 兼容 tsvector(22.1+) |
| [Spanner](spanner.sql) | SEARCH INDEX + TOKENIZE 函数 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 tsvector/tsquery |
| [PolarDB](polardb.sql) | MySQL 兼容 FULLTEXT |
| [openGauss](opengauss.sql) | PG 兼容 tsvector/tsquery，中文分词 |
| [TDSQL](tdsql.sql) | MySQL 兼容 FULLTEXT |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | 全文索引支持 |
| [KingbaseES](kingbase.sql) | PG 兼容 tsvector/tsquery |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 全文搜索 |
| [TDengine](tdengine.sql) | 不支持全文搜索 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 不支持全文搜索 |
| [Materialize](materialize.sql) | 不支持全文搜索 |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | FULLTEXT 支持(Lucene 集成) |
| [Derby](derby.sql) | 无全文搜索支持 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 无全文搜索标准 |

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

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **全文搜索方案** | FTS5 虚拟表（编译时扩展），非传统索引方式 | tokenbf_v1/ngrambf_v1 跳数索引实现简单全文查找 | 无原生全文索引，依赖 LIKE/REGEXP 或外部搜索服务 | MySQL FULLTEXT / PG tsvector+GIN / Oracle Text |
| **中文支持** | FTS5 可自定义分词器但需额外开发 | 支持 ngram 分词 | 无内置分词 | MySQL 5.7+ 内置 ngram / PG 需安装中文分词扩展 |
| **相关性排序** | FTS5 的 rank 函数 | 无内置相关性排序 | 无内置相关性排序 | MySQL MATCH / PG ts_rank / Oracle SCORE |
| **架构定位** | 轻量级嵌入式搜索 | OLAP 引擎，全文搜索非核心功能 | 分析型服务，全文搜索非核心功能 | RDBMS 内置全文搜索，中等复杂度可用 |

## 引擎开发者视角

**核心设计决策**：全文搜索是否作为引擎的核心功能。这决定了投入级别——从简单的 LIKE 优化到完整的倒排索引+分词+相关性排序，复杂度跨越数个量级。

**实现建议**：
- 最小可行方案：优化前缀 LIKE（`LIKE 'abc%'`）可以利用 B-Tree 索引。如果要支持任意位置匹配，Trigram 索引（PostgreSQL 的 pg_trgm）是成本较低的方案——不需要完整的分词器
- 完整全文搜索需要四个组件：分词器（tokenizer）、倒排索引（inverted index）、查询解析器（query parser）、相关性排序（ranking）。SQLite 的 FTS5 实现紧凑且自包含，是嵌入式引擎的优秀参考
- 多语言分词是持续的工程挑战：英文空格分词简单，CJK 语言需要专门的分词器。推荐提供可插拔的分词器接口——PostgreSQL 的 TEXT SEARCH CONFIGURATION 设计灵活
- 倒排索引的更新策略影响写入性能：实时更新（每条 INSERT 立即更新索引）vs 批量更新（后台定期重建）。PostgreSQL 的 GIN 索引使用 pending list 延迟更新是好的折中
- 相关性排序（TF-IDF/BM25）的实现不需要完美——用户对搜索引擎级别的相关性精度通常不期望在数据库中实现
- 常见错误：全文索引的存储开销和更新开销被低估。倒排索引可能比原始数据还大——引擎应在 CREATE INDEX 时估算并警告空间需求
