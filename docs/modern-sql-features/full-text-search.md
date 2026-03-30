# 全文检索

全文检索是数据库中最复杂的查询能力之一。它不是简单的 `LIKE '%keyword%'`，而是涉及分词、倒排索引、相关性评分、语言分析等一整套文本检索体系。各 SQL 方言在全文检索的实现上差异巨大：有的原生内置，有的依赖外部引擎，有的根本不支持。

## 核心概念

```
全文检索 vs LIKE:
  LIKE '%word%'    → 全表扫描，逐行匹配，无法利用索引
  全文检索         → 倒排索引，分词匹配，相关性排序

全文检索处理流程:
  文档 → 分词(Tokenize) → 词干化(Stemming) → 去停用词(Stop Words)
       → 构建倒排索引(Inverted Index)
       → 查询时: 查询词 → 同样处理 → 索引查找 → 相关性评分 → 返回结果

关键术语:
  倒排索引 (Inverted Index): 词 → 文档ID列表 的映射
  分词器 (Tokenizer/Analyzer): 将文本拆分为词条(Token)的组件
  词干化 (Stemming): running → run, flies → fly
  停用词 (Stop Words): the, a, is 等高频低信息量词
  TF-IDF: 词频-逆文档频率，经典相关性评分算法
  BM25: TF-IDF 的改进版，现代搜索引擎标准算法
```

## 全文检索支持总览

```
┌─────────────────────┬──────────┬────────────────────┬──────────────┬──────────┐
│ 引擎                │ 原生支持 │ 索引类型           │ 搜索语法     │ CJK 支持 │
├─────────────────────┼──────────┼────────────────────┼──────────────┼──────────┤
│ MySQL/MariaDB       │ ✓        │ FULLTEXT INDEX     │ MATCH AGAINST│ 插件     │
│ PostgreSQL          │ ✓        │ GIN/GiST           │ tsvector @@  │ 扩展     │
│ SQL Server          │ ✓        │ Full-Text Catalog  │ CONTAINS     │ ✓ 内置   │
│ Oracle              │ ✓        │ CONTEXT INDEX      │ CONTAINS     │ ✓ 内置   │
│ SQLite              │ ✓        │ FTS5 虚拟表        │ MATCH        │ 自定义   │
│ Elasticsearch SQL   │ ✓        │ Lucene 倒排索引    │ MATCH/QUERY  │ ✓ 插件   │
├─────────────────────┼──────────┼────────────────────┼──────────────┼──────────┤
│ Snowflake           │ ✗        │ --                 │ LIKE/SEARCH  │ --       │
│ BigQuery            │ 有限     │ SEARCH INDEX       │ SEARCH       │ 有限     │
│ Databricks          │ 有限     │ --                 │ 自定义 UDF   │ 有限     │
│ ClickHouse          │ 有限     │ tokenbf_v1 等      │ hasToken 等  │ 有限     │
│ DuckDB              │ 有限     │ FTS 扩展           │ MATCH        │ 有限     │
├─────────────────────┼──────────┼────────────────────┼──────────────┼──────────┤
│ Redshift            │ ✗        │ --                 │ LIKE/SIMILAR │ --       │
│ Teradata            │ 有限     │ --                 │ CONTAINS     │ 有限     │
│ Hive                │ ✗        │ --                 │ UDF          │ --       │
│ Spark SQL           │ ✗        │ --                 │ UDF          │ --       │
│ Presto/Trino        │ ✗        │ --                 │ UDF          │ --       │
│ CockroachDB         │ 有限     │ GIN (实验)         │ tsvector @@  │ 有限     │
│ TiDB                │ ✗        │ --                 │ --           │ --       │
│ OceanBase           │ 有限     │ FULLTEXT INDEX     │ MATCH AGAINST│ 有限     │
│ PolarDB (MySQL)     │ ✓        │ FULLTEXT INDEX     │ MATCH AGAINST│ 插件     │
│ PolarDB (PG)        │ ✓        │ GIN                │ tsvector @@  │ 扩展     │
│ GaussDB             │ ✓        │ GIN                │ tsvector @@  │ 扩展     │
│ openGauss           │ ✓        │ GIN                │ tsvector @@  │ 扩展     │
│ TDSQL               │ 有限     │ FULLTEXT INDEX     │ MATCH AGAINST│ 有限     │
│ AnalyticDB          │ 有限     │ 倒排索引           │ 自定义       │ ✓        │
│ StarRocks           │ 有限     │ 倒排索引           │ 自定义       │ 有限     │
│ Doris               │ ✓        │ INVERTED INDEX     │ MATCH        │ ✓        │
│ SingleStore (MemSQL)│ ✓        │ FULLTEXT           │ MATCH AGAINST│ 有限     │
│ Greenplum           │ ✓        │ GIN                │ tsvector @@  │ 扩展     │
│ YugabyteDB          │ 有限     │ GIN (部分)         │ tsvector @@  │ 有限     │
│ Citus               │ ✓        │ GIN                │ tsvector @@  │ 扩展     │
│ TimescaleDB         │ ✓        │ GIN                │ tsvector @@  │ 扩展     │
│ QuestDB             │ ✗        │ --                 │ --           │ --       │
│ InfluxDB (SQL)      │ ✗        │ --                 │ --           │ --       │
│ Cassandra (CQL)     │ 有限     │ SASI/SAI           │ LIKE (前缀)  │ 有限     │
│ ScyllaDB            │ 有限     │ secondary index    │ LIKE (前缀)  │ 有限     │
│ CrateDB             │ ✓        │ Lucene 倒排索引    │ MATCH        │ ✓ 插件   │
│ Vertica             │ 有限     │ text index         │ 自定义       │ 有限     │
│ Exasol              │ ✗        │ --                 │ --           │ --       │
│ SAP HANA            │ ✓        │ FULLTEXT INDEX     │ CONTAINS     │ ✓ 内置   │
│ IBM Db2             │ ✓        │ text search index  │ CONTAINS     │ ✓ 内置   │
│ Informix            │ 有限     │ bts index          │ CONTAINS     │ 有限     │
│ Firebird            │ ✗        │ --                 │ --           │ --       │
│ Derby               │ ✗        │ --                 │ --           │ --       │
│ H2                  │ ✓        │ Lucene 集成        │ 自定义       │ ✓ 插件   │
│ HSQLDB              │ ✗        │ --                 │ --           │ --       │
│ Spanner             │ 有限     │ tokenized index    │ SEARCH       │ 有限     │
│ AlloyDB             │ ✓        │ GIN                │ tsvector @@  │ 扩展     │
│ Aurora (MySQL)      │ ✓        │ FULLTEXT INDEX     │ MATCH AGAINST│ 插件     │
│ Aurora (PG)         │ ✓        │ GIN                │ tsvector @@  │ 扩展     │
└─────────────────────┴──────────┴────────────────────┴──────────────┴──────────┘
```

> **非 SQL 参考：** MongoDB (SQL 接口) 通过 text index 与 $text/$search 语法提供全文检索能力，支持 CJK；Atlas Search 基于 Lucene 提供更丰富的全文检索功能。因其并非 SQL 引擎，未纳入上方矩阵。

## MySQL / MariaDB: FULLTEXT INDEX + MATCH AGAINST

### 全文索引创建

```sql
-- InnoDB FULLTEXT INDEX (MySQL 5.6+)
CREATE TABLE articles (
    id      INT PRIMARY KEY AUTO_INCREMENT,
    title   VARCHAR(200),
    body    TEXT,
    FULLTEXT INDEX ft_title_body (title, body)
) ENGINE=InnoDB;

-- 对已有表添加全文索引
ALTER TABLE articles ADD FULLTEXT INDEX ft_body (body);
CREATE FULLTEXT INDEX ft_title ON articles(title);

-- MariaDB: 与 MySQL 语法基本一致
-- MariaDB 10.3.4+: InnoDB FULLTEXT 支持事务

-- 注意: MyISAM 也支持 FULLTEXT INDEX，但 InnoDB 是推荐引擎
-- InnoDB FULLTEXT 实际使用辅助表 (auxiliary tables) 存储倒排索引
```

### 搜索模式

```sql
-- 1. 自然语言模式 (默认)
SELECT *, MATCH(title, body) AGAINST('database optimization') AS relevance
FROM articles
WHERE MATCH(title, body) AGAINST('database optimization');
-- 返回按相关性排序的结果
-- 使用专有相关性评分公式 (MySQL 8.0, 基于词频、逆文档频率、文档长度，可与 BM25 家族类比，但非官方标准 BM25 实现)

-- 2. 布尔模式
SELECT * FROM articles
WHERE MATCH(title, body) AGAINST('+database -MySQL +optimization' IN BOOLEAN MODE);
-- + 必须包含
-- - 必须排除
-- > 提高相关性
-- < 降低相关性
-- * 通配符 (右截断)
-- "" 短语搜索
-- () 分组

-- 布尔模式高级示例
WHERE MATCH(title, body) AGAINST(
    '+database +"query optimization" -NoSQL >performance <legacy' IN BOOLEAN MODE
);

-- 3. 查询扩展模式
SELECT * FROM articles
WHERE MATCH(title, body) AGAINST('database' WITH QUERY EXPANSION);
-- 第一轮: 搜索 'database'
-- 第二轮: 将第一轮结果中的高频词加入查询，再次搜索
-- 效果类似 "相关搜索"，但可能引入噪音

-- 4. 自然语言模式 + 查询扩展
WHERE MATCH(title, body) AGAINST('database' IN NATURAL LANGUAGE MODE WITH QUERY EXPANSION);
```

### 相关性评分

```sql
-- MATCH AGAINST 返回浮点数相关性分数
SELECT id, title,
       MATCH(title, body) AGAINST('database optimization') AS score
FROM articles
WHERE MATCH(title, body) AGAINST('database optimization')
ORDER BY score DESC;

-- 重要: WHERE 和 SELECT 中的 MATCH AGAINST 只会执行一次 (MySQL 优化器识别)
-- 但参数必须完全一致，否则会执行两次

-- MySQL 8.0 InnoDB 使用专有相关性评分公式:
-- 基于词频(TF)、逆文档频率(IDF)、文档长度归一化，可与 BM25 家族类比
-- 但 MySQL 官方未声明其为标准 BM25 实现，具体参数和公式为内部实现细节
```

### 配置参数

```sql
-- 最小词长 (低于此长度的词被忽略)
-- InnoDB: innodb_ft_min_token_size = 3 (默认)
-- MyISAM: ft_min_word_len = 4 (默认)
-- 对中文: 建议设为 1

-- 最大词长
-- InnoDB: innodb_ft_max_token_size = 84 (默认)

-- 停用词表
-- 查看 InnoDB 默认停用词:
SELECT * FROM INFORMATION_SCHEMA.INNODB_FT_DEFAULT_STOPWORD;

-- 自定义停用词表
CREATE TABLE my_stopwords (value VARCHAR(18) NOT NULL DEFAULT '') ENGINE=InnoDB;
INSERT INTO my_stopwords VALUES ('的'), ('了'), ('和'), ('是'), ('在');
SET GLOBAL innodb_ft_server_stopword_table = 'mydb/my_stopwords';

-- 重建索引使配置生效
ALTER TABLE articles DROP INDEX ft_body;
ALTER TABLE articles ADD FULLTEXT INDEX ft_body (body);
-- 或: OPTIMIZE TABLE articles; (仅重组已删除的词)
```

