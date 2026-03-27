-- PostgreSQL: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] PostgreSQL Documentation - CREATE DATABASE
--       https://www.postgresql.org/docs/current/sql-createdatabase.html
--   [2] PostgreSQL Documentation - CREATE SCHEMA
--       https://www.postgresql.org/docs/current/sql-createschema.html
--   [3] PostgreSQL Documentation - CREATE USER / ROLE
--       https://www.postgresql.org/docs/current/sql-createuser.html

-- ============================================================
-- 命名层级: cluster > database > schema > object
-- 默认: postgres 数据库, public 模式
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

CREATE DATABASE myapp;

CREATE DATABASE myapp
    OWNER = myuser
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
    TEMPLATE = template0                        -- 使用干净模板
    TABLESPACE = pg_default
    CONNECTION LIMIT = 100;

-- 修改数据库
ALTER DATABASE myapp SET timezone TO 'Asia/Shanghai';
ALTER DATABASE myapp RENAME TO myapp_v2;
ALTER DATABASE myapp OWNER TO newowner;
ALTER DATABASE myapp SET search_path TO myschema, public;

-- 删除数据库
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;
DROP DATABASE myapp WITH (FORCE);               -- PostgreSQL 13+，强制断开连接

-- ============================================================
-- 2. 模式管理
-- ============================================================

CREATE SCHEMA myschema;
CREATE SCHEMA myschema AUTHORIZATION myuser;
CREATE SCHEMA IF NOT EXISTS myschema;

-- 删除模式
DROP SCHEMA myschema;
DROP SCHEMA myschema CASCADE;                   -- 级联删除所有对象

-- 设置默认模式搜索路径
SET search_path TO myschema, public;            -- 当前会话
ALTER DATABASE myapp SET search_path TO myschema, public;  -- 持久化

-- 查看当前搜索路径
SHOW search_path;

-- ============================================================
-- 3. 用户与角色管理
-- ============================================================

-- PostgreSQL 中 USER 和 ROLE 几乎等价，USER 自带 LOGIN 权限
CREATE USER myuser WITH PASSWORD 'secret123';

CREATE ROLE myuser WITH
    LOGIN                                       -- 允许登录
    PASSWORD 'secret123'
    CREATEDB                                    -- 允许创建数据库
    CREATEROLE                                  -- 允许创建角色
    VALID UNTIL '2026-12-31'                    -- 过期时间
    CONNECTION LIMIT 10;                        -- 连接数限制

-- 角色（不带登录权限）
CREATE ROLE analyst;
CREATE ROLE readonly NOLOGIN;

-- 修改用户
ALTER USER myuser WITH PASSWORD 'newsecret';
ALTER ROLE myuser RENAME TO newname;
ALTER ROLE myuser SET statement_timeout TO '30s';

-- 删除用户
DROP USER myuser;
DROP ROLE IF EXISTS myuser;

-- ============================================================
-- 4. 权限管理
-- ============================================================

-- 数据库权限
GRANT CONNECT ON DATABASE myapp TO myuser;
GRANT CREATE ON DATABASE myapp TO myuser;

-- 模式权限
GRANT USAGE ON SCHEMA myschema TO myuser;
GRANT CREATE ON SCHEMA myschema TO myuser;
GRANT ALL ON SCHEMA myschema TO myuser;

-- 表权限
GRANT SELECT ON ALL TABLES IN SCHEMA myschema TO readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON myschema.users TO myuser;

-- 默认权限（新建对象自动授权）
ALTER DEFAULT PRIVILEGES IN SCHEMA myschema
    GRANT SELECT ON TABLES TO readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA myschema
    GRANT USAGE ON SEQUENCES TO myuser;

-- 角色继承
GRANT analyst TO myuser;                        -- myuser 继承 analyst 权限
REVOKE analyst FROM myuser;

-- 收回权限
REVOKE ALL ON SCHEMA myschema FROM myuser;

-- ============================================================
-- 5. 查询元数据
-- ============================================================

-- 列出数据库
SELECT datname FROM pg_database WHERE datistemplate = false;

-- 列出模式
SELECT schema_name FROM information_schema.schemata;

-- 列出用户和角色
SELECT rolname, rolsuper, rolcreatedb, rolcanlogin
FROM pg_roles;

-- 查看当前连接信息
SELECT current_database(), current_schema(), current_user, session_user;

-- ============================================================
-- 6. 常用配置
-- ============================================================

-- pg_hba.conf 控制客户端认证（非 SQL）
-- postgresql.conf 控制服务器参数（非 SQL）

-- 运行时参数
ALTER SYSTEM SET max_connections = 200;         -- 需重启
SELECT pg_reload_conf();                        -- 重新加载配置
