-- Flink SQL: Full-Text Search
--
-- 参考资料:
--   [1] Flink SQL Documentation
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/
--   [2] Flink SQL - Built-in Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/
--   [3] Flink SQL - Data Types
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/

-- Flink SQL has no built-in full-text search engine
-- Text search is done through string functions and pattern matching

-- LIKE pattern matching
SELECT * FROM articles WHERE content LIKE '%database%';
SELECT * FROM articles WHERE content LIKE '%database%performance%';

-- Case-insensitive search
SELECT * FROM articles WHERE LOWER(content) LIKE '%database%';

-- SIMILAR TO (SQL standard regex)
SELECT * FROM articles WHERE content SIMILAR TO '%(database|performance)%';

-- Regular expression matching
SELECT * FROM articles WHERE REGEXP(content, '(?i)database.*performance');

-- Multiple term search
SELECT * FROM articles
WHERE LOWER(content) LIKE '%database%'
  AND LOWER(content) LIKE '%performance%';

-- Position-based search
SELECT * FROM articles WHERE POSITION('database' IN LOWER(content)) > 0;

-- Streaming text search (filter events by content)
INSERT INTO matched_events
SELECT * FROM event_stream
WHERE LOWER(message) LIKE '%error%'
   OR LOWER(message) LIKE '%critical%';

-- Streaming pattern matching with regex
INSERT INTO alert_events
SELECT * FROM log_stream
WHERE REGEXP(message, '(?i)(error|exception|fatal).*timeout');

-- Elasticsearch integration (lookup/sink for search)
-- Elasticsearch sink for indexing searchable content
CREATE TABLE es_articles (
    id      BIGINT,
    title   STRING,
    content STRING,
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'elasticsearch-7',
    'hosts' = 'http://localhost:9200',
    'index' = 'articles'
);

-- Index streaming data into Elasticsearch
INSERT INTO es_articles
SELECT id, title, content FROM article_stream;

-- Then query Elasticsearch directly for full-text search

-- Hive catalog integration (for batch search on stored data)
-- Flink can read from Hive tables that have text content
-- Then use string functions for basic search

-- Real-time text matching on streams
INSERT INTO keyword_matches
SELECT
    event_id,
    user_id,
    message,
    CASE
        WHEN LOWER(message) LIKE '%error%' THEN 'error'
        WHEN LOWER(message) LIKE '%warning%' THEN 'warning'
        WHEN LOWER(message) LIKE '%info%' THEN 'info'
        ELSE 'other'
    END AS severity
FROM log_events;

-- MATCH_RECOGNIZE for complex pattern matching on streams
-- (for sequential pattern matching, not text search)
SELECT *
FROM event_stream
MATCH_RECOGNIZE (
    PARTITION BY user_id
    ORDER BY event_time
    MEASURES
        A.event_time AS start_time,
        C.event_time AS end_time,
        A.event_type AS first_event,
        C.event_type AS last_event
    ONE ROW PER MATCH
    AFTER MATCH SKIP PAST LAST ROW
    PATTERN (A B+ C)
    DEFINE
        A AS A.event_type = 'login',
        B AS B.event_type = 'page_view',
        C AS C.event_type = 'purchase'
);

-- Note: Flink has no built-in full-text search index
-- Note: Use LIKE, SIMILAR TO, and REGEXP for basic text matching
-- Note: For production full-text search, index data into Elasticsearch via Flink sink
-- Note: MATCH_RECOGNIZE is for event pattern matching (CEP), not text search
-- Note: String functions (POSITION, REGEXP, etc.) work in streaming mode
-- Note: For complex NLP, use Flink's UDF support with external libraries
