-- CockroachDB: Permissions (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- CockroachDB uses PostgreSQL-compatible role-based access control

-- ============================================================
-- Create users/roles
-- ============================================================

CREATE ROLE alice LOGIN PASSWORD 'password123';
CREATE USER alice WITH PASSWORD 'password123';  -- same as above
CREATE ROLE app_read;                           -- no login (group role)
CREATE ROLE app_write;

-- ============================================================
-- Grant privileges
-- ============================================================

-- Table privileges
GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE ON users TO alice;
GRANT ALL PRIVILEGES ON users TO alice;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO alice;

-- Column-level privileges
GRANT SELECT (username, email) ON users TO alice;
GRANT UPDATE (email) ON users TO alice;

-- Schema privileges
GRANT USAGE ON SCHEMA myschema TO alice;
GRANT CREATE ON SCHEMA myschema TO alice;

-- Database privileges
GRANT CONNECT ON DATABASE mydb TO alice;
GRANT CREATE ON DATABASE mydb TO alice;

-- Sequence privileges
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO alice;

-- Type privileges
GRANT USAGE ON TYPE status TO alice;

-- ============================================================
-- Role inheritance
-- ============================================================

GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_read;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_write;
GRANT app_read TO alice;
GRANT app_write TO alice;

-- ============================================================
-- Default privileges
-- ============================================================

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_read;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO app_read;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT INSERT, UPDATE, DELETE ON TABLES TO app_write;

-- ============================================================
-- Revoke privileges
-- ============================================================

REVOKE INSERT ON users FROM alice;
REVOKE ALL PRIVILEGES ON users FROM alice;
REVOKE app_read FROM alice;

-- ============================================================
-- System privileges (CockroachDB-specific)
-- ============================================================

-- Grant system-level privileges
GRANT admin TO alice;                          -- superuser
GRANT VIEWACTIVITY TO alice;                   -- view cluster activity
GRANT CANCELQUERY TO alice;                    -- cancel other users' queries
GRANT MODIFYCLUSTERSETTING TO alice;           -- change cluster settings
GRANT EXTERNALCONNECTION TO alice;             -- create external connections
GRANT VIEWDEBUG TO alice;                      -- view debug pages
GRANT VIEWCLUSTERMETADATA TO alice;            -- view cluster metadata

-- ============================================================
-- View privileges
-- ============================================================

SHOW GRANTS ON users;
SHOW GRANTS FOR alice;
SHOW ROLES;

SELECT * FROM information_schema.role_table_grants WHERE grantee = 'alice';

-- ============================================================
-- Manage users
-- ============================================================

-- Change password
ALTER ROLE alice WITH PASSWORD 'new_password';

-- Set password expiration
ALTER ROLE alice WITH PASSWORD 'password123' VALID UNTIL '2025-12-31';

-- Login options
ALTER ROLE alice WITH LOGIN;
ALTER ROLE alice WITH NOLOGIN;

-- Connection limit
ALTER ROLE alice WITH CONNECTION LIMIT 10;

-- ============================================================
-- Row-level security (not supported)
-- ============================================================

-- CockroachDB does NOT support row-level security (RLS)
-- Use views or application-level filtering instead

-- Alternative: view-based row filtering
CREATE VIEW alice_orders AS
SELECT * FROM orders WHERE user_id = (SELECT id FROM users WHERE username = current_user);
GRANT SELECT ON alice_orders TO alice;

-- ============================================================
-- Drop roles
-- ============================================================

DROP ROLE alice;
DROP ROLE IF EXISTS alice;

-- Note: PostgreSQL-compatible RBAC
-- Note: System privileges are CockroachDB-specific
-- Note: No row-level security (RLS)
-- Note: admin role is the superuser equivalent
-- Note: Privileges apply across the distributed cluster
-- Note: No FLUSH PRIVILEGES needed; changes are immediate
