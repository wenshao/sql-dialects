# Databricks SQL: 全文搜索

> 参考资料:
> - [Databricks SQL Language Reference](https://docs.databricks.com/en/sql/language-manual/index.html)
> - [Databricks SQL - Built-in Functions](https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html)
> - [Delta Lake Documentation](https://docs.delta.io/latest/index.html)


Databricks 没有原生全文搜索引擎
使用 LIKE / RLIKE / 字符串函数进行文本搜索

## LIKE / ILIKE（基本文本搜索）


LIKE（大小写敏感）
```sql
SELECT * FROM articles WHERE content LIKE '%database%';
SELECT * FROM articles WHERE content LIKE 'database%';     -- 前缀匹配
```


ILIKE（大小写不敏感，Databricks 2022+）
```sql
SELECT * FROM articles WHERE content ILIKE '%database%';
```


通配符：% 任意字符序列，_ 单个字符
```sql
SELECT * FROM articles WHERE title LIKE 'SQL_____';
```


## RLIKE / REGEXP（正则表达式搜索）


RLIKE（正则匹配）
```sql
SELECT * FROM articles WHERE content RLIKE 'data(base|warehouse)';
SELECT * FROM articles WHERE content RLIKE '(?i)database';  -- 不区分大小写
```


REGEXP（RLIKE 的别名）
```sql
SELECT * FROM articles WHERE content REGEXP 'data[a-z]+';
```


REGEXP_EXTRACT（提取匹配）
```sql
SELECT REGEXP_EXTRACT(content, '([A-Z][a-z]+)', 1) AS first_word FROM articles;
```


REGEXP_REPLACE（替换）
```sql
SELECT REGEXP_REPLACE(content, '[0-9]+', '#') FROM articles;
```


REGEXP_EXTRACT_ALL（提取所有匹配）
```sql
SELECT REGEXP_EXTRACT_ALL(content, '\\b[A-Z][a-z]+\\b') AS words FROM articles;
```


REGEXP_COUNT（计数，Databricks 2023+）
```sql
SELECT REGEXP_COUNT(content, 'database') AS match_count FROM articles;
```


## 模拟全文搜索


多关键词搜索
```sql
SELECT * FROM articles
WHERE content ILIKE '%database%'
  AND content ILIKE '%performance%';
```


分词 + 搜索
```sql
SELECT title, word
FROM articles
LATERAL VIEW EXPLODE(SPLIT(LOWER(content), '\\s+')) t AS word
WHERE word IN ('database', 'performance', 'optimization');
```


简单 TF（词频）排名
```sql
SELECT title,
    SIZE(REGEXP_EXTRACT_ALL(LOWER(content), 'database')) AS tf_database,
    SIZE(REGEXP_EXTRACT_ALL(LOWER(content), 'performance')) AS tf_performance
FROM articles
WHERE content ILIKE '%database%' OR content ILIKE '%performance%'
ORDER BY tf_database + tf_performance DESC;
```


多关键词相关性
```sql
SELECT title, relevance FROM (
    SELECT title,
        (CASE WHEN content ILIKE '%database%' THEN 1 ELSE 0 END +
         CASE WHEN content ILIKE '%performance%' THEN 1 ELSE 0 END +
         CASE WHEN content ILIKE '%optimization%' THEN 1 ELSE 0 END) AS relevance
    FROM articles
) t
WHERE relevance > 0
ORDER BY relevance DESC;
```


## AI 函数进行语义搜索（Databricks 2024+）


ai_query 函数调用基础模型
SELECT * FROM articles
WHERE ai_similarity(content, 'database performance tuning') > 0.8;

向量搜索（需要 Mosaic AI Vector Search）
创建向量搜索索引后使用

## 外部全文搜索方案


方案一：Elasticsearch / OpenSearch
将数据同步到 Elasticsearch，搜索结果与 Databricks 关联

方案二：使用 Spark NLP 库在 notebook 中实现
在 PySpark notebook 中使用 spark-nlp 等库

方案三：Databricks Vector Search
将文本转为向量嵌入，使用向量相似度搜索

> **注意**: Databricks 没有原生全文搜索索引
> **注意**: ILIKE / RLIKE 在大表上需要全表扫描
> **注意**: REGEXP_EXTRACT_ALL 可用于简单的分词
> **注意**: 向量搜索 / AI 函数是新的语义搜索方向
> **注意**: 对于大规模全文搜索，建议使用专用搜索引擎
