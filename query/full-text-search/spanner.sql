-- Google Cloud Spanner: Full-Text Search (GoogleSQL, 2024+)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- Spanner provides full-text search via SEARCH indexes and TOKENLIST columns

-- ============================================================
-- Setup: create tokenized columns and search index
-- ============================================================

-- Add a TOKENLIST column (stores tokens for search)
CREATE TABLE Articles (
    ArticleId   INT64 NOT NULL,
    Title       STRING(500),
    Content     STRING(MAX),
    TitleTokens TOKENLIST AS (TOKENIZE_FULLTEXT(Title)) HIDDEN,
    ContentTokens TOKENLIST AS (TOKENIZE_FULLTEXT(Content)) HIDDEN
) PRIMARY KEY (ArticleId);

-- Create search index
CREATE SEARCH INDEX idx_articles_search
    ON Articles (TitleTokens, ContentTokens);

-- ============================================================
-- Basic search
-- ============================================================

-- SEARCH function
SELECT ArticleId, Title
FROM Articles
WHERE SEARCH(ContentTokens, 'database performance');

-- Search with AND (space = AND by default)
SELECT ArticleId, Title
FROM Articles
WHERE SEARCH(ContentTokens, 'database performance');

-- Search with OR
SELECT ArticleId, Title
FROM Articles
WHERE SEARCH(ContentTokens, 'database OR performance');

-- Search with NOT
SELECT ArticleId, Title
FROM Articles
WHERE SEARCH(ContentTokens, 'database -mysql');

-- Phrase search (exact phrase)
SELECT ArticleId, Title
FROM Articles
WHERE SEARCH(ContentTokens, '"full text search"');

-- ============================================================
-- Ranking
-- ============================================================

-- SCORE function for relevance ranking
SELECT ArticleId, Title,
    SCORE(ContentTokens, 'database') AS relevance
FROM Articles
WHERE SEARCH(ContentTokens, 'database')
ORDER BY relevance DESC;

-- ============================================================
-- Search across multiple columns
-- ============================================================

SELECT ArticleId, Title
FROM Articles
WHERE SEARCH(TitleTokens, 'database') OR SEARCH(ContentTokens, 'database');

-- ============================================================
-- Substring search (TOKENIZE_SUBSTRING)
-- ============================================================

CREATE TABLE Products (
    ProductId    INT64 NOT NULL,
    Name         STRING(255),
    NameSubstr   TOKENLIST AS (TOKENIZE_SUBSTRING(Name)) HIDDEN
) PRIMARY KEY (ProductId);

CREATE SEARCH INDEX idx_products_substr ON Products (NameSubstr);

-- Substring match (like ILIKE '%widget%')
SELECT ProductId, Name
FROM Products
WHERE SEARCH_SUBSTRING(NameSubstr, 'widget');

-- ============================================================
-- Numeric and other tokenizers
-- ============================================================

-- TOKENIZE_NUMBER for numeric search
-- TOKENIZE_BOOL for boolean search
-- TOKENIZE_NGRAMS for n-gram tokenization

-- ============================================================
-- Search index with STORING
-- ============================================================

CREATE SEARCH INDEX idx_search_with_data
    ON Articles (ContentTokens)
    STORING (Title, Content);

-- Note: Full-text search requires TOKENLIST columns and SEARCH indexes
-- Note: SEARCH() function uses search index for efficient lookup
-- Note: SCORE() function returns relevance score
-- Note: TOKENIZE_FULLTEXT for natural language, TOKENIZE_SUBSTRING for LIKE
-- Note: Unlike PostgreSQL, no tsvector/tsquery; uses TOKENLIST/SEARCH
-- Note: Full-text search is globally consistent
-- Note: Search indexes are managed separately from secondary indexes
