# SQL Server: 用户与数据库管理

> 参考资料:
> - [SQL Server - CREATE DATABASE](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-database-transact-sql)
> - [SQL Server - Security Architecture](https://learn.microsoft.com/en-us/sql/relational-databases/security/authentication-access/getting-started-with-database-engine-permissions)

## 命名层级: Server > Database > Schema > Object

SQL Server 的四层命名空间是其独特设计。
完全限定名: [server].[database].[schema].[object]
默认模式是 dbo（database owner），所有未指定模式的对象都归入 dbo。

横向对比:
  PostgreSQL: cluster > database > schema > object（类似但无跨库查询）
  MySQL:      server > database(=schema) > object（database 和 schema 是同义词）
  Oracle:     instance > user(=schema) > object（user 和 schema 绑定）

对引擎开发者的启示:
  SQL Server 允许跨数据库查询（SELECT * FROM otherdb.dbo.table）——
  PostgreSQL 不支持这个（需要 dblink/FDW）。跨库能力影响连接池设计和安全模型。

## 数据库管理

```sql
CREATE DATABASE myapp;
```

详细创建（指定文件组、文件位置、增长策略）
```sql
CREATE DATABASE myapp
ON PRIMARY (
    NAME = myapp_data,
    FILENAME = 'C:\Data\myapp.mdf',
    SIZE = 100MB, MAXSIZE = 10GB, FILEGROWTH = 100MB
)
LOG ON (
    NAME = myapp_log,
    FILENAME = 'C:\Data\myapp_log.ldf',
    SIZE = 50MB, MAXSIZE = 5GB, FILEGROWTH = 50MB
);
```

设计分析（对引擎开发者）:
  SQL Server 将数据和日志分离为不同的物理文件——这是其存储架构的基础。
  .mdf = 主数据文件, .ndf = 辅助数据文件, .ldf = 事务日志文件
  日志文件的大小管理是 DBA 的常见痛点（日志不自动截断，需要配合备份策略）。

  恢复模式直接影响日志行为:
```sql
ALTER DATABASE myapp SET RECOVERY FULL;    -- 完整: 日志不截断直到备份
ALTER DATABASE myapp SET RECOVERY SIMPLE;  -- 简单: 自动截断（无法做时间点恢复）

-- 数据库状态控制
ALTER DATABASE myapp SET READ_ONLY;
ALTER DATABASE myapp SET READ_WRITE;
ALTER DATABASE myapp SET SINGLE_USER WITH ROLLBACK IMMEDIATE;  -- 踢掉所有连接
ALTER DATABASE myapp SET MULTI_USER;

DROP DATABASE IF EXISTS myapp;  -- 2016+
USE myapp;                      -- 切换当前数据库
```

## Login vs User: SQL Server 独特的双层安全模型

Login = 服务器级身份（用于连接到 SQL Server 实例）
User  = 数据库级身份（用于访问特定数据库中的对象）
一个 Login 可以映射到多个 Database 中的 User。

这是 SQL Server 最独特的安全设计——其他数据库没有这个分离:
  MySQL:      user@host 直接拥有数据库权限
  PostgreSQL: ROLE 统一了用户和角色的概念
  Oracle:     USER = SCHEMA（建用户自动建模式）

```sql
CREATE LOGIN mylogin WITH PASSWORD = 'Secret123!',
    DEFAULT_DATABASE = myapp,
    CHECK_POLICY = ON,          -- 使用 Windows 密码策略
    CHECK_EXPIRATION = ON;      -- 密码过期

-- Windows 认证登录（域环境）
-- CREATE LOGIN [DOMAIN\username] FROM WINDOWS;

USE myapp;
CREATE USER myuser FOR LOGIN mylogin;
CREATE USER myuser FOR LOGIN mylogin WITH DEFAULT_SCHEMA = myschema;
```

无登录用户（仅数据库内使用，常用于安全上下文）
```sql
CREATE USER app_user WITHOUT LOGIN;
```

2012+: 包含数据库用户（无需服务器级登录）
```sql
CREATE USER alice WITH PASSWORD = 'Password123!';
```

Azure SQL: Microsoft Entra ID（前 Azure AD）用户
```sql
CREATE USER [alice@example.com] FROM EXTERNAL PROVIDER;
```

修改与删除
```sql
ALTER LOGIN mylogin WITH PASSWORD = 'NewSecret456!';
ALTER LOGIN mylogin DISABLE;
ALTER USER myuser WITH DEFAULT_SCHEMA = myschema;
DROP USER myuser;
DROP LOGIN mylogin;
```

## 模式管理

```sql
CREATE SCHEMA myschema;
CREATE SCHEMA myschema AUTHORIZATION myuser;
DROP SCHEMA myschema;  -- 必须为空
```

转移对象到另一个模式
```sql
ALTER SCHEMA newschema TRANSFER dbo.users;
```

设计分析:
  SQL Server 的 Schema 是纯命名空间（与用户解耦）。
  Oracle 中 Schema = User（建用户自动建 Schema），SQL Server 在 2005 改为解耦。
  这是更好的设计——多个用户可以共享一个 Schema，一个用户可以访问多个 Schema。

## 角色体系（固定角色 + 自定义角色）

固定服务器角色（内置，不可修改权限）
sysadmin: 全部权限    serveradmin: 服务器配置
securityadmin: 管理登录  dbcreator: 创建数据库
```sql
ALTER SERVER ROLE sysadmin ADD MEMBER mylogin;
```

固定数据库角色
db_owner: 全部权限     db_datareader: 所有表的 SELECT
db_datawriter: 所有表的 DML  db_ddladmin: DDL 权限
```sql
ALTER ROLE db_datareader ADD MEMBER myuser;
ALTER ROLE db_datawriter ADD MEMBER myuser;
```

自定义角色
```sql
CREATE ROLE analyst;
GRANT SELECT ON SCHEMA::dbo TO analyst;
ALTER ROLE analyst ADD MEMBER myuser;
DROP ROLE analyst;
```

## 权限管理: GRANT / DENY / REVOKE

SQL Server 的权限有三种状态: GRANT(授予) / DENY(拒绝) / REVOKE(撤销)
关键规则: DENY 优先级最高——即使通过角色获得了权限，DENY 也会覆盖
```sql
GRANT SELECT ON dbo.users TO myuser;
GRANT INSERT, UPDATE, DELETE ON dbo.users TO myuser;
DENY DELETE ON dbo.users TO myuser;  -- 即使有 db_datawriter 角色也无法 DELETE
REVOKE INSERT ON dbo.users FROM myuser;
```

列级权限
```sql
GRANT SELECT (id, username) ON dbo.users TO myuser;
```

Schema 级权限
```sql
GRANT SELECT ON SCHEMA::myschema TO myuser;
```

查看权限
```sql
SELECT * FROM fn_my_permissions('dbo.users', 'OBJECT');
SELECT * FROM fn_my_permissions(NULL, 'DATABASE');
```

当前上下文
```sql
SELECT DB_NAME() AS current_db, SCHEMA_NAME() AS default_schema,
       USER_NAME() AS current_user, SUSER_NAME() AS login_name;
```

## 数据库范围配置（2016+）

DATABASE SCOPED CONFIGURATION 是 SQL Server 2016 引入的数据库级设置，
替代了之前很多需要服务器级修改的配置。
```sql
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 4;
ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = OFF;
ALTER DATABASE SCOPED CONFIGURATION SET IDENTITY_CACHE = OFF;  -- 2017+
```

兼容级别（决定 T-SQL 行为版本）
```sql
ALTER DATABASE myapp SET COMPATIBILITY_LEVEL = 160;  -- SQL Server 2022

-- 对引擎开发者的启示:
--   数据库级配置 vs 服务器级配置是多租户场景的关键区分。
--   Azure SQL Database 中每个数据库就是一个租户，必须支持库级配置。
```
