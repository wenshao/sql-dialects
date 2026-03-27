-- DuckDB: Permissions
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- DuckDB does NOT support user authentication or permission management
-- As an embedded, in-process database, it runs within the application process
-- and inherits the application's security context

-- DuckDB's security model:

-- 1. File system security
-- Access control is managed by the OS file system permissions
-- The DuckDB database file (.duckdb) is protected by file permissions
-- chmod 600 my_database.duckdb   -- Only owner can read/write

-- 2. Read-only mode (open database in read-only)
-- ATTACH 'my_database.duckdb' (READ_ONLY);
-- Prevents any writes to the database

-- 3. Secrets management (v0.10+, for external credentials)
-- DuckDB has a secrets manager for external service credentials

-- Create a secret for S3 access
CREATE SECRET my_s3_secret (
    TYPE S3,
    KEY_ID 'AKIAIOSFODNN7EXAMPLE',
    SECRET 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
    REGION 'us-east-1'
);

-- Create a secret for HTTP bearer token
CREATE SECRET my_http_secret (
    TYPE HTTP,
    BEARER_TOKEN 'my-token-12345'
);

-- Temporary secret (session-scoped)
CREATE TEMPORARY SECRET session_secret (
    TYPE S3,
    KEY_ID 'AKIAIOSFODNN7EXAMPLE',
    SECRET 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
);

-- Persistent secret (stored in DuckDB config directory)
CREATE PERSISTENT SECRET prod_s3 (
    TYPE S3,
    KEY_ID 'AKIAIOSFODNN7EXAMPLE',
    SECRET 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
    SCOPE 's3://my-bucket'
);

-- List secrets
SELECT * FROM duckdb_secrets();

-- Drop secret
DROP SECRET my_s3_secret;
DROP SECRET IF EXISTS my_s3_secret;

-- 4. Extension security
-- Control which extensions can be loaded
-- SET allow_unsigned_extensions = false;  -- Default: only signed extensions

-- 5. Community extensions security
-- SET allow_community_extensions = true;  -- Allow community extensions

-- 6. Disable external access
-- SET enable_external_access = false;     -- Prevent file system and network access

-- 7. Attach with limited access
ATTACH 'analytics.duckdb' AS analytics (READ_ONLY);
-- The analytics database can only be read, not modified

-- 8. Views for data restriction (application-level access control)
-- Create views that limit what data users can see
CREATE VIEW public_users AS
SELECT id, username, city FROM users;  -- Hide email, phone, etc.

CREATE VIEW department_orders AS
SELECT * FROM orders WHERE department_id = 42;  -- Row-level filtering

-- 9. Application-level security patterns
-- In Python:
-- # Create a connection per user role
-- read_conn = duckdb.connect('db.duckdb', read_only=True)
-- admin_conn = duckdb.connect('db.duckdb', read_only=False)
-- # Use read_conn for regular users, admin_conn for admins

-- Note: No CREATE USER, CREATE ROLE, GRANT, or REVOKE statements
-- Note: No authentication mechanism (no passwords, no login)
-- Note: No row-level security (RLS) policies
-- Note: No column-level permissions
-- Note: Security is handled at the application and OS level
-- Note: Secrets manager handles credentials for external services (S3, HTTP)
-- Note: READ_ONLY attach mode is the primary write protection mechanism
-- Note: For multi-user scenarios, use application middleware for access control
