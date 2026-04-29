# 全文搜索排名算法 (Text Search Ranking Algorithms)

搜索引擎不只回答 "哪些文档匹配？"，更回答 "哪些文档最相关？"。匹配只是入门，**排序**才是搜索的灵魂——同样的查询词在 1000 万文档里可能命中 10 万条，用户却只看前 10 条。如何把 "最相关的 10 条" 排到顶部，是过去 50 年信息检索领域最核心的研究方向，也是现代数据库全文检索能力的真正分水岭。

## 没有 SQL 标准

与 `TABLESAMPLE` 由 SQL:2003 标准定义不同，**全文搜索排名算法在 SQL 标准中完全没有规定**。ISO/IEC 9075（SQL/MM Full-Text 部分曾在 SQL:2003 和后续版本中定义过 `CONTAINS` 谓词的语法骨架，但**未规定相关性评分（relevance scoring）的算法**——评分函数被显式留作 "implementation-defined"。

这导致每个引擎都自由发挥：

- PostgreSQL 用自创的 `ts_rank` / `ts_rank_cd`（基于词频与位置）
- MySQL InnoDB 用调优过的 BM25
- SQL Server / Oracle / DB2 用各自的 TF-IDF / BM25 变体
- Elasticsearch 用 Lucene 的 BM25（行业事实标准）
- 现代云数仓（BigQuery、Snowflake）用简化的 SEARCH 函数，不暴露评分细节

所以本文不讨论 "标准定义的语义"，而是横向对比各引擎的**实际算法选择**和**评分函数设计**。

## 算法发展历程

```
1971  TF-IDF (Salton, Cornell)
        词频 * 逆文档频率，第一个被广泛使用的相关性评分
1975  Vector Space Model (Salton)
        将文档表示为向量，引入余弦相似度
1976  Probabilistic Retrieval (Robertson & Spärck Jones)
        BIM 模型，BM25 的理论基础
1994  BM25 / Okapi BM25 (Stephen Robertson, City U London)
        TREC-3 提出，添加文档长度归一化与饱和函数
        参数 k1, b 可调，至今仍是默认选择
2008  PostgreSQL 8.3: ts_rank / ts_rank_cd
        非 BM25/TF-IDF，自创算法（基于权重与位置）
2009  Lucene 默认 TF-IDF
        Practical Scoring Function 变体
2013  MySQL 5.6 InnoDB FULLTEXT (BM25 调优变体)
2016  Lucene 6.0 切换默认评分到 BM25 (Robertson 经典版)
2016  Elasticsearch 5.0 默认使用 BM25
2019  ColBERT (Stanford, 后期交互检索)
2020  SPLADE (sparse learned retrieval)
2022  BigQuery SEARCH function GA
2023  Snowflake SEARCH function GA
2024+ 混合检索 (BM25 + 向量) 成为主流
        BGE-M3, learned sparse retrieval 大规模应用
```

关键人物：

- **Gerard Salton** (1927-1995): 信息检索之父，提出向量空间模型与 TF-IDF
- **Stephen E. Robertson** (1947-): BM25 之父，1994 年在 TREC-3 提出
- **Karen Spärck Jones** (1935-2007): IDF 概念提出者 (1972)

## 支持矩阵 (45+ 引擎)

### TF-IDF 支持

| 引擎 | TF-IDF | 备注 |
|------|--------|------|
| PostgreSQL | -- | 用自创 ts_rank，非标准 TF-IDF |
| MySQL (MyISAM) | 是 | 5.5 及以前的 MyISAM FULLTEXT 使用经典 TF-IDF |
| MySQL (InnoDB) | -- | 5.6+ 使用 BM25 变体 |
| MariaDB | 是 | 继承 MyISAM 行为 |
| SQL Server | 是 | TF-IDF 为主，融合 BM25 元素 |
| Oracle Text | 是 | SCORE() 基于 TF-IDF |
| SQLite FTS3/FTS4 | 是 | 默认 matchinfo 提供 TF-IDF 数据 |
| SQLite FTS5 | 可选 | bm25() 是默认，支持自定义 |
| Elasticsearch | 历史 | 5.0 之前默认 |
| Solr / Lucene | 历史 | 6.0 之前默认 |
| ClickHouse | -- | 无内置 |
| BigQuery | -- | SEARCH 不暴露 |
| Snowflake | -- | SEARCH 不暴露 |
| DuckDB FTS | 是 | match_bm25 是默认，但提供 score 数据 |
| MongoDB Text | 是 | textScore 基于 TF-IDF |
| CrateDB | 是 | 继承 Lucene |
| H2 | 是 | Lucene 集成 |

### BM25 支持

| 引擎 | BM25 | 默认评分 | 版本 |
|------|------|---------|------|
| Elasticsearch | 是 | 是 (5.0+) | 5.0 (2016) |
| OpenSearch | 是 | 是 | 全版本 |
| Solr | 是 | 是 (6.0+) | 6.0 (2016) |
| Lucene | 是 | 是 (6.0+) | 6.0 (2016) |
| MySQL InnoDB | 是 (变体) | 是 (5.6+) | 5.6 (2013) |
| MariaDB InnoDB | 是 (变体) | 是 | 10.0+ |
| SQLite FTS5 | 是 | 是 | 3.20+ (2017) |
| DuckDB FTS | 是 | 是 | 0.4+ |
| PostgreSQL (扩展) | 是 (RUM/pg_search/ParadeDB) | 否 (核心非默认) | RUM 1.0+ |
| ParadeDB | 是 | 是 | 0.5+ |
| Doris | 是 | 是 | 2.0+ |
| StarRocks | 是 | 是 | 3.1+ |
| Vespa | 是 | 是 | 全版本 |
| Manticore Search | 是 | 是 | 全版本 |
| Sphinx | 是 | 是 | 2.x+ |
| Apache Pinot | 是 | 是 | 0.10+ |
| Quickwit | 是 | 是 | 全版本 |
| Tantivy | 是 | 是 | 全版本 |
| MeiliSearch | 否 | 否 | 自创 ranking rules |
| Typesense | 否 | 否 | 自创 hybrid score |
| Couchbase FTS | 是 | 是 | 全版本 |
| MongoDB Atlas Search | 是 | 是 | Lucene 后端 |
| Oracle Text | 实验/混合 | 否 | 与 TF-IDF 共存 |
| SQL Server | -- | -- | 用 TF-IDF 系 |
| ClickHouse | -- | -- | 无内置 |

### BM25F (多字段加权 BM25) 支持

| 引擎 | BM25F | 备注 |
|------|-------|------|
| Elasticsearch | 是 | per-field boost: `title^3 body^1` |
| Solr | 是 | edismax `qf` 参数 |
| Vespa | 是 | rank-profile 中 fieldset |
| Lucene | 是 | MultiFieldQueryParser |
| ParadeDB | 是 | tsvector 权重 A/B/C/D |
| MySQL FULLTEXT | 部分 | 多列 FULLTEXT 索引但权重不可调 |
| PostgreSQL | 替代 | setweight(tsvector, 'A')，与 BM25F 不同 |
| Apache Solr | 是 | 全功能 |
| Quickwit | 是 | per-field weights |
| 其他 | -- | 多数不支持 |

### ts_rank PostgreSQL 风格

| 引擎 | ts_rank | ts_rank_cd | 备注 |
|------|---------|-----------|------|
| PostgreSQL | 是 | 是 | 8.3+ (2008) |
| Greenplum | 是 | 是 | 继承 PG |
| Citus | 是 | 是 | 继承 PG |
| TimescaleDB | 是 | 是 | 继承 PG |
| AlloyDB | 是 | 是 | 继承 PG |
| Aurora PostgreSQL | 是 | 是 | 继承 PG |
| GaussDB | 是 | 是 | 继承 PG |
| openGauss | 是 | 是 | 继承 PG |
| PolarDB (PG) | 是 | 是 | 继承 PG |
| YugabyteDB | 部分 | 部分 | GIN 实验 |
| CockroachDB | 部分 | -- | tsvector 实验 |

### CONTAINS / SCORE() Oracle/SQL Server 风格

