-- SAP HANA: Full-Text Search
--
-- 参考资料:
--   [1] SAP HANA SQL Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/

-- Create full-text index
CREATE FULLTEXT INDEX ft_content ON articles (content)
    SYNC;

-- Full-text index with fuzzy search enabled
CREATE FULLTEXT INDEX ft_title ON articles (title)
    FUZZY SEARCH INDEX ON
    SYNC;

-- Basic search using CONTAINS
SELECT * FROM articles
WHERE CONTAINS(content, 'database');

-- Phrase search
SELECT * FROM articles
WHERE CONTAINS(content, '"full text search"');

-- Boolean operators
SELECT * FROM articles
WHERE CONTAINS(content, 'database AND performance');

SELECT * FROM articles
WHERE CONTAINS(content, 'database OR warehouse');

SELECT * FROM articles
WHERE CONTAINS(content, 'database NOT mysql');

-- Wildcard
SELECT * FROM articles
WHERE CONTAINS(content, 'data*');

-- FUZZY search (SAP HANA-specific: approximate/typo-tolerant matching)
SELECT SCORE() AS relevance, title, content
FROM articles
WHERE CONTAINS(content, 'database', FUZZY(0.8));

-- Fuzzy search on specific column
SELECT SCORE() AS relevance, *
FROM articles
WHERE CONTAINS(title, 'datbase', FUZZY(0.7));  -- finds 'database' despite typo

-- Linguistic search (stemming)
SELECT * FROM articles
WHERE CONTAINS(content, 'running', LINGUISTIC);

-- Freestyle search (natural language)
SELECT SCORE() AS relevance, *
FROM articles
WHERE CONTAINS(content, 'how to improve database performance', FREESTYLE);

-- EXACT search
SELECT * FROM articles
WHERE CONTAINS(content, 'database', EXACT);

-- Ranked results with SCORE()
SELECT SCORE() AS relevance, title
FROM articles
WHERE CONTAINS(content, 'database')
ORDER BY SCORE() DESC;

-- Search across multiple columns
SELECT * FROM articles
WHERE CONTAINS((title, content), 'database');

-- Weighted multi-column search
SELECT SCORE() AS relevance, *
FROM articles
WHERE CONTAINS(title, 'database', WEIGHT(0.7))
   OR CONTAINS(content, 'database', WEIGHT(0.3))
ORDER BY SCORE() DESC;

-- Fulltext index with language detection
CREATE FULLTEXT INDEX ft_multi ON articles (content)
    FUZZY SEARCH INDEX ON
    LANGUAGE DETECTION ('EN', 'DE', 'FR')
    SYNC;

-- Highlighting
SELECT HIGHLIGHTED(content) FROM articles
WHERE CONTAINS(content, 'database');

-- Drop full-text index
DROP FULLTEXT INDEX ft_content;

-- Note: SAP HANA's FUZZY search is unique and very powerful
-- Note: FUZZY parameter (0.0-1.0) controls match tolerance
-- Note: FREESTYLE enables natural language queries
-- Note: column store text search does not require explicit indexes for basic CONTAINS
