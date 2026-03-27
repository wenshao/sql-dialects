-- CockroachDB: Full-Text Search (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- CockroachDB supports PostgreSQL-compatible full-text search (v22.2+)

-- Basic search: tsvector + tsquery
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database & performance');

-- Operators
-- &: AND
-- |: OR
-- !: NOT
-- <->: adjacent (phrase search)
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'full <-> text <-> search');

-- Ranking
SELECT title,
    ts_rank(to_tsvector('english', content), to_tsquery('english', 'database')) AS rank
FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database')
ORDER BY rank DESC;

-- ts_rank_cd (cover density ranking)
SELECT title,
    ts_rank_cd(to_tsvector('english', content), to_tsquery('english', 'database & performance')) AS rank
FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database & performance')
ORDER BY rank DESC;

-- GIN index for full-text search
CREATE INDEX idx_ft ON articles USING GIN (to_tsvector('english', content));
-- Or CockroachDB INVERTED INDEX syntax:
CREATE INVERTED INDEX idx_ft2 ON articles (to_tsvector('english', content));

-- Stored tsvector column (avoid recomputation)
ALTER TABLE articles ADD COLUMN search_vector TSVECTOR
    GENERATED ALWAYS AS (to_tsvector('english', coalesce(title,'') || ' ' || coalesce(content,''))) STORED;
CREATE INDEX idx_search ON articles USING GIN (search_vector);

-- plainto_tsquery (spaces become AND)
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ plainto_tsquery('english', 'database performance');

-- phraseto_tsquery (phrase search)
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ phraseto_tsquery('english', 'full text search');

-- websearch_to_tsquery (search engine syntax)
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ websearch_to_tsquery('english', '"full text" -mysql');

-- Headline (highlight matches)
SELECT ts_headline('english', content, to_tsquery('english', 'database'),
    'StartSel=<b>, StopSel=</b>, MaxFragments=3')
FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database');

-- Trigram search (pg_trgm extension, v22.2+)
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_trgm ON articles USING GIN (content gin_trgm_ops);
SELECT * FROM articles WHERE content ILIKE '%datab%';
SELECT * FROM articles WHERE content % 'database';  -- similarity

-- Note: Full-text search uses PostgreSQL's tsvector/tsquery system
-- Note: GIN / INVERTED INDEX required for performance
-- Note: Trigram (pg_trgm) supports LIKE/ILIKE with index
-- Note: websearch_to_tsquery supports Google-like search syntax
-- Note: Full-text search works across distributed nodes
