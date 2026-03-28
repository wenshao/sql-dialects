# TiDB: 全文搜索

> 参考资料:
> - [TiDB SQL Reference](https://docs.pingcap.com/tidb/stable/sql-statement-overview)
> - [TiDB - MySQL Compatibility](https://docs.pingcap.com/tidb/stable/mysql-compatibility)
> - [TiDB - Functions and Operators](https://docs.pingcap.com/tidb/stable/functions-and-operators-overview)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

```sql
SELECT * FROM articles WHERE content LIKE '%database%';
```

Warning: LIKE '%...%' cannot use indexes, performs full table scan

## Use REGEXP for regex matching (same as MySQL)

```sql
SELECT * FROM articles WHERE content REGEXP 'database|performance';

```

## External search engines (recommended)

Integrate with Elasticsearch, Apache Solr, or Meilisearch
Use TiCDC (Change Data Capture) to sync data to search engine
Query search engine for full-text results, then join back to TiDB

## TiDB + Elasticsearch architecture:

TiDB (transactional data) --> TiCDC --> Elasticsearch (search index)
Application queries Elasticsearch for text search
Application queries TiDB for transactional operations
Join results in application layer

## Expression index for exact token matching (limited use)

Create an expression index for specific JSON fields
```sql
CREATE INDEX idx_json_name ON events ((CAST(data->>'$.name' AS CHAR(64))));
SELECT * FROM events WHERE CAST(data->>'$.name' AS CHAR(64)) = 'alice';

```

## INSTR for substring search (same as MySQL, no index usage)

```sql
SELECT * FROM articles WHERE INSTR(content, 'database') > 0;

```

Limitations:
No FULLTEXT index support
No MATCH ... AGAINST syntax
No natural language search, boolean search, or query expansion
Must use external search engines for production full-text search
LIKE and REGEXP work but are slow on large datasets (full scan)
