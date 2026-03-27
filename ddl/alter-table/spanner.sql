-- Google Cloud Spanner: ALTER TABLE (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- Add column
ALTER TABLE Users ADD COLUMN Phone STRING(20);
ALTER TABLE Users ADD COLUMN IF NOT EXISTS Phone STRING(20);

-- Add column with default (2023+)
ALTER TABLE Users ADD COLUMN Status INT64 NOT NULL DEFAULT (0);

-- Add column with expression default
ALTER TABLE Users ADD COLUMN UpdatedAt TIMESTAMP DEFAULT (CURRENT_TIMESTAMP());

-- Drop column
ALTER TABLE Users DROP COLUMN Phone;

-- Rename column (not supported; must recreate)
-- Workaround: add new column, copy data, drop old column

-- Change column type (limited changes)
-- Can widen STRING(100) to STRING(200), but not shrink
ALTER TABLE Users ALTER COLUMN Bio STRING(MAX);

-- Set/drop NOT NULL
ALTER TABLE Users ALTER COLUMN Phone STRING(20) NOT NULL;  -- add NOT NULL
ALTER TABLE Users ALTER COLUMN Phone STRING(20);           -- drop NOT NULL

-- Set column default
ALTER TABLE Users ALTER COLUMN Status SET DEFAULT (1);

-- Add commit timestamp option
ALTER TABLE Users ALTER COLUMN UpdatedAt SET OPTIONS (allow_commit_timestamp = true);

-- Add foreign key
ALTER TABLE Orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (UserId) REFERENCES Users (UserId);

-- Drop constraint
ALTER TABLE Orders DROP CONSTRAINT fk_orders_user;

-- Add CHECK constraint (2022+)
ALTER TABLE Users ADD CONSTRAINT chk_age CHECK (Age >= 0 AND Age <= 150);

-- Add row deletion policy (TTL)
ALTER TABLE Events ADD ROW DELETION POLICY (OLDER_THAN(EventTime, INTERVAL 90 DAY));
ALTER TABLE Events DROP ROW DELETION POLICY;
ALTER TABLE Events REPLACE ROW DELETION POLICY (OLDER_THAN(EventTime, INTERVAL 30 DAY));

-- Add interleaving (not supported after creation)
-- INTERLEAVE must be specified at CREATE TABLE time

-- Rename table (not supported)
-- Must create new table, copy data, drop old table

-- Add stored generated column
ALTER TABLE Products ADD COLUMN TotalPrice NUMERIC
    AS (Price * Quantity) STORED;

-- Set/drop column options
ALTER TABLE Users ALTER COLUMN Email SET OPTIONS (
    allow_commit_timestamp = false
);

-- Note: Schema changes are executed in the background and can take minutes
-- Note: Cannot rename tables or columns
-- Note: Cannot change primary key after creation
-- Note: Cannot add INTERLEAVE after creation
-- Note: Type changes are limited to widening (e.g., STRING(100) to STRING(200))
-- Note: Adding NOT NULL column requires a default value
