-- DuckDB: Pagination (v0.8+)
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- LIMIT / OFFSET (standard)
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- LIMIT only
SELECT * FROM users ORDER BY id LIMIT 10;

-- SQL standard syntax (FETCH FIRST)
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- FETCH NEXT (same as FETCH FIRST)
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- Window function pagination
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- Keyset / cursor pagination (efficient for large offsets)
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- Keyset pagination with multiple sort columns
SELECT * FROM users
WHERE (created_at, id) > ('2024-01-15', 100)
ORDER BY created_at, id
LIMIT 10;

-- SAMPLE clause (DuckDB-specific: random sample instead of pagination)
SELECT * FROM users USING SAMPLE 10;           -- 10 rows
SELECT * FROM users USING SAMPLE 10%;          -- 10% of rows
SELECT * FROM users USING SAMPLE 10 ROWS;      -- 10 rows (explicit)

-- Sampling methods
SELECT * FROM users USING SAMPLE reservoir(10);  -- Reservoir sampling
SELECT * FROM users USING SAMPLE system(10%);    -- System sampling (block-level)
SELECT * FROM users USING SAMPLE bernoulli(10%); -- Bernoulli sampling (row-level)

-- TABLESAMPLE (SQL standard syntax)
SELECT * FROM users TABLESAMPLE reservoir(10 ROWS);

-- ORDER BY ALL (DuckDB-specific: order by all columns left-to-right)
SELECT * FROM users ORDER BY ALL;
SELECT * FROM users ORDER BY ALL DESC;

-- Note: DuckDB supports both LIMIT/OFFSET and FETCH FIRST syntax
-- Note: For large tables, keyset pagination is much faster than OFFSET
-- Note: SAMPLE is useful for analytical exploration (not deterministic pagination)
-- Note: No server-side cursor-based pagination (DuckDB is embedded)
