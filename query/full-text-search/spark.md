# Spark SQL: 全文搜索 (Full-Text Search)

> 参考资料:
> - [1] Spark SQL - String Functions
>   https://spark.apache.org/docs/latest/sql-ref-functions-builtin.html#string-functions
> - [2] Spark MLlib - Text Processing
>   https://spark.apache.org/docs/latest/ml-features.html


## 1. 核心设计: Spark SQL 没有内建全文搜索


 Spark SQL 不支持全文索引、倒排索引、文本评分排名等全文搜索能力。
 文本搜索通过字符串函数（LIKE/RLIKE）和外部系统集成实现。

 根本原因:
   全文搜索需要倒排索引——在列式存储（Parquet/ORC）上不可行。
   Parquet 的 Data Skipping 只支持 min/max 统计，无法加速 LIKE '%keyword%'。
   Spark 的定位是批处理引擎，不是搜索引擎。

 对比:
   MySQL:      FULLTEXT INDEX + MATCH ... AGAINST（InnoDB 5.6+）
   PostgreSQL: tsvector/tsquery + GIN 索引（最强大的内建全文搜索）
   Oracle:     Oracle Text（CONTAINS 函数，专业级全文搜索）
   SQL Server: Full-Text Search（CONTAINS/FREETEXT）
   ClickHouse: 倒排索引（23.1+）+ tokenbf_v1 Bloom Filter
   BigQuery:   SEARCH() 函数（结合 SEARCH INDEX）
   Hive:       无全文搜索
   Flink SQL:  无全文搜索
   Elasticsearch: 专业搜索引擎（通过 Spark Connector 集成）

## 2. LIKE / RLIKE: 基本文本搜索


```sql
SELECT * FROM articles WHERE content LIKE '%database%';
SELECT * FROM articles WHERE LOWER(content) LIKE '%database%'; -- 不区分大小写

```

RLIKE / REGEXP（正则表达式搜索）

```sql
SELECT * FROM articles WHERE content RLIKE '(?i)database.*performance';
SELECT * FROM articles WHERE content RLIKE '\\b(database|performance)\\b';
SELECT * FROM articles WHERE content REGEXP 'data(base|set)';

```

REGEXP_LIKE（Spark 3.2+）

```sql
SELECT * FROM articles WHERE REGEXP_LIKE(content, '(?i)database');

```

多关键词搜索

```sql
SELECT * FROM articles
WHERE LOWER(content) LIKE '%database%'
  AND LOWER(content) LIKE '%performance%';

```

## 3. 简单相关性评分


通过字符替换计算关键词出现次数

```sql
SELECT title, content,
    (LENGTH(content) - LENGTH(REPLACE(LOWER(content), 'database', ''))) / 8 AS term_count
FROM articles
WHERE LOWER(content) LIKE '%database%'
ORDER BY term_count DESC;

```

## 4. 分词与词频分析


SPLIT + EXPLODE 分词

```sql
SELECT id, title, word
FROM articles
LATERAL VIEW EXPLODE(SPLIT(LOWER(content), '\\s+')) words AS word
WHERE word IN ('database', 'performance', 'optimization');

```

词频统计（基本 TF 计算）

```sql
SELECT id, title, word, COUNT(*) AS word_freq
FROM articles
LATERAL VIEW EXPLODE(SPLIT(LOWER(content), '\\s+')) words AS word
WHERE word IN ('database', 'performance')
GROUP BY id, title, word
ORDER BY word_freq DESC;

```

## 5. 外部搜索引擎集成


 Elasticsearch-Hadoop Connector:
 CREATE TABLE articles_es
 USING org.elasticsearch.spark.sql
 OPTIONS (
     es.resource 'articles/_doc',
     es.nodes 'localhost:9200'
 );
 SELECT * FROM articles_es WHERE query = 'database performance';

 Spark MLlib 文本处理（TF-IDF, Word2Vec）:
 from pyspark.ml.feature import HashingTF, IDF, Tokenizer
 tokenizer = Tokenizer(inputCol="content", outputCol="words")
 hashingTF = HashingTF(inputCol="words", outputCol="rawFeatures")
 idf = IDF(inputCol="rawFeatures", outputCol="features")

 Databricks AI 函数:
 SELECT ai_query('What is the main topic?', content) FROM articles;

## 6. 性能考量


 LIKE '%keyword%' 的性能问题:
   在 Parquet/ORC 上，前缀通配符（%keyword%）无法利用任何索引或统计
   每次查询都是全表扫描——对 TB 级数据不可行
   解决方案:
### 1. 预处理: 构建关键词列（ETL 时提取关键词存入 ARRAY 列）

### 2. 分区裁剪: 先按日期/类别缩小范围再搜索

### 3. 外部索引: 使用 Elasticsearch 建立倒排索引，Spark 读取结果


## 7. 版本演进

Spark 2.0: LIKE, RLIKE, SPLIT, EXPLODE
Spark 3.2: REGEXP_LIKE
Spark 3.4: REGEXP_SUBSTR, REGEXP_INSTR
Databricks: AI Functions（语义搜索）

限制:
无内建倒排索引或全文搜索引擎
LIKE '%keyword%' 是全表扫描（无法加速）
无 MATCH ... AGAINST（MySQL 语法）
无 tsvector/tsquery（PostgreSQL 语法）
生产环境全文搜索应集成 Elasticsearch/Solr 等专业引擎
Spark MLlib 提供 TF-IDF、Word2Vec 等机器学习级文本分析