### MySQL / MariaDB CJK 支持

```sql
-- 默认分词器按空格和标点分词，对中日韩文无效

-- 方案 1: ngram 分词器 (MySQL 5.7.6+ / MariaDB)
CREATE TABLE articles_cjk (
    id    INT PRIMARY KEY AUTO_INCREMENT,
    title VARCHAR(200),
    body  TEXT,
    FULLTEXT INDEX ft_body (body) WITH PARSER ngram
) ENGINE=InnoDB;

-- ngram_token_size: 控制 n-gram 的 n 值 (默认 2)
-- '数据库' 会被分为: '数据', '据库'
-- 搜索 '数据' 可以匹配
SET GLOBAL ngram_token_size = 2;

-- 方案 2: MeCab 分词器 (MySQL 5.7.6+, 仅日语)
CREATE FULLTEXT INDEX ft_body ON articles(body) WITH PARSER mecab;

-- MariaDB 10.10+: Mroonga 引擎 (基于 Groonga 全文检索引擎)
CREATE TABLE articles_mroonga (
    id    INT PRIMARY KEY AUTO_INCREMENT,
    body  TEXT,
    FULLTEXT INDEX ft_body (body)
) ENGINE=Mroonga DEFAULT CHARSET=utf8mb4;
-- Mroonga 内置 CJK 分词支持，性能优于 ngram
```

## PostgreSQL: tsvector / tsquery + GIN

PostgreSQL 的全文检索是所有关系型数据库中设计最灵活的。

### 核心类型

```sql
-- tsvector: 文档的词条化表示 (存储用)
SELECT 'the quick brown fox jumps over the lazy dog'::tsvector;
-- 结果: 'brown' 'dog' 'fox' 'jumps' 'lazy' 'over' 'quick' 'the'

-- to_tsvector(): 带语言分析的转换 (推荐)
SELECT to_tsvector('english', 'The quick brown foxes jumped over the lazy dogs');
-- 结果: 'brown':3 'dog':9 'fox':4 'jump':5 'lazi':8 'quick':2
-- 注意: 停用词 the/over 被去除, foxes→fox, jumped→jump, lazy→lazi (词干化)

-- tsquery: 查询表达式
SELECT to_tsquery('english', 'quick & fox');
-- 结果: 'quick' & 'fox'

-- 匹配操作符 @@
SELECT to_tsvector('english', 'The quick brown fox') @@
       to_tsquery('english', 'quick & fox');
-- 结果: true
```

### 索引创建

```sql
-- GIN 索引 (推荐: 查询快，更新稍慢)
CREATE INDEX idx_fts ON articles USING GIN (to_tsvector('english', body));

-- GiST 索引 (构建快，查询稍慢，支持排序)
CREATE INDEX idx_fts ON articles USING GiST (to_tsvector('english', body));

-- 使用生成列 + 索引 (推荐方式)
ALTER TABLE articles ADD COLUMN tsv tsvector
    GENERATED ALWAYS AS (to_tsvector('english', coalesce(title,'') || ' ' || coalesce(body,''))) STORED;
CREATE INDEX idx_tsv ON articles USING GIN (tsv);

-- 或使用触发器 (PostgreSQL 12 之前)
CREATE FUNCTION articles_tsv_trigger() RETURNS trigger AS $$
BEGIN
    NEW.tsv := setweight(to_tsvector('english', coalesce(NEW.title,'')), 'A') ||
               setweight(to_tsvector('english', coalesce(NEW.body,'')), 'B');
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tsv BEFORE INSERT OR UPDATE ON articles
    FOR EACH ROW EXECUTE FUNCTION articles_tsv_trigger();
```

### 查询语法

```sql
-- 基本查询
SELECT * FROM articles
WHERE to_tsvector('english', body) @@ to_tsquery('english', 'database & optimization');

-- 使用预计算列查询 (更高效)
SELECT * FROM articles WHERE tsv @@ to_tsquery('english', 'database & optimization');

-- 布尔操作符
-- &  AND
-- |  OR
-- !  NOT
-- <-> 紧邻 (FOLLOWED BY, 短语搜索)
-- <N> N 个词距离

-- 短语搜索
SELECT * FROM articles
WHERE tsv @@ to_tsquery('english', 'query <-> optimization');
-- 'query' 紧跟 'optimization'

-- 近邻搜索
SELECT * FROM articles
WHERE tsv @@ to_tsquery('english', 'query <2> optimization');
-- 'query' 和 'optimization' 之间最多 1 个词

-- phraseto_tsquery: 自动构建短语查询
SELECT * FROM articles
WHERE tsv @@ phraseto_tsquery('english', 'query optimization techniques');
-- 等价于 'query' <-> 'optim' <-> 'techniqu'

-- websearch_to_tsquery (PostgreSQL 11+): 类似搜索引擎的语法
SELECT * FROM articles
WHERE tsv @@ websearch_to_tsquery('english', '"query optimization" -mysql OR postgres');
-- 双引号 = 短语, - = NOT, OR = OR, 空格 = AND

-- plainto_tsquery: 所有词用 AND 连接
SELECT * FROM articles
WHERE tsv @@ plainto_tsquery('english', 'query optimization');
-- 等价于 'query' & 'optim'
```

### 相关性排序与权重

```sql
-- ts_rank: 基于词频的排序
SELECT title, ts_rank(tsv, query) AS rank
FROM articles, to_tsquery('english', 'database & optimization') query
WHERE tsv @@ query
ORDER BY rank DESC;

-- ts_rank_cd: 基于覆盖密度 (Cover Density) 的排序
-- 考虑匹配词之间的距离，通常效果更好
SELECT title, ts_rank_cd(tsv, query) AS rank
FROM articles, to_tsquery('english', 'database') query
WHERE tsv @@ query
ORDER BY rank DESC;

-- 权重 (A > B > C > D)
-- setweight() 为不同字段设置不同权重
ALTER TABLE articles ADD COLUMN tsv tsvector;
UPDATE articles SET tsv =
    setweight(to_tsvector('english', coalesce(title,'')), 'A') ||
    setweight(to_tsvector('english', coalesce(body,'')), 'B');

-- 自定义权重比例
SELECT title, ts_rank('{0.1, 0.2, 0.4, 1.0}', tsv, query) AS rank
FROM articles, to_tsquery('english', 'database') query
WHERE tsv @@ query
ORDER BY rank DESC;
-- {D权重, C权重, B权重, A权重}

-- 归一化选项
SELECT title, ts_rank(tsv, query, 32) AS rank  -- 32: 除以文档长度
FROM articles, to_tsquery('english', 'database') query
WHERE tsv @@ query
ORDER BY rank DESC;
-- 常用选项: 0 (默认), 1 (除以 1+log(文档长度)), 2 (除以文档长度), 32 (除以 rank+1)
```

### 高亮与摘要

```sql
-- ts_headline: 生成带高亮标记的摘要
SELECT ts_headline('english', body, to_tsquery('english', 'database & optimization'),
    'StartSel=<b>, StopSel=</b>, MaxWords=35, MinWords=15, MaxFragments=3'
) AS snippet
FROM articles
WHERE tsv @@ to_tsquery('english', 'database & optimization');

-- 输出示例: ...in <b>database</b> systems, <b>optimization</b> of queries...

-- 注意: ts_headline 不使用索引，对大文本可能较慢
-- 建议: 先用 WHERE tsv @@ query 过滤，再对结果执行 ts_headline
```

### PostgreSQL CJK 支持

```sql
-- PostgreSQL 内置不支持 CJK 分词
-- 需要安装扩展

-- 方案 1: pg_jieba (结巴分词, 中文)
CREATE EXTENSION pg_jieba;
SELECT to_tsvector('jiebacfg', '全文检索是数据库中最复杂的查询能力');
-- 结果: '全文':1 '复杂':6 '数据库':3 '检索':2 '查询':8 '最':5 '能力':9

-- 方案 2: pg_bigm (bi-gram, 中日韩通用)
CREATE EXTENSION pg_bigm;
CREATE INDEX idx_bigm ON articles USING GIN (body gin_bigm_ops);
SELECT * FROM articles WHERE body LIKE '%全文检索%';
-- pg_bigm 使 LIKE 也能利用索引

-- 方案 3: zhparser (基于 SCWS 中文分词)
CREATE EXTENSION zhparser;
CREATE TEXT SEARCH CONFIGURATION chinese (PARSER = zhparser);
ALTER TEXT SEARCH CONFIGURATION chinese
    ADD MAPPING FOR n,v,a,i,e,l WITH simple;
SELECT to_tsvector('chinese', '全文检索是数据库查询');

-- 方案 4: pgroonga (基于 Groonga, 支持 CJK)
CREATE EXTENSION pgroonga;
CREATE INDEX idx_pgroonga ON articles USING pgroonga (body);
SELECT * FROM articles WHERE body &@~ '全文検索';

-- 方案 5: pg_cjk_parser (第三方扩展，兼容 PG 12+)
-- 基于 Unicode 字符分类的简单 CJK 分词
CREATE EXTENSION pg_cjk_parser;
```

## SQL Server: Full-Text Search + CONTAINS / FREETEXT

SQL Server 的全文检索是独立于普通索引的子系统，使用专门的 Full-Text Engine。

### 架构与安装

```sql
-- Full-Text Search 是可选组件，需要在安装时选择
-- 或后期添加: 控制面板 → SQL Server 安装中心 → 添加功能

-- 核心组件:
-- Full-Text Engine: 独立的 fdhost.exe 进程
-- iFilter: 解析文档格式 (PDF, Word, HTML 等)
-- Word Breaker: 分词器 (按语言)
-- Stemmer: 词干分析器
-- Thesaurus: 同义词词典
-- Stoplist: 停用词表

-- 查看已安装的分词器
SELECT * FROM sys.fulltext_languages;
-- 包含: 2052 (简体中文), 1041 (日语), 1042 (韩语) 等
```

### 全文目录与索引

```sql
-- 创建全文目录 (逻辑容器, SQL Server 2008+ 目录不再有物理含义)
CREATE FULLTEXT CATALOG ft_catalog AS DEFAULT;

-- 创建全文索引 (表必须有唯一索引)
CREATE FULLTEXT INDEX ON articles (
    title LANGUAGE 2052,         -- 简体中文
    body  LANGUAGE 1033          -- 英语
)
KEY INDEX pk_articles            -- 指定唯一索引
ON ft_catalog                    -- 指定目录
WITH (
    CHANGE_TRACKING AUTO,        -- 自动跟踪变更
    STOPLIST = SYSTEM            -- 使用系统停用词表
);

-- 变更跟踪选项:
-- AUTO: 自动更新全文索引
-- MANUAL: 需要手动 ALTER FULLTEXT INDEX ... START UPDATE POPULATION
-- OFF: 不跟踪

-- 手动填充索引
ALTER FULLTEXT INDEX ON articles START FULL POPULATION;
ALTER FULLTEXT INDEX ON articles START INCREMENTAL POPULATION;
```

