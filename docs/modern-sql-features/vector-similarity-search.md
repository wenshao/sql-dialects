# 向量类型与相似性搜索 (Vector Types and Similarity Search)

2022 年 11 月 ChatGPT 发布之后,RAG (Retrieval-Augmented Generation)、语义搜索、推荐系统对"向量相似性搜索"的需求在 18 个月内从"研究课题"变成了"生产数据库的必备能力"。2023 至 2025 年间,几乎所有主流关系数据库厂商都被迫紧急添加 `VECTOR` 类型与近似最近邻 (ANN) 索引——pgvector 在 2023 年 8 月引入 HNSW,Oracle 在 2024 年发布 23ai AI Vector Search,Snowflake 在 2024 年 GA `VECTOR` 数据类型,MySQL 在 9.0 (2024 年 7 月) 引入 `VECTOR`,MariaDB 在 11.6 (2024 年 11 月) 加入向量索引,Microsoft SQL Server 在 2025 年版本中提供原生 `vector` 类型。

这是 SQL 数据库历史上最罕见的"全行业同步演化"事件。本文系统对比 45+ SQL 引擎的向量类型、距离函数、ANN 索引、维度限制、量化、混合搜索能力,并给出每个引擎的具体语法示例。

## 为什么向量搜索成为数据库刚需

传统数据库基于**精确匹配**:`WHERE name = 'Alice'`、`WHERE age BETWEEN 20 AND 30`。但 LLM 时代的应用需要的是**语义匹配**:

1. **RAG 检索增强**:用户问"如何重置密码",需要从知识库中找出"语义最相似"的文档片段,而不是关键词匹配
2. **语义搜索**:搜索"便宜的红色连衣裙"应该匹配"低价的猩红色 dress"
3. **推荐系统**:用户向量与商品向量的相似度
4. **图像/音频/视频检索**:多模态嵌入向量
5. **去重与异常检测**:相似日志聚类、重复内容识别

实现路径是:用 Embedding 模型(OpenAI text-embedding-3、bge-large、E5)把文本/图像编码为 768 / 1024 / 1536 / 3072 维浮点向量,然后在数据库中存储并按"距离"排序检索。挑战是:

- **存储**:1536 维 float32 = 6 KB/行,1 亿条 = 600 GB
- **检索性能**:暴力计算 1 亿次距离需要数秒,生产环境必须 < 100 ms
- **索引算法**:HNSW、IVFFlat、ScaNN、DiskANN 等近似算法,以"召回率换吞吐"
- **混合查询**:既要语义相似又要满足 `WHERE category = 'shoes' AND price < 100`

数据库的核心价值在于:**事务一致性、ACID、关系连接、SQL 表达力**——把向量能力做进数据库,意味着不必再维护"PostgreSQL + Pinecone + Elasticsearch"三套系统。

## 没有 SQL 标准

截至 2025 年,ISO/IEC 9075 (SQL 标准) **未定义任何向量类型或向量操作符**。所有实现完全是厂商扩展,语法、语义、距离函数命名、索引类型彼此不兼容:

- pgvector 用 `<->` 表示 L2 距离,`<=>` 表示余弦距离,`<#>` 表示负内积
- Oracle 23ai 用 `VECTOR_DISTANCE(v1, v2, COSINE)` 函数式语法
- SQL Server 2025 用 `VECTOR_DISTANCE('cosine', v1, v2)`
- MySQL 9.0 用 `DISTANCE(v1, v2, 'COSINE')`
- Snowflake 用 `VECTOR_COSINE_SIMILARITY(v1, v2)`(注意是相似度不是距离)
- BigQuery 用 `VECTOR_SEARCH(table, column, query_table, ..., distance_type=>'COSINE')`

迁移时距离函数命名差异是最大的踩坑点。下文会列出所有方言的对照。

## 支持矩阵

### 1. 向量数据类型支持

| 引擎 | 类型名 | 维度参数 | 元素类型 | 引入版本 | 备注 |
|------|--------|---------|---------|---------|------|
| PostgreSQL | `vector(N)` | 必需 | float32 | pgvector 0.1+ (2021) | 需扩展 |
| PostgreSQL | `halfvec(N)` | 必需 | float16 | pgvector 0.7 (2024-04) | 半精度 |
| PostgreSQL | `sparsevec(N)` | 必需 | 稀疏 float32 | pgvector 0.7 | 稀疏向量 |
| PostgreSQL | `bit(N)` | 必需 | 位 | 内置/pgvector 0.7 | 二值向量 |
| MySQL | `VECTOR(N)` | 可选 | float32 | 9.0 (2024-07) | HeatWave 同名 |
| MariaDB | `VECTOR(N)` | 必需 | float32 | 11.6 (2024-11) | 内置 |
| SQLite | `FLOAT[N]` / blob | 必需 | float32/int8/bit | sqlite-vec 0.1+ (2024) | 需扩展 |
| Oracle | `VECTOR(N, *)` | 可选 | FLOAT32/64/INT8/BINARY | 23ai (2024) | 内置 |
| SQL Server | `vector(N)` | 必需 | float32 | 2025 (预览/GA) | 内置 |
| DB2 | `VECTOR(N, FLOAT32)` | 必需 | float32/8 | 11.5.9 / Watsonx | 部分版本 |
| Snowflake | `VECTOR(FLOAT, N)` | 必需 | float32 | GA 2024 | 内置 |
| BigQuery | `ARRAY<FLOAT64>` | -- | float64 | GA | 用数组承载 |
| Redshift | -- | -- | -- | -- | 通过 Bedrock 集成,无原生类型 |
| DuckDB | `FLOAT[N]` | 必需 | float32 | 0.10+ vss 扩展 | 固定长度数组 |
| ClickHouse | `Array(Float32)` | -- | float32 | 早期 | 用数组承载 |
| Trino | `array(double)` | -- | double | -- | 数组,无原生 |
| Presto | `array(double)` | -- | double | -- | 数组,无原生 |
| Spark SQL | `ARRAY<FLOAT>` | -- | float | -- | 数组承载 |
| Hive | `ARRAY<FLOAT>` | -- | float | -- | 数组承载 |
| Flink SQL | `ARRAY<FLOAT>` | -- | float | -- | 数组承载 |
| Databricks | `ARRAY<FLOAT>` | -- | float | -- | + 独立 Vector Search 服务 |
| Teradata | -- | -- | -- | -- | 不支持 |
| Greenplum | `vector(N)` | 必需 | float32 | pgvector 移植 | 继承 PG |
| CockroachDB | `VECTOR(N)` | 必需 | float32 | 24.2+ (2024) | 内置 |
| TiDB | `VECTOR(N)` | 可选 | float32 | 8.4+ (2024) | TiDB Serverless 优先 |
| OceanBase | `VECTOR(N)` | 必需 | float32 | 4.3.3+ (2024) | 内置 |
| YugabyteDB | `vector(N)` | 必需 | float32 | 2.25+ | 集成 pgvector |
| SingleStore | `VECTOR(N)` | 必需 | float32/8 | 8.5+ (2024) | 内置 |
| Vertica | -- | -- | -- | -- | 无原生类型 |
| Impala | -- | -- | -- | -- | 不支持 |
| StarRocks | `ARRAY<FLOAT>` | -- | float | 3.1+ | 数组 + ANN 索引 |
| Doris | `ARRAY<FLOAT>` | -- | float | 3.0+ | 数组 + ANN 索引 |
| MonetDB | -- | -- | -- | -- | 不支持 |
| CrateDB | `FLOAT_VECTOR(N)` | 必需 | float32 | 5.5+ (2024) | 内置 |
| TimescaleDB | `vector(N)` | 必需 | float32 | 继承 PG + pgvectorscale | 增强 |
| QuestDB | -- | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | -- | 不支持 |
| SAP HANA | `REAL_VECTOR(N)` | 必需 | float32 | 2.0 SPS 06+ (2024) | 内置 |
| Informix | -- | -- | -- | -- | 不支持 |
| Firebird | -- | -- | -- | -- | 不支持 |
| H2 | -- | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | -- | 不支持 |
| Amazon Athena | `array(double)` | -- | -- | -- | Trino 数组 |
| Azure Synapse | -- | -- | -- | -- | 暂无原生 |
| Google Spanner | `ARRAY<FLOAT32>` | -- | float32 | 2024 | + ANN 索引 |
| Materialize | -- | -- | -- | -- | 不支持 |
| RisingWave | -- | -- | -- | -- | 不支持 |
| InfluxDB | -- | -- | -- | -- | 不支持 |
| Databend | `VECTOR(N)` | 必需 | float32 | 1.2+ | 内置 |
| Yellowbrick | -- | -- | -- | -- | 不支持 |
| Firebolt | -- | -- | -- | -- | 不支持 |

