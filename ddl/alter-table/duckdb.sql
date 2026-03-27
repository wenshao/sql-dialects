-- DuckDB: ALTER TABLE (v0.8+)
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- Add column
ALTER TABLE users ADD COLUMN phone VARCHAR;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR;

-- Add column with default
ALTER TABLE users ADD COLUMN status INTEGER NOT NULL DEFAULT 1;

-- Drop column (v0.8+)
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMN IF EXISTS phone;

-- Rename column
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- Rename table
ALTER TABLE users RENAME TO members;

-- Change column type (v0.8+)
ALTER TABLE users ALTER COLUMN age SET DATA TYPE BIGINT;
ALTER TABLE users ALTER COLUMN age TYPE BIGINT;

-- Set / drop default
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- Set / drop NOT NULL (v0.8+)
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- Multiple operations in one statement are NOT supported
-- Must use separate ALTER TABLE statements:
ALTER TABLE users ADD COLUMN city VARCHAR;
ALTER TABLE users ADD COLUMN country VARCHAR;

-- Add column with complex types
ALTER TABLE users ADD COLUMN tags VARCHAR[];
ALTER TABLE users ADD COLUMN address STRUCT(street VARCHAR, city VARCHAR);
ALTER TABLE users ADD COLUMN meta MAP(VARCHAR, VARCHAR);

-- Note: No AFTER / FIRST clause; columns always added at the end
-- Note: No ALTER TABLE ... SET SCHEMA (schemas supported but no move operation)
-- Note: No ALTER TABLE ... ADD CONSTRAINT for foreign keys after creation
-- Note: Type changes may require compatible types or explicit USING not supported
-- Note: DuckDB is designed for analytics; schema changes are instant (metadata only)
