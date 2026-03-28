# PolarDB: 全文搜索

PolarDB-X (distributed, MySQL compatible).

> 参考资料:
> - [PolarDB-X SQL Reference](https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/)
> - [PolarDB MySQL Documentation](https://help.aliyun.com/zh/polardb/polardb-for-mysql/)


## 创建全文索引

```sql
CREATE FULLTEXT INDEX idx_ft_bio ON users (bio);
CREATE FULLTEXT INDEX idx_ft_multi ON articles (title, content);
```

## 自然语言模式（默认）

```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('database performance');
```

## 带相关度分数

```sql
SELECT title, MATCH(title, content) AGAINST('database performance') AS score
FROM articles
WHERE MATCH(title, content) AGAINST('database performance')
ORDER BY score DESC;
```

## 布尔模式

```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('+database -mysql +performance' IN BOOLEAN MODE);
```

## 短语搜索

```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('"full text search"' IN BOOLEAN MODE);
```

## 查询扩展模式

```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('database' WITH QUERY EXPANSION);
```

## 中文分词器（ngram）

```sql
CREATE FULLTEXT INDEX idx_ft_cjk ON articles (content) WITH PARSER ngram;
```

注意事项：
全文索引在每个分片上独立维护
跨分片的全文搜索需要合并各分片的结果
相关度分数在分布式环境下可能与单机不完全一致
ngram 分词器适合中日韩文本
