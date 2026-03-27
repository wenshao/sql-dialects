-- Azure Synapse Analytics: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] Microsoft Docs - CREATE DATABASE (Synapse)
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-database-transact-sql?view=azure-sqldw-latest
--   [2] Microsoft Docs - Synapse SQL Access Control
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/access-control

-- ============================================================
-- Synapse 有两种池：
-- - 专用 SQL 池（Dedicated Pool）: 类似 SQL Server 语法
-- - 无服务器 SQL 池（Serverless Pool）: 查询外部数据
-- 命名层级: server > database > schema > object
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

-- 专用 SQL 池
CREATE DATABASE myapp;

CREATE DATABASE myapp
    COLLATE Latin1_General_100_BIN2_UTF8;       -- 推荐排序规则

-- 无服务器 SQL 池
CREATE DATABASE myapp
    COLLATE Latin1_General_100_BIN2_UTF8;

-- 修改数据库
ALTER DATABASE myapp SET RESULT_SET_CACHING ON;  -- 结果集缓存

-- 删除数据库
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;

-- 切换数据库
USE myapp;

-- ============================================================
-- 2. 模式管理
-- ============================================================

CREATE SCHEMA myschema;
CREATE SCHEMA myschema AUTHORIZATION dbo;

DROP SCHEMA myschema;

-- ============================================================
-- 3. 用户管理
-- ============================================================

-- Azure AD 用户（推荐）
CREATE USER [alice@example.com] FROM EXTERNAL PROVIDER;
CREATE USER [MyAzureADGroup] FROM EXTERNAL PROVIDER;

-- SQL 认证用户
CREATE USER myuser WITH PASSWORD = 'Secret123!';
CREATE USER myuser WITH PASSWORD = 'Secret123!',
    DEFAULT_SCHEMA = myschema;

-- 从登录创建用户
CREATE LOGIN mylogin WITH PASSWORD = 'Secret123!';
CREATE USER myuser FOR LOGIN mylogin;

-- 修改用户
ALTER USER myuser WITH DEFAULT_SCHEMA = myschema;

-- 删除用户
DROP USER myuser;

-- ============================================================
-- 4. 角色管理
-- ============================================================

-- 系统角色
-- db_owner, db_datareader, db_datawriter, db_ddladmin

ALTER ROLE db_datareader ADD MEMBER myuser;
ALTER ROLE db_datawriter ADD MEMBER myuser;

-- 自定义角色
CREATE ROLE analyst;
ALTER ROLE analyst ADD MEMBER myuser;
DROP ROLE analyst;

-- 工作区级别角色（Synapse 特有）
-- Synapse Administrator, SQL Administrator, Spark Administrator
-- 通过 Azure Portal 管理

-- ============================================================
-- 5. 权限管理
-- ============================================================

GRANT SELECT ON SCHEMA::myschema TO myuser;
GRANT SELECT ON dbo.users TO myuser;
GRANT INSERT, UPDATE, DELETE ON dbo.users TO myuser;
DENY DELETE ON dbo.users TO myuser;

-- 列权限
GRANT SELECT ON dbo.users (id, username) TO myuser;

REVOKE SELECT ON dbo.users FROM myuser;

-- 外部数据权限（无服务器池）
GRANT REFERENCES ON DATABASE SCOPED CREDENTIAL::my_credential TO myuser;

-- ============================================================
-- 6. 外部数据源（无服务器 SQL 池）
-- ============================================================

-- 数据库范围凭据
CREATE DATABASE SCOPED CREDENTIAL my_credential
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
     SECRET = 'sas_token_here';

-- 外部数据源
CREATE EXTERNAL DATA SOURCE my_adls
WITH (
    LOCATION = 'https://account.dfs.core.windows.net/container',
    CREDENTIAL = my_credential
);

-- 外部文件格式
CREATE EXTERNAL FILE FORMAT parquet_format
WITH (FORMAT_TYPE = PARQUET);

-- ============================================================
-- 7. 查询元数据
-- ============================================================

SELECT DB_NAME() AS current_db, SCHEMA_NAME() AS default_schema,
       USER_NAME() AS current_user;

SELECT name, state_desc FROM sys.databases;
SELECT name FROM sys.schemas;
SELECT name, type_desc FROM sys.database_principals;

SELECT * FROM sys.fn_my_permissions(NULL, 'DATABASE');