### 搜索语法

```sql
-- 1. CONTAINS: 精确布尔搜索
SELECT * FROM articles
WHERE CONTAINS(body, 'database');

-- AND, OR, NOT
WHERE CONTAINS(body, 'database AND optimization');
WHERE CONTAINS(body, 'database OR index');
WHERE CONTAINS(body, 'database AND NOT MySQL');

-- 短语搜索
WHERE CONTAINS(body, '"query optimization"');

-- 前缀搜索
WHERE CONTAINS(body, '"data*"');

-- 近邻搜索 (NEAR)
WHERE CONTAINS(body, 'NEAR((database, optimization), 5)');
-- database 和 optimization 之间最多 5 个词

-- 近邻搜索 (有序)
WHERE CONTAINS(body, 'NEAR((database, optimization), 5, TRUE)');
-- database 必须在 optimization 之前

-- 词形变化 (FORMSOF)
WHERE CONTAINS(body, 'FORMSOF(INFLECTIONAL, run)');
-- 匹配 run, runs, running, ran

-- 同义词 (FORMSOF THESAURUS)
WHERE CONTAINS(body, 'FORMSOF(THESAURUS, database)');
-- 匹配 database 及其同义词 (需配置同义词文件)

-- 加权搜索 (ISABOUT)
WHERE CONTAINS(body, 'ISABOUT(database WEIGHT(0.9), optimization WEIGHT(0.5))');

-- 多列搜索
WHERE CONTAINS((title, body), 'database');

-- 2. FREETEXT: 自然语言搜索 (自动分词、词干化、去停用词)
SELECT * FROM articles
WHERE FREETEXT(body, 'how to optimize database queries');
-- 自动展开为: optimize, optimizing, optimized, query, queries...

-- 3. CONTAINSTABLE: 返回相关性排名
SELECT a.title, ft.RANK
FROM articles a
INNER JOIN CONTAINSTABLE(articles, body, 'database AND optimization') ft
    ON a.id = ft.[KEY]
ORDER BY ft.RANK DESC;

-- 4. FREETEXTTABLE: FREETEXT 的表值函数版本
SELECT a.title, ft.RANK
FROM articles a
INNER JOIN FREETEXTTABLE(articles, body, 'optimize database queries') ft
    ON a.id = ft.[KEY]
ORDER BY ft.RANK DESC;
```

### 停用词与同义词

```sql
-- 创建自定义停用词表
CREATE FULLTEXT STOPLIST my_stoplist FROM SYSTEM STOPLIST;
ALTER FULLTEXT STOPLIST my_stoplist ADD '的' LANGUAGE 2052;
ALTER FULLTEXT STOPLIST my_stoplist ADD '了' LANGUAGE 2052;
ALTER FULLTEXT STOPLIST my_stoplist ADD '和' LANGUAGE 2052;

-- 应用到全文索引
ALTER FULLTEXT INDEX ON articles SET STOPLIST my_stoplist;

-- 同义词文件: XML 格式，位于 SQL Server 安装目录
-- $MSSQL\FTDATA\tsenu.xml (英语)
-- $MSSQL\FTDATA\tschs.xml (简体中文)
-- <thesaurus>
--   <expansion><sub>DB</sub><sub>database</sub></expansion>
--   <replacement><pat>SQL Server</pat><sub>Microsoft SQL Server</sub></replacement>
-- </thesaurus>
```

### SQL Server 语义搜索

```sql
-- SQL Server 2012+ 语义搜索: 基于内容相似性而非关键词
-- 需要安装 Semantic Language Statistics Database

-- 查找与某文档相似的其他文档
SELECT a2.title, sdt.score
FROM SEMANTICSIMILARITYTABLE(articles, body, @article_id) sdt
JOIN articles a2 ON a2.id = sdt.matched_document_key
ORDER BY sdt.score DESC;

-- 查找文档的关键短语
SELECT keyphrase, score
FROM SEMANTICKEYPHRASETABLE(articles, body, @article_id)
ORDER BY score DESC;

-- 查找两个文档共有的关键短语
SELECT keyphrase, score
FROM SEMANTICSIMILARITYDETAILSTABLE(articles, body, @id1, body, @id2)
ORDER BY score DESC;
```

## Oracle: Oracle Text (CONTAINS / CATSEARCH / MATCHES)

Oracle Text 是 Oracle 数据库内置的全文检索引擎，功能极为丰富。

### 索引创建

```sql
-- 基本 CONTEXT 索引 (全文检索主力)
CREATE INDEX idx_body_ft ON articles(body) INDEXTYPE IS CTXSYS.CONTEXT;

-- CTXCAT 索引 (用于结构化 + 全文混合查询)
CREATE INDEX idx_cat ON products(description)
    INDEXTYPE IS CTXSYS.CTXCAT
    PARAMETERS ('INDEX SET product_iset');

-- 指定分词器 (Lexer)
-- 中文: CHINESE_LEXER
-- 日文: JAPANESE_LEXER
-- 韩文: KOREAN_MORPH_LEXER
-- 多语言: MULTI_LEXER / WORLD_LEXER
BEGIN
    CTX_DDL.CREATE_PREFERENCE('my_lexer', 'CHINESE_LEXER');
END;
/
CREATE INDEX idx_body_zh ON articles(body)
    INDEXTYPE IS CTXSYS.CONTEXT
    PARAMETERS ('LEXER my_lexer');

-- WORLD_LEXER: 自动检测语言 (Oracle 12c+)
BEGIN
    CTX_DDL.CREATE_PREFERENCE('world_lex', 'WORLD_LEXER');
END;
/
CREATE INDEX idx_body_world ON articles(body)
    INDEXTYPE IS CTXSYS.CONTEXT
    PARAMETERS ('LEXER world_lex');

-- 索引同步策略
-- ON COMMIT: 提交时同步 (实时)
-- EVERY "SYSDATE+1/24": 每小时同步
-- MANUAL: 手动同步
CREATE INDEX idx_body_rt ON articles(body)
    INDEXTYPE IS CTXSYS.CONTEXT
    PARAMETERS ('SYNC (ON COMMIT)');

-- 手动同步
EXEC CTX_DDL.SYNC_INDEX('idx_body_ft');
```

### 搜索语法

```sql
-- 1. CONTAINS: CONTEXT 索引的查询操作符
SELECT score(1), title FROM articles
WHERE CONTAINS(body, 'database', 1) > 0
ORDER BY score(1) DESC;

-- AND (&), OR (|), NOT (~)
WHERE CONTAINS(body, 'database & optimization') > 0;
WHERE CONTAINS(body, 'database | index') > 0;
WHERE CONTAINS(body, 'database ~ MySQL') > 0;

-- ACCUM (,): 累加评分 (出现越多分越高)
WHERE CONTAINS(body, 'database, optimization, performance') > 0;

-- 短语搜索
WHERE CONTAINS(body, '"query optimization"') > 0;

-- 近邻搜索 (NEAR)
WHERE CONTAINS(body, 'NEAR((database, optimization), 5)') > 0;
WHERE CONTAINS(body, 'NEAR((database, optimization), 5, TRUE)') > 0;  -- 有序

-- 词干化 ($)
WHERE CONTAINS(body, '$run') > 0;  -- 匹配 run, runs, running, ran

-- 模糊搜索 (FUZZY)
WHERE CONTAINS(body, 'FUZZY(database, 70, 5)') > 0;
-- 相似度 70%，最多返回 5 个扩展词

-- 通配符
WHERE CONTAINS(body, 'data%') > 0;   -- 右通配
WHERE CONTAINS(body, '%base') > 0;   -- 左通配 (需要 SUBSTRING_INDEX)
WHERE CONTAINS(body, 'da_a') > 0;    -- 单字符通配

-- 2. CATSEARCH: CTXCAT 索引的查询 (结构化 + 全文)
SELECT * FROM products
WHERE CATSEARCH(description, 'laptop', 'price > 1000 ORDER BY price') > 0;

-- 3. MATCHES: 分类查询 (文档匹配预定义规则)
-- 用于自动分类场景
```

### 高亮与摘要

```sql
-- CTX_DOC.SNIPPET: 生成摘要片段
SELECT CTX_DOC.SNIPPET('idx_body_ft', rowid, 'database optimization') AS snippet
FROM articles
WHERE CONTAINS(body, 'database & optimization') > 0;

-- CTX_DOC.MARKUP: 在文档中标记匹配词
DECLARE
    v_clob CLOB;
BEGIN
    CTX_DOC.MARKUP('idx_body_ft', :doc_rowid, 'database',
                   v_clob, tagset => 'HTML_DEFAULT');
END;
/

-- CTX_DOC.HIGHLIGHT: 返回匹配词的偏移和长度
DECLARE
    v_offsets CTX_DOC.HIGHLIGHT_TAB;
BEGIN
    CTX_DOC.HIGHLIGHT('idx_body_ft', :doc_rowid, 'database', v_offsets);
    FOR i IN v_offsets.FIRST .. v_offsets.LAST LOOP
        DBMS_OUTPUT.PUT_LINE('Offset: ' || v_offsets(i).offset ||
                           ' Length: ' || v_offsets(i).length);
    END LOOP;
END;
/
```

## SQLite: FTS5 虚拟表

SQLite 的全文检索通过虚拟表实现，轻量但功能完备。

### 创建与基本使用

```sql
-- 创建 FTS5 虚拟表
CREATE VIRTUAL TABLE articles_fts USING fts5(title, body);

-- 插入数据
INSERT INTO articles_fts VALUES ('Database Tuning', 'How to optimize database queries');

-- 基本搜索
SELECT * FROM articles_fts WHERE articles_fts MATCH 'database';

-- 与普通表关联 (content table)
CREATE VIRTUAL TABLE articles_fts USING fts5(
    title, body,
    content='articles',        -- 关联到 articles 表
    content_rowid='id'         -- 使用 articles.id 作为 rowid
);
-- 需要手动同步: INSERT INTO articles_fts(articles_fts) VALUES('rebuild');
```

### 查询语法

```sql
-- AND (默认, 空格分隔)
SELECT * FROM articles_fts WHERE articles_fts MATCH 'database optimization';

-- OR
SELECT * FROM articles_fts WHERE articles_fts MATCH 'database OR index';

-- NOT
SELECT * FROM articles_fts WHERE articles_fts MATCH 'database NOT mysql';

-- 短语搜索
SELECT * FROM articles_fts WHERE articles_fts MATCH '"query optimization"';

-- 列过滤
SELECT * FROM articles_fts WHERE articles_fts MATCH 'title:database';

-- 前缀搜索
SELECT * FROM articles_fts WHERE articles_fts MATCH 'data*';

-- NEAR 近邻搜索
SELECT * FROM articles_fts WHERE articles_fts MATCH 'NEAR(database optimization, 5)';

-- 列权重 + BM25 排序
SELECT *, bm25(articles_fts, 10.0, 1.0) AS rank  -- title 权重 10, body 权重 1
FROM articles_fts
WHERE articles_fts MATCH 'database'
ORDER BY rank;  -- bm25 返回负数，越小越相关

-- highlight(): 高亮
SELECT highlight(articles_fts, 1, '<b>', '</b>') FROM articles_fts
WHERE articles_fts MATCH 'database';

-- snippet(): 摘要
SELECT snippet(articles_fts, 1, '<b>', '</b>', '...', 20) FROM articles_fts
WHERE articles_fts MATCH 'database';
```

