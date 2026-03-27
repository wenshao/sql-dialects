-- MySQL: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] MySQL Reference Manual - CREATE DATABASE
--       https://dev.mysql.com/doc/refman/8.0/en/create-database.html
--   [2] MySQL Reference Manual - CREATE USER
--       https://dev.mysql.com/doc/refman/8.0/en/create-user.html

-- ============================================================
-- MySQL 中 DATABASE 和 SCHEMA 是同义词
-- 命名层级: server > database(schema) > object
-- 没有独立的 schema 层，一个 database 就是一个 schema
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;

CREATE DATABASE myapp
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

-- SCHEMA 是 DATABASE 的同义词
CREATE SCHEMA myapp;

-- 修改数据库
ALTER DATABASE myapp CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
ALTER DATABASE myapp READ ONLY = 1;             -- MySQL 8.0.22+

-- 删除数据库
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;

-- 切换数据库
USE myapp;

-- 查看数据库
SHOW DATABASES;
SHOW DATABASES LIKE 'my%';

-- ============================================================
-- 2. 用户管理
-- ============================================================

CREATE USER 'myuser'@'localhost' IDENTIFIED BY 'secret123';
CREATE USER 'myuser'@'%' IDENTIFIED BY 'secret123';         -- 允许任意主机
CREATE USER IF NOT EXISTS 'myuser'@'%' IDENTIFIED BY 'secret123';

-- 高级选项（MySQL 8.0+）
CREATE USER 'myuser'@'%'
    IDENTIFIED BY 'secret123'
    DEFAULT ROLE analyst                        -- 默认角色
    PASSWORD EXPIRE INTERVAL 90 DAY             -- 密码过期
    FAILED_LOGIN_ATTEMPTS 3                     -- 登录失败锁定
    PASSWORD_LOCK_TIME 1                        -- 锁定天数
    ACCOUNT LOCK;                               -- 初始锁定

-- 修改用户
ALTER USER 'myuser'@'%' IDENTIFIED BY 'newsecret';
ALTER USER 'myuser'@'%' ACCOUNT UNLOCK;
ALTER USER 'myuser'@'%' PASSWORD EXPIRE;
RENAME USER 'myuser'@'%' TO 'newuser'@'%';

-- 删除用户
DROP USER 'myuser'@'%';
DROP USER IF EXISTS 'myuser'@'%';

-- ============================================================
-- 3. 角色管理（MySQL 8.0+）
-- ============================================================

CREATE ROLE 'analyst', 'developer', 'admin';

GRANT SELECT ON myapp.* TO 'analyst';
GRANT ALL ON myapp.* TO 'developer';

GRANT 'analyst' TO 'myuser'@'%';
SET DEFAULT ROLE 'analyst' TO 'myuser'@'%';

-- 激活角色（当前会话）
SET ROLE 'analyst';
SET ROLE ALL;

DROP ROLE 'analyst';

-- ============================================================
-- 4. 权限管理
-- ============================================================

-- 全局权限
GRANT ALL PRIVILEGES ON *.* TO 'myuser'@'%' WITH GRANT OPTION;

-- 数据库级权限
GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.* TO 'myuser'@'%';

-- 表级权限
GRANT SELECT ON myapp.users TO 'myuser'@'%';

-- 列级权限
GRANT SELECT (id, username) ON myapp.users TO 'myuser'@'%';

-- 查看权限
SHOW GRANTS FOR 'myuser'@'%';

-- 收回权限
REVOKE INSERT ON myapp.* FROM 'myuser'@'%';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'myuser'@'%';

-- 刷新权限（修改权限表后）
FLUSH PRIVILEGES;

-- ============================================================
-- 5. 查询元数据
-- ============================================================

-- 当前数据库和用户
SELECT DATABASE(), USER(), CURRENT_USER();

-- 查看所有用户
SELECT user, host, account_locked FROM mysql.user;

-- 系统变量
SHOW VARIABLES LIKE 'character_set_database';
SHOW VARIABLES LIKE 'collation%';

-- information_schema
SELECT schema_name, default_character_set_name
FROM information_schema.schemata;

-- ============================================================
-- 6. 数据库级别设置
-- ============================================================

-- MySQL 没有数据库级别的参数设置
-- 全局设置影响所有数据库
SET GLOBAL max_connections = 200;
SET SESSION wait_timeout = 28800;

-- 注意：MySQL 中没有 PostgreSQL 那样的 search_path
-- 必须通过 USE database 或 database.table 来指定
