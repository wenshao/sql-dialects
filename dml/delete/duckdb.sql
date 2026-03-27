-- DuckDB: DELETE (v0.8+)
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- Basic delete
DELETE FROM users WHERE username = 'alice';

-- USING clause (multi-table delete, PostgreSQL-compatible)
DELETE FROM users
USING blacklist
WHERE users.email = blacklist.email;

-- Subquery delete
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- RETURNING (v0.9+)
DELETE FROM users WHERE status = 0 RETURNING id, username;
DELETE FROM users WHERE age > 100 RETURNING *;

-- CTE + DELETE
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

-- CTE + DELETE + RETURNING (archive then delete)
WITH deleted AS (
    DELETE FROM users WHERE status = 0 RETURNING *
)
INSERT INTO users_archive SELECT * FROM deleted;

-- EXISTS subquery
DELETE FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- Delete all rows
DELETE FROM users;

-- TRUNCATE (faster, drops and recreates storage)
TRUNCATE TABLE users;

-- Drop and recreate (alternative for full clear)
CREATE OR REPLACE TABLE users AS SELECT * FROM users WHERE false;

-- Note: DuckDB supports full PostgreSQL-compatible DELETE syntax
-- Note: TRUNCATE is faster than DELETE for removing all rows
-- Note: No CASCADE option on TRUNCATE
-- Note: DELETE uses MVCC internally for consistency
-- Note: For bulk deletions, consider creating a new table without unwanted rows:
--       CREATE OR REPLACE TABLE users AS SELECT * FROM users WHERE status != 0;