> 统计:约 22 个引擎提供原生或扩展形式的向量类型,约 8 个引擎用通用数组类型承载向量,约 18 个引擎完全没有向量能力。

### 2. 距离函数支持

向量搜索的"距离"通常有四种语义,业界常用的是 **L2 (欧几里得)、Cosine (余弦)、Inner Product (内积/点积)**,Manhattan (L1) 较少使用。

| 引擎 | L2 / Euclidean | Cosine | Inner Product | Manhattan / L1 | Hamming (bit) |
|------|----------------|--------|---------------|----------------|---------------|
| PostgreSQL (pgvector) | `<->` | `<=>` | `<#>` | `<+>` (0.7+) | `<~>` (bit) |
| MySQL 9.0 | `DISTANCE(...,'EUCLIDEAN')` | `DISTANCE(...,'COSINE')` | `DISTANCE(...,'DOT')` | -- | -- |
| MariaDB 11.6 | `VEC_DISTANCE_EUCLIDEAN` | `VEC_DISTANCE_COSINE` | -- | -- | -- |
| SQLite (sqlite-vec) | `vec_distance_L2` | `vec_distance_cosine` | -- | `vec_distance_L1` | `vec_distance_hamming` |
| Oracle 23ai | `EUCLIDEAN` / `L2_SQUARED` | `COSINE` | `DOT` | `MANHATTAN` | `HAMMING` |
| SQL Server 2025 | `VECTOR_DISTANCE('euclidean',...)` | `'cosine'` | `'dot'` | -- | -- |
| DB2 | `VECTOR_DISTANCE(...,EUCLIDEAN)` | `COSINE` | `DOT` | -- | -- |
| Snowflake | `VECTOR_L2_DISTANCE` | `VECTOR_COSINE_SIMILARITY` | `VECTOR_INNER_PRODUCT` | -- | -- |
| BigQuery | `distance_type=>'EUCLIDEAN'` | `'COSINE'` | `'DOT_PRODUCT'` | -- | -- |
| Redshift | -- | -- | -- | -- | -- |
| DuckDB (vss) | `array_distance` | `array_cosine_distance` | `array_inner_product` (负) | -- | -- |
| ClickHouse | `L2Distance` | `cosineDistance` | `dotProduct` | `L1Distance` | -- |
| Trino / Presto | UDF / 手写 | UDF / 手写 | UDF | -- | -- |
| Spark SQL | UDF (Spark MLlib) | UDF | UDF | -- | -- |
| Databricks | `array_distance` (DBR 14.2+) | -- | -- | -- | -- |
| Greenplum (pgvector) | `<->` | `<=>` | `<#>` | -- | -- |
| CockroachDB | `<->` | `<=>` | `<#>` | -- | -- |
| TiDB | `VEC_L2_DISTANCE` | `VEC_COSINE_DISTANCE` | `VEC_NEGATIVE_INNER_PRODUCT` | `VEC_L1_DISTANCE` | -- |
| OceanBase | `L2_DISTANCE` | `COSINE_DISTANCE` | `INNER_PRODUCT` | -- | -- |
| YugabyteDB | `<->` | `<=>` | `<#>` | -- | -- |
| SingleStore | `EUCLIDEAN_DISTANCE` | `DOT_PRODUCT` (与 cosine 配合归一化) | `DOT_PRODUCT` | -- | -- |
| StarRocks | `l2_distance` | `cosine_similarity` | -- | -- | -- |
| Doris | `l2_distance_approximate` | `cosine_distance_approximate` | `inner_product_approximate` | -- | -- |
| TimescaleDB | 同 pgvector | 同 pgvector | 同 pgvector | -- | -- |
| SAP HANA | `L2DISTANCE` | `COSINE_SIMILARITY` | -- | -- | -- |
| CrateDB | `vector_similarity` (Hamming-like) | -- | -- | -- | -- |
| Spanner | `EUCLIDEAN_DISTANCE` | `COSINE_DISTANCE` | `DOT_PRODUCT` | -- | -- |
| Databend | `l2_distance` | `cosine_distance` | `inner_product` | -- | -- |

> 关键陷阱:Snowflake 的 `VECTOR_COSINE_SIMILARITY` 返回 **相似度** (越大越好),其他多数引擎返回 **距离** (越小越好)。`ORDER BY` 方向必须一致检查。同样地 pgvector 的 `<#>` 返回的是 **负内积** (方便用 `ORDER BY ... ASC`)。

