# Hologres: 数据库、模式与用户管理

> 参考资料:
> - [Hologres Documentation - 数据库管理](https://help.aliyun.com/document_detail/171699.html)
> - [Hologres Documentation - 用户与权限](https://help.aliyun.com/document_detail/172191.html)


Hologres 兼容 PostgreSQL 协议
命名层级: 实例 > 数据库 > 模式 > 对象
默认: postgres 数据库, public 模式


## 数据库管理


## 通过 SQL 创建数据库

```sql
CREATE DATABASE myapp;

CREATE DATABASE myapp
    WITH ENCODING = 'UTF-8';
```

## 修改数据库

```sql
ALTER DATABASE myapp SET search_path TO myschema, public;
```

## 删除数据库

```sql
DROP DATABASE myapp;
```

## 注意：也可通过阿里云 Hologres 控制台创建数据库

## 模式管理


```sql
CREATE SCHEMA myschema;
CREATE SCHEMA IF NOT EXISTS myschema;
CREATE SCHEMA myschema AUTHORIZATION myuser;

DROP SCHEMA myschema;
DROP SCHEMA myschema CASCADE;

SET search_path TO myschema, public;
```

## 用户管理


Hologres 用户由阿里云 RAM 账号管理
需要先在 Hologres 实例中添加用户
创建用户（RAM 账号映射）

```sql
CREATE USER "p4_accountid";                     -- 阿里云账号 ID
CREATE USER "RAM$主账号:子用户名";               -- RAM 子账号
```

通过 Hologres 控制台添加用户更便捷
超级用户
ALTER USER "p4_accountid" SUPERUSER;
删除用户

```sql
DROP USER "p4_accountid";
```

## 角色与权限管理


## Hologres 提供简单权限模型（SPM）

开启 SPM

```sql
CALL spm_enable();
```

SPM 预定义角色：
<db>_admin: 数据库管理员
<db>_developer: 开发者
<db>_writer: 写入者
<db>_viewer: 只读者

```sql
CALL spm_grant('myapp_viewer', 'RAM$主账号:子用户名');
CALL spm_grant('myapp_developer', 'p4_accountid');

CALL spm_revoke('myapp_viewer', 'RAM$主账号:子用户名');
```

## 标准 PostgreSQL 权限（非 SPM 模式）

```sql
CREATE ROLE analyst;
GRANT USAGE ON SCHEMA myschema TO analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA myschema TO analyst;
GRANT analyst TO "p4_accountid";

ALTER DEFAULT PRIVILEGES IN SCHEMA myschema
    GRANT SELECT ON TABLES TO analyst;

REVOKE ALL ON SCHEMA myschema FROM analyst;
```

## 查询元数据


```sql
SELECT current_database(), current_schema(), current_user;

SELECT datname FROM pg_database;
SELECT nspname FROM pg_namespace;
SELECT rolname, rolsuper, rolcanlogin FROM pg_roles;
```

## Hologres 特有

```sql
SELECT * FROM hologres.hg_table_properties;     -- 表属性
```
