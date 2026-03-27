-- YugabyteDB: Full-Text Search (YSQL, v2.x+)
--
-- 参考资料:
--   [1] YugabyteDB YSQL Reference
--       https://docs.yugabyte.com/stable/api/ysql/
--   [2] YugabyteDB PostgreSQL Compatibility
--       https://docs.yugabyte.com/stable/explore/ysql-language-features/

-- YugabyteDB supports PostgreSQL-compatible full-text search

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

-- Trigram search (pg_trgm extension)
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_trgm ON articles USING GIN (content gin_trgm_ops);
SELECT * FROM articles WHERE content ILIKE '%datab%';
SELECT * FROM articles WHERE content % 'database';  -- similarity

-- Multi-column search
SELECT * FROM articles
WHERE to_tsvector('english', coalesce(title,'') || ' ' || coalesce(content,''))
    @@ to_tsquery('english', 'database & performance');

-- Note: Full-text search uses PostgreSQL's tsvector/tsquery system
-- Note: GIN index required for performance (distributed across tablets)
-- Note: Trigram (pg_trgm) supports LIKE/ILIKE with index
-- Note: websearch_to_tsquery supports Google-like search syntax
-- Note: Full-text search works across distributed tablets
-- Note: Based on PostgreSQL 11.2 full-text search implementation
