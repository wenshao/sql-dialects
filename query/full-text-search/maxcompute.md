# MaxCompute (ODPS): 全文搜索

> 参考资料:
> - [1] MaxCompute - String Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/string-functions
> - [2] MaxCompute SQL Overview
>   https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview


## 1. MaxCompute 不支持全文搜索引擎 —— 设计决策


 为什么批处理引擎不内置全文搜索?
   全文搜索需要倒排索引（inverted index）
   倒排索引的维护成本:
     每次 INSERT OVERWRITE 需要重建整个分区的倒排索引
     索引本身可能和原始数据一样大
     分布式环境下的全文索引一致性极其复杂
   MaxCompute 的定位: 大数据分析引擎，不是搜索引擎
   正确的做法: 将需要全文搜索的数据导出到 Elasticsearch/OpenSearch

   对比:
     MySQL:       InnoDB FULLTEXT INDEX（5.6+，适合中小数据量）
     PostgreSQL:  tsvector + GIN 索引（内置全文搜索，功能强大）
     BigQuery:    SEARCH 函数 + 搜索索引（2021+，有限场景）
     Snowflake:   SEARCH OPTIMIZATION SERVICE（Enterprise+）
     ClickHouse:  Full-text index（23.1+，基于 ngram/token bloom filter）
     Hive:        不支持全文搜索（与 MaxCompute 相同）

## 2. LIKE 模糊搜索（全表扫描）


```sql
SELECT * FROM articles WHERE content LIKE '%database%';

```

前缀匹配（可以利用 AliORC 的 min/max 统计做一定程度的裁剪）

```sql
SELECT * FROM articles WHERE title LIKE 'database%';

```

 性能分析:
   LIKE '%keyword%': 全表扫描，无法利用任何索引/统计信息
   LIKE 'prefix%':   列式存储的 min/max 统计可以跳过部分 Stripe
   对 TB 级数据: LIKE '%keyword%' 可能扫描数小时 — 不可接受

## 3. INSTR 查找子字符串


```sql
SELECT * FROM articles WHERE INSTR(LOWER(content), 'database') > 0;

```

 INSTR 返回子字符串位置（从 1 开始），0 表示未找到
 LOWER 实现大小写不敏感搜索（MaxCompute 字符串比较默认大小写敏感）

## 4. REGEXP 正则表达式搜索


RLIKE / REGEXP: 正则匹配

```sql
SELECT * FROM articles WHERE content RLIKE '(?i)database.*performance';

```

REGEXP_EXTRACT: 提取匹配内容

```sql
SELECT title,
    REGEXP_EXTRACT(content, '(database\\w*)', 1) AS matched
FROM articles
WHERE content RLIKE '(?i)database';

```

REGEXP_COUNT: 统计匹配次数（简单的"相关度"指标）

```sql
SELECT title,
    REGEXP_COUNT(content, '(?i)database') AS keyword_count
FROM articles
WHERE content RLIKE '(?i)database'
ORDER BY keyword_count DESC;

```

 正则语法: 使用 Java 正则表达式（java.util.regex）
   (?i): 大小写不敏感标志
   \\w: 单词字符
   \\d: 数字字符
   注意: 反斜杠需要双重转义（SQL 字符串 + 正则）

## 5. 多关键词搜索


OR 逻辑: 包含任一关键词

```sql
SELECT * FROM articles
WHERE content RLIKE '(?i)(database|performance|optimization)';

```

AND 逻辑: 同时包含多个关键词

```sql
SELECT * FROM articles
WHERE content LIKE '%database%' AND content LIKE '%performance%';

```

简单的 TF 相关度计算

```sql
SELECT title,
    (LENGTH(content) - LENGTH(REPLACE(LOWER(content), 'database', '')))
        / LENGTH('database') AS keyword_count
FROM articles
WHERE content LIKE '%database%'
ORDER BY keyword_count DESC;

```

## 6. 推荐方案: 外部搜索引擎


 阿里云生态中的全文搜索方案:
### 1. Elasticsearch (阿里云 ES): 最通用的全文搜索引擎

      MaxCompute → DataWorks 同步 → Elasticsearch → 搜索 API

### 2. OpenSearch (阿里云开放搜索): 托管搜索服务

      MaxCompute → Tunnel/DataWorks → OpenSearch → 搜索 API

### 3. Hologres: 阿里云实时分析引擎，支持全文搜索

      MaxCompute → Hologres 外部表 → 在 Hologres 中搜索

 架构模式:
   MaxCompute（存储和分析） → 数据同步 → ES/OpenSearch（搜索服务）
   这是大数据平台的标准架构: 分析和搜索用不同的引擎

## 7. 横向对比: 全文搜索能力


 内置全文搜索:
MaxCompute: 不支持    | Hive: 不支持
   PostgreSQL: tsvector + GIN（最完整的内置实现）
   MySQL:      FULLTEXT INDEX（InnoDB 5.6+）
   BigQuery:   SEARCH 函数 + 搜索索引（2021+）
   Snowflake:  SEARCH OPTIMIZATION SERVICE（Enterprise+）
   ClickHouse: bloom_filter/ngrambf 跳数索引

 字符串搜索函数:
   MaxCompute: LIKE/RLIKE/INSTR/REGEXP_EXTRACT（全表扫描）
   所有引擎均支持这些基本函数

## 8. 对引擎开发者的启示


### 1. 全文搜索与 OLAP 分析是不同的问题域 — 不应勉强合并

### 2. BigQuery 的搜索索引是有限但实用的折中: 不是全功能搜索，但加速 LIKE

### 3. ClickHouse 的 ngram bloom filter 是另一种折中: 低成本过滤明确不匹配的数据块

### 4. 如果引擎有列式存储: 字符串列的 min/max 统计可以优化前缀搜索

### 5. 正确的架构是: OLAP 引擎做分析 + 外部搜索引擎做搜索（各司其职）

### 6. 如果必须内置: 分区级的倒排索引是可行的折中（限制在分区范围内）