| 引擎 | CONTAINS | SCORE() / RANK | 备注 |
|------|----------|----------------|------|
| Oracle Text | 是 | SCORE() | CONTEXT/CTXCAT 索引 |
| SQL Server | 是 | RANK 列 (CONTAINSTABLE/FREETEXTTABLE) | -- |
| DB2 | 是 | SCORE | text search index |
| SAP HANA | 是 | SCORE() | FULLTEXT INDEX |
| Informix | 是 | -- | bts index |
| Sybase ASE | 是 | -- | 通过 Verity |

### 余弦相似度 / 向量评分

| 引擎 | 余弦相似度 | 内积 | L2 | 备注 |
|------|-----------|------|----|----|
| PostgreSQL (pgvector) | 是 (`<=>`) | 是 (`<#>`) | 是 (`<->`) | 0.5+ |
| Elasticsearch | 是 (cosineSimilarity) | dotProduct | l2norm | 7.3+ |
| OpenSearch | 是 | 是 | 是 | 1.0+ |
| Vespa | 是 | 是 | 是 | 全版本 |
| Snowflake | VECTOR_COSINE_SIMILARITY | VECTOR_INNER_PRODUCT | VECTOR_L2_DISTANCE | GA |
| BigQuery | ML.DISTANCE | ML.DISTANCE | ML.DISTANCE | GA |
| ClickHouse | cosineDistance | dotProduct | L2Distance | 23.x+ |
| Oracle 23ai | VECTOR_DISTANCE | VECTOR_DISTANCE | VECTOR_DISTANCE | 23ai (2024) |
| SQL Server 2025 | VECTOR_DISTANCE | -- | -- | 2025 |
| MySQL 9.0 | -- | -- | -- | 暂未支持向量 |
| MariaDB | VEC_DISTANCE_COSINE | -- | VEC_DISTANCE_EUCLIDEAN | 11.7+ |
| DuckDB (vss) | array_cosine_similarity | array_inner_product | array_distance | 0.10+ |
| MongoDB Atlas | 是 | 是 | 是 | 全版本 |
| Pinecone | 是 | 是 | 是 | 全版本 |
| Weaviate | 是 | 是 | 是 | 全版本 |
| Milvus | 是 | 是 | 是 | 全版本 |
| Qdrant | 是 | 是 | 是 | 全版本 |
| Chroma | 是 | 是 | 是 | 全版本 |
| Cassandra 5.0 | 是 | 是 | 是 | 5.0 (2024) |
| LanceDB | 是 | 是 | 是 | 全版本 |
| Doris | 否 | 否 | 否 | 暂无 |
| StarRocks | 是 | 是 | 是 | 3.x+ |
| TiDB | 是 | -- | -- | 8.x+ |
| OceanBase | 是 | 是 | 是 | 4.3+ |
| Redshift | -- | -- | -- | 暂无原生 |

### 学习排序 (Learning to Rank, LTR)

| 引擎 | 内置 LTR | 备注 |
|------|---------|------|
| Elasticsearch | 是 (Learning to Rank 插件) | LambdaMART 等 |
| Solr | 是 (LTR 模块) | 自 6.4+ |
| OpenSearch | 是 | LTR 插件 |
| Vespa | 是 | rank-profile 内嵌 ML |
| Quickwit | -- | 计划中 |
| 其他 | -- | 多数不支持，需外部 reranker |

### 综合：45+ 引擎全文搜索排名能力总览

| 引擎 | 排名算法 | 默认评分 | 可调参数 | 多字段加权 | 向量评分 |
|------|---------|---------|---------|-----------|----------|
| PostgreSQL | ts_rank / ts_rank_cd | ts_rank | 权重向量 | setweight A-D | pgvector |
| MySQL InnoDB | BM25 变体 | BM25 | -- | -- | -- |
| MySQL MyISAM | TF-IDF | TF-IDF | -- | -- | -- |
| MariaDB | BM25 / TF-IDF | BM25 | -- | -- | VEC_DISTANCE |
| SQL Server | TF-IDF 系 | TF-IDF | -- | RANK 排序 | VECTOR_DISTANCE 2025 |
| Oracle Text | TF-IDF (SCORE) | SCORE | section weights | 是 (sections) | 23ai 向量 |
| SQLite FTS5 | BM25 | BM25 | k1, b, weights | weights 数组 | sqlite-vec 扩展 |
| DuckDB FTS | BM25 (Okapi) | BM25 | k, b | -- | array_cosine |
| Elasticsearch | BM25 | BM25 | k1, b, boost | per-field boost | cosine/dot/l2 |
| OpenSearch | BM25 | BM25 | k1, b | per-field | 多种 |
| Solr / Lucene | BM25 | BM25 | k1, b | qf 加权 | 多种 |
| Vespa | BM25 / 自定义 | BM25 | rank-profile | fieldset | 多种 |
| ClickHouse | -- | -- | -- | -- | cosineDistance |
| Snowflake | SEARCH (黑盒) | -- | -- | -- | VECTOR_COSINE |
| BigQuery | SEARCH (黑盒) | -- | -- | -- | ML.DISTANCE |
| Databricks | -- | -- | -- | -- | UDF |
| Redshift | -- | -- | -- | -- | -- |
| Spark SQL | -- | -- | -- | -- | UDF |
| Trino / Presto | -- | -- | -- | -- | UDF |
| Doris | BM25 | BM25 | -- | -- | -- |
| StarRocks | BM25 | BM25 | -- | -- | 是 |
| TiDB | -- | -- | -- | -- | 8.x+ |
| OceanBase | BM25 (FULLTEXT) | BM25 | -- | -- | 4.3+ |
| PolarDB MySQL | BM25 | BM25 | -- | -- | -- |
| PolarDB PG | ts_rank | ts_rank | -- | setweight | 是 |
| Aurora MySQL | BM25 | BM25 | -- | -- | -- |
| Aurora PG | ts_rank | ts_rank | -- | setweight | pgvector |
| AlloyDB | ts_rank | ts_rank | -- | setweight | ScaNN 索引 |
| Greenplum | ts_rank | ts_rank | -- | setweight | -- |
| Citus | ts_rank | ts_rank | -- | setweight | pgvector |
| TimescaleDB | ts_rank | ts_rank | -- | setweight | pgvector |
| GaussDB | ts_rank | ts_rank | -- | setweight | 是 |
| openGauss | ts_rank | ts_rank | -- | setweight | -- |
| YugabyteDB | ts_rank (实验) | ts_rank | -- | -- | -- |
| CockroachDB | tsvector (实验) | -- | -- | -- | -- |
| SAP HANA | SCORE() | SCORE | -- | -- | 是 |
| IBM Db2 | SCORE | SCORE | -- | -- | -- |
| Informix | -- | -- | -- | -- | -- |
| Teradata | CONTAINS | -- | -- | -- | -- |
| H2 | Lucene BM25/TF-IDF | -- | -- | -- | -- |
| HSQLDB | -- | -- | -- | -- | -- |
| Derby | -- | -- | -- | -- | -- |
| Firebird | -- | -- | -- | -- | -- |
| CrateDB | BM25 (Lucene) | BM25 | k1, b | per-field | 是 |
| AnalyticDB | BM25 | BM25 | -- | -- | 是 |
| Vertica | -- | -- | -- | -- | -- |
| QuestDB | -- | -- | -- | -- | -- |
| InfluxDB (SQL) | -- | -- | -- | -- | -- |
| Materialize | -- | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- | -- |
| ParadeDB | BM25 (Tantivy) | BM25 | k1, b, boost | 是 | 是 |
| MongoDB Atlas Search | BM25 (Lucene) | BM25 | k1, b | 是 | 是 |
| Couchbase | BM25 | BM25 | -- | 是 | 是 |
| Cassandra (SAI) | -- | -- | -- | -- | 5.0+ |
| ScyllaDB | -- | -- | -- | -- | -- |
| Spanner | tokenized search | SCORE | -- | -- | -- |
| Firebolt | -- | -- | -- | -- | -- |
| SingleStore | TF-IDF | TF-IDF | -- | -- | DOT_PRODUCT |
| Yellowbrick | -- | -- | -- | -- | -- |
| MeiliSearch | 自创 ranking rules | -- | typo, attributes 等 | -- | 是 |
| Typesense | 自创 hybrid score | -- | -- | -- | 是 |

