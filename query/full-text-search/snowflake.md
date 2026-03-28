# Snowflake: 全文搜索

> 参考资料:
> - [1] Snowflake SQL Reference - LIKE / ILIKE
>   https://docs.snowflake.com/en/sql-reference/functions/like
> - [2] Snowflake SQL Reference - REGEXP
>   https://docs.snowflake.com/en/sql-reference/functions/rlike


## 1. 核心概念: Snowflake 没有全文搜索引擎


 Snowflake 不支持传统全文搜索索引（如 MySQL FULLTEXT, PG tsvector/GIN）。
 文本搜索依赖字符串函数 + 全表扫描（微分区裁剪无法加速文本搜索）。

## 2. 搜索方式


LIKE（模式匹配，大小写敏感）

```sql
SELECT * FROM articles WHERE content LIKE '%database%';

```

ILIKE（大小写不敏感，Snowflake/PostgreSQL 特有）

```sql
SELECT * FROM articles WHERE content ILIKE '%database%';

```

LIKE ANY / LIKE ALL（多模式匹配，Snowflake 独有）

```sql
SELECT * FROM articles WHERE content LIKE ANY ('%database%', '%performance%');
SELECT * FROM articles WHERE content LIKE ALL ('%database%', '%performance%');

```

CONTAINS（子字符串匹配，返回 BOOLEAN）

```sql
SELECT * FROM articles WHERE CONTAINS(content, 'database');

```

REGEXP / RLIKE（正则表达式）

```sql
SELECT * FROM articles WHERE content REGEXP '(?i)database.*performance';
SELECT * FROM articles WHERE REGEXP_LIKE(content, '(?i)database\\s+performance');

```

## 3. 语法设计分析（对 SQL 引擎开发者）


### 3.1 为什么没有全文搜索

 全文搜索需要倒排索引 (Inverted Index)，这与 Snowflake 架构冲突:
   (a) 不可变微分区: 倒排索引需要随数据变更实时更新
   (b) 列存格式: 倒排索引是行级结构，与列存不兼容
   (c) 计算存储分离: 关闭 Warehouse 时无法维护索引
   (d) 零管理哲学: 全文索引需要用户配置分词器、停用词等

 对比:
   PostgreSQL: tsvector + GIN 索引（功能最强的内置全文搜索）
   MySQL:      FULLTEXT 索引 + MATCH AGAINST
   Oracle:     Oracle Text（最完整的全文搜索方案）
   BigQuery:   无全文搜索（与 Snowflake 一致）
   Redshift:   无全文搜索
   Databricks: 无全文搜索

 对引擎开发者的启示:
   OLAP 引擎普遍不支持全文搜索（BigQuery/Redshift/Databricks 都不支持）。
   全文搜索的标准方案是集成 Elasticsearch/OpenSearch。
   Search Optimization Service 加速的是等值/子字符串查询，不是语义搜索。

### 3.2 ILIKE 和 LIKE ANY/ALL: Snowflake 的文本搜索增强

 ILIKE: 大小写不敏感的 LIKE（避免了 LOWER(col) LIKE '%...' 的写法）
 LIKE ANY: 匹配任一模式（OR 的简写）
 LIKE ALL: 匹配所有模式（AND 的简写）
 这些是 Snowflake 对缺少全文搜索的补偿性设计

## 4. 简单相关度排序


```sql
SELECT title,
    REGEXP_COUNT(LOWER(content), 'database') AS keyword_count
FROM articles
WHERE CONTAINS(content, 'database')
ORDER BY keyword_count DESC;

```

## 5. Search Optimization Service（Enterprise+）


SOS 可以加速 LIKE / CONTAINS 的子字符串搜索:

```sql
ALTER TABLE articles ADD SEARCH OPTIMIZATION ON SUBSTRING(content);
```

 但这不是全文搜索: 没有分词、没有相关度排序、没有同义词处理

## 6. COLLATE（排序规则敏感搜索）


```sql
SELECT * FROM articles
WHERE content COLLATE 'en-ci' LIKE '%database%';
```

 'en-ci' = English case-insensitive

## 7. Snowflake Cortex（AI 搜索，2023+）

 Snowflake Cortex 提供 AI 驱动的语义搜索能力:
 SELECT SNOWFLAKE.CORTEX.SEARCH('database performance tuning', content)
 这基于向量嵌入 (embedding) 而非传统倒排索引
 是 Snowflake 对全文搜索需求的新一代解决方案

## 横向对比: 文本搜索能力

| 能力          | Snowflake      | BigQuery  | PostgreSQL     | MySQL |
|------|------|------|------|------|
| 全文索引      | 不支持         | 不支持    | tsvector+GIN   | FULLTEXT |
| LIKE/ILIKE    | 全表扫描       | 全表扫描  | 索引可加速     | 索引可加速 |
| 正则搜索      | REGEXP         | REGEXP    | ~              | REGEXP(8.0) |
| 子字符串加速  | SOS(Enterprise)| 不支持    | GIN trigram    | 不支持 |
| 分词搜索      | 不支持         | 不支持    | to_tsvector    | 自然语言模式 |
| 语义搜索      | Cortex(AI)     | 不支持    | 不支持         | 不支持 |
| LIKE ANY/ALL  | 原生支持       | 不支持    | 不支持         | 不支持 |

