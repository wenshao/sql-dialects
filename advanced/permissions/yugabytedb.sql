-- YugabyteDB: Permissions (YSQL, v2.x+)
--
-- 参考资料:
--   [1] YugabyteDB YSQL Reference
--       https://docs.yugabyte.com/stable/api/ysql/
--   [2] YugabyteDB PostgreSQL Compatibility
--       https://docs.yugabyte.com/stable/explore/ysql-language-features/

-- YugabyteDB uses PostgreSQL-compatible role-based access control

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
GRANT USAGE ON SEQUENCE users_id_seq TO alice;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO alice;

-- Function privileges
GRANT EXECUTE ON FUNCTION my_function(INT) TO alice;

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
-- View privileges
-- ============================================================

\dp users                                       -- psql command
SELECT * FROM information_schema.role_table_grants WHERE grantee = 'alice';
SELECT * FROM pg_roles WHERE rolname = 'alice';

-- ============================================================
-- Manage users
-- ============================================================

-- Change password
ALTER ROLE alice WITH PASSWORD 'new_password';

-- Password expiration
ALTER ROLE alice VALID UNTIL '2025-12-31';

-- Login options
ALTER ROLE alice WITH LOGIN;
ALTER ROLE alice WITH NOLOGIN;

-- Superuser
ALTER ROLE alice WITH SUPERUSER;
ALTER ROLE alice WITH NOSUPERUSER;

-- Create database permission
ALTER ROLE alice WITH CREATEDB;

-- Create role permission
ALTER ROLE alice WITH CREATEROLE;

-- ============================================================
-- Row-level security (RLS, same as PostgreSQL)
-- ============================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Policy: users can only see their own rows
CREATE POLICY user_policy ON users
    USING (username = current_user);

-- Policy for INSERT
CREATE POLICY user_insert_policy ON users
    FOR INSERT
    WITH CHECK (username = current_user);

-- Policy for specific role
CREATE POLICY admin_policy ON users
    TO admin_role
    USING (true);                               -- admins see all rows

-- Drop policy
DROP POLICY user_policy ON users;

-- Disable RLS
ALTER TABLE users DISABLE ROW LEVEL SECURITY;

-- Force RLS on table owner too
ALTER TABLE users FORCE ROW LEVEL SECURITY;

-- ============================================================
-- Drop roles
-- ============================================================

DROP ROLE alice;
DROP ROLE IF EXISTS alice;

-- Note: Full PostgreSQL RBAC support
-- Note: Row-level security (RLS) supported
-- Note: Permissions are consistent across the distributed cluster
-- Note: SUPERUSER bypasses all permission checks
-- Note: No FLUSH PRIVILEGES needed; changes are immediate
-- Note: Based on PostgreSQL 11.2 permission model
-- Note: Tablespace-level permissions for geo-distributed access
