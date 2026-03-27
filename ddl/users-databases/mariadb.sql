-- MariaDB: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] MariaDB Documentation - CREATE DATABASE
--       https://mariadb.com/kb/en/create-database/
--   [2] MariaDB Documentation - CREATE USER
--       https://mariadb.com/kb/en/create-user/

-- ============================================================
-- MariaDB 与 MySQL 类似: DATABASE 和 SCHEMA 是同义词
-- 命名层级: server > database(schema) > object
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;

CREATE DATABASE myapp
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci
    COMMENT 'Main application database';        -- MariaDB 特有: 数据库注释

-- SCHEMA 是同义词
CREATE SCHEMA myapp;

-- 修改数据库
ALTER DATABASE myapp CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

-- 删除数据库
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;

-- 切换数据库
USE myapp;

-- 查看数据库
SHOW DATABASES;
SHOW CREATE DATABASE myapp;

-- ============================================================
-- 2. 用户管理
-- ============================================================

CREATE USER 'myuser'@'%' IDENTIFIED BY 'secret123';
CREATE USER IF NOT EXISTS 'myuser'@'%' IDENTIFIED BY 'secret123';

-- 认证插件
CREATE USER 'myuser'@'%' IDENTIFIED VIA mysql_native_password
    USING PASSWORD('secret123');
CREATE USER 'myuser'@'%' IDENTIFIED VIA ed25519
    USING PASSWORD('secret123');                 -- MariaDB 推荐

-- PAM 认证
-- CREATE USER 'myuser'@'%' IDENTIFIED VIA pam;

-- 修改用户
ALTER USER 'myuser'@'%' IDENTIFIED BY 'newsecret';
ALTER USER 'myuser'@'%' ACCOUNT LOCK;
ALTER USER 'myuser'@'%' ACCOUNT UNLOCK;
ALTER USER 'myuser'@'%' PASSWORD EXPIRE;

RENAME USER 'myuser'@'%' TO 'newuser'@'%';

-- 删除用户
DROP USER 'myuser'@'%';
DROP USER IF EXISTS 'myuser'@'%';

-- ============================================================
-- 3. 角色管理（MariaDB 10.0.5+）
-- ============================================================

CREATE ROLE analyst;
CREATE ROLE developer;

GRANT SELECT ON myapp.* TO analyst;
GRANT ALL ON myapp.* TO developer;

-- 授予角色给用户
GRANT analyst TO 'myuser'@'%';
SET DEFAULT ROLE analyst FOR 'myuser'@'%';

-- 激活角色
SET ROLE analyst;
SET ROLE ALL;                                   -- 所有已授予角色

-- 删除角色
DROP ROLE analyst;

-- ============================================================
-- 4. 权限管理
-- ============================================================

-- 全局权限
GRANT ALL PRIVILEGES ON *.* TO 'myuser'@'%' WITH GRANT OPTION;

-- 数据库级
GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.* TO 'myuser'@'%';

-- 表级
GRANT SELECT ON myapp.users TO 'myuser'@'%';

-- 列级
GRANT SELECT (id, username) ON myapp.users TO 'myuser'@'%';

-- 查看权限
SHOW GRANTS FOR 'myuser'@'%';

-- 收回权限
REVOKE INSERT ON myapp.* FROM 'myuser'@'%';

FLUSH PRIVILEGES;

-- ============================================================
-- 5. 查询元数据
-- ============================================================

SELECT DATABASE(), USER(), CURRENT_USER();

SELECT user, host, is_role, account_locked FROM mysql.user;

SELECT schema_name, default_character_set_name
FROM information_schema.schemata;

-- MariaDB 特有系统表
SELECT * FROM information_schema.applicable_roles;

-- ============================================================
-- 6. 资源限制
-- ============================================================

-- 用户级资源限制
CREATE USER 'myuser'@'%' IDENTIFIED BY 'secret123'
    WITH MAX_QUERIES_PER_HOUR 1000
         MAX_UPDATES_PER_HOUR 500
         MAX_CONNECTIONS_PER_HOUR 100
         MAX_USER_CONNECTIONS 10;

-- 全局设置
SET GLOBAL max_connections = 200;
