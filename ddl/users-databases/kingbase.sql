-- KingbaseES（人大金仓）: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] KingbaseES 文档 - CREATE DATABASE
--       https://help.kingbase.com.cn/v8/index.html
--   [2] KingbaseES 文档 - 用户与权限管理

-- ============================================================
-- KingbaseES 兼容 PostgreSQL（也支持 Oracle 兼容模式）
-- 命名层级: cluster > database > schema > object
-- 默认: security 数据库, public 模式
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

CREATE DATABASE myapp;

CREATE DATABASE myapp
    OWNER = myuser
    ENCODING = 'UTF8'
    TEMPLATE = template0;

ALTER DATABASE myapp SET timezone TO 'Asia/Shanghai';
ALTER DATABASE myapp RENAME TO myapp_v2;
ALTER DATABASE myapp OWNER TO newowner;

DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;

-- ============================================================
-- 2. 模式管理
-- ============================================================

CREATE SCHEMA myschema;
CREATE SCHEMA IF NOT EXISTS myschema;
CREATE SCHEMA myschema AUTHORIZATION myuser;

DROP SCHEMA myschema;
DROP SCHEMA myschema CASCADE;

SET search_path TO myschema, public;
SHOW search_path;

-- ============================================================
-- 3. 用户与角色管理
-- ============================================================

CREATE USER myuser WITH PASSWORD 'Secret123!';

CREATE ROLE myuser WITH
    LOGIN
    PASSWORD 'Secret123!'
    CREATEDB
    CREATEROLE
    VALID UNTIL '2026-12-31';

CREATE ROLE analyst NOLOGIN;
CREATE ROLE developer NOLOGIN;

ALTER USER myuser WITH PASSWORD 'NewSecret456!';
ALTER ROLE analyst RENAME TO data_analyst;

GRANT analyst TO myuser;
REVOKE analyst FROM myuser;

DROP USER myuser;
DROP ROLE analyst;

-- ============================================================
-- 4. 权限管理
-- ============================================================

GRANT CONNECT ON DATABASE myapp TO myuser;
GRANT USAGE ON SCHEMA myschema TO analyst;
GRANT CREATE ON SCHEMA myschema TO developer;

GRANT SELECT ON ALL TABLES IN SCHEMA myschema TO analyst;
GRANT INSERT, UPDATE, DELETE ON myschema.users TO developer;

ALTER DEFAULT PRIVILEGES IN SCHEMA myschema
    GRANT SELECT ON TABLES TO analyst;

REVOKE ALL ON SCHEMA myschema FROM myuser;

-- ============================================================
-- 5. 三权分立（KingbaseES 安全特性）
-- ============================================================

-- KingbaseES 支持三权分立安全模式：
-- - SYSADMIN: 系统管理员（管理数据库对象）
-- - SYSSAO: 安全管理员（管理安全策略）
-- - SYSAUDITOR: 审计管理员（管理审计）

-- 启用三权分立后，不同管理员各司其职，互相制约

-- ============================================================
-- 6. 查询元数据
-- ============================================================

SELECT current_database(), current_schema(), current_user;

SELECT datname FROM sys_database;
SELECT nspname FROM sys_namespace;
SELECT rolname, rolsuper, rolcanlogin FROM sys_roles;

-- 也支持 PostgreSQL 系统表
SELECT datname FROM pg_database;
SELECT rolname FROM pg_roles;

-- KingbaseES 特有系统表前缀: sys_ (对应 PostgreSQL 的 pg_)