### 3. ANN 索引算法支持

精确 KNN (k-Nearest Neighbors) 在百万级以上是 O(N),必须用 **近似最近邻 (ANN)** 索引。主流算法是 **HNSW** (Hierarchical Navigable Small World, 图索引,高召回低延迟,内存占用大) 和 **IVFFlat** (Inverted File, 聚类索引,内存友好,需训练)。**ScaNN** 是 Google 的量化方案,**DiskANN** 是 Microsoft 的磁盘索引算法,适合超大规模。

| 引擎 | HNSW | IVFFlat | IVFPQ | ScaNN | DiskANN | Flat (精确) | 索引版本 |
|------|------|---------|-------|-------|---------|-------------|---------|
| PostgreSQL (pgvector) | 0.5+ (2023-08) | 0.4+ | -- | -- | -- | 顺序扫描 | -- |
| TimescaleDB (pgvectorscale) | -- | -- | -- | -- | StreamingDiskANN | -- | 0.2+ |
| MySQL 9.0 | -- (HeatWave 内部) | -- | -- | -- | -- | 是 | -- |
| MariaDB 11.6 | 是 (mhnsw) | -- | -- | -- | -- | 是 | 11.6 GA |
| SQLite (sqlite-vec) | -- | -- | -- | -- | -- | 是 (暴力) | 早期 |
| Oracle 23ai | HNSW (内存) | IVF (混合内存/磁盘) | -- | -- | -- | -- | 23ai |
| SQL Server 2025 | DiskANN 路线 | -- | -- | -- | DiskANN | -- | 2025 |
| DB2 | HNSW | -- | -- | -- | -- | -- | 11.5.9 |
| Snowflake | 是 (隐式) | -- | -- | -- | -- | -- | GA |
| BigQuery | -- | `IVF` | -- | `TREE_AH` (ScaNN) | -- | `BRUTE_FORCE` | GA |
| Redshift | -- | -- | -- | -- | -- | -- | -- |
| DuckDB (vss) | HNSW | -- | -- | -- | -- | -- | 0.10+ |
| ClickHouse | 实验性 (annoy / usearch) | -- | -- | -- | -- | 暴力 | 23.1+ 实验 |
| Databricks | HNSW (Vector Search 服务) | -- | -- | -- | -- | -- | GA 2024 |
| Greenplum | 继承 pgvector | 继承 pgvector | -- | -- | -- | -- | -- |
| CockroachDB | C-SPANN (24.3 / 25.1) | -- | -- | -- | -- | -- | VECTOR 类型 24.2 / 索引后续版本 |
| TiDB | HNSW | -- | -- | -- | -- | -- | 8.4+ |
| OceanBase | HNSW | IVFFlat / IVFPQ / IVFSQ8 | 是 | -- | -- | 是 | 4.3.3+ |
| YugabyteDB | 继承 pgvector | 继承 pgvector | -- | -- | -- | -- | -- |
| SingleStore | HNSW (FLAT/HNSW_FLAT/HNSW_PQ) | IVF_FLAT/IVF_PQ | 是 | -- | -- | 是 | 8.5+ |
| StarRocks | HNSW | IVFPQ | 是 | -- | -- | -- | 3.1+ |
| Doris | HNSW | -- | -- | -- | -- | -- | 3.0+ |
| TimescaleDB | 继承 pgvector | 继承 pgvector | -- | -- | StreamingDiskANN | -- | -- |
| SAP HANA | HNSW | -- | -- | -- | -- | -- | 2024 QRC |
| CrateDB | HNSW (基于 Lucene) | -- | -- | -- | -- | -- | 5.5+ |
| Spanner | ScaNN | -- | -- | ScaNN | -- | -- | 2024 |
| Databend | -- | -- | -- | -- | -- | 暴力 | -- |

> 统计:HNSW 是当前事实标准,约 18 个引擎实现 HNSW。IVF 系列约 7 个引擎提供。SQL Server 2025 走 Microsoft Research 的 DiskANN 路线,与多数厂商不同。

### 4. 维度限制

| 引擎 | 默认/最大维度 | 索引时维度限制 | 备注 |
|------|--------------|---------------|------|
| PostgreSQL (pgvector) | `vector` 16000 / `halfvec` 16000 | HNSW: 2000 (vector), 4000 (halfvec); IVFFlat: 2000 | 0.7+ |
| MySQL 9.0 | 16383 (列存储) | -- | -- |
| MariaDB 11.6 | 65535 | 索引内 65535 | -- |
| SQLite (sqlite-vec) | 8192 (默认) | -- | 编译时可调 |
| Oracle 23ai | 65535 (FLOAT32) / 65535 (INT8) | HNSW 索引同 | -- |
| SQL Server 2025 | 1998 (float32) | -- | -- |
| Snowflake | 4096 | -- | -- |
| BigQuery | 任意 (ARRAY) | 索引建议 ≤ 1600 | -- |
| DuckDB (vss) | 任意 | HNSW 任意 | -- |
| TiDB | 16383 | -- | -- |
| OceanBase | 16000 | -- | -- |
| SingleStore | 16383 | -- | -- |
| CockroachDB | 16000 | -- | -- |
| StarRocks | 16384 | -- | -- |
| SAP HANA | 65000 | -- | -- |
| Spanner | 8000 | -- | -- |

### 5. 量化与压缩

float32 占 4 字节/维,1536 维 = 6 KB,量化能把存储压缩 4x (int8) 至 32x (binary)。

| 引擎 | float32 | float16 / half | int8 | binary / bit | sparsevec |
|------|---------|---------------|------|--------------|-----------|
| PostgreSQL pgvector 0.7 | `vector` | `halfvec` | -- | `bit` | `sparsevec` |
| pgvectorscale | + SBQ (Statistical Binary Quant) | -- | -- | -- | -- |
| Oracle 23ai | `FLOAT32` | -- | `INT8` | `BINARY` | -- |
| SQL Server 2025 | 是 | -- | -- | -- | -- |
| MariaDB 11.6 | 是 | -- | -- | -- | -- |
| MySQL 9.0 | 是 | -- | -- | -- | -- |
| SQLite (sqlite-vec) | 是 | -- | `int8` | `bit` | -- |
| OceanBase | 是 | -- | IVF_SQ8 量化 | -- | -- |
| SingleStore | 是 | -- | I8 | binary | -- |
| StarRocks | 是 | -- | PQ 量化 | -- | -- |
| Snowflake | 是 | -- | -- | -- | -- |
| Databricks | 是 | -- | -- | -- | -- |
| BigQuery | 是 (FLOAT64) | -- | -- | -- | -- |

