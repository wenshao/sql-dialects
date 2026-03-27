-- Teradata: ALTER TABLE
--
-- 参考资料:
--   [1] Teradata SQL Reference
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates
--   [2] Teradata Database Documentation
--       https://docs.teradata.com/

-- Add column
ALTER TABLE users ADD bio VARCHAR(5000);

-- Add column with default
ALTER TABLE users ADD status INTEGER DEFAULT 1;

-- Drop column
ALTER TABLE users DROP bio;

-- Rename column (14.10+)
ALTER TABLE users RENAME phone TO mobile;

-- Rename table
RENAME TABLE users TO members;

-- Modify column type (widen)
ALTER TABLE users ADD email VARCHAR(500);
-- Note: Teradata typically requires ADD for widening; narrowing is restricted

-- Modify default value
ALTER TABLE users ALTER status DEFAULT 0;

-- Add NOT NULL constraint
ALTER TABLE users ALTER email NOT NULL;

-- Drop NOT NULL (set column to allow NULL)
ALTER TABLE users ALTER email NULL;

-- Add primary index (cannot alter PI; must recreate table)
-- Note: PRIMARY INDEX cannot be changed via ALTER TABLE
-- Workaround: CTAS with new PI
CREATE TABLE users_new AS (SELECT * FROM users) WITH DATA
PRIMARY INDEX (new_column);
DROP TABLE users;
RENAME TABLE users_new TO users;

-- Add/drop secondary index
CREATE INDEX idx_email ON users (email);
DROP INDEX idx_email ON users;

-- Add partitioning
ALTER TABLE events
ADD RANGE_N(event_date BETWEEN DATE '2024-01-01' AND DATE '2024-12-31' EACH INTERVAL '1' MONTH, NO RANGE);

-- Drop partition range
ALTER TABLE events DROP RANGE BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';

-- Add column with COMPRESS (save storage for common values)
ALTER TABLE users ADD city VARCHAR(100) COMPRESS ('Unknown', 'Beijing', 'Shanghai');

-- Modify table to SET/MULTISET
-- Note: cannot alter between SET and MULTISET; must recreate

-- COLLECT STATISTICS after schema changes
COLLECT STATISTICS ON users;
