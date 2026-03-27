-- Google Cloud Spanner: Pagination (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- LIMIT / OFFSET
SELECT * FROM Users ORDER BY UserId LIMIT 10 OFFSET 20;

-- LIMIT only
SELECT * FROM Users ORDER BY UserId LIMIT 10;

-- Keyset pagination (cursor-based, recommended)
SELECT * FROM Users WHERE UserId > 100 ORDER BY UserId LIMIT 10;
-- More efficient than OFFSET for large tables

-- Keyset pagination with multiple columns
SELECT * FROM Users
WHERE (CreatedAt, UserId) > ('2024-01-15T10:00:00Z', 100)
ORDER BY CreatedAt, UserId
LIMIT 10;

-- Keyset pagination on interleaved tables
SELECT * FROM OrderItems
WHERE OrderId = 100 AND ItemId > 5
ORDER BY ItemId
LIMIT 10;
-- Very efficient because data is physically sorted by primary key

-- Window function pagination
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY UserId) AS rn
    FROM Users
) WHERE rn BETWEEN 21 AND 30;

-- Stale read for consistent pagination (Spanner-specific)
-- Bounded staleness: read data no older than 15 seconds
-- In client API: read_timestamp or max_staleness options
-- No SQL syntax for stale reads; configured at transaction level

-- Pagination with total count
SELECT *, COUNT(*) OVER () AS total_count
FROM Users
ORDER BY UserId
LIMIT 10 OFFSET 20;

-- Note: OFFSET is inefficient for large offsets (must scan skipped rows)
-- Note: Keyset (cursor) pagination is preferred
-- Note: Interleaved table scans are very efficient (data co-located and sorted)
-- Note: No FETCH FIRST ... ROWS ONLY syntax
-- Note: Stale reads configured at transaction level, not in SQL
-- Note: Primary key ordering determines physical data layout