> 统计：约 35 个 SQL 引擎/数据库提供某种形式的全文搜索评分能力，其中 BM25 系约 18 个、TF-IDF 系约 8 个、ts_rank PostgreSQL 系约 11 个、向量评分约 25 个。完全无内置评分能力的引擎包括 Redshift、Vertica、Spark SQL、Trino、ClickHouse 等。

## 各引擎深入剖析

### PostgreSQL: ts_rank 与 ts_rank_cd（自创算法，非 BM25/TF-IDF）

PostgreSQL 在 8.3 (2008) 引入完整的全文检索基础设施，但没有采用业界主流的 BM25 或 TF-IDF。它的 `ts_rank` 和 `ts_rank_cd` 是基于权重向量与覆盖密度的自创评分函数。

#### ts_rank: 基础评分

```sql
-- 创建 tsvector 列与 GIN 索引
CREATE TABLE articles (
    id      SERIAL PRIMARY KEY,
    title   TEXT,
    body    TEXT,
    tsv     TSVECTOR
);

UPDATE articles SET tsv =
    setweight(to_tsvector('english', title), 'A') ||
    setweight(to_tsvector('english', body),  'B');

CREATE INDEX idx_tsv ON articles USING GIN(tsv);

-- 基础排序
SELECT id, title, ts_rank(tsv, query) AS rank
FROM articles, plainto_tsquery('english', 'database performance') AS query
WHERE tsv @@ query
ORDER BY rank DESC
LIMIT 10;
```

ts_rank 计算公式（简化）：

```
rank = sum_over_terms(weight_i * tf_normalized_i / (tf_normalized_i + K))

其中:
  weight_i: setweight 标记 (A=1.0, B=0.4, C=0.2, D=0.1, 默认值)
  tf_normalized_i: 词频，按 normalization 参数归一化
  K: 平滑常数

normalization 参数 (位掩码):
  0: 不做归一化 (默认)
  1: 除以 1 + log(文档长度)
  2: 除以文档长度
  4: 除以平均词距
  8: 除以唯一词数
 16: 除以 1 + log(唯一词数)
 32: rank / (rank + 1)
```

```sql
-- 自定义权重向量与归一化
SELECT id, title,
       ts_rank(
           ARRAY[0.1, 0.2, 0.4, 1.0],  -- D, C, B, A 权重
           tsv, query, 32                -- normalization=32 (rank/(rank+1))
       ) AS rank
FROM articles, plainto_tsquery('english', 'database performance') AS query
WHERE tsv @@ query
ORDER BY rank DESC
LIMIT 10;
```

#### ts_rank_cd: 覆盖密度评分

`ts_rank_cd` 考虑了**词项之间的距离**，匹配词靠得越近评分越高：

```sql
-- ts_rank_cd 偏好查询词紧凑出现的文档
SELECT id, title,
       ts_rank_cd(tsv, query, 32) AS rank
FROM articles, plainto_tsquery('english', 'machine learning') AS query
WHERE tsv @@ query
ORDER BY rank DESC
LIMIT 10;
```

cd 表示 "Cover Density"，算法基于 Clarke、Cormack、Tudhope 1995 年的论文 "Relevance ranking for one to three term queries"。

#### PostgreSQL 评分的局限

```
1. 不是 BM25: 缺少文档长度饱和函数 (b 参数)
2. 不是 TF-IDF: IDF 计算简化，所有词项 IDF 默认相等
3. 性能: ts_rank 需读 tsvector 完整内容，对长文档慢
4. 替代方案:
   - RUM 索引: 更快的 ts_rank (索引内存储位置信息)
   - pg_search / ParadeDB: 真正的 BM25 (基于 Tantivy)
   - pg_trgm: 字符级模糊匹配 (非排序)
```

### PostgreSQL 扩展: RUM、pg_search、ParadeDB（真正的 BM25）

#### RUM 索引

```sql
-- RUM 是 GIN 的扩展，索引内嵌位置信息，加速 ts_rank
CREATE EXTENSION rum;

CREATE INDEX idx_rum ON articles USING rum (tsv rum_tsvector_ops);

SELECT id, title, tsv <=> query AS dist
FROM articles, plainto_tsquery('english', 'big data') AS query
WHERE tsv @@ query
ORDER BY tsv <=> query
LIMIT 10;
-- <=> 是 RUM 自定义的距离运算符，比 ts_rank 快 10-100 倍
```

#### ParadeDB / pg_search (基于 Tantivy)

```sql
-- ParadeDB 提供真正的 Lucene 风格 BM25 评分
CREATE EXTENSION pg_search;

CREATE INDEX search_idx ON articles
USING bm25 (id, title, body)
WITH (key_field='id');

-- BM25 评分
SELECT id, title, paradedb.score(id) AS bm25_score
FROM articles
WHERE id @@@ '(title:"database" OR body:"database") AND title:performance'
ORDER BY bm25_score DESC
LIMIT 10;
```

ParadeDB 引入：

- 真正的 BM25 (基于 Tantivy，Rust 实现的 Lucene)
- 多字段加权 (BM25F)
- 短语查询、模糊查询、布尔查询
- 高亮、聚合、过滤组合

### MySQL InnoDB FULLTEXT: BM25 调优变体

MySQL InnoDB FULLTEXT 自 5.6 (2013) 引入，使用 BM25 的调优变体作为默认评分。

```sql
CREATE TABLE articles (
    id      INT PRIMARY KEY AUTO_INCREMENT,
    title   VARCHAR(200),
    body    TEXT,
    FULLTEXT INDEX ft_title_body (title, body)
) ENGINE=InnoDB;

-- 自然语言模式（默认 BM25）
SELECT id, title,
       MATCH(title, body) AGAINST('database performance' IN NATURAL LANGUAGE MODE) AS score
FROM articles
WHERE MATCH(title, body) AGAINST('database performance' IN NATURAL LANGUAGE MODE)
ORDER BY score DESC
LIMIT 10;

-- 布尔模式（不评分，仅匹配）
SELECT id, title
FROM articles
WHERE MATCH(title, body) AGAINST('+database -obsolete' IN BOOLEAN MODE);

-- 查询扩展模式（基于初步结果再扩展查询）
SELECT id, title,
       MATCH(title, body) AGAINST('database' WITH QUERY EXPANSION) AS score
FROM articles
WHERE MATCH(title, body) AGAINST('database' WITH QUERY EXPANSION)
ORDER BY score DESC;
```

#### MySQL InnoDB BM25 实现细节