### 自定义分词器

```sql
-- FTS5 内置分词器:
-- unicode61: 默认, Unicode 分词 (按标点和空格)
-- ascii: ASCII 分词
-- porter: 英语词干化 (基于 Porter Stemmer)
-- trigram: 三元组分词 (子串匹配, 适合 CJK)

-- 使用 trigram 分词器 (CJK 友好)
CREATE VIRTUAL TABLE articles_cjk USING fts5(
    title, body,
    tokenize='trigram'
);
-- '数据库' → '数据', '据库'
-- 支持子串搜索: MATCH '数据' 可以匹配

-- 组合分词器
CREATE VIRTUAL TABLE articles_fts USING fts5(
    title, body,
    tokenize='porter unicode61'  -- 先 unicode61 分词，再 porter 词干化
);

-- 自定义分词器 (C 语言编写)
-- 通过 fts5_api 注册自定义分词器
-- 如 libsimple: SQLite 中文分词扩展
```

## Snowflake: 无原生全文检索

Snowflake 没有原生全文检索功能。它提供的 SEARCH OPTIMIZATION SERVICE 和 SEARCH() 函数
不是真正的全文检索，而是优化过的等值/子串查找。

```sql
-- SEARCH OPTIMIZATION SERVICE (Enterprise Edition+)
-- 这是查询加速服务，不是全文检索索引
ALTER TABLE articles ADD SEARCH OPTIMIZATION ON EQUALITY(body);
ALTER TABLE articles ADD SEARCH OPTIMIZATION ON SUBSTRING(body);

-- SEARCH() 函数 (Snowflake 2024+)
-- 本质是关键词匹配，不是全文检索
SELECT * FROM articles
WHERE SEARCH(body, 'database optimization');
-- 按空格拆分后做子串匹配

-- 多列搜索
SELECT * FROM articles
WHERE SEARCH((title, body), 'database optimization');

-- 与传统方式对比:
-- 传统: WHERE body LIKE '%database%' → 全扫描
-- SEARCH: WHERE SEARCH(body, 'database') → 利用搜索优化

-- Snowflake 不具备的全文检索能力:
-- 无倒排索引
-- 不支持布尔操作符 (AND, OR, NOT)
-- 不支持短语搜索
-- 不支持相关性排序
-- 不支持词干化 / 停用词
-- 不支持分词器配置
-- 如需全文检索，建议使用外部搜索引擎 (如 Elasticsearch)
```

## BigQuery: SEARCH 函数

```sql
-- BigQuery SEARCH INDEX (2023+)
CREATE SEARCH INDEX idx_articles ON articles(body)
OPTIONS (analyzer = 'LOG_ANALYZER');
-- 分析器选项: LOG_ANALYZER (日志), NO_OP_ANALYZER (原样), PATTERN_ANALYZER (正则)

-- SEARCH() 函数
SELECT * FROM articles
WHERE SEARCH(body, 'database optimization');

-- 搜索所有 STRING/JSON 列
SELECT * FROM articles
WHERE SEARCH(articles, 'database');

-- SEARCH 函数默认行为:
-- 所有搜索词用 AND 连接
-- 大小写不敏感
-- 自动利用 SEARCH INDEX (如果存在)

-- 使用 backtick 进行精确匹配
SELECT * FROM articles
WHERE SEARCH(body, '`database optimization`');
-- 精确匹配整个短语
```

## ClickHouse: 倒排索引与 hasToken

```sql
-- ClickHouse 全文检索方案

-- 方案 1: tokenbf_v1 (Token Bloom Filter, 跳过索引)
CREATE TABLE articles (
    id     UInt64,
    body   String,
    INDEX idx_body body TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 4
) ENGINE = MergeTree() ORDER BY id;
-- 基于布隆过滤器的跳过索引, 可能有假阳性

-- 方案 2: ngrambf_v1 (N-gram Bloom Filter)
CREATE TABLE articles_ngram (
    id     UInt64,
    body   String,
    INDEX idx_body body TYPE ngrambf_v1(3, 32768, 3, 0) GRANULARITY 4
) ENGINE = MergeTree() ORDER BY id;

-- 方案 3: 倒排索引 (ClickHouse 23.1+, 实验性)
CREATE TABLE articles_inv (
    id     UInt64,
    body   String,
    INDEX idx_body body TYPE inverted(0) GRANULARITY 1
) ENGINE = MergeTree() ORDER BY id;
-- 参数 0 表示使用默认分词器 (按标点和空格)
-- 参数 N>0 表示使用 N-gram 分词

-- 搜索函数
SELECT * FROM articles WHERE hasToken(body, 'database');
-- hasToken: 精确匹配一个词 (利用 tokenbf_v1 索引)

SELECT * FROM articles WHERE multiSearchAny(body, ['database', 'optimization']);
-- multiSearchAny: 任意一个词匹配

SELECT * FROM articles WHERE hasTokenCaseInsensitive(body, 'Database');
-- 大小写不敏感

-- ClickHouse 不提供:
-- 相关性排序
-- 词干化 / 停用词
-- 短语搜索 / 近邻搜索
-- 为此，通常与 Elasticsearch 配合使用
```

## DuckDB: FTS 扩展

```sql
-- 安装 FTS 扩展
INSTALL fts;
LOAD fts;

-- 创建全文索引 (实际是创建辅助表)
PRAGMA create_fts_index('articles', 'id', 'title', 'body');

-- 搜索
SELECT *, fts_main_articles.match_bm25(id, 'database optimization') AS score
FROM articles
WHERE score IS NOT NULL
ORDER BY score DESC;

-- 自定义参数
PRAGMA create_fts_index(
    'articles', 'id', 'title', 'body',
    stemmer='porter',
    stopwords='english',
    ignore='(\\.|[^a-z])+',
    strip_accents=1,
    lower=1
);

-- 删除索引
PRAGMA drop_fts_index('articles');

-- 局限: 索引不会自动更新，需要删除重建
```

## Doris: 倒排索引

```sql
-- Apache Doris 2.0+ 原生倒排索引
CREATE TABLE articles (
    id      BIGINT,
    title   VARCHAR(200),
    body    TEXT,
    INDEX idx_title (title) USING INVERTED PROPERTIES("parser" = "chinese") COMMENT '标题索引',
    INDEX idx_body (body) USING INVERTED PROPERTIES("parser" = "chinese", "support_phrase" = "true")
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1;

-- 分词器选项:
-- "parser" = "none"      不分词 (精确匹配)
-- "parser" = "english"   英文分词
-- "parser" = "chinese"   中文分词 (基于 jieba)
-- "parser" = "unicode"   Unicode 分词

-- 搜索语法
SELECT * FROM articles WHERE body MATCH 'database';
SELECT * FROM articles WHERE body MATCH_ALL 'database optimization';     -- AND
SELECT * FROM articles WHERE body MATCH_ANY 'database optimization';     -- OR
SELECT * FROM articles WHERE body MATCH_PHRASE 'query optimization';     -- 短语
SELECT * FROM articles WHERE body MATCH_PHRASE_PREFIX 'query optim';     -- 短语前缀

-- Doris 的倒排索引基于 CLucene 实现
```

## SAP HANA: 全文索引

```sql
-- SAP HANA 内置全文检索
CREATE FULLTEXT INDEX ft_body ON articles(body)
    LANGUAGE DETECTION ('en', 'zh', 'ja', 'ko')
    PHRASE INDEX RATIO 0.5
    FUZZY SEARCH INDEX ON
    SEARCH ONLY OFF;  -- OFF: 可在普通查询中使用

-- 搜索
SELECT * FROM articles
WHERE CONTAINS(body, 'database optimization', FUZZY(0.8));

-- 布尔搜索
SELECT * FROM articles
WHERE CONTAINS(body, 'database AND optimization NOT mysql');

-- 短语搜索
SELECT * FROM articles
WHERE CONTAINS(body, '"query optimization"');

-- 模糊搜索
SELECT * FROM articles
WHERE CONTAINS(body, 'databes', FUZZY(0.8));
-- 容错匹配 database (编辑距离)

-- 语言检测 + CJK 支持
-- HANA 内置对中日韩的分词支持，无需额外插件
SELECT * FROM articles
WHERE CONTAINS(body, '数据库优化', LANGUAGE 'zh');

-- 加权搜索
SELECT SCORE() AS relevance, title FROM articles
WHERE CONTAINS(body, 'database', FUZZY(0.8))
ORDER BY relevance DESC;
```

## IBM Db2: Text Search

```sql
-- Db2 Text Search 基于 Apache Lucene

-- 启用文本搜索 (系统级)
-- db2ts START FOR TEXT

-- 创建文本搜索索引
CREATE INDEX idx_body FOR TEXT ON articles(body)
    CONNECT TO mydb;

-- 更新索引
UPDATE INDEX idx_body FOR TEXT;

-- 搜索
SELECT * FROM articles
WHERE CONTAINS(body, 'database optimization') = 1;

-- 布尔查询
WHERE CONTAINS(body, '"database" AND "optimization"') = 1;

-- 模糊查询
WHERE CONTAINS(body, 'database~') = 1;

-- 相关性排序
SELECT SCORE(body, 'database optimization') AS rank, title
FROM articles
WHERE CONTAINS(body, 'database optimization') = 1
ORDER BY rank DESC;

-- Db2 for z/OS 使用不同的文本搜索接口
-- Db2 for LUW 使用基于 Lucene 的 OmniFind
```

## CrateDB: 基于 Lucene 的全文检索

```sql
-- CrateDB 底层使用 Lucene，全文检索是核心能力

-- 创建表时指定分析器
CREATE TABLE articles (
    title TEXT INDEX USING fulltext WITH (analyzer = 'standard'),
    body  TEXT INDEX USING fulltext WITH (analyzer = 'chinese')
);

-- 内置分析器: standard, simple, whitespace, keyword, pattern
-- 语言分析器: english, german, french, chinese, japanese (基于 Lucene analyzers)

-- 自定义分析器
CREATE ANALYZER my_analyzer (
    TOKENIZER standard,
    TOKEN_FILTERS (lowercase, stop, snowball WITH (language = 'english')),
    CHAR_FILTERS (html_strip)
);

-- MATCH 搜索
SELECT * FROM articles WHERE MATCH(body, 'database optimization');

-- 指定匹配类型
SELECT * FROM articles
WHERE MATCH(body, 'database optimization') USING best_fields;
-- 类型: best_fields, most_fields, cross_fields, phrase, phrase_prefix

-- 多列搜索 (带权重)
SELECT * FROM articles
WHERE MATCH((title 2.0, body 1.0), 'database optimization') USING best_fields;

-- 相关性评分
SELECT _score, title FROM articles
WHERE MATCH(body, 'database optimization')
ORDER BY _score DESC;

-- 短语搜索
SELECT * FROM articles
WHERE MATCH(body, 'query optimization') USING phrase;

-- 短语前缀
SELECT * FROM articles
WHERE MATCH(body, 'query optim') USING phrase_prefix;
```

