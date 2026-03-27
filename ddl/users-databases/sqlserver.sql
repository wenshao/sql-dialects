-- SQL Server: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] Microsoft Docs - CREATE DATABASE
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-database-transact-sql
--   [2] Microsoft Docs - CREATE USER / LOGIN
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-user-transact-sql

-- ============================================================
-- SQL Server 命名层级: server > database > schema > object
-- 默认模式: dbo
-- 登录(Login)与用户(User)分离
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

CREATE DATABASE myapp;

CREATE DATABASE myapp
ON PRIMARY (
    NAME = myapp_data,
    FILENAME = 'C:\Data\myapp.mdf',
    SIZE = 100MB,
    MAXSIZE = 10GB,
    FILEGROWTH = 100MB
)
LOG ON (
    NAME = myapp_log,
    FILENAME = 'C:\Data\myapp_log.ldf',
    SIZE = 50MB,
    MAXSIZE = 5GB,
    FILEGROWTH = 50MB
);

-- 修改数据库
ALTER DATABASE myapp SET RECOVERY FULL;         -- 恢复模式
ALTER DATABASE myapp SET READ_ONLY;
ALTER DATABASE myapp SET READ_WRITE;
ALTER DATABASE myapp SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
ALTER DATABASE myapp SET MULTI_USER;
ALTER DATABASE myapp MODIFY NAME = myapp_v2;

-- 删除数据库
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;                  -- SQL Server 2016+

-- 切换数据库
USE myapp;

-- ============================================================
-- 2. 模式管理
-- ============================================================

CREATE SCHEMA myschema;
CREATE SCHEMA myschema AUTHORIZATION myuser;

-- 删除模式（必须为空）
DROP SCHEMA myschema;

-- 转移对象到另一个模式
ALTER SCHEMA newschema TRANSFER dbo.users;

-- 默认模式：dbo（database owner）
-- 每个用户可以有不同的默认模式

-- ============================================================
-- 3. 登录与用户管理
-- ============================================================

-- SQL Server 区分 Login（服务器级）和 User（数据库级）

-- 创建服务器登录
CREATE LOGIN mylogin WITH PASSWORD = 'Secret123!';
CREATE LOGIN mylogin WITH PASSWORD = 'Secret123!',
    DEFAULT_DATABASE = myapp,
    CHECK_POLICY = ON,                          -- 密码策略
    CHECK_EXPIRATION = ON;

-- Windows 认证登录
-- CREATE LOGIN [DOMAIN\username] FROM WINDOWS;

-- 创建数据库用户（映射到登录）
USE myapp;
CREATE USER myuser FOR LOGIN mylogin;
CREATE USER myuser FOR LOGIN mylogin WITH DEFAULT_SCHEMA = myschema;

-- 没有登录的用户（仅数据库内使用）
CREATE USER app_user WITHOUT LOGIN;

-- Azure AD 用户（Azure SQL）
-- CREATE USER [alice@example.com] FROM EXTERNAL PROVIDER;

-- 修改用户
ALTER USER myuser WITH DEFAULT_SCHEMA = myschema;
ALTER USER myuser WITH LOGIN = mylogin;

-- 修改登录
ALTER LOGIN mylogin WITH PASSWORD = 'NewSecret456!';
ALTER LOGIN mylogin DISABLE;
ALTER LOGIN mylogin ENABLE;

-- 删除
DROP USER myuser;
DROP LOGIN mylogin;

-- ============================================================
-- 4. 角色管理
-- ============================================================

-- 固定服务器角色
-- sysadmin, serveradmin, securityadmin, dbcreator, bulkadmin ...

-- 固定数据库角色
-- db_owner, db_datareader, db_datawriter, db_ddladmin ...

-- 添加到固定角色
ALTER SERVER ROLE sysadmin ADD MEMBER mylogin;
ALTER ROLE db_datareader ADD MEMBER myuser;
ALTER ROLE db_datawriter ADD MEMBER myuser;

-- 自定义数据库角色
CREATE ROLE analyst;
ALTER ROLE analyst ADD MEMBER myuser;
DROP ROLE analyst;

-- ============================================================
-- 5. 权限管理
-- ============================================================

-- 服务器权限
GRANT CREATE ANY DATABASE TO mylogin;

-- 数据库权限
GRANT SELECT ON SCHEMA::myschema TO myuser;
GRANT EXECUTE ON SCHEMA::myschema TO myuser;
GRANT CREATE TABLE TO myuser;

-- 表权限
GRANT SELECT ON dbo.users TO myuser;
GRANT INSERT, UPDATE, DELETE ON dbo.users TO myuser;
DENY DELETE ON dbo.users TO myuser;            -- 显式拒绝

-- 列权限
GRANT SELECT ON dbo.users (id, username) TO myuser;

-- 收回
REVOKE SELECT ON dbo.users FROM myuser;

-- ============================================================
-- 6. 查询元数据
-- ============================================================

-- 列出数据库
SELECT name, state_desc, recovery_model_desc FROM sys.databases;

-- 列出模式
SELECT name FROM sys.schemas;

-- 列出登录
SELECT name, type_desc, is_disabled FROM sys.server_principals;

-- 列出用户
SELECT name, type_desc, default_schema_name FROM sys.database_principals;

-- 当前上下文
SELECT DB_NAME() AS current_db, SCHEMA_NAME() AS default_schema,
       USER_NAME() AS current_user, SUSER_NAME() AS login_name;

-- 查看权限
SELECT * FROM fn_my_permissions(NULL, 'DATABASE');
SELECT * FROM fn_my_permissions('dbo.users', 'OBJECT');

-- ============================================================
-- 7. 数据库级别设置
-- ============================================================

-- 数据库范围配置（SQL Server 2016+）
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 4;
ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = OFF;
ALTER DATABASE SCOPED CONFIGURATION SET QUERY_OPTIMIZER_HOTFIXES = ON;

-- 兼容级别
ALTER DATABASE myapp SET COMPATIBILITY_LEVEL = 160;  -- SQL Server 2022
