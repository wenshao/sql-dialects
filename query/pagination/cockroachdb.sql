-- CockroachDB: Pagination (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- LIMIT / OFFSET (same as PostgreSQL)
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- SQL standard syntax (FETCH FIRST)
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- Keyset pagination (cursor-based, recommended for distributed systems)
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
-- More efficient than OFFSET for large datasets

-- Keyset pagination with multiple columns
SELECT * FROM users
WHERE (created_at, id) > ('2024-01-15 10:00:00', 100)
ORDER BY created_at, id
LIMIT 10;

-- Window function pagination
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- AS OF SYSTEM TIME for consistent pagination (CockroachDB-specific)
-- Prevents phantom reads across pages
SELECT * FROM users AS OF SYSTEM TIME '-10s'
WHERE id > 100 ORDER BY id LIMIT 10;
-- Using follower reads for lower latency

-- Pagination with total count
SELECT *, COUNT(*) OVER () AS total_count
FROM users
ORDER BY id
LIMIT 10 OFFSET 20;

-- Note: OFFSET is inefficient for large values (must scan skipped rows)
-- Note: Keyset (cursor) pagination is preferred for distributed databases
-- Note: AS OF SYSTEM TIME provides consistent snapshots across pages
-- Note: FETCH FIRST ... ROWS ONLY is SQL standard syntax
