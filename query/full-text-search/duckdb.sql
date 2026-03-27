-- DuckDB: Full-Text Search (v0.9+ with FTS extension)
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- Install and load the full-text search extension
INSTALL fts;
LOAD fts;

-- Create a full-text search index
PRAGMA create_fts_index('articles', 'id', 'title', 'content');

-- Options for FTS index
PRAGMA create_fts_index('articles', 'id', 'title', 'content',
    stemmer='english',
    stopwords='english',
    ignore='(\\.|[^a-z])+',
    strip_accents=1,
    lower=1,
    overwrite=1
);

-- Basic search using the FTS index
SELECT a.*, score
FROM (
    SELECT *, fts_main_articles.match_bm25(id, 'database performance') AS score
    FROM articles
) a
WHERE score IS NOT NULL
ORDER BY score DESC;

-- Search with stem matching
SELECT *, fts_main_articles.match_bm25(id, 'running') AS score
FROM articles
WHERE score IS NOT NULL
ORDER BY score DESC;

-- Drop FTS index
PRAGMA drop_fts_index('articles');

-- Without FTS extension: LIKE / ILIKE pattern matching
SELECT * FROM articles WHERE content LIKE '%database%';
SELECT * FROM articles WHERE content ILIKE '%DATABASE%';   -- Case insensitive

-- SIMILAR TO (SQL standard regex)
SELECT * FROM articles WHERE content SIMILAR TO '%(database|performance)%';

-- Regular expression matching
SELECT * FROM articles WHERE regexp_matches(content, 'data(base|set)');
SELECT * FROM articles WHERE content ~ 'data(base|set)';     -- PostgreSQL-style

-- CONTAINS (DuckDB-specific, substring check)
SELECT * FROM articles WHERE CONTAINS(content, 'database');

-- String search functions
SELECT * FROM articles WHERE POSITION('database' IN LOWER(content)) > 0;

-- Combining multiple search terms manually
SELECT * FROM articles
WHERE LOWER(content) LIKE '%database%'
  AND LOWER(content) LIKE '%performance%';

-- Levenshtein distance (fuzzy matching)
SELECT * FROM articles
WHERE levenshtein(LOWER(title), 'databse') <= 2;

-- Jaccard similarity
SELECT * FROM articles
WHERE jaccard(LOWER(title), 'database performance') > 0.3;

-- Note: DuckDB FTS extension uses BM25 ranking (Okapi BM25)
-- Note: FTS extension creates an inverted index with stemming and stopword removal
-- Note: Without FTS extension, use LIKE/ILIKE/regexp for basic text matching
-- Note: No built-in tsvector/tsquery like PostgreSQL
-- Note: FTS is designed for analytical use cases, not real-time search
-- Note: For production search, consider external search engines (Elasticsearch, etc.)
