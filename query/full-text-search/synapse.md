# Azure Synapse: 全文搜索

> 参考资料:
> - [Synapse SQL Features](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)
> - [Synapse T-SQL Differences](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


Synapse 专用 SQL 池不支持 SQL Server 的全文搜索功能
使用 LIKE / CHARINDEX / PATINDEX 进行文本搜索

## LIKE（基本文本搜索）


LIKE（大小写取决于排序规则，默认不敏感）
```sql
SELECT * FROM articles WHERE content LIKE '%database%';
SELECT * FROM articles WHERE content LIKE 'database%';     -- 前缀匹配
SELECT * FROM articles WHERE content LIKE '%database';     -- 后缀匹配
```


通配符
```sql
SELECT * FROM articles WHERE title LIKE 'SQL_____';        -- _ 单个字符
SELECT * FROM articles WHERE title LIKE '[A-Z]%';          -- [] 字符范围
SELECT * FROM articles WHERE title LIKE '[^0-9]%';         -- [^] 排除
```


强制大小写敏感
```sql
SELECT * FROM articles
WHERE content COLLATE Latin1_General_CS_AS LIKE '%Database%';
```


## 字符串搜索函数


CHARINDEX（查找位置）
```sql
SELECT * FROM articles WHERE CHARINDEX('database', content) > 0;
```


PATINDEX（模式位置）
```sql
SELECT * FROM articles WHERE PATINDEX('%data[a-z]ase%', content) > 0;
```


## 模拟全文搜索


多关键词搜索
```sql
SELECT * FROM articles
WHERE content LIKE '%database%'
  AND content LIKE '%performance%';
```


简单相关性排名
```sql
SELECT title,
    (CASE WHEN content LIKE '%database%' THEN 1 ELSE 0 END +
     CASE WHEN content LIKE '%performance%' THEN 1 ELSE 0 END +
     CASE WHEN content LIKE '%optimization%' THEN 1 ELSE 0 END) AS relevance
FROM articles
WHERE content LIKE '%database%'
   OR content LIKE '%performance%'
   OR content LIKE '%optimization%'
ORDER BY relevance DESC;
```


词频计算
```sql
SELECT title,
    (LEN(content) - LEN(REPLACE(content, 'database', ''))) / LEN('database') AS word_count
FROM articles
WHERE content LIKE '%database%'
ORDER BY word_count DESC;
```


## Serverless 池的文本搜索


```sql
SELECT * FROM OPENROWSET(
    BULK 'https://account.dfs.core.windows.net/container/articles/*.parquet',
    FORMAT = 'PARQUET'
) AS data
WHERE data.content LIKE '%database%';
```


## 外部全文搜索方案


方案一：Azure Cognitive Search
将数据索引到 Azure Cognitive Search
通过 REST API 搜索，结果与 Synapse 关联查询

方案二：SQL Server 全文搜索（仅限 Synapse Link）
使用 Synapse Link 将数据同步到 SQL Server
在 SQL Server 中使用 CONTAINS / FREETEXT

方案三：Azure Databricks 上的全文搜索
使用 Spark MLlib 或专用搜索库

注意：Synapse 专用池不支持 FULLTEXT INDEX / CONTAINS / FREETEXT
注意：这些是 SQL Server 的功能，Synapse 专用池不支持
注意：LIKE 在大表上性能差（全表扫描，无法利用列存索引）
注意：建议将全文搜索需求卸载到 Azure Cognitive Search
注意：Serverless 池同样不支持全文搜索