> pgvector 0.7 (2024 年 4 月) 引入了 `halfvec`(2 字节/维)、`sparsevec`(用于词袋类稀疏向量)和 `bit`(用于二值哈希)三种新类型,大幅扩展了 PostgreSQL 在向量场景的成本竞争力。

### 6. 混合搜索 (Vector + Keyword + Filter)

生产应用很少做"纯向量"搜索,几乎都需要结合元数据过滤(`WHERE category = 'shoes'`)和关键词全文搜索(BM25)。混合搜索的两大模式是 **预过滤 (pre-filter)** 和 **后过滤 (post-filter)**,以及融合多路结果的 **RRF (Reciprocal Rank Fusion)**。

| 引擎 | 元数据 WHERE 过滤 | 全文 + 向量混合 | RRF / Hybrid Score |
|------|------------------|---------------|------------------|
| PostgreSQL (pgvector + tsvector) | 是 (任意 SQL) | tsvector + vector,人工 RRF | 手动 |
| Oracle 23ai | 是 | Oracle Text + VECTOR | DBMS_HYBRID_VECTOR |
| SQL Server 2025 | 是 | FTS + vector | 手动 |
| MySQL 9.0 | 是 | FULLTEXT + VECTOR | 手动 |
| MariaDB 11.6 | 是 | FULLTEXT + VECTOR | 手动 |
| Snowflake | 是 | Cortex Search 混合 | 内置 |
| BigQuery | 是 (`VECTOR_SEARCH` `options` 过滤) | + SEARCH 索引 | 手动 |
| Databricks Vector Search | 是 | + Hybrid Search 接口 | 内置 |
| Elasticsearch (ES SQL) | 是 | knn + match,RRF | 内置 |
| TiDB | 是 | + 全文(实验) | 手动 |
| OceanBase | 是 | -- | 手动 |
| SingleStore | 是 | + FULLTEXT BM25 | 手动 |
| CrateDB | 是 | + 全文(Lucene) | 手动 |
| StarRocks | 是 | -- | 手动 |
| Spanner | 是 | -- | 手动 |

## 各引擎语法详解

### PostgreSQL + pgvector (生态最成熟)

pgvector 由 Andrew Kane 开发,2021 年首次发布,2023 年 8 月的 0.5.0 版本引入 HNSW 索引,2024 年 4 月的 0.7.0 版本引入 `halfvec`、`sparsevec`、`bit` 类型与 `<+>` (L1 距离) 操作符。它已经成为 PostgreSQL 生态(及其衍生数据库 Greenplum、CockroachDB、YugabyteDB、TimescaleDB、Aurora、AlloyDB、Cloud SQL 等)的事实标准。

```sql
-- 安装扩展
CREATE EXTENSION vector;

-- 建表
CREATE TABLE documents (
    id        bigserial PRIMARY KEY,
    content   text,
    embedding vector(1536)
);

-- 插入
INSERT INTO documents (content, embedding) VALUES
    ('PostgreSQL is open source', '[0.012, -0.034, ..., 0.078]');

-- 距离操作符
SELECT id, content, embedding <-> '[...]'::vector AS l2_distance
FROM documents
ORDER BY embedding <-> '[...]'::vector
LIMIT 10;

-- 操作符表
-- <->  : L2 距离 (Euclidean)
-- <=>  : 余弦距离 (1 - cosine_similarity)
-- <#>  : 负内积 (-(a·b))
-- <+>  : L1 距离 (Manhattan, 0.7+)
-- <~>  : Hamming 距离 (bit 类型, 0.7+)

-- HNSW 索引 (0.5+, 推荐)
CREATE INDEX ON documents USING hnsw (embedding vector_l2_ops)
    WITH (m = 16, ef_construction = 64);

-- 余弦距离 HNSW
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);

-- IVFFlat 索引 (0.4+, 需先填充数据再建索引)
CREATE INDEX ON documents USING ivfflat (embedding vector_l2_ops)
    WITH (lists = 100);

-- 查询时控制召回率
SET hnsw.ef_search = 100;
SET ivfflat.probes = 10;

-- 0.7+ 半精度 halfvec (节省 50% 存储)
ALTER TABLE documents ADD COLUMN embedding_h halfvec(1536);
CREATE INDEX ON documents USING hnsw (embedding_h halfvec_l2_ops);

-- 0.7+ 二值化 bit (节省 32x 存储)
ALTER TABLE documents ADD COLUMN embedding_b bit(1536);
CREATE INDEX ON documents USING hnsw (embedding_b bit_hamming_ops);

-- 0.7+ 稀疏向量 sparsevec (词袋类场景)
ALTER TABLE documents ADD COLUMN embedding_s sparsevec(30000);

-- 混合搜索:向量 + 元数据过滤 (HNSW 支持过滤后扫描)
SELECT id, content
FROM documents
WHERE category = 'tech' AND created_at > '2024-01-01'
ORDER BY embedding <=> '[...]'::vector
LIMIT 10;
```

pgvectorscale (Timescale 开源) 在 pgvector 之上引入了 **StreamingDiskANN** 索引和 **SBQ (Statistical Binary Quantization)** 量化,在 99% 召回时延迟比 pgvector HNSW 低 28x、吞吐高 16x(Timescale 官方基准)。

### Oracle 23ai AI Vector Search

Oracle 在 2024 年 5 月正式发布 **23ai (原 23c) AI Vector Search**,把向量原生类型、HNSW/IVF 索引、向量函数以及与 Oracle Text、SQL、PL/SQL、JSON 的统一查询能力做进了核心引擎。这是最早把向量做成"一等公民"的传统大型商业数据库。

