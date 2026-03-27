-- CockroachDB: ALTER TABLE (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- Add column (same as PostgreSQL)
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20);

-- Add column with default and constraint
ALTER TABLE users ADD COLUMN status INT NOT NULL DEFAULT 1;

-- Drop column
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMN IF EXISTS phone;

-- Rename column
ALTER TABLE users RENAME COLUMN username TO user_name;

-- Change column type (limited type changes, requires rewrite)
ALTER TABLE users ALTER COLUMN age TYPE BIGINT;
ALTER TABLE users ALTER COLUMN bio TYPE VARCHAR(500);

-- Set/drop default
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- Set/drop NOT NULL
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;

-- Rename table
ALTER TABLE users RENAME TO members;

-- Add constraint
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id);

-- Add CHECK constraint
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 150);

-- Add UNIQUE constraint
ALTER TABLE users ADD CONSTRAINT uq_email UNIQUE (email);

-- Drop constraint
ALTER TABLE orders DROP CONSTRAINT fk_orders_user;
ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_age;

-- Validate constraint (same as PostgreSQL)
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT fk_orders_user;

-- Change primary key (CockroachDB-specific ALTER PRIMARY KEY)
ALTER TABLE users ALTER PRIMARY KEY USING COLUMNS (id, region);

-- Add hash-sharded index via ALTER
ALTER TABLE events ADD INDEX idx_ts (ts) USING HASH;

-- Set table locality (multi-region, v21.1+)
ALTER TABLE users SET LOCALITY REGIONAL BY ROW;
ALTER TABLE users SET LOCALITY GLOBAL;
ALTER TABLE users SET LOCALITY REGIONAL BY TABLE IN 'us-east1';

-- Column families
ALTER TABLE wide_table ADD COLUMN extra BYTES CREATE FAMILY f_extra;
ALTER TABLE wide_table ADD COLUMN more TEXT CREATE IF NOT EXISTS FAMILY f_extra;

-- Configure zone (replication/placement)
ALTER TABLE users CONFIGURE ZONE USING num_replicas = 5;
ALTER TABLE users CONFIGURE ZONE USING
    num_replicas = 5,
    gc.ttlseconds = 86400;

-- Schema changes
ALTER TABLE users SET SCHEMA myschema;

-- Note: Schema changes are online and non-blocking
-- Note: Some ALTER operations run as background schema changes
-- Note: ALTER PRIMARY KEY creates a new hidden rowid column if needed
-- Note: No ALTER TABLE ... ADD COLUMN with GENERATED ALWAYS AS (must recreate)
