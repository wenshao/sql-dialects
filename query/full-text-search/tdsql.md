# TDSQL: 全文搜索 (Full Text Search)

TDSQL distributed MySQL-compatible syntax.
Note: Full-text search support is limited in TDSQL distributed mode.

> 参考资料:
> - [TDSQL-C MySQL Documentation - Full-Text Search](https://cloud.tencent.com/document/product/1003)
> - [TDSQL MySQL Documentation - Index Types](https://cloud.tencent.com/document/product/557)
> - [MySQL 8.0 Reference - Full-Text Search](https://dev.mysql.com/doc/refman/8.0/en/fulltext-search.html)
> - [MySQL 8.0 Reference - FULLTEXT Indexes](https://dev.mysql.com/doc/refman/8.0/en/create-index.html)


## 创建全文索引


示例数据:
articles(id, title, content, author, created_at, shardkey)
users(id, username, bio, shardkey)
单列全文索引

```sql
CREATE FULLTEXT INDEX idx_ft_bio ON users (bio);
```

## 多列全文索引

```sql
CREATE FULLTEXT INDEX idx_ft_multi ON articles (title, content);
```

## 建表时定义全文索引

```sql
CREATE TABLE articles (
    id          BIGINT PRIMARY KEY,
    title       VARCHAR(200),
    content     TEXT,
    author      VARCHAR(100),
    created_at  DATETIME,
    shardkey    INT,
    FULLTEXT INDEX idx_ft_title_content (title, content)
) ENGINE=InnoDB;
```

TDSQL 分布式注意:
全文索引在各分片内独立创建和维护。
跨分片搜索需要汇总各分片的全文索引结果。

## 自然语言搜索 (Natural Language Mode)


## 基本搜索（默认模式: IN NATURAL LANGUAGE MODE）

```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('database performance');
```

## 带相关度分数

```sql
SELECT title,
    MATCH(title, content) AGAINST('database performance') AS score
FROM articles
WHERE MATCH(title, content) AGAINST('database performance')
ORDER BY score DESC;
```

自然语言模式特点:
按相关度排序（TF-IDF 算法）
自动过滤停用词（the, a, an 等）
50% 阈值: 出现在超过50%行中的词被认为无意义，自动忽略
最小词长: InnoDB 默认 3 个字符（ft_min_word_len 可配置）

## 布尔模式搜索 (Boolean Mode)


## 必须包含 + 排除

```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('+database -mysql' IN BOOLEAN MODE);
```

## 短语搜索（双引号）

```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('"full text search"' IN BOOLEAN MODE);
```

## OR 组合

```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('database OR performance' IN BOOLEAN MODE);
```

## 通配符前缀搜索

```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('data*' IN BOOLEAN MODE);
```

## 增加权重

```sql
SELECT title,
    MATCH(title, content) AGAINST('>database +performance' IN BOOLEAN MODE) AS score
FROM articles
WHERE MATCH(title, content) AGAINST('>database +performance' IN BOOLEAN MODE)
ORDER BY score DESC;
```

布尔模式运算符:
+    必须包含
必须不包含
>    增加权重
<    降低权重
*    前缀通配符
""   短语匹配
()   分组
~    取反（负权重）

## 查询扩展搜索 (Query Expansion)


WITH QUERY EXPANSION: 两轮搜索
第一轮: 搜索匹配文档
第二轮: 使用第一轮匹配文档中的关键词再次搜索

```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('database' WITH QUERY EXPANSION);
```

## 适用场景: 用户搜索词不够精确时，自动扩展相关词汇

风险: 可能返回大量不相关结果（搜索漂移）

## 全文索引配置参数


InnoDB 全文索引参数:
innodb_ft_min_token_size: 最小索引词长度（默认 3）
innodb_ft_max_token_size: 最大索引词长度（默认 84）
ft_query_expansion_limit: 查询扩展的匹配数（默认 20）
innodb_ft_cache_size: 全文索引缓存大小（默认 8MB）
innodb_ft_total_cache_size: 全局全文索引缓存（默认 640MB）
查看当前配置:

```sql
SHOW VARIABLES LIKE 'innodb_ft_min_token_size';
SHOW VARIABLES LIKE 'ft_query_expansion_limit';
```

## 注意: innodb_ft_min_token_size 需要重启实例生效

对于中文，通常需要设为 1 或 2（InnoDB ngram 解析器更方便）

## 中文全文搜索 (ngram 解析器)


## MySQL 5.7.6+ / TDSQL 支持 ngram 全文解析器（适合中日韩文字）

创建使用 ngram 解析器的全文索引

```sql
CREATE FULLTEXT INDEX idx_ft_chinese
ON articles (content) WITH PARSER ngram;
```

## 建表时指定 ngram 解析器

```sql
CREATE TABLE articles_cn (
    id      BIGINT PRIMARY KEY,
    title   VARCHAR(200),
    content TEXT,
    FULLTEXT INDEX idx_ft_cn (title, content) WITH PARSER ngram
) ENGINE=InnoDB;
```

ngram 参数:
ngram_token_size: n-gram 的 n 值（默认 2，适合中文双字分词）
对于中文推荐设为 2
ngram 搜索示例:

```sql
SELECT * FROM articles_cn
WHERE MATCH(title, content) AGAINST('数据库' IN NATURAL LANGUAGE MODE);

SELECT * FROM articles_cn
WHERE MATCH(title, content) AGAINST('+"搜索引擎"' IN BOOLEAN MODE);
```

ngram 局限性:
基于 n-gram 的机械分词，不是语义分词
与 Elasticsearch/PostgreSQL zhparser 的分词质量有差距
适合简单中文搜索场景

## 分布式环境下的全文搜索限制


TDSQL 分布式架构的全文搜索限制:
(a) 全文索引只在各分片内独立生效
(b) 跨分片搜索时各分片返回各自结果，由协调节点合并
(c) 50% 阈值是各分片独立计算，导致不同分片行为不一致
(d) 全文索引更新在分片间没有事务一致性保证
相关度分数在分布式环境下的偏差:
MATCH ... AGAINST 返回的分数基于分片内的 TF-IDF。
不同分片的文档数量不同，分数不可直接比较。
解决: 在协调节点进行二次排序（归一化分数后合并）

## 替代方案


## 方案 1: LIKE 模糊搜索（无索引支持，性能差）

```sql
SELECT * FROM articles WHERE content LIKE '%database%';
```

## 方案 2: REGEXP 正则搜索（无索引支持，性能差）

```sql
SELECT * FROM articles WHERE content REGEXP 'database|performance';
```

方案 3: 外部搜索引擎（推荐用于生产环境）
Elasticsearch: 功能最强，需要数据同步（Canal/Debezium）
MeiliSearch: 轻量级，适合中小规模
通过 binlog 同步数据到搜索引擎
方案 4: 触发器 + 搜索表（轻量替代）

```sql
CREATE TABLE search_index (
    article_id  BIGINT,
    keyword     VARCHAR(100),
    weight      DECIMAL(5,2),
    INDEX idx_keyword (keyword)
);
```

## 通过触发器或应用层维护关键词索引

```sql
SELECT DISTINCT a.* FROM articles a
INNER JOIN search_index s ON a.id = s.article_id
WHERE s.keyword IN ('database', 'performance')
ORDER BY s.weight DESC;
```

## 横向对比: TDSQL vs 其他数据库的全文搜索


## 集成度:

TDSQL/MySQL:  FULLTEXT 索引（InnoDB 5.6+），功能有限
PostgreSQL:   内置核心（tsvector/tsquery/GIN），SQL 完全融合
Oracle:       Oracle Text（功能丰富但配置复杂）
Elasticsearch: 专用搜索引擎（功能最强，需独立部署）
2. 中文搜索:
TDSQL/MySQL:  ngram 解析器（机械分词，质量一般）
PostgreSQL:   zhparser / pg_jieba 扩展（高质量中文分词）
Elasticsearch: IK / jieba 分词器（生产级中文分词）
3. 分布式全文搜索:
TDSQL:       分片内独立索引，协调节点合并
PolarDB MySQL: 单机存储共享，全文索引全局有效
Elasticsearch: 分布式倒排索引，原生支持

## 对引擎开发者的启示


(1) MySQL 的 FULLTEXT 索引功能有限:
不支持短语搜索（无类似 PostgreSQL <-> 的相邻运算符）。
不支持自定义分词器（仅 ngram 和内置英文分词器）。
TF-IDF 算法未考虑文档长度归一化（不如 BM25 先进）。
(2) 分布式全文搜索是核心挑战:
TDSQL 各分片独立维护全文索引，跨分片搜索需要合并。
相关度分数的分片间不可比是主要的准确性问题。
生产环境建议使用外部搜索引擎（Elasticsearch）。
(3) ngram 解析器的适用场景:
适合简单的中文搜索（双字匹配）。
不适合需要语义理解的搜索（如近义词、纠错）。
对于严肃的中文搜索需求，Elasticsearch + IK 分词器是更好的选择。

## 版本演进

MySQL 5.6:   InnoDB FULLTEXT 索引支持
MySQL 5.7.6: ngram 全文解析器（中日韩文字支持）
MySQL 8.0:   全文索引性能改进，降序索引支持
TDSQL:       继承 MySQL 全文搜索能力，分布式模式下有额外限制