```sql
-- 维度可省略 (灵活维度)
CREATE TABLE docs (
    id      NUMBER PRIMARY KEY,
    content CLOB,
    embedding VECTOR(1536, FLOAT32)
);

-- INT8 量化版本
CREATE TABLE docs_q (
    id      NUMBER PRIMARY KEY,
    embedding VECTOR(1536, INT8)
);

-- BINARY 二值
CREATE TABLE docs_b (embedding VECTOR(1536, BINARY));

-- 距离查询
SELECT id, VECTOR_DISTANCE(embedding, :q, COSINE) AS dist
FROM docs
ORDER BY VECTOR_DISTANCE(embedding, :q, COSINE)
FETCH FIRST 10 ROWS ONLY;

-- 简化语法
SELECT * FROM docs
ORDER BY VECTOR_DISTANCE(embedding, :q, COSINE)
FETCH APPROX FIRST 10 ROWS ONLY;     -- APPROX 触发 ANN 索引

-- HNSW 内存索引 (Oracle 称之为 In-Memory Neighbor Graph)
CREATE VECTOR INDEX docs_hnsw ON docs (embedding)
ORGANIZATION INMEMORY NEIGHBOR GRAPH
DISTANCE COSINE
WITH TARGET ACCURACY 95
PARAMETERS (TYPE HNSW, NEIGHBORS 16, EFCONSTRUCTION 200);

-- IVF 磁盘索引 (Neighbor Partition)
CREATE VECTOR INDEX docs_ivf ON docs (embedding)
ORGANIZATION NEIGHBOR PARTITIONS
DISTANCE EUCLIDEAN
PARAMETERS (TYPE IVF, NEIGHBOR PARTITIONS 100);

-- 距离类型: EUCLIDEAN, EUCLIDEAN_SQUARED, COSINE, DOT, MANHATTAN, HAMMING, JACCARD
```

Oracle 还提供 `VECTOR_EMBEDDING()` 函数直接调用 ONNX 模型生成嵌入向量,这意味着 SQL 内可以"一站式"完成 RAG。

### SQL Server 2025

Microsoft 在 2024 年 11 月 Ignite 大会公布 SQL Server 2025 计划,在 Azure SQL Database 中先行预览 `vector` 类型,2025 年随 SQL Server 2025 GA。SQL Server 选择了 Microsoft Research 自研的 **DiskANN** 算法路线。

```sql
-- 创建表
CREATE TABLE documents (
    id INT PRIMARY KEY,
    content NVARCHAR(MAX),
    embedding VECTOR(1536) NOT NULL
);

-- 插入 (JSON 数组字面量自动转换)
INSERT INTO documents (id, content, embedding)
VALUES (1, 'hello', '[0.1, 0.2, ..., 0.9]');

-- 距离函数
SELECT TOP 10 id, content,
    VECTOR_DISTANCE('cosine', embedding, CAST('[...]' AS VECTOR(1536))) AS dist
FROM documents
ORDER BY dist;

-- 距离类型: 'cosine', 'euclidean', 'dot'

-- DiskANN 索引 (2025 GA)
CREATE VECTOR INDEX vix_documents ON documents (embedding)
WITH (METRIC = 'cosine', TYPE = 'diskann');
```

### MySQL 9.0 / HeatWave

MySQL 9.0 (2024 年 7 月发布) 引入 `VECTOR` 数据类型,但**不内置 ANN 索引**,只能在 InnoDB 上做暴力距离计算。Oracle 把"加速能力"放在 HeatWave (云端列存加速器) 上,HeatWave 在 GenAI 场景提供 HNSW 与多 GPU 加速。

```sql
CREATE TABLE docs (
    id INT PRIMARY KEY,
    content TEXT,
    embedding VECTOR(1536)
);

INSERT INTO docs VALUES (1, 'hello', STRING_TO_VECTOR('[0.1, 0.2, ...]'));

-- 转换函数
SELECT VECTOR_TO_STRING(embedding) FROM docs;

-- 距离 (9.0 引入 DISTANCE 函数, 格式可能因小版本调整)
SELECT id, DISTANCE(embedding, STRING_TO_VECTOR(:q), 'COSINE') AS dist
FROM docs
ORDER BY dist
LIMIT 10;
```

### MariaDB 11.6 / 11.7

MariaDB 11.6 (2024 年 11 月 GA) 同时引入 `VECTOR` 类型与 **mhnsw** HNSW 向量索引,11.7 (2025 年 2 月 GA) 进一步打磨。完全开源、社区版可用,这一点与 MySQL 9.0 形成对比。

```sql
CREATE TABLE docs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    content TEXT,
    embedding VECTOR(1536) NOT NULL,
    VECTOR INDEX (embedding) M=8 DISTANCE=cosine
);

-- 插入 (二进制小端序 float32)
INSERT INTO docs (content, embedding)
VALUES ('hello', VEC_FromText('[0.1, 0.2, ..., 0.9]'));

-- 查询
SELECT id, content, VEC_DISTANCE_COSINE(embedding, VEC_FromText(:q)) AS dist
FROM docs
ORDER BY dist
LIMIT 10;

-- 函数: VEC_DISTANCE_EUCLIDEAN, VEC_DISTANCE_COSINE
-- 文本互转: VEC_FromText, VEC_ToText
```

### Snowflake

Snowflake 在 2024 年中将 `VECTOR` 类型 GA,作为 Cortex AI 平台的一部分。它没有暴露索引参数,内部自动选择算法。距离函数返回的是**相似度**(越大越好),这点与多数引擎相反。

```sql
CREATE TABLE docs (
    id INT,
    content STRING,
    embedding VECTOR(FLOAT, 1536)
);

-- 内置 embedding 函数
INSERT INTO docs
SELECT id, content, SNOWFLAKE.CORTEX.EMBED_TEXT_1024('snowflake-arctic-embed-m', content)
FROM source;

-- 距离/相似度函数
SELECT id, VECTOR_COSINE_SIMILARITY(embedding, [...]::VECTOR(FLOAT, 1536)) AS sim
FROM docs
ORDER BY sim DESC                                      -- 降序!
LIMIT 10;

-- 函数: VECTOR_L2_DISTANCE, VECTOR_COSINE_SIMILARITY, VECTOR_INNER_PRODUCT
```

### BigQuery

BigQuery 用 `ARRAY<FLOAT64>` 承载向量,通过 `CREATE VECTOR INDEX` 语句创建 IVF 或 ScaNN 索引,通过表函数 `VECTOR_SEARCH` 检索。

```sql
CREATE TABLE my.docs (
    id INT64,
    content STRING,
    embedding ARRAY<FLOAT64>
);

-- 创建 IVF 索引
CREATE VECTOR INDEX docs_idx ON my.docs(embedding)
OPTIONS(index_type = 'IVF', distance_type = 'COSINE',
        ivf_options = '{"num_lists": 1000}');

-- 创建 ScaNN 索引 (2024 推出, Google 内部算法)
CREATE VECTOR INDEX docs_scann ON my.docs(embedding)
OPTIONS(index_type = 'TREE_AH', distance_type = 'EUCLIDEAN');

-- VECTOR_SEARCH 表函数
SELECT base.id, base.content, distance
FROM VECTOR_SEARCH(
    TABLE my.docs, 'embedding',
    (SELECT [0.1, 0.2, ..., 0.9] AS embedding),
    top_k => 10,
    distance_type => 'COSINE',
    options => '{"fraction_lists_to_search": 0.05}'
);

-- 距离类型: EUCLIDEAN, COSINE, DOT_PRODUCT
```

