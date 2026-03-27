-- SQL Server: 权限管理（Login/User + RLS + Dynamic Data Masking）
--
-- 参考资料:
--   [1] SQL Server - Security
--       https://learn.microsoft.com/en-us/sql/relational-databases/security/authentication-access/getting-started-with-database-engine-permissions

-- ============================================================
-- 1. Login/User 双层模型（详见 users-databases 章节）
-- ============================================================

CREATE LOGIN alice WITH PASSWORD = 'Password123!', CHECK_POLICY = ON;
USE mydb;
CREATE USER alice FOR LOGIN alice WITH DEFAULT_SCHEMA = dbo;

-- ============================================================
-- 2. GRANT / DENY / REVOKE 三态权限
-- ============================================================

GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE ON users TO alice;
GRANT SELECT ON SCHEMA::dbo TO alice;

-- DENY: SQL Server 独有的"显式拒绝"——优先级最高
DENY DELETE ON users TO alice;
-- 即使 alice 通过 db_datawriter 角色获得了 DELETE 权限，DENY 也会覆盖

REVOKE INSERT ON users FROM alice;

-- 设计分析（对引擎开发者）:
--   SQL Server 的三态权限模型: GRANT(授予) + DENY(拒绝) + REVOKE(撤销)
--   DENY 是关键差异——大多数数据库只有 GRANT 和 REVOKE:
--     PostgreSQL: 无 DENY（通过不授予权限实现拒绝）
--     MySQL:      无 DENY
--     Oracle:     无 DENY
--
--   DENY 的价值: 在复杂的角色继承中，精确控制"某用户不能做某事"。
--   DENY 的风险: 权限调试困难——用户可能被某个角色的 DENY 影响而不自知。

-- 列级权限
GRANT SELECT (id, username) ON users TO alice;
GRANT UPDATE (email) ON users TO alice;

-- ============================================================
-- 3. 角色体系
-- ============================================================

-- 固定数据库角色（内置）
ALTER ROLE db_datareader ADD MEMBER alice;   -- SELECT all
ALTER ROLE db_datawriter ADD MEMBER alice;   -- INSERT/UPDATE/DELETE all
ALTER ROLE db_owner ADD MEMBER alice;        -- 全部权限

-- 自定义角色
CREATE ROLE analyst;
GRANT SELECT ON SCHEMA::dbo TO analyst;
ALTER ROLE analyst ADD MEMBER alice;

-- 查看权限
SELECT * FROM fn_my_permissions('users', 'OBJECT');
SELECT * FROM fn_my_permissions(NULL, 'DATABASE');

-- ============================================================
-- 4. 行级安全（Row-Level Security, 2016+）
-- ============================================================

-- RLS 通过安全策略自动过滤行——用户查询不需要添加 WHERE 条件
CREATE FUNCTION dbo.fn_user_predicate(@username NVARCHAR(64))
RETURNS TABLE WITH SCHEMABINDING
AS RETURN SELECT 1 AS result WHERE @username = USER_NAME();

CREATE SECURITY POLICY user_filter
ADD FILTER PREDICATE dbo.fn_user_predicate(username) ON dbo.users,
ADD BLOCK PREDICATE dbo.fn_user_predicate(username) ON dbo.users
WITH (STATE = ON);

-- FILTER PREDICATE: 过滤 SELECT/UPDATE/DELETE 返回的行
-- BLOCK PREDICATE:  阻止 INSERT/UPDATE 违反策略的行

-- 设计分析（对引擎开发者）:
--   RLS 在查询优化器内部注入谓词——对应用层完全透明。
--   这比在每个查询中手动添加 WHERE tenant_id = @current_tenant 安全得多。
--
-- 横向对比:
--   PostgreSQL: CREATE POLICY ... ON t USING (tenant_id = current_setting('app.tenant'))
--               PostgreSQL 的 RLS 更灵活（支持 current_setting 获取运行时上下文）
--   Oracle:     VPD（Virtual Private Database）——功能最强但语法最复杂
--   MySQL:      不支持 RLS

-- ============================================================
-- 5. 动态数据掩码（Dynamic Data Masking, 2016+）
-- ============================================================

ALTER TABLE users ALTER COLUMN email ADD MASKED WITH (FUNCTION = 'email()');
ALTER TABLE users ALTER COLUMN phone ADD MASKED WITH (FUNCTION = 'partial(0,"XXX-",4)');
ALTER TABLE users ALTER COLUMN salary ADD MASKED WITH (FUNCTION = 'default()');

-- 掩码函数:
-- default():            数字→0, 字符串→XXXX, 日期→01.01.2000
-- email():              aXXX@XXXX.com
-- partial(前缀, 填充, 后缀字符数):  自定义掩码
-- random(start, end):   随机数替代

GRANT UNMASK TO analyst;  -- 允许看到原始数据

-- 设计分析:
--   DDM 是展示层掩码——数据在存储中不加密，只在查询结果中替换。
--   安全性有限: 有权限的用户可以通过推导（如 WHERE salary BETWEEN ...）
--   逐步缩小范围还原原始值。
--   真正的数据保护应使用: Always Encrypted（列级加密，客户端解密）

-- ============================================================
-- 6. 查看权限元数据
-- ============================================================

SELECT dp.name AS principal, dp.type_desc,
       perm.permission_name, perm.state_desc,
       OBJECT_NAME(perm.major_id) AS object_name
FROM sys.database_permissions perm
JOIN sys.database_principals dp ON perm.grantee_principal_id = dp.principal_id
WHERE dp.name = 'alice';

EXEC sp_helpuser 'alice';

-- 版本演进:
-- 2005+ : Schema 与 User 解耦, 固定角色
-- 2012+ : Contained Database Users
-- 2016+ : Row-Level Security, Dynamic Data Masking
-- 2016+ : Always Encrypted（客户端加密）
-- 2019+ : Always Encrypted with Secure Enclaves
