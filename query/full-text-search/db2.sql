-- IBM Db2: Full-Text Search (Db2 Text Search / Net Search Extender)
--
-- 参考资料:
--   [1] Db2 SQL Reference
--       https://www.ibm.com/docs/en/db2/11.5?topic=sql
--   [2] Db2 Built-in Functions
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in

-- Enable text search on a column
-- db2ts "ENABLE DATABASE FOR TEXT CONNECT TO mydb"
-- db2ts "CREATE INDEX ft_content FOR TEXT ON articles(content) CONNECT TO mydb"
-- db2ts "UPDATE INDEX ft_content FOR TEXT CONNECT TO mydb"

-- Basic search using CONTAINS
SELECT * FROM articles
WHERE CONTAINS(content, 'database') = 1;

-- Phrase search
SELECT * FROM articles
WHERE CONTAINS(content, '"full text search"') = 1;

-- Boolean operators
SELECT * FROM articles
WHERE CONTAINS(content, 'database AND performance') = 1;

SELECT * FROM articles
WHERE CONTAINS(content, 'database OR warehouse') = 1;

SELECT * FROM articles
WHERE CONTAINS(content, 'database NOT mysql') = 1;

-- Wildcard search
SELECT * FROM articles
WHERE CONTAINS(content, 'data%') = 1;

-- Fuzzy search (approximate matching)
SELECT * FROM articles
WHERE CONTAINS(content, 'FUZZY FORM OF "database"') = 1;

-- Ranked search with SCORE
SELECT title, SCORE(content, 'database') AS relevance
FROM articles
WHERE CONTAINS(content, 'database') = 1
ORDER BY relevance DESC;

-- Search with result limit
SELECT title, SCORE(content, 'performance') AS relevance
FROM articles
WHERE CONTAINS(content, 'performance') = 1
ORDER BY relevance DESC
FETCH FIRST 10 ROWS ONLY;

-- XML text search
SELECT * FROM xml_docs
WHERE CONTAINS(doc, 'SECTION("/customer/name") "Smith"') = 1;

-- Linguistic search (stemming)
SELECT * FROM articles
WHERE CONTAINS(content, 'LINGUISTIC FORM OF "running"') = 1;

-- Drop text index
-- db2ts "DROP INDEX ft_content FOR TEXT CONNECT TO mydb"

-- Alternative: LIKE for simple pattern matching
SELECT * FROM articles WHERE content LIKE '%database%';

-- Alternative: XMLQUERY for XML full-text
SELECT * FROM xml_docs
WHERE XMLEXISTS('$d/article[contains(., "database")]' PASSING doc AS "d");

-- Note: requires Db2 Text Search component (separate installation)
-- Note: CONTAINS returns 1 (match) or 0 (no match)
-- Note: SCORE returns relevance score (0.0 to 1.0)
-- Note: text indexes must be updated manually or scheduled
