-- OceanBase: Full-Text Search
-- OceanBase has dual mode: MySQL mode and Oracle mode. Both shown where relevant.
--
-- 参考资料:
--   [1] OceanBase SQL Reference (MySQL Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase SQL Reference (Oracle Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- MySQL Mode (4.0+)
-- ============================================================

-- Create fulltext index (4.0+, MySQL mode)
CREATE FULLTEXT INDEX idx_ft_bio ON users (bio);
CREATE FULLTEXT INDEX idx_ft_multi ON articles (title, content);

-- Natural language mode (default, same as MySQL)
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('database performance');

-- With relevance score
SELECT title, MATCH(title, content) AGAINST('database performance') AS score
FROM articles
WHERE MATCH(title, content) AGAINST('database performance')
ORDER BY score DESC;

-- Boolean mode (same as MySQL)
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('+database -mysql +performance' IN BOOLEAN MODE);

-- Phrase search
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('"full text search"' IN BOOLEAN MODE);

-- Query expansion mode
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('database' WITH QUERY EXPANSION);

-- ngram parser for CJK languages (4.0+)
CREATE FULLTEXT INDEX idx_ft_cjk ON articles (content) WITH PARSER ngram;

-- ============================================================
-- Oracle Mode
-- ============================================================

-- Oracle mode: use LIKE or built-in text functions
-- OceanBase Oracle mode has limited full-text search support compared to Oracle DB

-- LIKE pattern matching
SELECT * FROM articles WHERE content LIKE '%database%';

-- INSTR for substring search
SELECT * FROM articles WHERE INSTR(content, 'database') > 0;

-- REGEXP_LIKE (Oracle mode)
SELECT * FROM articles WHERE REGEXP_LIKE(content, 'database|performance');

-- Note: Oracle DB's CONTAINS() / CTX_QUERY functions are NOT supported
-- in OceanBase Oracle mode

-- ============================================================
-- Workarounds
-- ============================================================

-- For complex full-text search needs, integrate with:
-- OceanBase + Elasticsearch via OMS (OceanBase Migration Service) for data sync
-- Use Elasticsearch for full-text queries, OceanBase for transactional queries

-- Limitations:
-- MySQL mode: fulltext search supported in 4.0+ (same syntax as MySQL)
-- Oracle mode: no CONTAINS/CTX_QUERY, use LIKE/REGEXP_LIKE instead
-- Fulltext index performance may differ from MySQL
-- Minimum token size and stopword configuration similar to MySQL
