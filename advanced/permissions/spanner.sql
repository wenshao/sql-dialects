-- Google Cloud Spanner: Permissions (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- Spanner uses Google Cloud IAM for access control
-- No SQL-level CREATE USER, GRANT, or REVOKE statements
-- Fine-grained access control (FGAC) available for row/column-level security

-- ============================================================
-- IAM roles (managed via Google Cloud Console, gcloud CLI, or API)
-- ============================================================

-- Predefined IAM roles:
-- roles/spanner.admin          -- Full admin access
-- roles/spanner.databaseAdmin  -- Database admin (DDL, but not instance)
-- roles/spanner.databaseReader -- Read-only access to databases
-- roles/spanner.databaseUser   -- Read/write access to databases
-- roles/spanner.viewer         -- View metadata only

-- Grant IAM role via gcloud CLI:
-- gcloud spanner databases add-iam-policy-binding mydb \
--     --instance=myinstance \
--     --member='user:alice@example.com' \
--     --role='roles/spanner.databaseReader'

-- ============================================================
-- Fine-grained access control (FGAC, 2022+)
-- ============================================================

-- Create database role
CREATE ROLE reader;
CREATE ROLE writer;
CREATE ROLE admin;

-- Grant table-level privileges
GRANT SELECT ON TABLE Users TO ROLE reader;
GRANT SELECT, INSERT, UPDATE ON TABLE Users TO ROLE writer;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE Users TO ROLE admin;

-- Grant on all tables
GRANT SELECT ON TABLE Users, Orders, Products TO ROLE reader;

-- Column-level privileges
GRANT SELECT (Username, Email) ON TABLE Users TO ROLE reader;
GRANT UPDATE (Email) ON TABLE Users TO ROLE writer;

-- ============================================================
-- Row-level security via views (workaround)
-- ============================================================

-- Create view for filtered access
CREATE VIEW UserView SQL SECURITY INVOKER AS
SELECT * FROM Users WHERE Region = 'us-east1';

GRANT SELECT ON VIEW UserView TO ROLE us_reader;

-- ============================================================
-- Change stream access
-- ============================================================

GRANT SELECT ON CHANGE STREAM UserChanges TO ROLE stream_reader;

-- ============================================================
-- Role hierarchy
-- ============================================================

-- Grant role to another role
GRANT reader TO ROLE writer;                   -- writer inherits reader
GRANT writer TO ROLE admin;                    -- admin inherits writer

-- Map IAM principal to database role:
-- gcloud spanner databases add-iam-policy-binding mydb \
--     --instance=myinstance \
--     --member='user:alice@example.com' \
--     --role='roles/spanner.fineGrainedAccessUser' \
--     --condition='expression=resource.name.endsWith("/databaseRoles/reader")'

-- ============================================================
-- Revoke privileges
-- ============================================================

REVOKE SELECT ON TABLE Users FROM ROLE reader;
REVOKE INSERT, UPDATE ON TABLE Users FROM ROLE writer;
REVOKE reader FROM ROLE writer;

-- ============================================================
-- Drop roles
-- ============================================================

DROP ROLE reader;
DROP ROLE IF EXISTS reader;

-- ============================================================
-- View privileges
-- ============================================================

SELECT * FROM INFORMATION_SCHEMA.TABLE_PRIVILEGES;
SELECT * FROM INFORMATION_SCHEMA.COLUMN_PRIVILEGES;

-- View roles
SELECT * FROM INFORMATION_SCHEMA.ROLES;
SELECT * FROM INFORMATION_SCHEMA.ROLE_TABLE_GRANTS;

-- Note: Primary access control is via Google Cloud IAM
-- Note: Fine-grained access control (FGAC) for table/column-level SQL grants
-- Note: No CREATE USER or ALTER USER in SQL (managed via IAM)
-- Note: No row-level security (RLS) policy syntax
-- Note: SQL SECURITY INVOKER views for filtered access
-- Note: Roles are database-scoped, not instance-scoped
-- Note: FGAC roles are mapped to IAM principals via conditions