## Google Spanner: 搜索索引

```sql
-- Spanner 全文搜索 (2024+)
CREATE SEARCH INDEX articles_search
ON articles(body_tokens)
OPTIONS (sort_order_sharding = true);

-- 需要先创建 TOKENLIST 列
ALTER TABLE articles ADD COLUMN body_tokens TOKENLIST
    AS (TOKENIZE_FULLTEXT(body)) HIDDEN;

-- 搜索
SELECT * FROM articles
WHERE SEARCH(body_tokens, 'database optimization');

-- SEARCH_SUBSTRING: 子串搜索
SELECT * FROM articles
WHERE SEARCH_SUBSTRING(body_tokens, 'datab');

-- SCORE: 相关性评分
SELECT SCORE(body_tokens, 'database optimization') AS relevance, title
FROM articles
WHERE SEARCH(body_tokens, 'database optimization')
ORDER BY relevance DESC;
```

## SingleStore (MemSQL): FULLTEXT

```sql
-- SingleStore 全文检索
CREATE TABLE articles (
    id     BIGINT AUTO_INCREMENT,
    title  VARCHAR(200),
    body   LONGTEXT,
    FULLTEXT INDEX ft_body (body),
    SORT KEY (id),
    SHARD KEY (id)
);

-- 搜索 (兼容 MySQL 语法)
SELECT *, MATCH(body) AGAINST('database optimization') AS score
FROM articles
WHERE MATCH(body) AGAINST('database optimization');

-- 布尔模式
WHERE MATCH(body) AGAINST('+database -mysql' IN BOOLEAN MODE);

-- SingleStore 特有: MATCH 支持列存表
-- 在列存引擎上也能使用全文检索 (与行存行为一致)
```

## 搜索语法对比矩阵

```
┌────────────────────┬──────────────┬──────────────┬──────────────┬──────────────┬──────────┐
│ 能力               │ MySQL        │ PostgreSQL   │ SQL Server   │ Oracle       │ SQLite   │
├────────────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────┤
│ 基本搜索           │ MATCH AGAINST│ @@ tsquery   │ CONTAINS     │ CONTAINS     │ MATCH    │
│ AND                │ + 或空格     │ &            │ AND          │ & 或 AND     │ 空格     │
│ OR                 │ 无 (隐含)    │ |            │ OR           │ | 或 OR      │ OR       │
│ NOT                │ -            │ !            │ AND NOT      │ ~ 或 NOT     │ NOT      │
│ 短语搜索           │ "..."        │ <->          │ "..."        │ "..."        │ "..."    │
│ 近邻搜索           │ ✗            │ <N>          │ NEAR(,N)     │ NEAR(,N)     │ NEAR(,N) │
│ 前缀通配           │ word*        │ word:*       │ "word*"      │ word%        │ word*    │
│ 词干化             │ ✗ 内置       │ 语言配置     │ FORMSOF      │ $            │ porter   │
│ 模糊搜索           │ ✗            │ pg_trgm      │ ✗            │ FUZZY()      │ ✗        │
│ 权重/字段加权      │ 有限         │ setweight    │ ISABOUT      │ WEIGHT       │ bm25()   │
│ 相关性排序         │ MATCH 返回值 │ ts_rank      │ RANK (表函数)│ SCORE()      │ bm25()   │
│ 高亮               │ ✗            │ ts_headline  │ ✗ 原生       │ CTX_DOC      │highlight │
│ 摘要               │ ✗            │ ts_headline  │ ✗ 原生       │ SNIPPET      │ snippet  │
└────────────────────┴──────────────┴──────────────┴──────────────┴──────────────┴──────────┘
```

```
┌────────────────────┬──────────────┬──────────────┬──────────────┬──────────────┬──────────┐
│ 能力               │ Snowflake    │ BigQuery     │ ClickHouse   │ Doris        │ CrateDB  │
├────────────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────┤
│ 基本搜索           │ ✗ (无FTS)    │ SEARCH()     │ hasToken()   │ MATCH        │ MATCH    │
│ AND                │ --           │ 空格 (隐含)  │ AND          │ MATCH_ALL    │ 默认     │
│ OR                 │ --           │ ✗            │ OR           │ MATCH_ANY    │ ✗        │
│ NOT                │ --           │ ✗            │ NOT          │ ✗            │ ✗        │
│ 短语搜索           │ --           │ `...`        │ ✗            │ MATCH_PHRASE │ phrase   │
│ 近邻搜索           │ --           │ ✗            │ ✗            │ ✗            │ ✗        │
│ 前缀通配           │ --           │ ✗            │ ✗            │ PHRASE_PREFIX│ ✓        │
│ 词干化             │ --           │ ✗            │ ✗            │ ✗            │ snowball │
│ 模糊搜索           │ --           │ ✗            │ ✗            │ ✗            │ ✗        │
│ 权重/字段加权      │ --           │ ✗            │ ✗            │ ✗            │ ✓        │
│ 相关性排序         │ --           │ ✗            │ ✗            │ ✗            │ _score   │
│ 高亮               │ --           │ ✗            │ ✗            │ ✗            │ ✗        │
│ 摘要               │ --           │ ✗            │ ✗            │ ✗            │ ✗        │
└────────────────────┴──────────────┴──────────────┴──────────────┴──────────────┴──────────┘
```

## 索引实现对比

```
┌─────────────────────┬───────────────────┬──────────────────────────────────────────────┐
│ 引擎                │ 索引类型          │ 实现细节                                     │
├─────────────────────┼───────────────────┼──────────────────────────────────────────────┤
│ MySQL InnoDB        │ FULLTEXT INDEX    │ 辅助表 (auxiliary tables) 存储倒排索引        │
│                     │                   │ FTS_DOC_ID 隐式列, 批量更新 (FTS cache)      │
│                     │                   │ 删除使用标记删除 + OPTIMIZE TABLE 清理       │
├─────────────────────┼───────────────────┼──────────────────────────────────────────────┤
│ PostgreSQL          │ GIN (倒排索引)    │ 通用倒排索引, 也用于数组/JSONB 等            │
│                     │                   │ pending list 缓冲批量插入 (fastupdate)       │
│                     │                   │ 压缩的 posting list, 支持并行扫描            │
│                     │ GiST (签名树)     │ 有损压缩, 需要 recheck, 支持排序             │
├─────────────────────┼───────────────────┼──────────────────────────────────────────────┤
│ SQL Server          │ Full-Text Catalog │ 独立的 fdhost.exe 进程                       │
│                     │                   │ 倒排索引存储在文件系统, 非数据库页内         │
│                     │                   │ 增量填充 (timestamp 列) / 变更跟踪           │
├─────────────────────┼───────────────────┼──────────────────────────────────────────────┤
│ Oracle Text         │ CONTEXT INDEX     │ $I (倒排索引), $K (docid映射), $R (rowid映射)│
│                     │                   │ $N (负列表/已删除文档)                       │
│                     │                   │ DRG$ 内部表, SYNC 策略控制更新               │
├─────────────────────┼───────────────────┼──────────────────────────────────────────────┤
│ SQLite FTS5         │ 虚拟表 (shadow表) │ B-tree 存储的倒排索引                        │
│                     │                   │ segment merge (类 LSM-tree), doclist 压缩    │
│                     │                   │ content table 模式: 不复制文档内容           │
├─────────────────────┼───────────────────┼──────────────────────────────────────────────┤
│ ClickHouse          │ tokenbf_v1        │ 布隆过滤器 (跳过索引), 有假阳性             │
│                     │ inverted (实验)   │ 倒排索引, 按 granule 存储                    │
├─────────────────────┼───────────────────┼──────────────────────────────────────────────┤
│ Doris               │ INVERTED INDEX    │ 基于 CLucene 的倒排索引                      │
│                     │                   │ segment 级别索引, 支持 AND/OR 下推           │
├─────────────────────┼───────────────────┼──────────────────────────────────────────────┤
│ CrateDB             │ Lucene 倒排索引   │ 直接使用 Lucene, 与 Elasticsearch 相同底层   │
├─────────────────────┼───────────────────┼──────────────────────────────────────────────┤
│ SAP HANA            │ FULLTEXT INDEX    │ 内存倒排索引, 支持 delta merge               │
│                     │                   │ 内置 CJK 分词和模糊搜索                      │
├─────────────────────┼───────────────────┼──────────────────────────────────────────────┤
│ Db2                 │ Text Search Index │ 基于 Apache Lucene (OmniFind)                │
│                     │                   │ 独立的 text search server 进程               │
└─────────────────────┴───────────────────┴──────────────────────────────────────────────┘
```

## 分词器 / 分析器详解

### 分词处理流程

```
文本输入: "The Quick Brown Foxes jumped over 2 lazy dogs!"
         ↓
字符过滤 (Char Filter):
  HTML 去标签, 字符映射 (é→e)
         ↓
分词 (Tokenizer):
  ["The", "Quick", "Brown", "Foxes", "jumped", "over", "2", "lazy", "dogs"]
         ↓
词条过滤 (Token Filter):
  小写化: ["the", "quick", "brown", "foxes", "jumped", "over", "2", "lazy", "dogs"]
  去停用词: ["quick", "brown", "foxes", "jumped", "lazy", "dogs"]
  词干化: ["quick", "brown", "fox", "jump", "lazi", "dog"]
         ↓
倒排索引: {
  "quick": [doc1:pos2],
  "brown": [doc1:pos3],
  "fox":   [doc1:pos4],
  "jump":  [doc1:pos5],
  "lazi":  [doc1:pos8],
  "dog":   [doc1:pos9]
}
```

### CJK 分词策略对比

```
中文文本: "全文检索是数据库的核心功能"

策略 1: 基于词典的分词 (Dictionary-based)
  代表: jieba, SCWS, ICTCLAS, HanLP
  结果: ["全文检索", "是", "数据库", "的", "核心", "功能"]
  优点: 语义准确, 支持新词发现
  缺点: 需要维护词典, 有歧义 (如 "南京市长江大桥")

策略 2: N-gram 分词
  代表: MySQL ngram, SQLite trigram, pg_bigm
  结果 (bigram): ["全文", "文检", "检索", "索是", "是数", "数据", "据库", ...]
  优点: 无词典依赖, 无漏词
  缺点: 索引膨胀, 假阳性高

策略 3: 基于统计/机器学习
  代表: Stanford NLP, BERT-based tokenizer
  结果: 取决于训练数据
  优点: 处理新词/未登录词好
  缺点: 计算成本高, 不适合数据库内置

策略 4: Unicode 字符分类
  代表: pg_cjk_parser, ICU BreakIterator
  结果: 按 Unicode Script 分段: ["全文检索", "是", "数据库", "的", "核心功能"]
  优点: 无外部依赖
  缺点: 精度有限

各引擎 CJK 分词支持:
┌──────────────┬─────────────────────────────────────────────────────────┐
│ 引擎         │ CJK 分词方案                                          │
├──────────────┼─────────────────────────────────────────────────────────┤
│ MySQL        │ ngram 分词器 (内置), MeCab (日语, 需编译安装)          │
│ MariaDB      │ ngram (内置), Mroonga 引擎 (CJK 全文检索)             │
│ PostgreSQL   │ pg_jieba (中文), pg_bigm (CJK), zhparser, pgroonga    │
│ SQL Server   │ 内置中日韩分词器 (word breaker), 效果良好              │
│ Oracle       │ CHINESE_LEXER, JAPANESE_LEXER, KOREAN_MORPH_LEXER     │
│ SQLite       │ trigram 分词器, libsimple (第三方)                     │
│ SAP HANA     │ 内置 CJK 分词, 语言自动检测                           │
│ IBM Db2      │ 内置 CJK 分词 (基于 Lucene CJKAnalyzer)               │
│ Doris        │ 内置中文分词 (基于 jieba)                              │
│ CrateDB      │ Lucene CJKAnalyzer                                    │
│ Elasticsearch│ ik_analyzer (中文), kuromoji (日语), nori (韩语)       │
│ MongoDB      │ Lucene analyzers (Atlas Search)                        │
│ ClickHouse   │ N-gram 索引, 无内置 CJK 分词                          │
│ Snowflake    │ 无全文检索, 无 CJK 分词支持                            │
│ BigQuery     │ 有限的 CJK 支持                                       │
└──────────────┴─────────────────────────────────────────────────────────┘
```

