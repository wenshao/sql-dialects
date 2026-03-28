# OceanBase: 全文搜索

> 参考资料:
> - [OceanBase SQL Reference (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase SQL Reference (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL Mode (4.0+)


Create fulltext index (4.0+, MySQL mode)
```sql
CREATE FULLTEXT INDEX idx_ft_bio ON users (bio);
CREATE FULLTEXT INDEX idx_ft_multi ON articles (title, content);

```

Natural language mode (default, same as MySQL)
```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('database performance');

```

With relevance score
```sql
SELECT title, MATCH(title, content) AGAINST('database performance') AS score
FROM articles
WHERE MATCH(title, content) AGAINST('database performance')
ORDER BY score DESC;

```

Boolean mode (same as MySQL)
```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('+database -mysql +performance' IN BOOLEAN MODE);

```

Phrase search
```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('"full text search"' IN BOOLEAN MODE);

```

Query expansion mode
```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('database' WITH QUERY EXPANSION);

```

ngram parser for CJK languages (4.0+)
```sql
CREATE FULLTEXT INDEX idx_ft_cjk ON articles (content) WITH PARSER ngram;

```

## Oracle Mode


Oracle mode: use LIKE or built-in text functions
OceanBase Oracle mode has limited full-text search support compared to Oracle DB

LIKE pattern matching
```sql
SELECT * FROM articles WHERE content LIKE '%database%';

```

INSTR for substring search
```sql
SELECT * FROM articles WHERE INSTR(content, 'database') > 0;

```

REGEXP_LIKE (Oracle mode)
```sql
SELECT * FROM articles WHERE REGEXP_LIKE(content, 'database|performance');

```

Note: Oracle DB's CONTAINS() / CTX_QUERY functions are NOT supported
in OceanBase Oracle mode

## Workarounds


For complex full-text search needs, integrate with:
OceanBase + Elasticsearch via OMS (OceanBase Migration Service) for data sync
Use Elasticsearch for full-text queries, OceanBase for transactional queries

Limitations:
MySQL mode: fulltext search supported in 4.0+ (same syntax as MySQL)
Oracle mode: no CONTAINS/CTX_QUERY, use LIKE/REGEXP_LIKE instead
Fulltext index performance may differ from MySQL
Minimum token size and stopword configuration similar to MySQL