BigQuery 还提供 `ML.GENERATE_EMBEDDING` 函数直接在 SQL 内调用 Vertex AI 嵌入模型,实现"完全 SQL 内的 RAG 流水线"。

### Databricks Vector Search

Databricks 在 2024 年 5 月 GA 了独立的 **Vector Search** 服务,与 Delta Lake 的"Delta Sync Index"集成——你只需在 Delta 表上声明同步索引,服务自动维护向量索引,并提供 REST API、Python SDK 与 SQL 查询接口。

```sql
-- 在 Delta 表上创建向量搜索索引
-- (CLI/REST/Python 中操作,这里是核心 SQL 检索语义)
SELECT *
FROM vector_search(
    index => 'main.rag.docs_index',
    query_vector => array(0.1, 0.2, ..., 0.9),
    num_results => 10
);

-- 数组距离函数 (DBR 14.2+)
SELECT id, array_distance(embedding, array(...)) AS dist
FROM docs
ORDER BY dist
LIMIT 10;
```

### DuckDB + vss 扩展

DuckDB 的 `vss` 扩展在 0.10 版本(2024 年初)引入,提供 **HNSW** 索引和 `array_distance` 系列函数,但目前仅支持 `FLOAT[N]` 固定长度数组类型。它最大的卖点是单文件嵌入式与 OLAP 性能的结合,适合本地 RAG 实验。

```sql
INSTALL vss;
LOAD vss;

CREATE TABLE docs (id INT, embedding FLOAT[1536]);

-- HNSW 索引
CREATE INDEX docs_hnsw ON docs USING HNSW (embedding)
WITH (metric = 'cosine');

-- 查询
SELECT id, array_cosine_distance(embedding, [0.1, ..., 0.9]::FLOAT[1536]) AS d
FROM docs
ORDER BY d
LIMIT 10;

-- 函数: array_distance (L2), array_cosine_distance, array_inner_product
```

### SQLite + sqlite-vec

`sqlite-vec` 是 Alex Garcia 开发的轻量扩展(2024 年发布),取代了之前的 `sqlite-vss`,**纯 C 实现、无依赖、可嵌入到任何 SQLite 应用**(包括 WASM/浏览器),支持 float32、int8、bit 三种元素类型。当前是 **暴力扫描**,无 ANN 索引,但对 < 100 万行的嵌入式场景足够。

```sql
.load vec0

CREATE VIRTUAL TABLE docs USING vec0(
    id INTEGER PRIMARY KEY,
    embedding float[1536]
);

INSERT INTO docs VALUES (1, '[0.1, 0.2, ..., 0.9]');

SELECT id, distance
FROM docs
WHERE embedding MATCH '[0.1, 0.2, ..., 0.9]'
ORDER BY distance
LIMIT 10;

-- int8 量化
CREATE VIRTUAL TABLE docs_q USING vec0(embedding int8[1536]);

-- bit 二值
CREATE VIRTUAL TABLE docs_b USING vec0(embedding bit[1536]);
```

### ClickHouse

ClickHouse 把向量类型当作普通 `Array(Float32)` 处理,用 `L2Distance`/`cosineDistance`/`dotProduct` 等数组函数计算距离。23.1 版本引入了**实验性** ANN 索引(基于 Annoy 与 USearch),目前不建议生产使用。

```sql
CREATE TABLE docs (
    id UInt64,
    content String,
    embedding Array(Float32)
) ENGINE = MergeTree() ORDER BY id;

SELECT id, L2Distance(embedding, [0.1, 0.2, ..., 0.9]) AS d
FROM docs
ORDER BY d ASC
LIMIT 10;

-- 实验性 ANN 索引 (需开启设置)
SET allow_experimental_annoy_index = 1;
ALTER TABLE docs ADD INDEX ann embedding TYPE annoy('cosineDistance') GRANULARITY 100;
```

### TiDB

TiDB 8.4 (2024) 引入 `VECTOR(N)` 类型与 HNSW 索引,在 TiDB Serverless 上率先 GA。

```sql
CREATE TABLE docs (
    id INT PRIMARY KEY,
    embedding VECTOR(1536),
    VECTOR INDEX ((VEC_COSINE_DISTANCE(embedding)))
);

SELECT id, VEC_COSINE_DISTANCE(embedding, '[0.1, ..., 0.9]') AS d
FROM docs
ORDER BY d
LIMIT 10;

-- 函数: VEC_L2_DISTANCE, VEC_COSINE_DISTANCE, VEC_NEGATIVE_INNER_PRODUCT, VEC_L1_DISTANCE
```

### OceanBase

OceanBase 4.3.3 (2024) 引入向量类型与多种 ANN 索引,是国产数据库中向量能力最完整的之一。

```sql
CREATE TABLE docs (
    id INT PRIMARY KEY,
    embedding VECTOR(1536),
    VECTOR INDEX vidx (embedding) WITH (distance=COSINE, type=HNSW, m=16, ef_construction=200)
);

SELECT id, COSINE_DISTANCE(embedding, '[0.1, ..., 0.9]') AS d
FROM docs ORDER BY d APPROXIMATE LIMIT 10;

-- 索引类型: HNSW, IVF_FLAT, IVF_PQ, IVF_SQ8
```

### SingleStore

SingleStore (前 MemSQL) 8.5 (2024) 把向量原生加进列存表,提供 `VECTOR(N, F32)`、`VECTOR(N, I8)` 等多种元素类型,以及 HNSW/IVF/PQ 多种索引。

```sql
CREATE TABLE docs (
    id INT PRIMARY KEY,
    embedding VECTOR(1536, F32) NOT NULL
);

-- HNSW 索引
ALTER TABLE docs ADD VECTOR INDEX vidx (embedding)
INDEX_OPTIONS '{"index_type":"HNSW_FLAT", "metric_type":"DOT_PRODUCT"}';

SELECT id, DOT_PRODUCT(embedding, '[0.1, ..., 0.9]':>VECTOR(1536, F32)) AS sim
FROM docs
ORDER BY sim DESC
LIMIT 10;
```

### CockroachDB

CockroachDB 24.2 (2024 年 8 月) 引入 `VECTOR(N)` 类型,继承 pgvector 操作符;自研的 **C-SPANN** 分布式向量索引在更晚的版本 (24.3 / 25.1) 才陆续落地,而非与 VECTOR 类型同时发布。