MySQL 5.7 文档明确说明 InnoDB 使用 BM25 变体（[源码](https://github.com/mysql/mysql-server/blob/8.0/storage/innobase/fts/fts0que.cc) 中可见 idf 与 bm25 计算逻辑）：

```
score = sum_over_terms(idf_i^2 * tf_i / (tf_i + k_doc_norm))

其中:
  idf_i = log((N - n_i + 0.5) / (n_i + 0.5))
  tf_i: 词在文档中的频率
  k_doc_norm = 1.2 * (0.25 + 0.75 * dl/avgdl)
              ≈ BM25 中 k1*(1-b+b*dl/avgdl), 此处 k1=1.2, b=0.75

注意: idf 平方项是 MySQL 的特殊设计（早期 Lucene 也曾用 idf^2，2015 年改回 idf）
```

#### MySQL MyISAM FULLTEXT (TF-IDF)

5.6 之前的 MyISAM FULLTEXT 使用经典 TF-IDF：

```
score(D, Q) = sum_over_terms(tf_i * idf_i * doc_weight)

其中:
  tf_i: 词在文档中的出现次数
  idf_i = log(N/n_i)
  doc_weight: 反映了文档总长度的归一化因子

特别处理:
  - 出现在 50% 以上文档的词被视为停用词 (50% threshold)
  - 短于 ft_min_word_len (默认 4) 的词被忽略
  - 词必须按 ft_query_extra_word_chars 模式匹配
```

```sql
-- MyISAM 引擎下查询，停用词与最小词长设定不同
CREATE TABLE old_articles (
    id INT PRIMARY KEY AUTO_INCREMENT,
    body TEXT,
    FULLTEXT (body)
) ENGINE=MyISAM;
```

### SQL Server: CONTAINS / FREETEXTTABLE 与 RANK

SQL Server 提供 `CONTAINSTABLE` 和 `FREETEXTTABLE` 两个函数，返回带 RANK 列的虚拟表，RANK 值范围 0-1000。

```sql
-- CONTAINS 不返回评分
SELECT * FROM Articles
WHERE CONTAINS(Body, 'database AND performance');

-- CONTAINSTABLE 返回 [KEY, RANK] 表，可以排序
SELECT a.Id, a.Title, ct.RANK
FROM Articles a
INNER JOIN CONTAINSTABLE(Articles, Body, 'database AND performance', 10) AS ct
    ON a.Id = ct.[KEY]
ORDER BY ct.RANK DESC;

-- FREETEXTTABLE: 自然语言模式（不要求精确语法）
SELECT a.Id, a.Title, ft.RANK
FROM Articles a
INNER JOIN FREETEXTTABLE(Articles, Body, 'fast database queries') AS ft
    ON a.Id = ft.[KEY]
ORDER BY ft.RANK DESC;

-- ISABOUT: 加权查询
SELECT a.Title, ct.RANK
FROM Articles a
INNER JOIN CONTAINSTABLE(Articles, *,
    'ISABOUT(database WEIGHT(0.8), performance WEIGHT(0.2))') ct
    ON a.Id = ct.[KEY]
ORDER BY ct.RANK DESC;
```

#### SQL Server 评分算法

SQL Server 的评分算法是 **TF-IDF 系（不完全是经典 TF-IDF）**，根据查询类型不同采用不同策略：

```
CONTAINSTABLE (精确查询):
  - 基于 Jaccard / OKAPI 变体
  - 考虑词频、逆文档频率、文档长度

FREETEXTTABLE (自然语言):
  - 词干化 + 同义词扩展
  - 加权综合 (Word Breaker + Stemmer + Thesaurus)

RANK 值范围: 0-1000 (整数，便于排序)
```

### Oracle Text: SCORE() 函数

Oracle Text (CONTEXT、CTXCAT、CTXRULE 三种索引) 通过 `SCORE()` 函数返回相关性，范围 0-100。

```sql
-- CONTEXT 索引（默认，最常用）
CREATE INDEX articles_text_idx ON articles(body)
INDEXTYPE IS CTXSYS.CONTEXT;

-- CONTAINS 谓词 + SCORE() 函数
SELECT id, title, SCORE(1) AS relevance
FROM articles
WHERE CONTAINS(body, 'database AND performance', 1) > 0
ORDER BY SCORE(1) DESC
FETCH FIRST 10 ROWS ONLY;
-- SCORE(1) 中的 1 是 label，对应 CONTAINS 的第三参数

-- 加权评分
SELECT id, title, SCORE(1) AS relevance
FROM articles
WHERE CONTAINS(body, 'database * 5 AND performance * 2', 1) > 0
ORDER BY SCORE(1) DESC;
-- * N 是 Oracle 的术语权重语法

-- CTXCAT (适合短文本+结构化过滤)
CREATE INDEX articles_ctxcat ON articles(title)
INDEXTYPE IS CTXSYS.CTXCAT
PARAMETERS('LEXER ctxsys.context_lexer');

SELECT id, title FROM articles
WHERE CATSEARCH(title, 'database', NULL) > 0;
```

#### Oracle SCORE 算法

```
Oracle SCORE 基于 INVERSE FREQUENCY 评分:
  SCORE = 3 * f * log(N/n) * w

其中:
  f: 词频比例 (term frequency / max term frequency in doc)
  N: 总文档数
  n: 包含该词的文档数
  w: 操作符权重 (* N 语法)

特别行为:
  - SCORE 是 0-100 范围
  - 多个词组合时取加权和
  - NEAR 算子使用距离衰减
```

### SQLite FTS5: BM25 (默认)

SQLite FTS5 (3.20+, 2017) 默认使用 BM25 评分，是 SQLite 全文检索的现代标准。

```sql
-- 创建 FTS5 虚拟表
CREATE VIRTUAL TABLE articles_fts USING fts5(
    title,
    body,
    tokenize='unicode61 remove_diacritics 1'
);

INSERT INTO articles_fts (title, body) VALUES
    ('Database Performance', 'How to optimize SQL queries...'),
    ('Performance Tuning', 'Database tuning is critical...');

-- bm25() 函数（注意：SQLite BM25 返回值是负数，越小越相关）
SELECT title, bm25(articles_fts) AS rank
FROM articles_fts
WHERE articles_fts MATCH 'database performance'
ORDER BY rank;
-- 不需要 DESC，因为越小越相关

-- 自定义列权重（BM25F 风格）
SELECT title, bm25(articles_fts, 10.0, 1.0) AS rank
FROM articles_fts
WHERE articles_fts MATCH 'database performance'
ORDER BY rank;
-- title 权重 10x，body 权重 1x
```

#### SQLite FTS5 BM25 实现

```c
// SQLite FTS5 中的 BM25 (sqlite/ext/fts5/fts5_aux.c)
double bm25(int avgdl, int dl, int n, int N, double f, double k1, double b) {
    double idf = log((N - n + 0.5) / (n + 0.5));
    double norm = k1 * (1.0 - b + b * dl / avgdl);
    return idf * f * (k1 + 1.0) / (f + norm);
}

// 默认参数: k1=1.2, b=0.75 (Robertson 经典值)
```

### DuckDB FTS: BM25

DuckDB FTS 扩展 (0.4+) 提供 BM25 评分。

```sql
INSTALL fts; LOAD fts;

CREATE TABLE articles (
    id INTEGER PRIMARY KEY,
    title VARCHAR,
    body VARCHAR
);

INSERT INTO articles VALUES
    (1, 'Database Performance', 'How to optimize SQL queries effectively'),
    (2, 'Vector Search', 'Cosine similarity for embeddings');

-- 创建 FTS 索引
PRAGMA create_fts_index(
    'articles', 'id', 'title', 'body',
    stemmer='english',
    stopwords='english',
    ignore='(\\.|[^a-z])+',
    strip_accents=1,
    lower=1
);

-- 使用 match_bm25 查询
SELECT id, title, score
FROM (
    SELECT *,
           fts_main_articles.match_bm25(id, 'database performance', k:=1.2, b:=0.75) AS score
    FROM articles
) sq
WHERE score IS NOT NULL
ORDER BY score DESC
LIMIT 10;
```

DuckDB BM25 参数：

```
k: BM25 的 k1 参数 (默认 1.2)
b: BM25 的 b 参数 (默认 0.75)
conjunctive: 是否所有词都必须匹配 (默认 false = 析取)
fields: 限制搜索特定字段
```

### Elasticsearch / OpenSearch: BM25 (默认自 5.0)

Elasticsearch 5.0 (2016) 将默认评分从 TF-IDF 切换到 BM25。这是行业里程碑事件，标志着 BM25 成为现代搜索引擎的事实标准。

```json
// 创建索引时配置 BM25 参数
PUT /articles
{
  "settings": {
    "similarity": {
      "my_bm25": {
        "type": "BM25",
        "k1": 1.2,
        "b": 0.75
      }
    }
  },
  "mappings": {
    "properties": {
      "title": {
        "type": "text",
        "similarity": "my_bm25"
      },
      "body": {
        "type": "text",
        "similarity": "my_bm25"
      }
    }
  }
}
```

```sql
-- Elasticsearch SQL (X-Pack)
SELECT id, title, SCORE() AS relevance
FROM articles
WHERE MATCH(title, 'database performance')
ORDER BY SCORE() DESC
LIMIT 10;

-- 多字段加权 (BM25F)
SELECT id, title, SCORE() AS relevance
FROM articles
WHERE MATCH('title^3,body^1', 'database performance')
ORDER BY SCORE() DESC;
-- title 权重是 body 的 3 倍
```

```json
// Query DSL 等价语法
GET /articles/_search
{
  "query": {
    "multi_match": {
      "query": "database performance",
      "fields": ["title^3", "body^1"],
      "type": "best_fields",
      "tie_breaker": 0.3
    }
  }
}
```

#### Elasticsearch 高级评分

```json
// function_score: 自定义评分函数
{
  "query": {
    "function_score": {
      "query": { "match": { "body": "database" } },
      "functions": [
        { "filter": { "term": { "lang": "en" } }, "weight": 2 },
        {
          "field_value_factor": {
            "field": "popularity",
            "factor": 1.2,
            "modifier": "log1p"
          }
        }
      ],
      "score_mode": "sum",
      "boost_mode": "multiply"
    }
  }
}

// rescore: 二阶段重排
{
  "query": { "match": { "body": "database" } },
  "rescore": {
    "window_size": 100,
    "query": {
      "rescore_query": {
        "match_phrase": { "body": { "query": "database", "slop": 2 } }
      },
      "query_weight": 0.7,
      "rescore_query_weight": 1.5
    }
  }
}
```

### Vespa: BM25 与可编程评分

Vespa (Yahoo 开源的搜索引擎) 提供最灵活的评分系统，支持完全可编程的 rank-profile：

```
# article.sd
schema article {
    document article {
        field title type string {
            indexing: index | summary
            index: enable-bm25
        }
        field body type string {
            indexing: index | summary
            index: enable-bm25
        }
        field popularity type float {
            indexing: attribute | summary
        }
    }

    rank-profile default {
        first-phase {
            expression: bm25(title) * 3 + bm25(body) + log(attribute(popularity) + 1)
        }
    }

    rank-profile two_phase {
        first-phase {
            expression: bm25(title) + bm25(body)
        }
        second-phase {
            expression: 0.7 * firstPhase + 0.3 * sum(matchfeatures("dotProduct"))
            rerank-count: 100
        }
    }
}
```

Vespa 的优势是 BM25、向量、ML 模型、自定义函数可以在同一个表达式里组合。

### ClickHouse: 字符串函数（无内置 BM25）

ClickHouse 没有内置的 BM25 或 TF-IDF 实现，全文检索依赖：

```sql
-- 1. tokenbf_v1 索引（基于 token 的 Bloom filter）
CREATE TABLE articles (
    id UInt64,
    body String,
    INDEX body_idx body TYPE tokenbf_v1(8192, 3, 0) GRANULARITY 4
) ENGINE = MergeTree()
ORDER BY id;

-- 仅加速 hasToken 查询，不评分
SELECT id, body FROM articles
WHERE hasToken(body, 'database') AND hasToken(body, 'performance');

-- 2. ngrambf_v1 索引（基于 n-gram 的 Bloom filter）
CREATE TABLE articles2 (
    id UInt64,
    body String,
    INDEX body_idx body TYPE ngrambf_v1(3, 8192, 3, 0) GRANULARITY 4
) ENGINE = MergeTree()
ORDER BY id;

-- 3. 字符串函数模拟（无评分）
SELECT id,
       countMatches(body, 'database') AS db_count,
       countMatches(body, 'performance') AS perf_count
FROM articles
WHERE positionCaseInsensitive(body, 'database') > 0
ORDER BY db_count + perf_count DESC;
-- 这是粗糙的 TF 替代，没有 IDF 部分

-- 4. 实验性 full_text_search 索引（24.x+）
-- ClickHouse 24.x 引入实验性的 inverted index 与 BM25 评分
SET allow_experimental_full_text_index = 1;
ALTER TABLE articles ADD INDEX body_full_text body TYPE full_text(0) GRANULARITY 1;
```

### Snowflake: SEARCH 函数（黑盒）

Snowflake SEARCH 函数 (2023 GA) 提供简化的全文搜索，但**不暴露评分细节**，无法获得 BM25 score。

```sql
-- 创建搜索优化 (Search Optimization Service)
ALTER TABLE articles
ADD SEARCH OPTIMIZATION ON SUBSTRING(body);

-- SEARCH 函数（自然语言）
SELECT id, title
FROM articles
WHERE SEARCH(body, 'database performance');

-- SEARCH 多列
SELECT id, title
FROM articles
WHERE SEARCH((title, body), 'database performance');

-- 不支持: 获取 SCORE 或 RANK，结果是无序集合
-- 排序需要应用层或自行实现 ORDER BY 子句
```

### BigQuery: SEARCH 函数

BigQuery SEARCH (2022 GA) 同样是简化设计，主打高吞吐扫描，**默认不返回评分**。

```sql
-- 创建 SEARCH INDEX
CREATE SEARCH INDEX my_index
ON `dataset.articles` (body);

-- 基础 SEARCH
SELECT id, title FROM `dataset.articles`
WHERE SEARCH(body, 'database performance');

-- 多列 SEARCH (使用 ALL_COLUMNS)
SELECT id, title FROM `dataset.articles`
WHERE SEARCH(STRUCT(title, body), 'database');

-- analyzer 选项
SELECT id, title FROM `dataset.articles`
WHERE SEARCH(
    body,
    '"database performance"',
    analyzer => 'LOG_ANALYZER'
);

-- 想要排名? 需要用结构化方式表达
SELECT id, title,
       (CASE WHEN SEARCH(title, 'database') THEN 3 ELSE 0 END) +
       (CASE WHEN SEARCH(body, 'database') THEN 1 ELSE 0 END) AS manual_score
FROM `dataset.articles`
WHERE SEARCH(STRUCT(title, body), 'database')
ORDER BY manual_score DESC;
```

### Doris / StarRocks: BM25 倒排索引

Apache Doris 与 StarRocks 都支持 INVERTED INDEX 与 MATCH 操作，使用 BM25 评分。

```sql
-- Doris
CREATE TABLE articles (
    id INT,
    title VARCHAR(200),
    body STRING,
    INDEX body_idx (body) USING INVERTED PROPERTIES("parser" = "english")
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 10;

-- MATCH 函数（BM25 评分）
SELECT id, title FROM articles
WHERE body MATCH_ANY 'database performance'
ORDER BY body MATCH_ANY 'database performance' DESC
LIMIT 10;

-- MATCH_ALL: 所有词都必须出现
SELECT id, title FROM articles
WHERE body MATCH_ALL 'database performance';

-- MATCH_PHRASE: 短语精确匹配
SELECT id, title FROM articles
WHERE body MATCH_PHRASE 'database performance';
```

### MariaDB FULLTEXT

MariaDB 继承 MySQL 5.6+ 的 InnoDB FULLTEXT 实现，使用 BM25 变体：

```sql
CREATE TABLE articles (
    id INT PRIMARY KEY AUTO_INCREMENT,
    title VARCHAR(200),
    body TEXT,
    FULLTEXT (title, body)
) ENGINE=InnoDB;

SELECT id, title,
       MATCH(title, body) AGAINST('database' IN NATURAL LANGUAGE MODE) AS score
FROM articles
WHERE MATCH(title, body) AGAINST('database' IN NATURAL LANGUAGE MODE)
ORDER BY score DESC
LIMIT 10;
```

MariaDB 还有 Mroonga / Sphinx 集成可选，提供更丰富的评分能力。

## BM25 公式深入解析

BM25 (Best Matching 25) 是 Stephen Robertson 与 Karen Spärck Jones 在 1994 年 TREC-3 提出的概率检索模型，至今 30 年仍是默认选择。

### BM25 核心公式

```
score(D, Q) = sum_over_q_in_Q [ IDF(q) * tf_normalized(q, D) ]

其中:

IDF(q) = log( (N - n_q + 0.5) / (n_q + 0.5) + 1 )
  N: 文档总数
  n_q: 包含词 q 的文档数

tf_normalized(q, D) = ( f(q,D) * (k1 + 1) ) / ( f(q,D) + k1 * (1 - b + b * (|D| / avgdl)) )
  f(q,D): 词 q 在文档 D 中的频率
  |D|: 文档 D 的长度（词数）
  avgdl: 集合内文档的平均长度
  k1: 控制词频饱和速度，默认 1.2 (取值 1.2-2.0)
  b: 控制文档长度归一化强度，默认 0.75 (取值 0-1)
```

### 三个直觉

```
1. IDF: 稀有词比常见词更重要
   "the" 出现在每个文档 → IDF ≈ 0
   "quantum" 只出现在少数文档 → IDF 高

2. TF 饱和: 词频从 0 到 5 比从 50 到 55 更重要
   k1 控制饱和曲线: 越大越接近线性，越小越快饱和
   k1 = 0:    退化为布尔检索 (有/无)
   k1 = 无穷: 退化为线性 TF
   k1 = 1.2:  经验最优，5 次出现已接近饱和

3. 文档长度归一化: 长文档不应仅因长而胜
   b 控制归一化强度
   b = 0:   完全不归一化 (长文档容易胜出)
   b = 1:   完全归一化 (短文档与长文档比拼词频密度)
   b = 0.75: 折中 (经验最优)
```

### k1 和 b 调参实战

```
不同场景下的最优参数:

新闻、博客（平均 500 词）:
  k1 = 1.2, b = 0.75 (默认)

学术论文（平均 5000 词）:
  k1 = 1.5, b = 0.85 (长文档更需归一化)

商品描述（平均 50 词）:
  k1 = 0.7, b = 0.3 (短文档不需要太强归一化)

代码搜索（结构化文本）:
  k1 = 1.2, b = 0.5 (代码长度方差大，弱归一化)

中文文本（分词后短）:
  k1 = 1.5, b = 0.85 (中文词数与英文不同)
```

### BM25F: 多字段加权 BM25

BM25F 是 BM25 的多字段扩展，每个字段有独立的权重。常见公式：

```
score(D, Q) = sum_q IDF(q) * tf_F(q, D) * (k1 + 1) / (tf_F(q, D) + k1)

其中:
  tf_F(q, D) = sum_f boost_f * f(q, D, f) / (1 - b_f + b_f * len_f(D)/avglen_f)
  boost_f: 字段 f 的权重
  b_f: 字段 f 的长度归一化参数
```

ParadeDB / Elasticsearch / Solr 都支持此能力。

### BM25+ 与 BM25L

针对长文档评分偏低的问题，有两个改进版本：

```
BM25L (Lv & Zhai, 2011):
  在归一化项中加入下界 delta 防止短文档过度优势

BM25+ (Lv & Zhai, 2011):
  tf 项额外加 delta 偏移
  确保即使长文档也能获得最低分

这些变体在学术界使用较多，工业界仍以经典 BM25 为主。
```

### BM25 vs 向量搜索的语义差异

```
BM25:
  - 关键词级匹配，词必须出现
  - 同义词、改写完全失效 ("car" 找不到 "automobile")
  - 数学优化是凸的，可解释性强
  - 评分稳定，不依赖训练数据

向量搜索 (cosine similarity):
  - 语义级匹配，意思相近即可
  - 同义词、改写自然处理
  - 依赖嵌入模型，模型质量决定一切
  - 评分依赖训练数据分布，不易解释
```

## TF-IDF vs BM25 对比

```
维度          TF-IDF                  BM25
─────────────────────────────────────────────────────
诞生年代      1971                    1994
理论基础      向量空间模型            概率检索模型
词频项        线性 (tf)               饱和函数 (tf*(k1+1)/(tf+k1*norm))
文档长度      简单归一化              带 b 参数的可调归一化
IDF           log(N/n_q)              log((N-n_q+0.5)/(n_q+0.5)+1)
参数          少，难调                k1 + b 两参数，可调
工程效果      短文档偏好              长短文档平衡
工业默认      Lucene 6.0 之前         Lucene 6.0+ / ES 5.0+
```

### TF-IDF 公式

```
score(D, Q) = sum_q tf(q,D) * idf(q)

其中:
  tf(q,D) = 词 q 在 D 中出现次数 (或归一化形式如 1+log(f))
  idf(q) = log(N/n_q)

向量空间模型下的余弦版本:
  score(D, Q) = (V_D · V_Q) / (|V_D| * |V_Q|)
  其中 V_D, V_Q 是文档与查询的 TF-IDF 向量
```

### 为什么 BM25 替代了 TF-IDF？

```
1. 文档长度处理: TF-IDF 对长文档过度偏好，BM25 通过 b 参数解决
2. 词频饱和: TF-IDF 线性词频导致 "重复词刷分"，BM25 饱和后稳定
3. 概率基础: BM25 基于概率排序原理 (PRP)，理论更扎实
4. 可调性: k1, b 让工程师能为特定语料调优
5. 工业验证: TREC 评测中 BM25 长期占优
```

### 何时仍应选择 TF-IDF？

```
1. 文档长度高度均匀 (b 参数无意义)
2. 极小语料 (<1000 文档，IDF 不稳定)
3. 历史系统兼容 (替换需要重新评估排序)
4. 与余弦相似度结合的向量空间模型场景
```

## 余弦相似度与向量评分

向量搜索使用嵌入模型将文本转为高维向量，再用相似度度量排序。

### 三种主要距离度量

```
余弦相似度 (Cosine Similarity):
  cos(A, B) = (A · B) / (|A| * |B|)
  范围: [-1, 1]，1 表示同方向，0 表示正交，-1 表示反方向
  特点: 忽略向量长度，只关心方向，最适合归一化嵌入

内积 (Inner Product / Dot Product):
  IP(A, B) = sum(A_i * B_i)
  范围: 实数，越大越相似
  特点: 包含向量长度信息，对未归一化嵌入更有意义

L2 距离 (Euclidean Distance):
  L2(A, B) = sqrt(sum((A_i - B_i)^2))
  范围: 非负实数，越小越相似
  特点: 几何直观，对归一化向量与余弦相似度等价
```

### PostgreSQL pgvector 示例

```sql
CREATE EXTENSION vector;

CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding VECTOR(1536)  -- OpenAI ada-002 维度
);

-- HNSW 索引（pgvector 0.5+）
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);

-- 余弦距离搜索
SELECT id, content, embedding <=> '[0.1, 0.2, ...]'::vector AS cosine_distance
FROM documents
ORDER BY embedding <=> '[0.1, 0.2, ...]'::vector
LIMIT 10;

-- 内积
SELECT id, content, embedding <#> '[0.1, 0.2, ...]'::vector AS inner_product
FROM documents
ORDER BY embedding <#> '[0.1, 0.2, ...]'::vector
LIMIT 10;

-- L2 距离
SELECT id, content, embedding <-> '[0.1, 0.2, ...]'::vector AS l2_distance
FROM documents
ORDER BY embedding <-> '[0.1, 0.2, ...]'::vector
LIMIT 10;
```

### Elasticsearch 向量评分

```json
GET /docs/_search
{
  "knn": {
    "field": "embedding",
    "query_vector": [0.1, 0.2, 0.3, ...],
    "k": 10,
    "num_candidates": 100
  }
}

// 或使用 script_score 自定义余弦
{
  "query": {
    "script_score": {
      "query": { "match_all": {} },
      "script": {
        "source": "cosineSimilarity(params.query_vector, 'embedding') + 1.0",
        "params": { "query_vector": [0.1, 0.2, ...] }
      }
    }
  }
}
```

### Snowflake 向量评分

```sql
SELECT id, content,
       VECTOR_COSINE_SIMILARITY(embedding, [0.1, 0.2, ...]::VECTOR(FLOAT, 1536)) AS sim
FROM documents
ORDER BY sim DESC
LIMIT 10;

-- 内积
SELECT id, content,
       VECTOR_INNER_PRODUCT(embedding, [0.1, 0.2, ...]::VECTOR(FLOAT, 1536)) AS ip
FROM documents
ORDER BY ip DESC;

-- L2 距离
SELECT id, content,
       VECTOR_L2_DISTANCE(embedding, [0.1, 0.2, ...]::VECTOR(FLOAT, 1536)) AS dist
FROM documents
ORDER BY dist ASC;
```

详见 [向量相似性搜索](vector-similarity-search.md)。

## 混合检索 (Hybrid Search): BM25 + 向量

混合检索结合 BM25 的精确性与向量搜索的语义性。这是 2024+ 行业主流做法。

### 为什么需要混合？

```
BM25 优势: 精确词项匹配、专有名词、ID、代码符号
BM25 劣势: 无法处理同义词、改写、多语言

向量搜索优势: 语义理解、同义、跨语言
向量搜索劣势: "iPhone 15 Pro Max" 等具体型号、人名、代号容易丢失

混合: 取两者之长
```

### 评分融合方法

#### 1. RRF (Reciprocal Rank Fusion)

```
RRF(d) = sum_i (1 / (k + rank_i(d)))

其中:
  k: 平滑常数 (常用 60)
  rank_i(d): 文档 d 在第 i 个检索器结果中的排名

优点: 不需要分数归一化，跨检索器鲁棒
缺点: 丢失分数细节
```

```sql
-- PostgreSQL 模拟 RRF
WITH bm25_ranks AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY ts_rank(tsv, query) DESC) AS rank
    FROM articles, plainto_tsquery('english', 'database performance') AS query
    WHERE tsv @@ query
    LIMIT 100
),
vector_ranks AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY embedding <=> $1) AS rank
    FROM articles
    ORDER BY embedding <=> $1
    LIMIT 100
)
SELECT a.id, a.title,
       COALESCE(1.0 / (60 + b.rank), 0) + COALESCE(1.0 / (60 + v.rank), 0) AS rrf_score
FROM articles a
LEFT JOIN bm25_ranks b ON a.id = b.id
LEFT JOIN vector_ranks v ON a.id = v.id
WHERE b.id IS NOT NULL OR v.id IS NOT NULL
ORDER BY rrf_score DESC
LIMIT 10;
```

#### 2. 线性加权 (Linear Combination)

```
final = alpha * normalize(bm25_score) + (1-alpha) * normalize(vector_score)

需要先归一化分数 (min-max 或 z-score)
alpha 通常需要离线调优
```

#### 3. Convex Combination (CC)

```
final = alpha * bm25 + (1 - alpha) * vector
直接相加，要求两者尺度可比
```

### Elasticsearch 混合检索

```json
GET /articles/_search
{
  "query": {
    "match": { "body": "database performance" }
  },
  "knn": {
    "field": "embedding",
    "query_vector": [0.1, 0.2, ...],
    "k": 10,
    "num_candidates": 100
  },
  "rank": {
    "rrf": { "rank_constant": 60, "rank_window_size": 100 }
  }
}
```

### Vespa 混合检索

```
rank-profile hybrid {
    first-phase {
        expression: bm25(title) + bm25(body) + closeness(field, embedding)
    }
}
```

### ParadeDB 混合检索

```sql
-- ParadeDB 内置 BM25 + pgvector 混合查询
WITH semantic_search AS (
    SELECT id, RANK() OVER (ORDER BY embedding <=> $1) AS rank
    FROM articles ORDER BY embedding <=> $1 LIMIT 20
),
bm25_search AS (
    SELECT id, RANK() OVER (ORDER BY paradedb.score(id) DESC) AS rank
    FROM articles WHERE id @@@ 'body:"database"' LIMIT 20
)
SELECT
    COALESCE(semantic_search.id, bm25_search.id) AS id,
    COALESCE(1.0 / (60 + semantic_search.rank), 0.0) +
    COALESCE(1.0 / (60 + bm25_search.rank), 0.0) AS rrf_score
FROM semantic_search FULL OUTER JOIN bm25_search USING (id)
ORDER BY rrf_score DESC LIMIT 10;
```

### MongoDB Atlas Search 混合检索

```js
db.articles.aggregate([
  {
    $search: {
      index: "default",
      compound: {
        should: [
          { text: { query: "database", path: "body", score: { boost: { value: 0.7 } } } },
          { knnBeta: { vector: [0.1, 0.2, ...], path: "embedding", k: 10, score: { boost: { value: 0.3 } } } }
        ]
      }
    }
  }
])
```

### 重排序 (Reranking)

混合检索的进阶是 cross-encoder 重排：

```
阶段 1 (召回): BM25 + 向量 → 100 候选 (毫秒级，bi-encoder)
阶段 2 (重排): cross-encoder (如 BGE-reranker) → 10 终选 (百毫秒级)

cross-encoder 同时考虑 query 和 doc，
不能预计算，但精度高于 bi-encoder
```

## 学习排序 (Learning to Rank, LTR)

LTR 用机器学习模型代替手工调参的评分函数。

### 三种范式

```
Pointwise: 单文档评分（回归/分类）
  - 模型: GBDT, XGBoost, RankNet
  - 损失: MSE, BCE

Pairwise: 文档对偏好学习
  - 模型: LambdaRank, RankSVM
  - 损失: pairwise hinge

Listwise: 整列表优化
  - 模型: LambdaMART, ListNet
  - 损失: NDCG, MAP 直接优化
```

### Elasticsearch LTR 插件

```json
// 注册特征集
POST /_ltr/_featureset/article_features
{
  "featureset": {
    "features": [
      {
        "name": "bm25_title",
        "params": ["query"],
        "template_language": "mustache",
        "template": { "match": { "title": "{{query}}" } }
      },
      {
        "name": "bm25_body",
        "params": ["query"],
        "template": { "match": { "body": "{{query}}" } }
      },
      {
        "name": "popularity",
        "template": { "function_score": { "field_value_factor": { "field": "views" } } }
      }
    ]
  }
}

// 加载训练好的 RankLib 模型
POST /_ltr/_model/article_ranker
{
  "model": {
    "name": "article_ranker",
    "model": {
      "type": "model/ranklib",
      "definition": "## XGBoost..."
    }
  }
}

// 在查询中使用 LTR 重排
GET /articles/_search
{
  "query": { "match": { "body": "database" } },
  "rescore": {
    "window_size": 100,
    "query": {
      "rescore_query": {
        "sltr": {
          "params": { "query": "database" },
          "model": "article_ranker"
        }
      }
    }
  }
}
```

### Solr LTR

Solr 6.4+ 提供 LTR 模块，通过 `org.apache.solr.ltr.feature.SolrFeature` 注册特征，配置 `LinearModel` 或 RankLib 兼容模型。每个特征可基于字段查询、外部文件或函数查询，模型在 ranking phase 通过 `rq=ltr` 参数启用。

### 主流 LTR 算法

```
LambdaMART (微软):
  - 当前工业最广用
  - GBDT + listwise loss
  - 直接优化 NDCG
  - Bing, Yahoo 的核心排序模型

RankNet:
  - 神经网络 pairwise
  - 已被 LambdaRank 取代

XGBoost / LightGBM:
  - rank:pairwise / rank:ndcg 目标
  - 大多数工业 LTR 实际使用

近年神经检索:
  - ColBERT, SPLADE, BGE-M3
  - 兼具召回与排序，端到端训练
  - 但通常不直接替代 BM25，而是与之融合
```

## 评估指标

排序质量评估常用以下指标：

```
Precision@K: 前 K 个结果中相关的比例
  Precision@10 = (前 10 个中相关数) / 10

Recall@K: 召回的相关结果占全部相关结果的比例
  Recall@10 = (前 10 个中相关数) / (总相关数)

MRR (Mean Reciprocal Rank):
  MRR = mean(1/rank_first_relevant)
  关注首个相关结果的位置

MAP (Mean Average Precision):
  AP = sum_k (Precision@k * rel(k)) / total_relevant
  MAP = mean(AP over queries)

NDCG (Normalized Discounted Cumulative Gain):
  DCG@K = sum_k (rel(k) * 2^rel(k) - 1) / log2(k+1)
  NDCG = DCG / IDCG (理想 DCG)
  能处理多级相关性，工业最常用
```

### 在 SQL 中计算 NDCG (PostgreSQL 示例)

```sql
WITH ranked_results AS (
    SELECT search_id, doc_id, relevance_label,
           ROW_NUMBER() OVER (PARTITION BY search_id ORDER BY score DESC) AS rank
    FROM search_results
),
dcg AS (
    SELECT search_id,
           SUM((POWER(2, relevance_label) - 1) / LOG(2, rank + 1)) AS dcg_score
    FROM ranked_results
    WHERE rank <= 10
    GROUP BY search_id
),
ideal_ranked AS (
    SELECT search_id, doc_id, relevance_label,
           ROW_NUMBER() OVER (PARTITION BY search_id ORDER BY relevance_label DESC) AS ideal_rank
    FROM search_results
),
idcg AS (
    SELECT search_id,
           SUM((POWER(2, relevance_label) - 1) / LOG(2, ideal_rank + 1)) AS idcg_score
    FROM ideal_ranked
    WHERE ideal_rank <= 10
    GROUP BY search_id
)
SELECT AVG(dcg.dcg_score / NULLIF(idcg.idcg_score, 0)) AS ndcg_at_10
FROM dcg JOIN idcg USING (search_id);
```

## 关键发现

### 1. BM25 已成为事实标准

```
切换时间表:
  2016 Lucene 6.0: 默认从 TF-IDF 切到 BM25
  2016 Elasticsearch 5.0: 同步切换
  2017 Solr 7.0: 同步切换
  2017 SQLite FTS5: 默认 BM25
  2013 MySQL 5.6 InnoDB: 已是 BM25 变体

唯一持续偏离的主流引擎:
  PostgreSQL (ts_rank, 自创算法)
  Oracle Text (TF-IDF 系)
  SQL Server (TF-IDF 系)
  MeiliSearch / Typesense (自创规则)
```

### 2. 没有 SQL 标准是双刃剑

```
负面: 跨引擎迁移困难
  - PostgreSQL 的 setweight A-D 在 MySQL 不存在
  - SQL Server CONTAINSTABLE 与 Oracle SCORE() 语法完全不同
  - Snowflake/BigQuery 干脆不暴露评分

正面: 各引擎自由演进
  - Elasticsearch 能自由迭代到 BM25
  - DuckDB / SQLite 能选最简单实现
  - Vespa 能搞极致灵活的 rank-profile
```

### 3. PostgreSQL 在排序上落后于专业搜索引擎

```
ts_rank 的局限:
  1. 不是 BM25，文档长度处理不如现代算法
  2. 性能差 (需要读完整 tsvector 才能评分)
  3. 多字段加权只到 4 级 (A/B/C/D)，不如 BM25F 灵活

补救:
  1. RUM 索引: 索引内嵌位置，加速 ts_rank
  2. ParadeDB / pg_search: 用 Tantivy 实现真正 BM25
  3. zombodb: PostgreSQL 与 Elasticsearch 同步桥
```

### 4. 现代云数仓刻意简化评分

```
Snowflake / BigQuery 的 SEARCH:
  - 不暴露 BM25 score
  - 主打 "扫描加速" 而非 "相关性排序"
  - 适合 "是否包含" 而非 "最相关 N 条"
  - 想做精排还需要外部组件

设计哲学:
  数仓优先: 保留对全表的高吞吐扫描能力
  搜索次之: 不与 Elasticsearch 直接竞争
```

### 5. 混合检索是 2024+ 主流

```
检索栈演进:
  早期 (2000s): 纯 BM25
  中期 (2010s): BM25 + LTR 重排
  现代 (2020s): BM25 + 向量召回 + cross-encoder 重排

ES、Vespa、ParadeDB、MongoDB Atlas、Couchbase
都已原生支持混合检索 (RRF 或自定义)

PostgreSQL 用户通常组合 pg_search + pgvector
```

### 6. 中文等 CJK 语言对 BM25 的影响

```
BM25 假设 "词" 是清晰边界，但中文需要分词:
  - 分词错误直接影响词频与 IDF 计算
  - 字粒度 vs 词粒度的选择
  - 同一查询不同分词器结果可能差很多

工程建议:
  - 使用统一的分词器 (索引时 + 查询时)
  - 中文文本调高 b 参数 (~0.85)
  - 调高 k1 参数 (~1.5)
  - CJK 引擎: jieba (中文), kuromoji (日文), nori (韩文)
```

详见 [分词器与分析器](tokenization-analyzers.md)。

### 7. 引擎选型建议

```
场景                         推荐方案
─────────────────────────────────────────────────────────────
高并发、相关性最优           Elasticsearch / OpenSearch / Solr
PG 生态 + 简单全文检索       PostgreSQL ts_rank
PG 生态 + 现代 BM25         ParadeDB / pg_search
MySQL 生态                  InnoDB FULLTEXT (BM25)
嵌入式、本地                 SQLite FTS5 / DuckDB FTS
极致灵活、可编程评分          Vespa
HTAP + 全文                 Doris / StarRocks
云数仓 + 简单全文            Snowflake SEARCH / BigQuery SEARCH
混合检索 (BM25+向量)        ParadeDB / Elasticsearch / MongoDB Atlas
学习排序 (LTR)              Elasticsearch LTR / Solr LTR / Vespa
```

### 8. 调参与 A/B 测试

```
工业实践:
  1. 不要盲目用默认 k1=1.2, b=0.75
  2. 对自己的语料做 grid search:
     k1: [0.5, 0.8, 1.0, 1.2, 1.5, 2.0]
     b:  [0.0, 0.25, 0.5, 0.75, 1.0]
  3. 使用 NDCG@10 或线上点击率作为指标
  4. 多字段场景下 BM25F 权重更难调，建议用 LTR

工具:
  Elasticsearch Rank Eval API
  Solr Relevance Test
  人工标注 + offline 评测
```

### 9. 评分稳定性与版本升级风险

```
警告:
  Lucene 升级时 BM25 实现可能微调 (e.g. saturation 函数)
  Elasticsearch 主版本升级排序结果可能变化
  upsert 后即时评分受文档统计影响 (IDF 在更新中)

保险措施:
  1. 升级前做 A/B 评测
  2. 关键查询保留 baseline 测试
  3. 使用 explain API 调试评分公式
```

### 10. 评分函数的开放与黑盒之争

```
开放派 (评分函数全公开):
  Elasticsearch / Solr / Vespa / Lucene / PostgreSQL
  - 优点: 调参、调试、自定义
  - 缺点: 引擎升级可能破坏调优

黑盒派 (评分函数不暴露):
  Snowflake / BigQuery / MeiliSearch / Typesense
  - 优点: 引擎可任意改进，用户无感
  - 缺点: 无法精准调优，不适合复杂场景

行业趋势:
  Bottom-up SQL 引擎 (PG/MySQL/SQLite/DuckDB) 偏开放
  Top-down 云服务 (Snowflake/BigQuery) 偏黑盒
  搜索专用引擎 (ES/Solr/Vespa) 极致开放
```

## 参考资料

- Robertson, S. & Zaragoza, H. (2009). "The Probabilistic Relevance Framework: BM25 and Beyond". Foundations and Trends in Information Retrieval.
- Robertson, S., Walker, S. (1994). "Some simple effective approximations to the 2-Poisson model for probabilistic weighted retrieval". SIGIR'94.
- Spärck Jones, K. (1972). "A statistical interpretation of term specificity and its application in retrieval".
- Salton, G., Buckley, C. (1988). "Term-weighting approaches in automatic text retrieval".
- Clarke, C., Cormack, G., Tudhope, E. (1995). "Relevance ranking for one to three term queries".
- Lv, Y. & Zhai, C. (2011). "When documents are very long, BM25 fails!". SIGIR'11.
- PostgreSQL: [Text Search Functions](https://www.postgresql.org/docs/current/textsearch-controls.html)
- Elasticsearch: [Practical BM25](https://www.elastic.co/blog/practical-bm25-part-2-the-bm25-algorithm-and-its-variables)
- Lucene 6.0: [Default similarity changed to BM25](https://issues.apache.org/jira/browse/LUCENE-6789)
- MySQL: [Full-Text Search Functions](https://dev.mysql.com/doc/refman/8.0/en/fulltext-search.html)
- Oracle Text: [Reference Guide](https://docs.oracle.com/en/database/oracle/oracle-database/19/ccref/index.html)
- SQLite: [FTS5 Extension](https://www.sqlite.org/fts5.html)
- DuckDB: [Full-Text Search](https://duckdb.org/docs/extensions/full_text_search)
- ParadeDB: [BM25 Documentation](https://docs.paradedb.com/)
- Vespa: [Ranking](https://docs.vespa.ai/en/ranking.html)
- BM25 Wikipedia: [Okapi BM25](https://en.wikipedia.org/wiki/Okapi_BM25)
- Cormack, G., Clarke, C., Buettcher, S. (2009). "Reciprocal rank fusion outperforms Condorcet and individual rank learning methods".
- Burges, C. et al. (2005). "Learning to rank using gradient descent" (RankNet).
- Burges, C. (2010). "From RankNet to LambdaRank to LambdaMART: An Overview". Microsoft Research.

## 相关文章

- [全文检索](full-text-search.md)
- [分词器与分析器](tokenization-analyzers.md)
- [向量相似性搜索](vector-similarity-search.md)
- [近似查询函数](approx-functions.md)
- [采样查询](sampling-query.md)
