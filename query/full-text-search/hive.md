# Hive: 全文搜索 (无原生支持)

> 参考资料:
> - [1] Apache Hive Language Manual - UDF
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF
> - [2] Apache Hive Language Manual - SELECT
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select


## 1. Hive 没有内置全文搜索引擎

 没有 FULLTEXT INDEX、MATCH ... AGAINST、tsvector/tsquery。
 所有文本搜索都是暴力扫描（全表/全分区）。

 为什么 Hive 不需要全文搜索?
1. 批处理引擎: 全文搜索是在线交互式操作，Hive 面向离线批处理

2. 索引已废弃: Hive 3.0 废弃了所有索引，全文索引更不可能

3. 生态分工: 全文搜索交给 Elasticsearch/Solr，Hive 负责 ETL 和聚合


## 2. LIKE 模糊搜索

```sql
SELECT * FROM articles WHERE content LIKE '%database%';

```

多关键词 AND

```sql
SELECT * FROM articles
WHERE content LIKE '%database%' AND content LIKE '%performance%';

```

 LIKE 的性能问题:
 LIKE '%keyword%' 无法利用任何索引或统计信息，必须全量扫描
 分区裁剪是唯一的优化手段: WHERE dt = '2024-01-15' AND content LIKE '%keyword%'

## 3. RLIKE / REGEXP (正则搜索)

```sql
SELECT * FROM articles WHERE content RLIKE '(?i)database.*performance';
SELECT * FROM articles WHERE content REGEXP '(?i)database';

```

多关键词 OR

```sql
SELECT * FROM articles
WHERE content RLIKE '(?i)(database|performance|optimization)';

```

REGEXP_EXTRACT: 提取匹配内容

```sql
SELECT title,
    REGEXP_EXTRACT(content, '(database\\w*)', 1) AS matched
FROM articles
WHERE content RLIKE '(?i)database';

```

## 4. 简单相关度排序

通过关键词出现次数模拟相关度

```sql
SELECT title,
    (LENGTH(content) - LENGTH(REGEXP_REPLACE(LOWER(content), 'database', '')))
    / LENGTH('database') AS keyword_count
FROM articles
WHERE content RLIKE '(?i)database'
ORDER BY keyword_count DESC;

```

INSTR 判断子串存在

```sql
SELECT * FROM articles
WHERE INSTR(LOWER(content), 'database') > 0;

```

## 5. Hive 文本分析函数

SENTENCES: 分句分词

```sql
SELECT SENTENCES('Hello world. How are you?');
```

返回: [["Hello","world"],["How","are","you"]]

配合 LATERAL VIEW 展开为词

```sql
SELECT word FROM (SELECT 'Hello world. How are you?' AS text) t
LATERAL VIEW EXPLODE(SENTENCES(text)) s AS sentence
LATERAL VIEW EXPLODE(sentence) w AS word;

```

## 6. 替代方案: Elasticsearch 集成

 生产环境的全文搜索通常使用 Hive + Elasticsearch:
1. Hive ETL 处理原始数据 → 写入 Elasticsearch

2. Elasticsearch 提供全文索引和搜索能力

3. 搜索结果的 ID 回联 Hive 表做关联分析


 也可以使用 Hive 的 ES Storage Handler:
 CREATE EXTERNAL TABLE es_articles (...)
 STORED BY 'org.elasticsearch.hadoop.hive.EsStorageHandler'
 TBLPROPERTIES ('es.resource' = 'articles/_doc');

## 7. 跨引擎对比: 全文搜索能力

 引擎          全文搜索                     设计理由
 MySQL         FULLTEXT INDEX + MATCH        InnoDB 5.6+ 内置
 PostgreSQL    tsvector/tsquery + GIN 索引   最强大的内置全文搜索
 Oracle        Oracle Text (CONTAINS)        企业级全文搜索
 Hive          LIKE/RLIKE(暴力扫描)          批处理不需要全文索引
 Spark SQL     LIKE/RLIKE(暴力扫描)          同 Hive
 BigQuery      SEARCH() 函数(预览)           列存优化的文本搜索
 ClickHouse    LIKE/ngramSearch              tokenbf_v1 索引(实验性)
 Trino         LIKE/RLIKE                    查询引擎，依赖数据源

## 8. 对引擎开发者的启示

1. 全文搜索不是所有 SQL 引擎的必需:

    分析引擎可以将全文搜索委托给专门的搜索引擎
2. LIKE '%keyword%' 的优化空间:

    列存格式的字典编码可以加速 LIKE 查询（先搜索字典再定位行）
3. 文本分析函数（SENTENCES/LEVENSHTEIN）在大数据引擎中有价值:

Hive 内置的文本分析函数是 ETL 文本处理的实用工具