## 外部搜索引擎集成

### Elasticsearch 集成模式

```
模式 1: 双写 (Dual Write)
  应用程序 → 写入数据库 + 写入 Elasticsearch
  优点: 简单直接
  缺点: 一致性难保证, 应用层负担重

  适用引擎: 所有 (与数据库无关)

模式 2: CDC (Change Data Capture)
  数据库 → Debezium/Canal → Kafka → Elasticsearch
  优点: 最终一致性好, 解耦
  缺点: 延迟较高, 架构复杂

  MySQL → Canal → ES
  PostgreSQL → Debezium → ES
  SQL Server → Debezium (CDC) → ES
  MongoDB → Change Streams → ES

模式 3: 数据库原生插件/联邦查询
  直接在 SQL 中查询 Elasticsearch

  PostgreSQL:
    -- pg_es_fdw (Foreign Data Wrapper)
    CREATE EXTENSION pg_es_fdw;
    CREATE SERVER es_server FOREIGN DATA WRAPPER pg_es_fdw
        OPTIONS (host 'localhost', port '9200');
    CREATE FOREIGN TABLE es_articles (
        title TEXT, body TEXT, _score FLOAT
    ) SERVER es_server OPTIONS (index 'articles');
    SELECT * FROM es_articles WHERE body = 'database optimization';

    -- ZomboDB: PostgreSQL 扩展，深度集成 Elasticsearch
    CREATE INDEX idx_zdb ON articles USING zombodb (
        (articles.*) zombodb.zdb_all_text
    );
    SELECT * FROM articles WHERE articles ==> 'body:database AND title:optimization';

  Spark SQL:
    -- Elasticsearch Hadoop connector
    val df = spark.read.format("org.elasticsearch.spark.sql")
        .option("es.resource", "articles")
        .load()
    df.filter("body = 'database optimization'")

  Presto/Trino:
    -- Elasticsearch connector
    SELECT * FROM elasticsearch.default.articles
    WHERE query = 'database optimization';

模式 4: Elasticsearch SQL
  -- Elasticsearch 自带 SQL 接口
  POST /_sql
  {
    "query": "SELECT title, _score FROM articles WHERE MATCH(body, 'database optimization')"
  }
  -- 支持有限的 SQL 子集
  -- 不支持 JOIN, 子查询有限
```

### 其他搜索引擎集成

```
Apache Solr:
  - DIH (Data Import Handler): 直接从 JDBC 导入
  - 适合批量全量/增量索引

Meilisearch / Typesense:
  - 轻量级搜索引擎
  - 通常通过应用层同步
  - 适合前端即时搜索 (typo tolerance)

Tantivy (Rust):
  - Lucene 的 Rust 实现
  - 适合嵌入式场景
  - 被一些数据库引擎直接集成 (如 ParadeDB)

ParadeDB:
  - PostgreSQL 扩展，基于 Tantivy
  - CREATE INDEX ON articles USING bm25 (body) WITH (text_fields='{"body": {}}');
  - SELECT * FROM articles WHERE body @@@ 'database optimization';
  - 比 tsvector 更快, BM25 原生支持
```

## 自然语言搜索 vs 布尔搜索

```
┌──────────────────────┬──────────────────────────┬──────────────────────────┐
│ 特性                 │ 自然语言模式             │ 布尔模式                 │
├──────────────────────┼──────────────────────────┼──────────────────────────┤
│ 输入方式             │ 自然语言 (如搜索引擎)    │ 结构化查询表达式         │
│ 运算符               │ 无 (系统自动处理)        │ AND, OR, NOT, NEAR 等    │
│ 相关性排序           │ 自动 (TF-IDF/BM25)       │ 通常无 (命中即返回)      │
│ 停用词处理           │ 自动去除                 │ 可选                     │
│ 词干化               │ 自动                     │ 取决于引擎               │
│ 使用场景             │ 终端用户搜索框           │ 精确筛选, 高级搜索       │
│ 空结果可能           │ 所有词都是停用词时       │ 条件过于严格时           │
├──────────────────────┼──────────────────────────┼──────────────────────────┤
│ MySQL                │ IN NATURAL LANGUAGE MODE │ IN BOOLEAN MODE          │
│ PostgreSQL           │ plainto_tsquery          │ to_tsquery               │
│                      │ websearch_to_tsquery     │                          │
│ SQL Server           │ FREETEXT                 │ CONTAINS                 │
│ Oracle               │ (默认 CONTAINS 行为)     │ CONTAINS 显式运算符      │
│ SQLite FTS5          │ 默认                     │ AND/OR/NOT               │
│ Elasticsearch        │ match query              │ bool query               │
└──────────────────────┴──────────────────────────┴──────────────────────────┘
```

## 相关性评分算法

```
1. TF-IDF (经典)
   TF(t,d) = 词 t 在文档 d 中出现的次数
   IDF(t) = log(总文档数 / 包含词 t 的文档数)
   Score = TF * IDF

2. BM25 (现代标准, Okapi BM25)
   Score = Σ IDF(t) * (TF(t,d) * (k1 + 1)) / (TF(t,d) + k1 * (1 - b + b * |d|/avgdl))
   k1 = 1.2 (词频饱和参数)
   b = 0.75 (文档长度归一化参数)

各引擎使用的算法:
┌──────────────────┬───────────────────────────────────────────┐
│ 引擎             │ 评分算法                                  │
├──────────────────┼───────────────────────────────────────────┤
│ MySQL 8.0        │ 专有评分公式（基于 TF-IDF 思想，可类比 BM25 但非标准实现）│
│ MySQL 5.7        │ 专有相关性公式（可类比 TF-IDF 家族）       │
│ PostgreSQL       │ ts_rank: 自定义权重模型 (非 BM25)         │
│                  │ ts_rank_cd: Cover Density 算法            │
│ SQL Server       │ 专有 IDF 变体 (CONTAINSTABLE RANK)        │
│ Oracle Text      │ TF-IDF 变体 (可配置)                      │
│ SQLite FTS5      │ Okapi BM25                                │
│ Elasticsearch    │ BM25 (默认), 可切换 TF-IDF                │
│ CrateDB          │ BM25 (Lucene 默认)                        │
│ Doris            │ 无内置评分 (仅过滤)                       │
│ ClickHouse       │ 无评分                                    │
│ Snowflake        │ 无全文检索 (无评分)                        │
│ BigQuery         │ 无评分                                    │
│ SAP HANA         │ TF-IDF 变体                               │
│ Db2              │ TF-IDF (Lucene 可配置)                    │
└──────────────────┴───────────────────────────────────────────┘

关于 PostgreSQL ts_rank 不使用 BM25 的说明:
  PostgreSQL 的 ts_rank 使用的是一种基于词频和权重的简单评分模型
  而非 BM25。如果需要 BM25, 可以:
  1. 使用 ParadeDB 扩展 (pg_search, 原生 BM25)
  2. 手动计算 BM25 (用 SQL 函数)
  3. 将数据导出到 Elasticsearch

  这是 PostgreSQL 全文检索的一个已知弱点
```

## WHERE 中全文搜索 vs 专用函数

```sql
-- 不同引擎处理全文搜索位置的差异:

-- MySQL: WHERE 中直接使用
SELECT * FROM articles WHERE MATCH(title) AGAINST('database');
-- 优化器识别: 如果 WHERE 中有 MATCH，使用全文索引扫描
-- 如果只在 SELECT 中有 MATCH (无 WHERE)，全表扫描后计算分数

-- PostgreSQL: WHERE 中使用操作符 @@
SELECT * FROM articles WHERE tsv @@ to_tsquery('english', 'database');
-- GIN 索引通过 bitmap index scan 加速

-- SQL Server: WHERE 中使用谓词 或 JOIN 表值函数
-- 方式 1: WHERE 谓词 (无排名)
SELECT * FROM articles WHERE CONTAINS(body, 'database');
-- 方式 2: JOIN 表值函数 (有排名)
SELECT a.*, ft.RANK FROM articles a
INNER JOIN CONTAINSTABLE(articles, body, 'database') ft ON a.id = ft.[KEY];

-- Oracle: WHERE 中使用，SCORE() 在 SELECT 中
SELECT SCORE(1) AS rank, title FROM articles
WHERE CONTAINS(body, 'database', 1) > 0
ORDER BY rank DESC;
-- SCORE(label) 引用 CONTAINS 中的 label

-- SQLite: WHERE 中 MATCH，但必须左侧是表名
SELECT * FROM articles_fts WHERE articles_fts MATCH 'database';  -- 正确
-- SELECT * FROM articles_fts WHERE body MATCH 'database';  -- FTS5 也支持列名

-- 关键差异: 是否支持全文搜索与其他条件组合
-- MySQL: MATCH AGAINST 可以与其他 WHERE 条件 AND
SELECT * FROM articles
WHERE MATCH(body) AGAINST('database') AND created_at > '2024-01-01';
-- 但优化器可能不走全文索引 (取决于代价估算)

-- PostgreSQL: 自由组合
SELECT * FROM articles
WHERE tsv @@ to_tsquery('english', 'database')
  AND created_at > '2024-01-01'
  AND category = 'tech';
-- 可利用多索引 bitmap AND

-- SQL Server: CONTAINSTABLE 作为 JOIN，自由组合
SELECT a.* FROM articles a
INNER JOIN CONTAINSTABLE(articles, body, 'database') ft ON a.id = ft.[KEY]
WHERE a.created_at > '2024-01-01';
```

## 短语搜索与近邻搜索详解