```sql
CREATE TABLE docs (
    id INT PRIMARY KEY,
    embedding VECTOR(1536)
);

CREATE VECTOR INDEX ON docs (embedding);

SELECT id, embedding <-> '[...]' AS d FROM docs ORDER BY d LIMIT 10;
```

### YugabyteDB

YugabyteDB 2.25 起原生集成 pgvector,继承 PostgreSQL 操作符与 HNSW 索引,在分布式环境下提供向量能力。语法与 pgvector 完全一致。

### CrateDB

CrateDB 5.5 (2024) 引入 `FLOAT_VECTOR(N)` 类型与基于 Lucene 的 HNSW 索引。

```sql
CREATE TABLE docs (
    id INT PRIMARY KEY,
    embedding FLOAT_VECTOR(1536)
);

SELECT id, _score
FROM docs
WHERE knn_match(embedding, [0.1, 0.2, ..., 0.9], 10)
ORDER BY _score DESC;
```

### SAP HANA

SAP HANA Cloud 2024 QRC 引入 `REAL_VECTOR(N)` 类型与 HNSW 索引。

```sql
CREATE TABLE docs (
    id INT PRIMARY KEY,
    embedding REAL_VECTOR(1536)
);

CREATE HNSW VECTOR INDEX vidx ON docs(embedding)
SIMILARITY FUNCTION COSINE_SIMILARITY
BUILD CONFIGURATION '{"M":16, "efConstruction":128}';

SELECT TOP 10 id, COSINE_SIMILARITY(embedding, TO_REAL_VECTOR('[...]')) AS sim
FROM docs ORDER BY sim DESC;
```

### Google Spanner

Spanner 在 2024 年加入了 `ARRAY<FLOAT32>` 上的 ScaNN 索引,继承 Google 自家算法。

```sql
CREATE TABLE docs (
    id INT64 NOT NULL,
    embedding ARRAY<FLOAT32>(vector_length=>1536)
) PRIMARY KEY (id);

CREATE VECTOR INDEX docs_idx ON docs(embedding)
OPTIONS (distance_type = 'COSINE', tree_depth = 3, num_leaves = 1000);

SELECT id, APPROX_COSINE_DISTANCE(embedding, [0.1, ..., 0.9]) AS d
FROM docs
ORDER BY d
LIMIT 10;
```

### StarRocks / Doris

StarRocks 3.1+ 与 Apache Doris 3.0+ 在 OLAP 列存上加入 ANN 索引(HNSW、IVFPQ),向量字段使用 `ARRAY<FLOAT>` 承载。

```sql
-- StarRocks
CREATE TABLE docs (
    id INT,
    embedding ARRAY<FLOAT> NOT NULL,
    INDEX index_vec (embedding) USING VECTOR ("index_type"="hnsw","metric_type"="cosine_similarity","dim"="1536")
) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 1;

-- Doris
SELECT id, l2_distance_approximate(embedding, [0.1, ..., 0.9]) AS d
FROM docs ORDER BY d LIMIT 10;
```

### DB2

IBM Db2 11.5.9 (2024) 引入 `VECTOR(N, FLOAT32)` 类型,与 Watsonx 集成。

```sql
CREATE TABLE docs (
    id INT PRIMARY KEY,
    embedding VECTOR(1536, FLOAT32)
);

SELECT id, VECTOR_DISTANCE(embedding, VECTOR('[0.1,...]', 1536, FLOAT32), COSINE) AS d
FROM docs ORDER BY d FETCH FIRST 10 ROWS ONLY;
```

### Databend

Databend 1.2 引入 `VECTOR(N)` 类型与距离函数。

```sql
CREATE TABLE docs (id INT, embedding VECTOR(1536));
SELECT id, cosine_distance(embedding, [0.1, ..., 0.9]) AS d
FROM docs ORDER BY d LIMIT 10;
```

### Trino / Presto / Spark / Hive / Flink

