# 达梦 (DM): 数据库、模式与用户管理

> 参考资料:
> - [达梦数据库 SQL 参考手册 - CREATE USER](https://eco.dameng.com/docs/zh-cn/sql-dev/dmpl-sql/create-user.html)
> - [达梦数据库 SQL 参考手册 - 用户与权限](https://eco.dameng.com/docs/zh-cn/sql-dev/dmpl-sql/grant.html)
> - ============================================================
> - 达梦命名层级: 实例 > 数据库 > 模式(=用户) > 对象
> - 类似 Oracle: 用户和模式一一对应
> - 创建用户自动创建同名模式
> - ============================================================
> - ============================================================
> - 1. 数据库管理
> - ============================================================
> - 达梦的数据库通过 dminit 工具创建（非 SQL）
> - $ dminit PATH=/dm/data DB_NAME=myapp INSTANCE_NAME=DMSERVER
> - 一个达梦实例通常对应一个数据库
> - 不支持 SQL 的 CREATE DATABASE
> - ============================================================
> - 2. 模式管理
> - ============================================================
> - 创建模式（需要 DBA 权限）

```sql
CREATE SCHEMA myschema AUTHORIZATION myuser;
```

或者通过创建用户自动创建模式
CREATE USER myuser ...  -- 自动创建 MYUSER 模式
删除模式

```sql
DROP SCHEMA myschema CASCADE;
```

## 切换当前模式

```sql
SET SCHEMA myschema;
```

## 用户管理


```sql
CREATE USER myuser IDENTIFIED BY 'Secret123!';

CREATE USER myuser IDENTIFIED BY 'Secret123!'
    DEFAULT TABLESPACE main
    DEFAULT INDEX TABLESPACE main
    QUOTA UNLIMITED ON main
    PASSWORD_POLICY 2;                          -- 密码策略
```

## 修改用户

```sql
ALTER USER myuser IDENTIFIED BY 'NewSecret456!';
ALTER USER myuser ACCOUNT LOCK;
ALTER USER myuser ACCOUNT UNLOCK;
ALTER USER myuser PASSWORD_POLICY 0;            -- 关闭密码策略
```

## 删除用户

```sql
DROP USER myuser;
DROP USER myuser CASCADE;                       -- 级联删除所有对象
```

## 角色管理


```sql
CREATE ROLE analyst;
CREATE ROLE developer;
```

## 系统角色: DBA, PUBLIC, RESOURCE, VTI, SOI

```sql
GRANT analyst TO myuser;
GRANT DBA TO admin_user;

REVOKE analyst FROM myuser;
DROP ROLE analyst;
```

## 权限管理


## 系统权限

```sql
GRANT CREATE SESSION TO myuser;                 -- 允许登录
GRANT CREATE TABLE TO myuser;
GRANT CREATE VIEW TO myuser;
GRANT CREATE PROCEDURE TO myuser;
```

## 对象权限

```sql
GRANT SELECT ON myuser.users TO analyst;
GRANT INSERT, UPDATE, DELETE ON myuser.users TO developer;
GRANT ALL PRIVILEGES ON myuser.users TO admin;
```

## 角色权限

```sql
GRANT SELECT ANY TABLE TO analyst;
GRANT CREATE TABLE, CREATE VIEW TO developer;
```

## 收回权限

```sql
REVOKE SELECT ON myuser.users FROM analyst;
REVOKE CREATE TABLE FROM developer;
```

## 表空间管理


```sql
CREATE TABLESPACE app_data
    DATAFILE '/dm/data/app_data.dbf' SIZE 500;  -- 单位 MB

ALTER TABLESPACE app_data ADD DATAFILE '/dm/data/app_data2.dbf' SIZE 500;
ALTER TABLESPACE app_data RESIZE DATAFILE '/dm/data/app_data.dbf' TO 1000;

DROP TABLESPACE app_data;
```

## 查询元数据


```sql
SELECT USER FROM DUAL;
SELECT SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') FROM DUAL;
```

## 列出用户

```sql
SELECT USERNAME, ACCOUNT_STATUS, DEFAULT_TABLESPACE FROM DBA_USERS;
```

## 列出模式

```sql
SELECT DISTINCT OWNER FROM ALL_TABLES;
```

## 查看权限

```sql
SELECT * FROM DBA_SYS_PRIVS WHERE GRANTEE = 'MYUSER';
SELECT * FROM DBA_TAB_PRIVS WHERE GRANTEE = 'MYUSER';
SELECT * FROM DBA_ROLE_PRIVS WHERE GRANTEE = 'MYUSER';
```

## 注意：达梦兼容 Oracle 语法

大部分 Oracle 的用户管理语法在达梦中可用
