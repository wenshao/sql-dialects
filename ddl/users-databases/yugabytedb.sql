-- YugabyteDB: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] YugabyteDB Documentation - CREATE DATABASE
--       https://docs.yugabyte.com/latest/api/ysql/the-sql-language/statements/ddl_create_database/
--   [2] YugabyteDB Documentation - Authorization
--       https://docs.yugabyte.com/latest/secure/authorization/

-- ============================================================
-- YugabyteDB 支持两种 API:
-- - YSQL: 兼容 PostgreSQL（推荐）
-- - YCQL: 兼容 Cassandra
-- 命名层级 (YSQL): cluster > database > schema > object
-- 命名层级 (YCQL): cluster > keyspace > table
-- ============================================================

-- ============================================================
-- YSQL 模式（兼容 PostgreSQL）
-- ============================================================

-- 1. 数据库管理
CREATE DATABASE myapp;
CREATE DATABASE myapp OWNER myuser ENCODING 'UTF8';

-- 全局事务设置（分布式特有）
ALTER DATABASE myapp SET yb_enable_read_committed_isolation = true;

ALTER DATABASE myapp RENAME TO myapp_v2;
ALTER DATABASE myapp OWNER TO newowner;

DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;

-- 2. 模式管理
CREATE SCHEMA myschema;
CREATE SCHEMA IF NOT EXISTS myschema AUTHORIZATION myuser;

DROP SCHEMA myschema CASCADE;

SET search_path TO myschema, public;

-- 3. 用户与角色
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

-- 4. 权限管理
GRANT CONNECT ON DATABASE myapp TO myuser;
GRANT USAGE ON SCHEMA myschema TO analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA myschema TO analyst;
GRANT INSERT, UPDATE, DELETE ON myschema.users TO developer;

ALTER DEFAULT PRIVILEGES IN SCHEMA myschema
    GRANT SELECT ON TABLES TO analyst;

REVOKE ALL ON SCHEMA myschema FROM myuser;

-- ============================================================
-- YCQL 模式（兼容 Cassandra）
-- ============================================================

-- 1. Keyspace 管理
CREATE KEYSPACE myapp;
CREATE KEYSPACE IF NOT EXISTS myapp
    WITH REPLICATION = {'class': 'SimpleStrategy', 'replication_factor': 3};

DROP KEYSPACE myapp;

USE myapp;

-- 2. 角色管理（YCQL）
CREATE ROLE 'myuser' WITH PASSWORD = 'secret123' AND LOGIN = true;
ALTER ROLE 'myuser' WITH PASSWORD = 'newsecret';
DROP ROLE 'myuser';

-- 3. 权限管理（YCQL）
GRANT ALL ON KEYSPACE myapp TO 'myuser';
GRANT SELECT ON TABLE myapp.users TO 'myuser';
REVOKE SELECT ON TABLE myapp.users FROM 'myuser';

-- ============================================================
-- 5. 查询元数据
-- ============================================================

-- YSQL
SELECT current_database(), current_schema(), current_user;
SELECT datname FROM pg_database;
SELECT nspname FROM pg_namespace;
SELECT rolname, rolsuper, rolcanlogin FROM pg_roles;

-- YugabyteDB 特有
-- $ yb-admin list_all_masters
-- $ yb-admin list_all_tablet_servers

-- 注意：YugabyteDB 是分布式 SQL 数据库
-- YSQL 完全兼容 PostgreSQL 的用户/权限管理
-- YCQL 兼容 Cassandra 的角色管理
-- 推荐使用 YSQL 模式
