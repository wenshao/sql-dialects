-- DuckDB: Indexes (v0.8+)
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- DuckDB uses ART (Adaptive Radix Tree) indexes
-- Indexes are optional; DuckDB uses zonemaps and min/max statistics automatically

-- Create index (ART index, default)
CREATE INDEX idx_age ON users (age);

-- Unique index
CREATE UNIQUE INDEX uk_email ON users (email);

-- Composite index
CREATE INDEX idx_city_age ON users (city, age);

-- IF NOT EXISTS
CREATE INDEX IF NOT EXISTS idx_age ON users (age);

-- Drop index
DROP INDEX idx_age;
DROP INDEX IF EXISTS idx_age;

-- Note: DuckDB creates indexes primarily for point lookups (equality queries)
-- For range scans and analytics, DuckDB relies on its columnar storage and
-- automatic zonemaps (min/max per column chunk) which are more efficient

-- Expression index (v0.9+)
CREATE INDEX idx_lower_email ON users (LOWER(email));

-- DuckDB-specific: ART indexes are best for:
-- 1. Primary key lookups
-- 2. Foreign key joins
-- 3. OLTP-like point queries on specific columns

-- DuckDB does NOT support:
-- Hash indexes, GIN indexes, GiST indexes, BRIN indexes
-- Partial indexes (WHERE clause on CREATE INDEX)
-- INCLUDE columns
-- Concurrent index creation (CONCURRENTLY)

-- Pragmas to inspect indexes
PRAGMA table_info('users');
PRAGMA database_size;

-- DuckDB storage info (alternative to index inspection)
SELECT * FROM duckdb_indexes();

-- Best practices:
-- 1. DuckDB rarely needs explicit indexes for analytical workloads
-- 2. Zonemaps handle range scans efficiently on sorted/clustered data
-- 3. Use indexes mainly for point lookups on unsorted columns
-- 4. For large joins, DuckDB's hash join is typically faster than indexed lookup
-- 5. Consider sorting data on insert for natural zonemap efficiency
