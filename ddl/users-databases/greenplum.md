# Greenplum: 数据库、模式与用户管理

> 参考资料:
> - [Greenplum Documentation - CREATE DATABASE](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-CREATE_DATABASE.html)
> - [Greenplum Documentation - Managing Roles and Privileges](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-roles_privs.html)


## Greenplum 基于 PostgreSQL，命名层级相同:

cluster > database > schema > object
默认: postgres 数据库, public 模式

## 1. 数据库管理


```sql
CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;            -- Greenplum 扩展

CREATE DATABASE myapp
    OWNER = myuser
    ENCODING = 'UTF8'
    TEMPLATE = template0
    CONNECTION LIMIT = 100;
```


修改数据库
```sql
ALTER DATABASE myapp SET timezone TO 'Asia/Shanghai';
ALTER DATABASE myapp RENAME TO myapp_v2;
ALTER DATABASE myapp OWNER TO newowner;
```


删除数据库
```sql
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;
```


## 2. 模式管理


```sql
CREATE SCHEMA myschema;
CREATE SCHEMA IF NOT EXISTS myschema;
CREATE SCHEMA myschema AUTHORIZATION myuser;

DROP SCHEMA myschema;
DROP SCHEMA myschema CASCADE;

SET search_path TO myschema, public;
SHOW search_path;
```


## 3. 用户与角色管理


同 PostgreSQL
```sql
CREATE USER myuser WITH PASSWORD 'secret123';

CREATE ROLE myuser WITH
    LOGIN
    PASSWORD 'secret123'
    CREATEDB
    RESOURCE QUEUE pg_default;                  -- 资源队列

CREATE ROLE analyst NOLOGIN;

ALTER USER myuser WITH PASSWORD 'newsecret';

DROP USER myuser;
DROP ROLE analyst;
```


角色继承
```sql
GRANT analyst TO myuser;
```


## 4. 权限管理


```sql
GRANT CONNECT ON DATABASE myapp TO myuser;
GRANT USAGE ON SCHEMA myschema TO analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA myschema TO analyst;
GRANT INSERT, UPDATE, DELETE ON myschema.users TO developer;

ALTER DEFAULT PRIVILEGES IN SCHEMA myschema
    GRANT SELECT ON TABLES TO analyst;

REVOKE ALL ON SCHEMA myschema FROM myuser;
```


## 5. 资源管理


资源队列（传统方式）
```sql
CREATE RESOURCE QUEUE report_queue
    WITH (ACTIVE_STATEMENTS=10, MAX_COST=1000000000);

ALTER ROLE analyst RESOURCE QUEUE report_queue;

DROP RESOURCE QUEUE report_queue;
```


资源组（Greenplum 6+，推荐）
```sql
CREATE RESOURCE GROUP rg_analytics
    WITH (CONCURRENCY=10, CPU_RATE_LIMIT=30, MEMORY_LIMIT=30);

ALTER ROLE analyst RESOURCE GROUP rg_analytics;

DROP RESOURCE GROUP rg_analytics;
```


## 6. 查询元数据


```sql
SELECT current_database(), current_schema(), current_user;

SELECT datname FROM pg_database;
SELECT nspname FROM pg_namespace;
SELECT rolname, rolsuper, rolcanlogin FROM pg_roles;
```


Greenplum 特有系统表
```sql
SELECT * FROM gp_segment_configuration;         -- 节点配置
SELECT * FROM gp_toolkit.gp_resgroup_config;    -- 资源组配置
```
