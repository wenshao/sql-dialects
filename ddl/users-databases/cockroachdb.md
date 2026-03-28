# CockroachDB: 数据库与用户管理

> 参考资料:
> - [CockroachDB Documentation - CREATE DATABASE](https://www.cockroachlabs.com/docs/stable/create-database)
> - [CockroachDB Documentation - CREATE USER / ROLE](https://www.cockroachlabs.com/docs/stable/create-user)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

## CockroachDB 兼容 PostgreSQL 协议

命名层级: cluster > database > schema > object
默认: defaultdb 数据库, public 模式
## 数据库管理

```sql
CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;

CREATE DATABASE myapp
    ENCODING = 'UTF8'
    PRIMARY REGION = 'us-east1'                 -- 多区域部署
    REGIONS = 'us-east1', 'us-west1', 'eu-west1'
    SURVIVE REGION FAILURE;                     -- 区域级容灾

```

单区域数据库
```sql
CREATE DATABASE myapp
    PRIMARY REGION = 'us-east1';

```

修改数据库
```sql
ALTER DATABASE myapp ADD REGION 'asia-southeast1';
ALTER DATABASE myapp SET PRIMARY REGION = 'eu-west1';
ALTER DATABASE myapp RENAME TO myapp_v2;
ALTER DATABASE myapp OWNER TO newowner;

```

删除数据库
```sql
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp CASCADE;

```

切换数据库
```sql
USE myapp;
SET DATABASE = myapp;

```

## 模式管理


```sql
CREATE SCHEMA myschema;
CREATE SCHEMA IF NOT EXISTS myschema;
CREATE SCHEMA myschema AUTHORIZATION myuser;

```

删除模式
```sql
DROP SCHEMA myschema;
DROP SCHEMA myschema CASCADE;

```

设置搜索路径
```sql
SET search_path = myschema, public;

```

## 用户与角色管理


CockroachDB 中 USER 和 ROLE 统一（同 PostgreSQL）
```sql
CREATE USER myuser WITH PASSWORD 'secret123';
CREATE USER IF NOT EXISTS myuser WITH PASSWORD 'secret123';

CREATE USER myuser WITH
    PASSWORD 'secret123'
    LOGIN                                       -- 允许登录（默认）
    VALID UNTIL '2026-12-31';

CREATE ROLE analyst;
CREATE ROLE developer WITH LOGIN PASSWORD 'secret123';

```

修改
```sql
ALTER USER myuser WITH PASSWORD 'newsecret';
ALTER ROLE analyst WITH NOLOGIN;

```

删除
```sql
DROP USER myuser;
DROP ROLE analyst;

```

角色继承
```sql
GRANT analyst TO myuser;
GRANT developer TO myuser;
REVOKE analyst FROM myuser;

```

## 权限管理


数据库权限
```sql
GRANT CONNECT ON DATABASE myapp TO myuser;
GRANT CREATE ON DATABASE myapp TO developer;
GRANT ALL ON DATABASE myapp TO admin;

```

模式权限
```sql
GRANT USAGE ON SCHEMA myschema TO analyst;
GRANT CREATE ON SCHEMA myschema TO developer;

```

表权限
```sql
GRANT SELECT ON TABLE myschema.users TO analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA myschema TO analyst;
GRANT INSERT, UPDATE, DELETE ON TABLE myschema.users TO developer;

```

默认权限
```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA myschema
    GRANT SELECT ON TABLES TO analyst;

```

收回权限
```sql
REVOKE ALL ON DATABASE myapp FROM myuser;

```

## 查询元数据


```sql
SHOW DATABASES;
SHOW SCHEMAS;
SHOW USERS;
SHOW ROLES;
SHOW GRANTS ON DATABASE myapp;
SHOW GRANTS FOR myuser;

SELECT current_database(), current_schema(), current_user;

```

CockroachDB 特有系统表
```sql
SELECT * FROM crdb_internal.databases;
SELECT * FROM crdb_internal.zones;              -- 数据分布区域

```

## 多区域配置


区域级别表（数据按区域分布）
ALTER TABLE myapp.public.users SET LOCALITY REGIONAL BY ROW;
ALTER TABLE myapp.public.users SET LOCALITY GLOBAL;

查看区域配置
```sql
SHOW REGIONS;
SHOW REGIONS FROM DATABASE myapp;
SHOW ZONE CONFIGURATION FOR DATABASE myapp;

```
