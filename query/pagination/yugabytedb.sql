-- YugabyteDB: Pagination (YSQL, v2.x+)
--
-- 参考资料:
--   [1] YugabyteDB YSQL Reference
--       https://docs.yugabyte.com/stable/api/ysql/
--   [2] YugabyteDB PostgreSQL Compatibility
--       https://docs.yugabyte.com/stable/explore/ysql-language-features/

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

-- Keyset on range-sharded tables (very efficient)
-- Table with PRIMARY KEY (id ASC) preserves order
SELECT * FROM events WHERE id > 1000 ORDER BY id LIMIT 10;

-- Keyset on hash-sharded tables (requires full scan + sort)
-- Table with PRIMARY KEY (id HASH) does not preserve order
-- Consider range sharding for pagination-heavy workloads

-- Window function pagination
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- Pagination with total count
SELECT *, COUNT(*) OVER () AS total_count
FROM users
ORDER BY id
LIMIT 10 OFFSET 20;

-- Cursor-based pagination (PostgreSQL-compatible)
BEGIN;
DECLARE user_cursor CURSOR FOR SELECT * FROM users ORDER BY id;
FETCH FORWARD 10 FROM user_cursor;
FETCH FORWARD 10 FROM user_cursor;            -- next page
CLOSE user_cursor;
COMMIT;

-- Note: OFFSET is inefficient for large values (must scan skipped rows)
-- Note: Keyset (cursor) pagination is preferred for distributed databases
-- Note: Range-sharded tables (ASC/DESC) are better for ordered pagination
-- Note: Hash-sharded tables require full scan + sort for ORDER BY on primary key
-- Note: FETCH FIRST ... ROWS ONLY is SQL standard syntax
-- Note: Declarative cursors supported for server-side pagination
