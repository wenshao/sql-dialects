-- Teradata: Full-Text Search
--
-- 参考资料:
--   [1] Teradata SQL Reference
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates
--   [2] Teradata Database Documentation
--       https://docs.teradata.com/

-- CONTAINS (requires Teradata full-text index)
-- Create full-text index first
CREATE INDEX ft_content ON articles (content) AS FULLTEXT;

-- Basic search
SELECT * FROM articles
WHERE CONTAINS(content, 'database');

-- Multiple terms (AND)
SELECT * FROM articles
WHERE CONTAINS(content, 'database AND performance');

-- OR search
SELECT * FROM articles
WHERE CONTAINS(content, 'database OR warehouse');

-- NOT search
SELECT * FROM articles
WHERE CONTAINS(content, 'database NOT mysql');

-- Phrase search (exact phrase)
SELECT * FROM articles
WHERE CONTAINS(content, '"full text search"');

-- Wildcard search
SELECT * FROM articles
WHERE CONTAINS(content, 'data*');

-- Proximity search (words near each other)
SELECT * FROM articles
WHERE CONTAINS(content, 'database NEAR performance');

-- Search with ranking
SELECT title, content
FROM articles
WHERE CONTAINS(content, 'database')
ORDER BY RANK(content, 'database') DESC;

-- Search across multiple columns
SELECT * FROM articles
WHERE CONTAINS((title, content), 'database');

-- Drop full-text index
DROP INDEX ft_content ON articles;

-- Alternative: LIKE for simple pattern matching
SELECT * FROM articles WHERE content LIKE '%database%';

-- Alternative: REGEXP_SIMILAR for regex matching
SELECT * FROM articles
WHERE REGEXP_SIMILAR(content, '.*database.*performance.*', 'i') = 1;

-- Note: full-text search requires Teradata Text add-on
-- Note: CONTAINS is not available in base Teradata without the add-on
-- Note: for basic pattern matching, use LIKE or REGEXP functions
-- Note: consider pre-processing text in ETL pipeline for search workloads
