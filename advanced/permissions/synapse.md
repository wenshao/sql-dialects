# Azure Synapse: 权限管理

> 参考资料:
> - [Synapse SQL Features](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)
> - [Synapse T-SQL Differences](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


## 用户和登录


创建登录（在 master 数据库中）
```sql
CREATE LOGIN alice WITH PASSWORD = 'Password123!';
```


创建数据库用户（在目标数据库中）
```sql
CREATE USER alice FOR LOGIN alice;
CREATE USER alice FROM LOGIN alice;
```


Azure AD 用户（推荐）
```sql
CREATE USER [alice@contoso.com] FROM EXTERNAL PROVIDER;
```


## 角色


创建数据库角色
```sql
CREATE ROLE analysts;
CREATE ROLE data_engineers;
```


添加用户到角色
```sql
ALTER ROLE analysts ADD MEMBER alice;
ALTER ROLE data_engineers ADD MEMBER alice;
```


从角色中移除用户
```sql
ALTER ROLE analysts DROP MEMBER alice;
```


内置角色
db_owner: 完全控制
db_datareader: 读取所有表
db_datawriter: 写入所有表

```sql
ALTER ROLE db_datareader ADD MEMBER alice;
ALTER ROLE db_datawriter ADD MEMBER data_engineers;
```


## 授权


表级权限
```sql
GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE, DELETE ON users TO alice;
GRANT ALL ON users TO data_engineers;
```


Schema 级权限
```sql
GRANT SELECT ON SCHEMA::dbo TO analysts;
GRANT CONTROL ON SCHEMA::staging TO data_engineers;
```


列级权限
```sql
GRANT SELECT ON users (username, email) TO alice;
```


视图权限
```sql
GRANT SELECT ON v_active_users TO analysts;
```


存储过程权限
```sql
GRANT EXECUTE ON get_user TO alice;
GRANT EXECUTE ON SCHEMA::dbo TO data_engineers;
```


数据库权限
```sql
GRANT CONNECT TO alice;
GRANT CREATE TABLE TO data_engineers;
GRANT ALTER ANY SCHEMA TO data_engineers;
```


## 撤销权限


```sql
REVOKE SELECT ON users FROM alice;
REVOKE ALL ON users FROM alice;
```


DENY（显式拒绝，优先于 GRANT）
```sql
DENY SELECT ON sensitive_data TO analysts;
DENY DELETE ON users TO alice;
```


## Serverless 池权限


Serverless 池使用外部数据源，权限有所不同
创建凭据
```sql
CREATE DATABASE SCOPED CREDENTIAL my_credential
WITH IDENTITY = 'Managed Identity';
```


授权使用凭据
```sql
GRANT REFERENCES ON CREDENTIAL::my_credential TO alice;
```


授权使用外部数据源
```sql
GRANT REFERENCES ON EXTERNAL DATA SOURCE my_adls TO alice;
```


Serverless 池中使用 OPENROWSET 需要 ADMINISTER BULK OPERATIONS 权限
```sql
GRANT ADMINISTER BULK OPERATIONS TO alice;
```


## 工作区级安全


Synapse 工作区使用 Azure RBAC
工作区角色：
Synapse Administrator: 完全控制
Synapse SQL Administrator: SQL 管理
Synapse Contributor: 创建和管理
Synapse User: 查看和使用

## 动态数据掩码


创建带掩码的表
```sql
CREATE TABLE users (
    id       BIGINT IDENTITY(1, 1),
    email    NVARCHAR(255) MASKED WITH (FUNCTION = 'email()'),
    phone    NVARCHAR(20) MASKED WITH (FUNCTION = 'partial(0,"XXX-XXX-",4)'),
    ssn      NVARCHAR(11) MASKED WITH (FUNCTION = 'default()')
)
WITH (DISTRIBUTION = HASH(id));
```


授权查看未掩码的数据
```sql
GRANT UNMASK TO data_engineers;
GRANT UNMASK ON users (email) TO alice;  -- 列级
```


## 查看权限


```sql
SELECT * FROM sys.database_principals WHERE type IN ('S', 'U', 'G', 'R');
SELECT * FROM sys.database_permissions WHERE grantee_principal_id = USER_ID('alice');
SELECT * FROM sys.database_role_members;
```


查看自己的权限
```sql
SELECT * FROM fn_my_permissions(NULL, 'DATABASE');
SELECT * FROM fn_my_permissions('users', 'OBJECT');
```


## 删除用户/角色


```sql
DROP USER alice;
DROP ROLE analysts;
DROP LOGIN alice;  -- 在 master 数据库中
```


注意：推荐使用 Azure AD 认证（而非 SQL 登录）
注意：DENY 优先于 GRANT（显式拒绝）
注意：Serverless 池和专用池的权限模型有差异
注意：动态数据掩码在查询时自动掩码敏感数据
注意：工作区级安全使用 Azure RBAC
注意：专用池支持行级安全（RLS），使用 CREATE SECURITY POLICY