```sql
-- 短语搜索: 词必须按顺序紧邻出现
-- 近邻搜索: 词必须在指定距离内出现 (可能不要求顺序)

-- MySQL: 短语搜索 (布尔模式)
WHERE MATCH(body) AGAINST('"query optimization"' IN BOOLEAN MODE);
-- 近邻搜索: 不支持

-- PostgreSQL: 短语搜索
WHERE tsv @@ phraseto_tsquery('english', 'query optimization');
-- 等价于: 'query' <-> 'optim' (紧邻)
-- 近邻搜索:
WHERE tsv @@ to_tsquery('english', 'query <3> optimization');
-- query 和 optimization 之间最多 2 个词

-- SQL Server: 短语搜索
WHERE CONTAINS(body, '"query optimization"');
-- 近邻搜索:
WHERE CONTAINS(body, 'NEAR((query, optimization), 5)');       -- 无序, 5 词内
WHERE CONTAINS(body, 'NEAR((query, optimization), 5, TRUE)'); -- 有序, 5 词内

-- Oracle: 短语搜索
WHERE CONTAINS(body, '"query optimization"') > 0;
-- 近邻搜索:
WHERE CONTAINS(body, 'NEAR((query, optimization), 5)') > 0;
WHERE CONTAINS(body, 'NEAR((query, optimization), 5, TRUE)') > 0;

-- SQLite FTS5: 短语搜索
WHERE articles_fts MATCH '"query optimization"';
-- 近邻搜索:
WHERE articles_fts MATCH 'NEAR(query optimization, 5)';

-- Elasticsearch SQL:
-- 短语搜索通过 match_phrase 查询
-- 近邻搜索通过 match_phrase + slop 参数
-- 在 SQL 接口中受限，通常需要 DSL

-- CrateDB:
WHERE MATCH(body, 'query optimization') USING phrase;
-- 近邻搜索: 不直接支持 (需要 Lucene DSL)

-- 近邻搜索实现难度分析:
-- 需要在倒排索引中存储位置信息 (positional index)
-- 存储开销: 位置信息通常占倒排索引的 50%+ 空间
-- 查询算法: 需要在 posting list 上做位置交集
-- 这就是为什么很多简单的全文检索实现不支持近邻搜索
```

## 通配符搜索

```sql
-- 通配符搜索: 在全文检索中支持前缀/后缀/中间通配

-- MySQL (布尔模式):
WHERE MATCH(body) AGAINST('data*' IN BOOLEAN MODE);
-- 只支持右通配 (前缀搜索)

-- PostgreSQL:
WHERE tsv @@ to_tsquery('english', 'data:*');
-- 只支持前缀通配

-- SQL Server:
WHERE CONTAINS(body, '"data*"');
-- 前缀通配

-- Oracle:
WHERE CONTAINS(body, 'data%') > 0;       -- 右通配
WHERE CONTAINS(body, 'da_abase') > 0;    -- 单字符通配
-- 需要 SUBSTRING_INDEX 支持左通配 (%base)

-- SQLite FTS5:
WHERE articles_fts MATCH 'data*';
-- 前缀通配

-- 为什么大多数引擎只支持前缀通配?
-- 倒排索引按词的字母序排列，前缀查找 = 范围扫描 (高效)
-- 后缀查找需要反转索引或扫描所有词条 (低效)
-- 中间通配需要 N-gram 索引或正则扫描 (代价更高)

-- 解决后缀通配的方案:
-- 1. 维护反转词索引 (Oracle SUBSTRING_INDEX)
-- 2. 使用 N-gram 索引 (如 PostgreSQL pg_trgm)
-- 3. 使用正则表达式 (不利用全文索引)
```

## 高亮与摘要提取

```sql
-- 高亮: 在搜索结果中标记匹配的关键词
-- 摘要: 从长文本中提取包含关键词的片段

-- PostgreSQL: ts_headline (最灵活)
SELECT ts_headline('english', body,
    to_tsquery('english', 'database & optimization'),
    'StartSel=<em>, StopSel=</em>, MaxWords=50, MinWords=20, ' ||
    'ShortWord=3, HighlightAll=false, MaxFragments=3, FragmentDelimiter=" ... "'
) FROM articles WHERE tsv @@ to_tsquery('english', 'database & optimization');

-- SQLite FTS5: highlight() 和 snippet()
SELECT highlight(articles_fts, 0, '<em>', '</em>') AS highlighted_title,
       snippet(articles_fts, 1, '<em>', '</em>', '...', 30) AS body_snippet
FROM articles_fts WHERE articles_fts MATCH 'database';

-- Oracle Text: CTX_DOC.SNIPPET
SELECT CTX_DOC.SNIPPET('idx_body_ft', rowid, 'database optimization',
    starttag => '<em>', endtag => '</em>',
    separator => '...', maxlen => 200
) AS snippet
FROM articles WHERE CONTAINS(body, 'database & optimization') > 0;

-- SQL Server: 无原生高亮函数
-- 需要在应用层实现, 或使用 CLR 函数

-- Elasticsearch: 内置 highlight
-- POST /articles/_search
-- { "query": { "match": { "body": "database" } },
--   "highlight": { "fields": { "body": {} } } }
-- SQL 接口不支持 highlight

-- MySQL: 无原生高亮函数
-- 需要在应用层实现

-- 高亮实现要点:
-- 1. 需要访问原文 (不能只靠倒排索引)
-- 2. 需要知道匹配词的位置
-- 3. 性能瓶颈: 对大量结果做高亮很慢
-- 4. 建议: 先过滤 (用索引), 再对 TOP-N 结果做高亮
```

## 性能考量

```
全文索引的空间与时间开销:

┌──────────────────┬──────────────┬──────────────┬──────────────┐
│ 引擎             │ 索引空间     │ 构建速度     │ 更新延迟     │
│                  │ (vs 原文)    │              │              │
├──────────────────┼──────────────┼──────────────┼──────────────┤
│ MySQL InnoDB     │ 100-200%     │ 慢           │ 近实时       │
│ PostgreSQL GIN   │ 50-100%      │ 中等         │ 同步(fastupdate=off) / 异步(fastupdate=on, 默认) │
│ SQL Server FT    │ 30-80%       │ 快           │ 可配置       │
│ Oracle Text      │ 50-150%      │ 中等         │ 可配置       │
│ SQLite FTS5      │ 30-50%       │ 快           │ 实时         │
│ Elasticsearch    │ 100-300%     │ 快           │ 近实时 (1s)  │
│ ClickHouse inv.  │ 20-50%       │ 快           │ 批量         │
│ Doris            │ 50-100%      │ 快           │ 批量         │
└──────────────────┴──────────────┴──────────────┴──────────────┘

性能优化建议:
1. 避免 SELECT * + 全文搜索: 全文索引只返回 docid, 还需回表
2. 使用 LIMIT: 全文搜索结果按相关性排序, 通常只需 TOP-N
3. 全文搜索 + 常规过滤: 让优化器选择最优路径
4. 批量更新索引: 避免逐行更新 (MySQL OPTIMIZE TABLE, Oracle SYNC)
5. 分区 + 全文索引: 减少索引扫描范围

MySQL InnoDB FULLTEXT 的已知性能问题:
  - 大表上 OPTIMIZE TABLE 非常慢 (重建所有辅助表)
  - 高并发写入时 FTS cache 成为瓶颈
  - innodb_ft_cache_size (默认 8MB) 可能不够
  - 建议: 读密集场景使用, 写密集场景考虑外部引擎

PostgreSQL GIN 优化:
  - fastupdate=on (默认): 批量写入 pending list, 读时合并
  - gin_pending_list_limit: 控制 pending list 大小
  - maintenance_work_mem: 影响 GIN 构建速度
  - 并行 vacuum: PostgreSQL 14+ 支持并行 GIN vacuum
```

## 云数据库全文检索服务

```
┌──────────────────────┬──────────────────────────────────────────────────┐
│ 云服务               │ 全文检索方案                                     │
├──────────────────────┼──────────────────────────────────────────────────┤
│ AWS Aurora MySQL     │ 兼容 MySQL FULLTEXT (InnoDB)                     │
│ AWS Aurora PG        │ 兼容 PostgreSQL tsvector (无法装第三方分词扩展)  │
│ AWS OpenSearch       │ 独立搜索服务 (Elasticsearch fork)                │
│ AWS RDS              │ 各引擎原生全文检索                               │
├──────────────────────┼──────────────────────────────────────────────────┤
│ Azure SQL Database   │ 兼容 SQL Server Full-Text Search                │
│ Azure Cognitive Search│ 独立搜索服务 (BM25 + 向量搜索)                 │
├──────────────────────┼──────────────────────────────────────────────────┤
│ GCP AlloyDB          │ 兼容 PostgreSQL tsvector                        │
│ GCP Cloud SQL        │ 各引擎原生全文检索                               │
│ GCP Spanner          │ SEARCH 函数 + TOKENLIST                         │
│ GCP BigQuery         │ SEARCH 函数 + SEARCH INDEX                      │
├──────────────────────┼──────────────────────────────────────────────────┤
│ 阿里云 PolarDB      │ 兼容 MySQL/PG 全文检索                          │
│ 阿里云 AnalyticDB   │ 内置全文检索 (倒排索引)                          │
│ 阿里云 Lindorm       │ 内置搜索引擎 (基于 Lucene)                      │
│ 阿里云 OpenSearch   │ 独立搜索服务                                     │
├──────────────────────┼──────────────────────────────────────────────────┤
│ 腾讯云 TDSQL        │ 兼容 MySQL FULLTEXT                              │
│ 华为云 GaussDB      │ 兼容 PostgreSQL tsvector                        │
│ OceanBase (蚂蚁)    │ 兼容 MySQL FULLTEXT (有限)                       │
└──────────────────────┴──────────────────────────────────────────────────┘

云数据库的限制:
  - 通常不允许安装自定义分词扩展 (如 Aurora PG 无法装 pg_jieba)
  - CJK 支持可能受限于内置分词器
  - 建议: CJK 全文检索需求强的场景，使用独立搜索服务
```

## 对引擎开发者的实现建议

### 最小可行全文检索实现

```
Phase 1: 基础功能 (MVP)
  1. 倒排索引存储结构
     - 简单方案: 词 → posting list (docid 列表) 存在 B-tree 中
     - 高效方案: 词 → 压缩的 posting list (varint/PForDelta 编码)
     - 位置信息: 如果要支持短语搜索, posting list 中需要存储位置

  2. 分词器接口
     - 定义 Tokenizer 接口: text → [(token, position, offset)]
     - 内置: WhitespaceTokenizer, UnicodeTokenizer
     - 可插拔: 允许用户注册自定义分词器

  3. 基本查询
     - 单词查询: 查倒排索引
     - AND 查询: posting list 交集
     - OR 查询: posting list 并集
     - NOT 查询: posting list 差集

  4. SQL 语法选择
     - 推荐: MATCH(column, 'query') 谓词 (最通用)
     - 或: column @@ 'query' 操作符 (PostgreSQL 风格)
     - 避免: CONTAINS (与 SQL Server/Oracle 冲突, 语义不同)

Phase 2: 增强功能
  5. BM25 评分
     - 维护: 文档总数, 每文档词频, 平均文档长度
     - 返回值: SCORE() 函数或 MATCH() 返回浮点数

  6. 词干化与停用词
     - Snowball 词干化库 (支持 15+ 语言, BSD 许可)
     - 停用词: 可配置的词表, 默认按语言提供

  7. 短语搜索
     - 需要位置索引 (positional index)
     - posting list 格式: docid → [pos1, pos2, ...]
     - 查询算法: 对每个查询词的 posting list 做位置对齐

  8. 前缀搜索
     - 倒排索引的词按字典序存储 (B-tree), 前缀 = 范围扫描

Phase 3: 高级功能
  9. CJK 分词
     - 最低成本: N-gram 分词 (无需外部依赖)
     - 推荐: 可插拔分词器 + 提供 N-gram 默认实现
     - 参考: ICU BreakIterator (Unicode 标准分词)

  10. 高亮与摘要
      - 需要访问原文 + 匹配位置信息
      - 实现: 在原文中标记 [offset, length] 的匹配位置

  11. 索引更新策略
      - 实时更新: 写时更新倒排索引 (简单, 写放大)
      - 延迟更新: pending list → 批量合并 (PostgreSQL GIN 方式)
      - 异步更新: WAL → 后台线程更新索引 (MySQL InnoDB 方式)
```

