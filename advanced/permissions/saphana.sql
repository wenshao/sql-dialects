-- SAP HANA: Permissions
--
-- 参考资料:
--   [1] SAP HANA SQL Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/

-- Create user
CREATE USER alice PASSWORD Password123;
-- With specific options
CREATE USER bob PASSWORD Password456
    NO FORCE_FIRST_PASSWORD_CHANGE;

-- Create role
CREATE ROLE app_read;
CREATE ROLE app_write;

-- Grant table privileges
GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE ON users TO alice;
GRANT ALL PRIVILEGES ON users TO alice;

-- Column-level privileges
GRANT SELECT (username, email) ON users TO alice;
GRANT UPDATE (email) ON users TO alice;

-- Grant to role
GRANT SELECT ON users TO app_read;
GRANT INSERT, UPDATE, DELETE ON users TO app_write;

-- Assign role to user
GRANT app_read TO alice;
GRANT app_write TO alice;

-- Grant with admin option
GRANT app_read TO alice WITH ADMIN OPTION;

-- Schema privileges
GRANT SELECT ON SCHEMA myschema TO alice;
GRANT CREATE ANY ON SCHEMA myschema TO alice;
GRANT ALL PRIVILEGES ON SCHEMA myschema TO alice;

-- System privileges
GRANT CATALOG READ TO alice;           -- read system views
GRANT TRACE ADMIN TO alice;            -- manage traces
GRANT AUDIT ADMIN TO alice;            -- manage audit policies
GRANT USER ADMIN TO alice;             -- manage users
GRANT ROLE ADMIN TO alice;             -- manage roles
GRANT CREATE SCHEMA TO alice;
GRANT MONITOR ADMIN TO alice;
GRANT IMPORT TO alice;
GRANT EXPORT TO alice;

-- Application privilege (SAP HANA-specific)
GRANT EXECUTE ON _SYS_REPO.GRANT_ACTIVATED_ROLE TO alice;

-- Analytic privilege (control row-level access to analytic views)
CREATE STRUCTURED PRIVILEGE ap_region
    FOR SELECT ON my_calc_view
    RESTRICTION (region = 'APAC');
GRANT STRUCTURED PRIVILEGE ap_region TO alice;

-- Procedure privileges
GRANT EXECUTE ON PROCEDURE my_procedure TO alice;
GRANT EXECUTE ON FUNCTION my_function TO alice;

-- Debug privilege
GRANT DEBUG ON PROCEDURE my_procedure TO alice;

-- Revoke privileges
REVOKE SELECT ON users FROM alice;
REVOKE ALL PRIVILEGES ON users FROM alice;
REVOKE app_read FROM alice;

-- Modify user
ALTER USER alice PASSWORD NewPassword789;
ALTER USER alice DISABLE;
ALTER USER alice ENABLE;
ALTER USER alice RESET CONNECT ATTEMPTS;

-- Password policy
ALTER USER alice SET PARAMETER PASSWORD_LOCK_TIME = 1440;
ALTER USER alice SET PARAMETER PASSWORD_LIFETIME = 180;

-- Drop user
DROP USER alice;
DROP USER alice CASCADE;  -- also drop owned objects

-- View privileges
SELECT * FROM EFFECTIVE_PRIVILEGES WHERE USER_NAME = 'ALICE';
SELECT * FROM GRANTED_PRIVILEGES WHERE GRANTEE = 'ALICE';
SELECT * FROM GRANTED_ROLES WHERE GRANTEE = 'ALICE';

-- Audit policy
CREATE AUDIT POLICY audit_dml
    AUDITING ALL
    INSERT, UPDATE, DELETE ON users
    LEVEL INFO;
ALTER AUDIT POLICY audit_dml ENABLE;

-- Note: SAP HANA has structured privileges for row-level access control on views
-- Note: system privileges control administrative operations
-- Note: first login forces password change unless NO FORCE_FIRST_PASSWORD_CHANGE
-- Note: audit policies track data access and changes
