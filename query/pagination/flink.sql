-- Flink SQL: Pagination (Flink 1.11+)
--
-- 参考资料:
--   [1] Flink SQL Documentation
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/
--   [2] Flink SQL - Built-in Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/
--   [3] Flink SQL - Data Types
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/

-- LIMIT (batch mode only)
SELECT * FROM users ORDER BY id LIMIT 10;

-- LIMIT with OFFSET (Flink 1.15+, batch mode)
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- FETCH FIRST (SQL standard, Flink 1.15+, batch mode)
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- Window function pagination (batch mode)
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- Streaming Top-N (Flink-optimized pattern)
-- This is the streaming equivalent of pagination / top results
SELECT * FROM (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY sales DESC) AS rn
    FROM products
)
WHERE rn <= 10;

-- Streaming deduplication (keep latest per key)
SELECT * FROM (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY event_time DESC) AS rn
    FROM user_events
)
WHERE rn = 1;

-- Streaming: earliest N events per user
SELECT * FROM (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY event_time ASC) AS rn
    FROM user_events
)
WHERE rn <= 5;

-- Note: Traditional LIMIT/OFFSET only works in batch mode
-- Note: Streaming mode has no concept of "pages" (data is unbounded)
-- Note: In streaming mode, use Top-N pattern (ROW_NUMBER + filter) for bounded results
-- Note: Flink optimizes ROW_NUMBER + WHERE rn <= N into incremental Top-N operators
-- Note: ORDER BY without LIMIT is not supported in streaming mode
-- Note: Streaming pagination is typically done at the application layer
--       (e.g., query a materialized view or database sink)
