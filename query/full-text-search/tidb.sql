-- TiDB: Full-Text Search
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- FULLTEXT INDEX: NOT SUPPORTED
-- TiDB does not support FULLTEXT indexes or MATCH ... AGAINST syntax

-- Attempting to create a fulltext index will result in an error:
-- CREATE FULLTEXT INDEX idx_ft_bio ON users (bio);  -- ERROR

-- Workarounds for full-text search in TiDB:

-- 1. Use LIKE for simple pattern matching (same as MySQL)
SELECT * FROM articles WHERE content LIKE '%database%';
-- Warning: LIKE '%...%' cannot use indexes, performs full table scan

-- 2. Use REGEXP for regex matching (same as MySQL)
SELECT * FROM articles WHERE content REGEXP 'database|performance';

-- 3. External search engines (recommended)
-- Integrate with Elasticsearch, Apache Solr, or Meilisearch
-- Use TiCDC (Change Data Capture) to sync data to search engine
-- Query search engine for full-text results, then join back to TiDB

-- 4. TiDB + Elasticsearch architecture:
-- TiDB (transactional data) --> TiCDC --> Elasticsearch (search index)
-- Application queries Elasticsearch for text search
-- Application queries TiDB for transactional operations
-- Join results in application layer

-- 5. Expression index for exact token matching (limited use)
-- Create an expression index for specific JSON fields
CREATE INDEX idx_json_name ON events ((CAST(data->>'$.name' AS CHAR(64))));
SELECT * FROM events WHERE CAST(data->>'$.name' AS CHAR(64)) = 'alice';

-- 6. INSTR for substring search (same as MySQL, no index usage)
SELECT * FROM articles WHERE INSTR(content, 'database') > 0;

-- Limitations:
-- No FULLTEXT index support
-- No MATCH ... AGAINST syntax
-- No natural language search, boolean search, or query expansion
-- Must use external search engines for production full-text search
-- LIKE and REGEXP work but are slow on large datasets (full scan)