### 索引存储设计

```
方案 A: 基于 B-tree 的倒排索引 (推荐起步方案)
  优点: 复用现有 B-tree 基础设施, 支持事务
  缺点: 空间效率低于专用结构
  实现: CREATE INDEX ... USING btree ON (token, docid)
  参考: PostgreSQL GIN (本质是 B-tree of posting lists)

方案 B: 专用倒排索引文件
  优点: 空间效率高, 查询快
  缺点: 需要独立的事务/崩溃恢复机制
  实现: 词典文件 + posting list 文件
  参考: Lucene 的 segment 设计, SQLite FTS5 的 shadow tables

方案 C: LSM-tree 风格
  优点: 写入友好, 适合高吞吐
  缺点: 读放大, 需要 compaction
  参考: ClickHouse inverted index (基于 segment)

posting list 压缩:
  - Variable Byte Encoding (VByte): 简单, 通用
  - PForDelta: 批量压缩, 高吞吐
  - Roaring Bitmap: 适合稀疏 docid 集
  - 选择建议: 先用 VByte, 性能不够再换 PForDelta/Roaring
```

### 查询优化器集成

```
全文搜索与优化器的集成要点:

1. 代价估算
   - 倒排索引可以提供精确的文档频率 (DF)
   - 代价 ≈ DF * 回表代价 + 索引扫描代价
   - 与范围索引不同: 全文索引的选择率难以提前估算 (取决于查询词)

2. 执行计划选择
   - 全文搜索 + 主键过滤: 先全文索引, 再过滤 (如果全文结果少)
   - 全文搜索 + 范围过滤: 可能需要 bitmap AND
   - 纯全文搜索: 直接使用倒排索引

3. 与 ORDER BY 的交互
   - ORDER BY score: 可以在索引扫描时排序 (如果支持)
   - ORDER BY other_column: 需要额外排序步骤
   - LIMIT + ORDER BY score: 可以用 top-K 堆优化

4. 多索引组合
   - 全文索引 AND B-tree 索引: bitmap AND (PostgreSQL 方式)
   - 或: 先全文索引过滤, 再 B-tree seek (嵌套循环)
   - 选择: 取决于两个索引的选择率

5. 并行执行
   - 倒排索引天然适合并行: 不同 posting list 可以并行处理
   - segment 级并行: 不同 segment 的索引可以并行扫描后合并
```

### 需要避免的陷阱

```
1. 不要在全文索引中存储过长的文档
   - 单个文档 > 1MB 时, 分词和索引构建会非常慢
   - 建议: 设置最大文档长度限制, 或者截断后索引

2. 不要忽视索引更新的事务性
   - 倒排索引的更新必须与数据行的更新在同一事务中
   - 否则: 崩溃后可能出现索引和数据不一致
   - 参考: MySQL InnoDB 使用 redo log 保证一致性

3. 不要使用 DELETE + INSERT 更新倒排索引
   - 每次更新文档都要删除旧的 posting list entries + 插入新的
   - 大量更新会导致索引碎片化
   - 方案: 标记删除 + 后台 compaction (类似 LSM-tree)

4. 不要忽视内存管理
   - 倒排索引构建需要大量内存 (排序、合并)
   - 需要 spill-to-disk 机制
   - 查询时 posting list 的解压也消耗内存

5. 不要假设所有文本都是 ASCII
   - 分词器必须正确处理 UTF-8 多字节字符
   - Unicode 标准化 (NFC/NFD) 会影响搜索结果
   - 大小写折叠需要考虑 locale (如土耳其语 İ → i vs I → ı)

6. 不要忽略 NULL 和空字符串的处理
   - NULL 值是否应该出现在全文索引中?
   - 空字符串应该产生零个 token
   - 建议: NULL 不索引, 空字符串索引但匹配不到任何查询

7. 不要低估 CJK 的复杂性
   - 中文没有空格分词: 必须有分词器
   - 日文混合平假名/片假名/汉字/罗马字: 分词更复杂
   - 韩文有空格但需要词干化 (조사 处理)
   - 最低成本方案: N-gram (bigram/trigram)
   - 推荐方案: 可插拔分词器接口 + 内置 N-gram 默认实现
```

### 同步与异步索引一致性

全文索引的更新策略直接影响查询一致性:

```
同步更新 (MySQL InnoDB FTS, SQLite FTS5):
  INSERT/UPDATE → 立即更新倒排索引 → 后续查询可见
  + 强一致: 写入后立即可搜索
  - 写放大: 每次 DML 都触发索引更新
  - 写入延迟: 分词 + 索引更新在事务路径上

异步更新 (SQL Server, Oracle Text, PostgreSQL GIN pending list):
  INSERT/UPDATE → 写入 pending list → 后台线程合并到主索引
  + 写入快: 主事务路径不含索引更新
  - 幻读风险: 刚写入的数据可能无法被全文搜索命中 (stale results)
  - 一致性窗口: 取决于后台合并频率 (通常毫秒到秒级)
```

**引擎实现建议**:
- 明确文档化索引更新的一致性保证 (强一致 / 最终一致)
- 如果使用异步更新，提供 `SYNC INDEX` 或 `FLUSH` 命令强制刷新 pending list
- SQL Server 的 `CHANGE_TRACKING AUTO` vs `MANUAL` 是一个好的配置模型
- 对于 OLTP 场景，考虑提供可选的同步模式 (牺牲写入性能换取一致性)

### 向量搜索与全文检索的融合趋势

现代搜索场景越来越需要混合搜索 (hybrid search): 结合关键词精确匹配 (FTS) 和语义相似性 (向量搜索):

```
混合搜索架构:

查询 "如何优化数据库性能"
  ├── FTS 通道: MATCH(body, '优化 数据库 性能') → 关键词精确匹配结果
  └── 向量通道: vector_column <=> embedding('如何优化数据库性能') → 语义近似结果
      ↓
  融合排序 (Reciprocal Rank Fusion / 加权线性组合)
      ↓
  最终排序结果

已支持混合搜索的引擎/扩展:
  - PostgreSQL: pg_search (ParadeDB) 同时支持 BM25 + pgvector
  - Elasticsearch 8.x: kNN + full-text 在同一查询中
  - SingleStore: VECTOR INDEX + FULLTEXT 组合查询
  - Google Spanner: 搜索索引 + 向量索引 (2024+)
```

**引擎实现建议**:
- 如果引擎已支持全文索引，规划向量索引时应考虑查询优化器的统一: 全文评分和向量距离应能在同一 ORDER BY 中组合
- 提供内置的融合排序函数 (如 `HYBRID_SCORE(fts_score, vector_distance, weight)`)
- 索引存储上，倒排索引和向量索引可共享文档 ID 空间，简化 JOIN 操作

### FTS 索引膨胀与在线维护

全文索引随时间推移会出现严重膨胀，引擎必须提供在线维护机制:

```
索引膨胀的来源:
  1. 标记删除累积: UPDATE/DELETE 后旧的 posting list entry 被标记删除但未物理回收
  2. pending list 增长: 异步更新模式下，如果合并速度跟不上写入速度
  3. 词典碎片: 频繁更新导致词典条目分散在不同页面

膨胀程度评估:
  PostgreSQL: SELECT pg_relation_size('idx_fts') -- 与逻辑数据量对比
  MySQL:      SELECT * FROM INFORMATION_SCHEMA.INNODB_FT_DELETED -- 已删除文档数
  Oracle:     CTX_REPORT.INDEX_SIZE / CTX_REPORT.TOKEN_INFO

在线维护操作:
  PostgreSQL: REINDEX CONCURRENTLY idx_fts      -- 不阻塞读写
  MySQL:      OPTIMIZE TABLE articles            -- 重建 FTS 索引 (短暂锁表)
  Oracle:     CTX_DDL.OPTIMIZE_INDEX('idx', 'FULL')  -- 后台优化
  SQL Server: ALTER FULLTEXT CATALOG ... REORGANIZE   -- 合并碎片
```

**引擎实现建议**:
- 提供在线 REINDEX / OPTIMIZE 操作，不阻塞并发读写 (参考 PostgreSQL 的 `REINDEX CONCURRENTLY`)
- 实现自动膨胀检测: 当索引大小超过逻辑数据量的 N 倍时发出警告
- 提供后台 compaction 线程 (类似 LSM-tree 的 compaction)，持续回收已删除条目的空间
- 在系统视图中暴露索引健康指标: 膨胀率、pending list 大小、最后优化时间、已删除但未回收的文档数

### SQL 语法设计建议

```sql
-- 推荐的 SQL 语法设计 (综合各引擎优点):

-- 1. 全文索引创建
CREATE FULLTEXT INDEX idx_name ON table(column)
    [USING parser_name]
    [WITH (
        language = 'english',
        min_token_length = 2,
        stopwords = 'english'  -- 或 'none', 或自定义表名
    )];

-- 2. 搜索谓词 (WHERE 中使用)
SELECT * FROM articles
WHERE MATCH(body, 'search query');                  -- 自然语言 (默认)
WHERE MATCH(body, 'search query', mode => 'boolean'); -- 布尔模式
WHERE MATCH(body, '"exact phrase"');                 -- 短语 (自动识别引号)

-- 3. 评分函数 (SELECT 中使用)
SELECT SCORE(body, 'search query') AS relevance FROM articles
WHERE MATCH(body, 'search query')
ORDER BY relevance DESC;

-- 4. 高亮函数
SELECT HIGHLIGHT(body, 'search query',
    start_tag => '<em>', end_tag => '</em>',
    max_length => 200, fragment_count => 3
) AS snippet
FROM articles WHERE MATCH(body, 'search query');

-- 5. 多列搜索
WHERE MATCH((title, body), 'search query');
-- 或带权重:
WHERE MATCH((title WEIGHT 5, body WEIGHT 1), 'search query');

-- 设计原则:
-- a. MATCH 既是谓词 (WHERE) 又暗示使用全文索引
-- b. SCORE 和 HIGHLIGHT 是辅助函数, 不影响过滤
-- c. 布尔操作符在查询字符串内部, 不在 SQL 层面
-- d. 语法尽量简单, 高级选项通过命名参数传递
```
