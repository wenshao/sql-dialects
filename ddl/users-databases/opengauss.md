# openGauss: 数据库、模式与用户管理

> 参考资料:
> - [openGauss Documentation - CREATE DATABASE](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/CREATE-DATABASE.html)
> - [openGauss Documentation - CREATE USER](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/CREATE-USER.html)
> - ============================================================
> - openGauss 基于 PostgreSQL 内核
> - 命名层级: cluster > database > schema > object
> - 默认: postgres 数据库, public 模式
> - ============================================================
> - ============================================================
> - 1. 数据库管理
> - ============================================================

```sql
CREATE DATABASE myapp;

CREATE DATABASE myapp
    OWNER = myuser
    ENCODING = 'UTF8'
    TEMPLATE = template0
    DBCOMPATIBILITY = 'PG'                      -- 兼容模式: PG, B(MySQL), C(Oracle), A
    CONNECTION LIMIT = 100;
```

## 修改数据库

```sql
ALTER DATABASE myapp SET timezone TO 'Asia/Shanghai';
ALTER DATABASE myapp RENAME TO myapp_v2;
ALTER DATABASE myapp OWNER TO newowner;
ALTER DATABASE myapp SET search_path TO myschema, public;
```

## 删除数据库

```sql
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;
```

## 模式管理


```sql
CREATE SCHEMA myschema;
CREATE SCHEMA IF NOT EXISTS myschema;
CREATE SCHEMA myschema AUTHORIZATION myuser;

DROP SCHEMA myschema;
DROP SCHEMA myschema CASCADE;

SET search_path TO myschema, public;
```

## 用户与角色管理


```sql
CREATE USER myuser PASSWORD 'Secret123!';

CREATE USER myuser PASSWORD 'Secret123!'
    SYSADMIN                                    -- 系统管理员
    CREATEDB
    CREATEROLE
    LOGIN
    VALID BEGIN '2024-01-01'
    VALID UNTIL '2026-12-31'
    CONNECTION LIMIT 10
    RESOURCE POOL 'default_pool';

CREATE ROLE analyst PASSWORD 'Secret123!' NOLOGIN;

ALTER USER myuser PASSWORD 'NewSecret456!';
ALTER USER myuser ACCOUNT LOCK;
ALTER USER myuser ACCOUNT UNLOCK;

DROP USER myuser;
DROP USER myuser CASCADE;

GRANT analyst TO myuser;
REVOKE analyst FROM myuser;
```

## 权限管理


```sql
GRANT CONNECT ON DATABASE myapp TO myuser;
GRANT USAGE ON SCHEMA myschema TO analyst;
GRANT CREATE ON SCHEMA myschema TO developer;

GRANT SELECT ON ALL TABLES IN SCHEMA myschema TO analyst;
GRANT INSERT, UPDATE, DELETE ON myschema.users TO developer;

ALTER DEFAULT PRIVILEGES IN SCHEMA myschema
    GRANT SELECT ON TABLES TO analyst;

REVOKE ALL ON SCHEMA myschema FROM myuser;
```

## 行级安全

```sql
CREATE ROW LEVEL SECURITY POLICY region_policy ON myschema.sales
    USING (region = CURRENT_USER);
ALTER TABLE myschema.sales ENABLE ROW LEVEL SECURITY;
```

## 资源管理


## 资源池

```sql
CREATE RESOURCE POOL rp_analytics
    WITH (MEM_PERCENT=30, CPU_AFFINITY=0-3);

ALTER USER myuser RESOURCE POOL 'rp_analytics';

DROP RESOURCE POOL rp_analytics;
```

## 审计


openGauss 支持细粒度审计
ALTER SYSTEM SET audit_enabled = on;
ALTER SYSTEM SET audit_login_logout = 7;
ALTER SYSTEM SET audit_dml_state = 1;

## 查询元数据


```sql
SELECT current_database(), current_schema(), current_user;

SELECT datname, datcompatibility FROM pg_database;
SELECT nspname FROM pg_namespace;
SELECT rolname, rolsuper, rolcanlogin FROM pg_roles;
SELECT usename, usesysid FROM pg_user;
```

## openGauss 特有视图

```sql
SELECT * FROM pg_total_user_resource_info;      -- 用户资源使用
```
