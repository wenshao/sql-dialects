-- Spark SQL: Full-Text Search
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Spark SQL has no built-in full-text search engine
-- Text search is done through string functions, LIKE, and regex

-- LIKE pattern matching
SELECT * FROM articles WHERE content LIKE '%database%';
SELECT * FROM articles WHERE content LIKE '%database%performance%';

-- Case-insensitive LIKE
SELECT * FROM articles WHERE LOWER(content) LIKE '%database%';

-- RLIKE / REGEXP (regular expression matching)
SELECT * FROM articles WHERE content RLIKE '(?i)database.*performance';
SELECT * FROM articles WHERE content RLIKE '\\b(database|performance)\\b';
SELECT * FROM articles WHERE content REGEXP 'data(base|set)';

-- REGEXP_LIKE (Spark 3.2+)
SELECT * FROM articles WHERE regexp_like(content, '(?i)database');

-- INSTR (find position of substring)
SELECT * FROM articles WHERE INSTR(LOWER(content), 'database') > 0;

-- LOCATE
SELECT * FROM articles WHERE LOCATE('database', LOWER(content)) > 0;

-- CONTAINS (check substring, Databricks SQL only, not standard Spark)
-- SELECT * FROM articles WHERE CONTAINS(LOWER(content), 'database');

-- Multiple term search
SELECT * FROM articles
WHERE LOWER(content) LIKE '%database%'
  AND LOWER(content) LIKE '%performance%';

-- Simple relevance scoring (count term occurrences)
SELECT title, content,
    (LENGTH(content) - LENGTH(REPLACE(LOWER(content), 'database', ''))) / 8 AS term_count
FROM articles
WHERE LOWER(content) LIKE '%database%'
ORDER BY term_count DESC;

-- Tokenization with SPLIT and EXPLODE
SELECT id, title, word
FROM articles
LATERAL VIEW EXPLODE(SPLIT(LOWER(content), '\\s+')) words AS word
WHERE word IN ('database', 'performance', 'optimization');

-- Word count per document (basic TF calculation)
SELECT id, title, word, COUNT(*) AS word_freq
FROM articles
LATERAL VIEW EXPLODE(SPLIT(LOWER(content), '\\s+')) words AS word
WHERE word IN ('database', 'performance')
GROUP BY id, title, word
ORDER BY word_freq DESC;

-- Integration with external search engines:
-- 1. Elasticsearch-Hadoop connector
-- CREATE TABLE articles_es
-- USING org.elasticsearch.spark.sql
-- OPTIONS (es.resource 'articles/_doc', es.nodes 'localhost:9200');
-- SELECT * FROM articles_es WHERE query = 'database performance';

-- 2. Delta Lake + Databricks: Use Databricks SQL for search capabilities

-- Note: Spark has no built-in inverted index or text search ranking
-- Note: LIKE and RLIKE are the primary text search mechanisms
-- Note: For production search, use Elasticsearch, Solr, or similar with Spark connectors
-- Note: Spark MLlib has text processing (TF-IDF, Word2Vec) for ML-based text analysis
-- Note: Databricks has AI functions for semantic search
