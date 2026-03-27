-- IBM Db2: Permissions
--
-- 参考资料:
--   [1] Db2 SQL Reference
--       https://www.ibm.com/docs/en/db2/11.5?topic=sql
--   [2] Db2 Built-in Functions
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in

-- Create user (OS-level, not SQL; Db2 relies on OS authentication)
-- Db2 users are OS users; create them at OS level first
-- Db2 Cloud: CREATE USER via admin console

-- Create role (Db2 9.5+)
CREATE ROLE app_read;
CREATE ROLE app_write;

-- Grant table privileges
GRANT SELECT ON TABLE users TO USER alice;
GRANT SELECT, INSERT, UPDATE ON TABLE users TO USER alice;
GRANT ALL PRIVILEGES ON TABLE users TO USER alice;

-- Column-level privileges
GRANT SELECT (username, email) ON TABLE users TO USER alice;
GRANT UPDATE (email) ON TABLE users TO USER alice;

-- Grant to role
GRANT SELECT ON TABLE users TO ROLE app_read;
GRANT INSERT, UPDATE, DELETE ON TABLE users TO ROLE app_write;

-- Assign role to user
GRANT ROLE app_read TO USER alice;
GRANT ROLE app_write TO USER alice;

-- Grant with admin option (role management)
GRANT ROLE app_read TO USER alice WITH ADMIN OPTION;

-- Schema privileges
GRANT CREATEIN ON SCHEMA myschema TO USER alice;
GRANT DROPIN ON SCHEMA myschema TO USER alice;
GRANT ALTERIN ON SCHEMA myschema TO USER alice;

-- Database privileges
GRANT CONNECT ON DATABASE TO USER alice;
GRANT CREATETAB ON DATABASE TO USER alice;
GRANT BINDADD ON DATABASE TO USER alice;

-- Sequence privileges
GRANT USAGE ON SEQUENCE seq_orders TO USER alice;

-- Routine privileges
GRANT EXECUTE ON PROCEDURE my_procedure TO USER alice;
GRANT EXECUTE ON FUNCTION my_function TO USER alice;

-- Package privileges
GRANT BIND ON PACKAGE my_package TO USER alice;
GRANT EXECUTE ON PACKAGE my_package TO USER alice;

-- Authorities (higher-level privileges)
GRANT DBADM ON DATABASE TO USER alice;          -- database admin
GRANT SECADM ON DATABASE TO USER alice;         -- security admin
GRANT DATAACCESS ON DATABASE TO USER alice;     -- full data access
GRANT ACCESSCTRL ON DATABASE TO USER alice;     -- access control admin
-- SYSADM, SYSCTRL, SYSMAINT: instance-level (set in DBM config)

-- Revoke privileges
REVOKE SELECT ON TABLE users FROM USER alice;
REVOKE ALL PRIVILEGES ON TABLE users FROM USER alice;
REVOKE ROLE app_read FROM USER alice;

-- View privileges
SELECT * FROM SYSCAT.TABAUTH WHERE GRANTEE = 'ALICE';
SELECT * FROM SYSCAT.DBAUTH WHERE GRANTEE = 'ALICE';
SELECT * FROM SYSCAT.ROLEAUTH WHERE GRANTEE = 'ALICE';

-- Row and Column Access Control (RCAC, Db2 10.1+)
-- Row permission
CREATE PERMISSION user_row_perm ON users
    FOR ROWS WHERE username = SESSION_USER
    ENFORCED FOR ALL ACCESS
    ENABLE;
ALTER TABLE users ACTIVATE ROW ACCESS CONTROL;

-- Column mask
CREATE MASK salary_mask ON employees
    FOR COLUMN salary RETURN
    CASE WHEN VERIFY_ROLE_FOR_USER(SESSION_USER, 'HR_ADMIN') = 1
         THEN salary
         ELSE 0
    END
    ENABLE;
ALTER TABLE employees ACTIVATE COLUMN ACCESS CONTROL;

-- Trusted contexts (multi-tier security)
CREATE TRUSTED CONTEXT app_ctx
    BASED UPON CONNECTION USING SYSTEM AUTHID app_user
    ATTRIBUTES (ADDRESS '192.168.1.100')
    DEFAULT ROLE app_read
    ENABLE;

-- Note: Db2 uses OS-level user authentication (no CREATE USER SQL)
-- Note: RCAC provides row and column level security
-- Note: authorities (DBADM, SECADM) provide admin-level access
-- Note: trusted contexts enable 3-tier application security
