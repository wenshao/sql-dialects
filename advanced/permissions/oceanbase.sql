-- OceanBase: Permissions
-- OceanBase has dual mode: MySQL mode and Oracle mode. Both shown where relevant.
--
-- 参考资料:
--   [1] OceanBase SQL Reference (MySQL Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase SQL Reference (Oracle Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- MySQL Mode (same as MySQL)
-- ============================================================

-- Create user
CREATE USER 'alice'@'%' IDENTIFIED BY 'password123';
CREATE USER 'alice'@'localhost' IDENTIFIED BY 'password123';

-- Roles
CREATE ROLE 'app_read', 'app_write';

-- Grant privileges
GRANT SELECT ON mydb.* TO 'alice'@'%';
GRANT SELECT, INSERT, UPDATE ON mydb.users TO 'alice'@'%';
GRANT ALL PRIVILEGES ON mydb.* TO 'alice'@'%';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%' WITH GRANT OPTION;

-- Column-level privileges
GRANT SELECT (username, email) ON mydb.users TO 'alice'@'%';

-- Role grants
GRANT SELECT ON mydb.* TO 'app_read';
GRANT INSERT, UPDATE, DELETE ON mydb.* TO 'app_write';
GRANT 'app_read', 'app_write' TO 'alice'@'%';
SET DEFAULT ROLE ALL TO 'alice'@'%';

-- Revoke
REVOKE INSERT ON mydb.users FROM 'alice'@'%';

-- View grants
SHOW GRANTS FOR 'alice'@'%';

-- Alter user
ALTER USER 'alice'@'%' IDENTIFIED BY 'new_password';

-- Drop user
DROP USER IF EXISTS 'alice'@'%';

-- OceanBase-specific: tenant-level administration (MySQL mode)
-- OceanBase has multi-tenancy: each tenant is an isolated database instance
-- sys tenant: manages the cluster
-- user tenants: isolated MySQL or Oracle mode instances

-- Cluster admin (sys tenant)
-- CREATE TENANT creates an isolated database instance
-- Users within a tenant cannot see other tenants' data

-- ============================================================
-- Oracle Mode
-- ============================================================

-- Create user (Oracle syntax)
CREATE USER alice IDENTIFIED BY password123;

-- User with default/temporary tablespace
CREATE USER alice IDENTIFIED BY password123
    DEFAULT TABLESPACE users_ts
    TEMPORARY TABLESPACE temp_ts;

-- Grant system privileges
GRANT CREATE SESSION TO alice;           -- connect privilege
GRANT CREATE TABLE TO alice;
GRANT CREATE VIEW TO alice;
GRANT CREATE PROCEDURE TO alice;
GRANT CREATE SEQUENCE TO alice;
GRANT CREATE TRIGGER TO alice;

-- Grant object privileges
GRANT SELECT ON mydb.users TO alice;
GRANT SELECT, INSERT, UPDATE ON mydb.users TO alice;
GRANT ALL ON mydb.users TO alice;

-- Column-level privileges (Oracle mode)
GRANT SELECT (username, email) ON mydb.users TO alice;
GRANT UPDATE (email) ON mydb.users TO alice;

-- Grant with GRANT OPTION (pass privilege to others)
GRANT SELECT ON mydb.users TO alice WITH GRANT OPTION;

-- Roles (Oracle mode)
CREATE ROLE app_readonly;
CREATE ROLE app_readwrite;

GRANT SELECT ON mydb.users TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON mydb.users TO app_readwrite;
GRANT app_readonly TO alice;
GRANT app_readwrite TO alice;

-- Default role
ALTER USER alice DEFAULT ROLE app_readonly;

-- Activate roles in session
SET ROLE app_readwrite;
SET ROLE ALL;
SET ROLE ALL EXCEPT app_readwrite;
SET ROLE NONE;

-- Grant DBA role (full administrative privileges)
GRANT DBA TO alice;

-- Revoke (Oracle syntax)
REVOKE CREATE TABLE FROM alice;
REVOKE SELECT ON mydb.users FROM alice;
REVOKE app_readonly FROM alice;

-- View privileges
SELECT * FROM USER_SYS_PRIVS;            -- system privileges for current user
SELECT * FROM USER_TAB_PRIVS;            -- object privileges for current user
SELECT * FROM USER_ROLE_PRIVS;           -- roles for current user
SELECT * FROM DBA_SYS_PRIVS WHERE GRANTEE = 'ALICE';
SELECT * FROM DBA_TAB_PRIVS WHERE GRANTEE = 'ALICE';

-- Password management (Oracle mode)
ALTER USER alice IDENTIFIED BY new_password;
-- Profile for password policy
CREATE PROFILE strict_profile LIMIT
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LIFE_TIME 90
    PASSWORD_REUSE_MAX 5
    PASSWORD_LOCK_TIME 1;
ALTER USER alice PROFILE strict_profile;

-- Drop user
DROP USER alice CASCADE;  -- CASCADE drops all objects owned by user

-- Public synonym (Oracle mode)
CREATE PUBLIC SYNONYM users_syn FOR mydb.users;
GRANT SELECT ON users_syn TO PUBLIC;

-- Limitations:
-- MySQL mode: same as MySQL privilege model
-- Oracle mode: Oracle-compatible privilege model
-- Multi-tenancy: users isolated within tenants
-- Cluster-level vs tenant-level administration
-- Some advanced Oracle security features may have limited support
