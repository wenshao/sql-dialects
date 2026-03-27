-- MariaDB: Permissions
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- Create user (same as MySQL)
CREATE USER 'alice'@'localhost' IDENTIFIED BY 'password123';
CREATE USER 'alice'@'%' IDENTIFIED BY 'password123';
CREATE USER 'alice'@'192.168.1.%' IDENTIFIED BY 'password123';

-- CREATE OR REPLACE USER (MariaDB-specific, 10.1.3+)
-- Not available in MySQL
CREATE OR REPLACE USER 'alice'@'%' IDENTIFIED BY 'password123';

-- Roles (10.0.5+, earlier than MySQL 8.0)
-- MariaDB supported roles before MySQL did
CREATE ROLE app_read;
CREATE ROLE app_write;

-- Grant privileges (same as MySQL)
GRANT SELECT ON mydb.* TO 'alice'@'localhost';
GRANT SELECT, INSERT, UPDATE ON mydb.users TO 'alice'@'localhost';
GRANT ALL PRIVILEGES ON mydb.* TO 'alice'@'localhost';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' WITH GRANT OPTION;

-- Column-level privileges (same as MySQL)
GRANT SELECT (username, email) ON mydb.users TO 'alice'@'localhost';

-- Role grants (10.0.5+)
GRANT SELECT ON mydb.* TO app_read;
GRANT INSERT, UPDATE, DELETE ON mydb.* TO app_write;
GRANT app_read, app_write TO 'alice'@'localhost';

-- Set default role (10.0.5+)
SET DEFAULT ROLE app_read FOR 'alice'@'localhost';

-- Set role in session (10.0.5+)
SET ROLE app_read;
SET ROLE NONE;

-- Roles: key differences from MySQL 8.0:
-- MariaDB roles do NOT have a host component (just role_name, not 'role'@'host')
-- MySQL 8.0 roles are user-like accounts with host
CREATE ROLE admin_role;  -- MariaDB: no @host
-- MySQL: CREATE ROLE 'admin_role'@'%';

-- Revoke (same as MySQL)
REVOKE INSERT ON mydb.users FROM 'alice'@'localhost';
REVOKE ALL PRIVILEGES ON mydb.* FROM 'alice'@'localhost';

-- View grants (same as MySQL)
SHOW GRANTS FOR 'alice'@'localhost';
SHOW GRANTS FOR CURRENT_USER;

-- Alter user (same as MySQL)
ALTER USER 'alice'@'localhost' IDENTIFIED BY 'new_password';

-- Password expiration (10.4.3+)
ALTER USER 'alice'@'localhost' PASSWORD EXPIRE;
ALTER USER 'alice'@'localhost' PASSWORD EXPIRE INTERVAL 90 DAY;
ALTER USER 'alice'@'localhost' PASSWORD EXPIRE NEVER;

-- Account locking (10.4.2+)
ALTER USER 'alice'@'localhost' ACCOUNT LOCK;
ALTER USER 'alice'@'localhost' ACCOUNT UNLOCK;

-- Drop user (same as MySQL)
DROP USER IF EXISTS 'alice'@'localhost';

-- Authentication plugins (MariaDB-specific options):
-- mysql_native_password (default)
-- ed25519 (MariaDB-specific, 10.1.22+, more secure than mysql_native_password)
-- unix_socket (MariaDB-specific, authenticate via OS user)
-- pam (10.0+)
-- gssapi (10.1+, Kerberos/SPNEGO)

-- ed25519 authentication (MariaDB-specific, more secure)
INSTALL SONAME 'auth_ed25519';
CREATE USER 'secure'@'%' IDENTIFIED VIA ed25519 USING PASSWORD('strong_password');

-- Unix socket authentication (MariaDB-specific)
-- Authenticate using the OS user running the client process
CREATE USER 'root'@'localhost' IDENTIFIED VIA unix_socket;
-- No password needed; must be logged in as OS user 'root'

-- Multiple authentication methods (10.4+, MariaDB-specific)
-- User can authenticate via any of the specified methods
CREATE USER 'alice'@'localhost' IDENTIFIED VIA
    ed25519 USING PASSWORD('password123')
    OR unix_socket;

-- IDENTIFIED VIA vs IDENTIFIED BY:
-- IDENTIFIED BY: password-based (same as MySQL)
-- IDENTIFIED VIA: plugin-based (MariaDB syntax for plugin authentication)

-- Flush privileges (same as MySQL)
FLUSH PRIVILEGES;

-- Differences from MySQL 8.0:
-- CREATE OR REPLACE USER (MariaDB-specific, 10.1.3+)
-- Roles supported since 10.0.5 (earlier than MySQL 8.0)
-- Roles have no host component (MySQL roles are user@host)
-- ed25519 authentication plugin (MariaDB-specific)
-- Unix socket authentication (MariaDB-specific)
-- Multiple authentication methods (10.4+, OR syntax)
-- No partial revokes (MySQL 8.0 feature)
-- Same core GRANT/REVOKE privilege model
-- Same column-level privilege support