这些 SQL on lake/stream 引擎本身**没有向量类型**,通常做法是用 `array(double)`/`ARRAY<FLOAT>` 承载向量,然后用 UDF 计算距离。Trino 社区有讨论提案(Trino #20596)但截至 2025 年仍未合入官方。生产实践中,这些引擎一般通过外接 Pinecone、Milvus、Elasticsearch 实现 ANN 检索,或在数据湖中跑暴力 KNN(Spark MLlib 提供 `BucketedRandomProjectionLSH`)。

```sql
-- Spark SQL 示例 (借助 UDF/MLlib)
SELECT id, sqrt(aggregate(zip_with(embedding, array(0.1, ..., 0.9), (a, b) -> (a-b)*(a-b)),
                          0D, (acc, x) -> acc + x)) AS l2
FROM docs ORDER BY l2 LIMIT 10;
```

### Vertica / Teradata / Redshift / Athena / Synapse / Greenplum

- **Vertica**: 截至 2025 年无原生向量类型,推荐用 `ARRAY[FLOAT]` 加 UDF。
- **Teradata**: ClearScape Analytics 提供向量函数(td_vector_distances),但不在 SQL 引擎核心。
- **Redshift**: 通过 SageMaker / Bedrock 集成提供嵌入函数 (`SAGEMAKER_INVOKE_ENDPOINT`),无原生向量类型与 ANN 索引。
- **Amazon Athena**: 继承 Trino,无原生向量。
- **Azure Synapse**: 暂无原生向量,推荐配合 Azure AI Search。
- **Greenplum**: 通过 pgvector 端口完整继承 PostgreSQL 能力。

### Materialize / RisingWave / QuestDB / InfluxDB

流式与时序数据库截至 2025 年都不提供原生向量类型,RisingWave 在 1.x 路线图中讨论过但未实现。

## PostgreSQL + pgvector 深度剖析

pgvector 之所以成为生态最成熟的方案,有几个关键原因。

### 设计哲学

**最小核心,最大生态**。pgvector 只做"向量类型 + 距离函数 + 索引",不做嵌入模型、不做 RAG 框架,把上层留给 LangChain、LlamaIndex、Haystack。这种克制让它能被 AWS Aurora、Google AlloyDB、Azure Database for PostgreSQL、Supabase、Neon、Crunchy Data 等所有云托管服务无缝采纳。

### 索引内部机制

HNSW (`m=16, ef_construction=64` 默认参数) 在内存中维护一个**多层小世界图**:第 0 层包含全部向量,每往上一层节点数减半。搜索从最高层开始贪心下降,每层保留 `ef_search` 个候选。`m` 控制每个节点的连接数(更大召回更高、内存占用更大),`ef_construction` 控制构建质量。

IVFFlat 把数据分到 `lists` 个聚类中(KMeans 训练),查询时只扫描最近的 `probes` 个聚类。**IVFFlat 必须先填充数据再建索引**,否则聚类质量很差;而 HNSW 可以增量构建,这是 0.5 之后 HNSW 成为推荐索引的原因。

### 0.7 版本三大新类型的工程意义

- **halfvec(N)**:float16 元素,存储减半,索引最大维度从 vector 的 2000 提升到 4000,正好覆盖 OpenAI text-embedding-3-large 的 3072 维。
- **sparsevec(N)**:稀疏向量,存储 `{index: value, ...}` 对。适合 SPLADE 这类"学习稀疏检索"模型,以及 BM25 风格的词袋表示。
- **bit(N) + Hamming**:二值化向量(每维 1 bit),32x 压缩,Hamming 距离用 popcount 指令在 CPU 上极快。配合"先用二值粗排再用 float32 重排"的两阶段检索,可在 10x 召回开销下逼近原始精度。

### 与 PostgreSQL 生态融合

pgvector 真正的杀手锏是它能与以下能力**自由组合**:

1. **任意 WHERE 过滤**:`WHERE category = ? AND tenant_id = ? ORDER BY embedding <=> ?`
2. **JOIN 与子查询**:向量检索结果直接 JOIN 元数据表
3. **分区与分片**:Citus、Postgres 原生分区
4. **RLS 行级安全**:多租户 SaaS 场景的天然支持
5. **触发器与函数**:可在写入时自动调用 `OpenAI()` UDF 生成嵌入
6. **逻辑复制**:跨集群同步嵌入数据
7. **pg_trgm + tsvector**:三者协作做混合检索 (向量 + 模糊 + 全文)

## 关键发现

**1. 向量能力已成 2024 年数据库新基线**。约 22 个引擎在 18 个月内新增或显著强化了向量类型,这是 SQL 数据库历史上最快的"全行业同步演化"事件。

**2. PostgreSQL 生态遥遥领先**。pgvector 加上 pgvectorscale (StreamingDiskANN + SBQ 量化)、Citus 分片、TimescaleDB 分区,构成了开源向量数据库的完整工具链。所有"PostgreSQL 兼容"的产品(Greenplum、CockroachDB、YugabyteDB、Aurora、AlloyDB、Cloud SQL、Neon、Supabase、Crunchy)都"免费"获得了向量能力。

**3. HNSW 是事实标准**。约 18 个引擎选择 HNSW,其余少数(SQL Server、Spanner)选择了 DiskANN/ScaNN。IVFFlat 在新引擎中已逐渐被 HNSW 取代,但在内存受限的场景仍然有用。

**4. 距离函数命名极度碎片化**。pgvector `<=>`、Oracle `VECTOR_DISTANCE(...,COSINE)`、SQL Server `VECTOR_DISTANCE('cosine',...)`、MySQL `DISTANCE(...,'COSINE')`、MariaDB `VEC_DISTANCE_COSINE`、Snowflake `VECTOR_COSINE_SIMILARITY`、BigQuery `distance_type=>'COSINE'`、TiDB `VEC_COSINE_DISTANCE`、OceanBase `COSINE_DISTANCE`——七种命名风格。**Snowflake 返回相似度而非距离**,排序方向需特别注意。

**5. 维度限制差异显著**。pgvector vector 16000 / HNSW 索引 2000;SQL Server 2025 是 1998;Oracle 23ai 高达 65535;Snowflake 4096。OpenAI text-embedding-3-large 3072 维超出了 pgvector vector HNSW 的限制,必须用 halfvec(限制 4000) 或降维。

**6. 量化是下一战场**。pgvector 0.7 的 halfvec/bit/sparsevec、pgvectorscale 的 SBQ、Oracle 的 INT8/BINARY、SingleStore 的 I8/binary、StarRocks 的 PQ——成本压力推动量化成为 2024-2025 的主旋律。

**7. 混合搜索仍在演化**。绝大多数引擎只提供"向量距离 + WHERE 过滤"的最简形式,真正成熟的"BM25 + 向量 + RRF 融合"仅 Elasticsearch、Snowflake Cortex Search、Databricks Vector Search、Oracle 23ai 等少数提供端到端方案,其他引擎都依赖应用层手动融合。

**8. 传统大型商业数据库快速跟进**。Oracle 23ai、SQL Server 2025、DB2 11.5.9、SAP HANA 2024 QRC 都在 12 个月内补齐向量能力,反映出企业 RAG 场景的强需求。

**9. 国产数据库齐头并进**。OceanBase 4.3.3、TiDB 8.4、StarRocks 3.1、Doris 3.0、PolarDB(基于 pgvector)都在 2024 年提供了向量能力,与国际厂商基本同步。

**10. 仍有不少引擎缺位**。Vertica、Teradata、Redshift、Athena、Azure Synapse、Materialize、RisingWave、Firebolt、Yellowbrick、QuestDB、InfluxDB、H2、HSQLDB、Derby、Firebird、Informix、Exasol、MonetDB——这些引擎截至 2025 年仍然没有原生向量类型,在 RAG 场景需要外接专用向量数据库 (Pinecone、Milvus、Qdrant、Weaviate)。

**11. 流处理与时序数据库是空白**。Flink SQL、RisingWave、Materialize、QuestDB、InfluxDB 均无原生向量,这是流式 RAG 与实时推荐场景的明显空白点。

**12. 专用向量数据库的定位被压缩**。当 PostgreSQL/Oracle/SQL Server/MySQL 都内置了向量,Pinecone、Milvus、Weaviate、Qdrant 等专用产品的差异化必须靠"极致性能、超大规模、托管运营"来体现——它们的核心战场从"通用向量库"转向了"百亿级向量、亚毫秒延迟、多租户隔离"。

向量类型不会取代传统 SQL,而是成为 SQL 的新维度。未来三年的关键变化将围绕:**统一标准的尝试**(可能由 ISO SQL 工作组牵头)、**量化与混合精度的工程化**(int4、二值哈希两阶段检索)、**索引算法持续演进**(DiskANN、ScaNN、SPANN 分布式)、以及**SQL 内置嵌入与 RAG 流水线**(Snowflake Cortex、Oracle VECTOR_EMBEDDING、BigQuery ML.GENERATE_EMBEDDING、PostgreSQL pgai)。理解这些差异,是当下每一个 SQL 引擎开发者与应用架构师都无法回避的功课。
