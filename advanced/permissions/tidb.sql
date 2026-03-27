-- TiDB: Permissions
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- Create user (same as MySQL)
CREATE USER 'alice'@'%' IDENTIFIED BY 'password123';
CREATE USER 'alice'@'localhost' IDENTIFIED BY 'password123';
CREATE USER 'alice'@'192.168.1.%' IDENTIFIED BY 'password123';

-- Roles (same as MySQL 8.0)
CREATE ROLE 'app_read', 'app_write';

-- Grant privileges (same as MySQL)
GRANT SELECT ON mydb.* TO 'alice'@'%';
GRANT SELECT, INSERT, UPDATE ON mydb.users TO 'alice'@'%';
GRANT ALL PRIVILEGES ON mydb.* TO 'alice'@'%';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%' WITH GRANT OPTION;

-- Column-level privileges (same as MySQL)
GRANT SELECT (username, email) ON mydb.users TO 'alice'@'%';

-- Role grants (same as MySQL 8.0)
GRANT SELECT ON mydb.* TO 'app_read';
GRANT INSERT, UPDATE, DELETE ON mydb.* TO 'app_write';
GRANT 'app_read', 'app_write' TO 'alice'@'%';
SET DEFAULT ROLE ALL TO 'alice'@'%';

-- Revoke (same as MySQL)
REVOKE INSERT ON mydb.users FROM 'alice'@'%';
REVOKE ALL PRIVILEGES ON mydb.* FROM 'alice'@'%';

-- View grants (same as MySQL)
SHOW GRANTS FOR 'alice'@'%';
SHOW GRANTS FOR CURRENT_USER;

-- Alter user (same as MySQL)
ALTER USER 'alice'@'%' IDENTIFIED BY 'new_password';
ALTER USER 'alice'@'%' PASSWORD EXPIRE INTERVAL 90 DAY;

-- Drop user (same as MySQL)
DROP USER IF EXISTS 'alice'@'%';

-- Flush privileges (same as MySQL, usually not needed)
FLUSH PRIVILEGES;

-- TiDB-specific: SUPER privilege and dynamic privileges
-- TiDB maps some MySQL privileges to its own dynamic privilege system

-- TiDB-specific: resource groups (7.0+)
-- Control resource allocation per user/session
CREATE RESOURCE GROUP rg_read
    RU_PER_SEC = 1000
    PRIORITY = LOW;

CREATE RESOURCE GROUP rg_write
    RU_PER_SEC = 2000
    PRIORITY = MEDIUM;

-- Assign resource group to user
ALTER USER 'alice'@'%' RESOURCE GROUP rg_read;

-- Or set resource group per session
SET RESOURCE GROUP rg_write;

-- TiDB-specific: placement policy privileges
-- Users need specific privileges to manage placement policies
GRANT PLACEMENT_ADMIN ON *.* TO 'admin'@'%';

-- TiDB-specific: BACKUP and RESTORE privileges
GRANT BACKUP_ADMIN ON *.* TO 'backup_user'@'%';
GRANT RESTORE_ADMIN ON *.* TO 'backup_user'@'%';

-- TiDB-specific: DASHBOARD_CLIENT privilege
-- Access to TiDB Dashboard
GRANT DASHBOARD_CLIENT ON *.* TO 'monitor'@'%';

-- TiDB-specific: SYSTEM_VARIABLES_ADMIN
-- Ability to modify system variables
GRANT SYSTEM_VARIABLES_ADMIN ON *.* TO 'admin'@'%';

-- TiDB-specific: RESTRICTED_TABLES_ADMIN
-- Access to system tables in mysql schema
GRANT RESTRICTED_TABLES_ADMIN ON *.* TO 'admin'@'%';

-- Authentication plugins
-- TiDB supports: mysql_native_password (default), caching_sha2_password, tidb_sm3_password
-- tidb_sm3_password: Chinese national encryption standard SM3 (TiDB-specific)
CREATE USER 'secure'@'%' IDENTIFIED WITH caching_sha2_password BY 'password123';

-- Limitations:
-- Same privilege model as MySQL with additional TiDB dynamic privileges
-- Resource groups for resource isolation (7.0+)
-- No partial revokes (MySQL 8.0 feature) in earlier TiDB versions
-- Password complexity validation available (same as MySQL)
-- Account locking supported: ALTER USER 'alice'@'%' ACCOUNT LOCK;
