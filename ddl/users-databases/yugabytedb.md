# YugabyteDB: 数据库与用户管理

> 参考资料:
> - [YugabyteDB Documentation - CREATE DATABASE](https://docs.yugabyte.com/latest/api/ysql/the-sql-language/statements/ddl_create_database/)
> - [YugabyteDB Documentation - Authorization](https://docs.yugabyte.com/latest/secure/authorization/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

## YugabyteDB 支持两种 API:

- YSQL: 兼容 PostgreSQL（推荐）
- YCQL: 兼容 Cassandra
命名层级 (YSQL): cluster > database > schema > object
命名层级 (YCQL): cluster > keyspace > table
YSQL 模式（兼容 PostgreSQL）
## 数据库管理

```sql
CREATE DATABASE myapp;
CREATE DATABASE myapp OWNER myuser ENCODING 'UTF8';

```

全局事务设置（分布式特有）
```sql
ALTER DATABASE myapp SET yb_enable_read_committed_isolation = true;

ALTER DATABASE myapp RENAME TO myapp_v2;
ALTER DATABASE myapp OWNER TO newowner;

DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;

```

## 模式管理

```sql
CREATE SCHEMA myschema;
CREATE SCHEMA IF NOT EXISTS myschema AUTHORIZATION myuser;

DROP SCHEMA myschema CASCADE;

SET search_path TO myschema, public;

```

## 用户与角色

```sql
CREATE USER myuser WITH PASSWORD 'secret123';
CREATE ROLE analyst NOLOGIN;

CREATE ROLE myuser WITH
    LOGIN
    PASSWORD 'secret123'
    SUPERUSER                                   -- 超级用户
    CREATEDB
    CREATEROLE;

ALTER USER myuser WITH PASSWORD 'newsecret';
DROP USER myuser;

GRANT analyst TO myuser;

```

## 权限管理

```sql
GRANT CONNECT ON DATABASE myapp TO myuser;
GRANT USAGE ON SCHEMA myschema TO analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA myschema TO analyst;
GRANT INSERT, UPDATE, DELETE ON myschema.users TO developer;

ALTER DEFAULT PRIVILEGES IN SCHEMA myschema
    GRANT SELECT ON TABLES TO analyst;

REVOKE ALL ON SCHEMA myschema FROM myuser;

```

## YCQL 模式（兼容 Cassandra）


## Keyspace 管理

```sql
CREATE KEYSPACE myapp;
CREATE KEYSPACE IF NOT EXISTS myapp
    WITH REPLICATION = {'class': 'SimpleStrategy', 'replication_factor': 3};

DROP KEYSPACE myapp;

USE myapp;

```

## 角色管理（YCQL）

```sql
CREATE ROLE 'myuser' WITH PASSWORD = 'secret123' AND LOGIN = true;
ALTER ROLE 'myuser' WITH PASSWORD = 'newsecret';
DROP ROLE 'myuser';

```

## 权限管理（YCQL）

```sql
GRANT ALL ON KEYSPACE myapp TO 'myuser';
GRANT SELECT ON TABLE myapp.users TO 'myuser';
REVOKE SELECT ON TABLE myapp.users FROM 'myuser';

```

## 查询元数据


YSQL
```sql
SELECT current_database(), current_schema(), current_user;
SELECT datname FROM pg_database;
SELECT nspname FROM pg_namespace;
SELECT rolname, rolsuper, rolcanlogin FROM pg_roles;

```

YugabyteDB 特有
$ yb-admin list_all_masters
$ yb-admin list_all_tablet_servers

**注意:** YugabyteDB 是分布式 SQL 数据库
YSQL 完全兼容 PostgreSQL 的用户/权限管理
YCQL 兼容 Cassandra 的角色管理
推荐使用 YSQL 模式
