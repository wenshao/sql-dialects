-- SQL Server: 权限管理
--
-- 参考资料:
--   [1] SQL Server T-SQL - GRANT
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/grant-transact-sql
--   [2] SQL Server T-SQL - CREATE LOGIN
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-login-transact-sql
--   [3] SQL Server T-SQL - CREATE USER
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-user-transact-sql

-- 创建登录名（服务器级别）
CREATE LOGIN alice WITH PASSWORD = 'Password123!';
CREATE LOGIN alice WITH PASSWORD = 'Password123!',
    DEFAULT_DATABASE = mydb,
    CHECK_POLICY = ON;           -- 强制密码策略

-- 创建数据库用户（数据库级别）
USE mydb;
CREATE USER alice FOR LOGIN alice;
CREATE USER alice FOR LOGIN alice WITH DEFAULT_SCHEMA = dbo;

-- 授权
GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE ON users TO alice;
GRANT SELECT ON SCHEMA::dbo TO alice;                -- Schema 级别

-- 列级权限
GRANT SELECT (username, email) ON users TO alice;
GRANT UPDATE (email) ON users TO alice;

-- 角色
CREATE ROLE app_read;
CREATE ROLE app_write;
GRANT SELECT ON users TO app_read;
GRANT INSERT, UPDATE, DELETE ON users TO app_write;
ALTER ROLE app_read ADD MEMBER alice;
ALTER ROLE app_write ADD MEMBER alice;

-- 预定义数据库角色
ALTER ROLE db_datareader ADD MEMBER alice;            -- 所有表的 SELECT
ALTER ROLE db_datawriter ADD MEMBER alice;            -- 所有表的 INSERT/UPDATE/DELETE
ALTER ROLE db_owner ADD MEMBER alice;                 -- 完全权限

-- 预定义服务器角色
ALTER SERVER ROLE sysadmin ADD MEMBER alice;           -- 完全管理员
ALTER SERVER ROLE dbcreator ADD MEMBER alice;          -- 创建数据库

-- DENY（显式拒绝，优先级最高）
DENY DELETE ON users TO alice;
-- 即使 alice 通过角色获得了 DELETE 权限，DENY 也会覆盖

-- 撤销权限
REVOKE INSERT ON users FROM alice;
REVOKE SELECT ON SCHEMA::dbo FROM alice;

-- 查看权限
SELECT * FROM fn_my_permissions('users', 'OBJECT');
SELECT * FROM sys.database_permissions WHERE grantee_principal_id = USER_ID('alice');
EXEC sp_helpuser 'alice';

-- 修改密码
ALTER LOGIN alice WITH PASSWORD = 'NewPassword123!';
ALTER LOGIN alice WITH PASSWORD = 'NewPassword123!' OLD_PASSWORD = 'Password123!';

-- 行级安全（2016+）
CREATE FUNCTION dbo.fn_user_predicate(@username NVARCHAR(64))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS result WHERE @username = USER_NAME();

CREATE SECURITY POLICY user_filter
ADD FILTER PREDICATE dbo.fn_user_predicate(username) ON dbo.users,
ADD BLOCK PREDICATE dbo.fn_user_predicate(username) ON dbo.users
WITH (STATE = ON);

-- 动态数据掩码（2016+）
ALTER TABLE users ALTER COLUMN email ADD MASKED WITH (FUNCTION = 'email()');
ALTER TABLE users ALTER COLUMN phone ADD MASKED WITH (FUNCTION = 'partial(0,"XXX-",4)');
GRANT UNMASK TO alice;                                -- 允许看到原始数据

-- 2012+: CONTAINED DATABASE USERS（无需服务器级别登录）
CREATE USER alice WITH PASSWORD = 'Password123!';

-- 删除
DROP USER alice;
DROP LOGIN alice;
