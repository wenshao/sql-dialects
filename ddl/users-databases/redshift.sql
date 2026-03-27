-- Redshift: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] AWS Redshift Documentation - CREATE DATABASE
--       https://docs.aws.amazon.com/redshift/latest/dg/r_CREATE_DATABASE.html
--   [2] AWS Redshift Documentation - CREATE USER
--       https://docs.aws.amazon.com/redshift/latest/dg/r_CREATE_USER.html

-- ============================================================
-- Redshift 命名层级: cluster > database > schema > object
-- 类似 PostgreSQL，但有 AWS 特定扩展
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

CREATE DATABASE myapp;

CREATE DATABASE myapp
    OWNER myuser
    CONNECTION LIMIT 100;                       -- 最大连接数

-- 从另一个数据库共享（数据共享）
-- CREATE DATABASE shared_db FROM DATASHARE my_datashare OF ACCOUNT '123456789012' NAMESPACE 'ns-id';

-- 修改数据库
ALTER DATABASE myapp OWNER TO newowner;
ALTER DATABASE myapp CONNECTION LIMIT 200;
ALTER DATABASE myapp RENAME TO myapp_v2;

-- 删除数据库
DROP DATABASE myapp;

-- 切换数据库（不支持 USE，必须重新连接）
-- Redshift 不支持跨数据库查询（除非通过数据共享）

-- ============================================================
-- 2. 模式管理
-- ============================================================

CREATE SCHEMA myschema;
CREATE SCHEMA IF NOT EXISTS myschema;
CREATE SCHEMA myschema AUTHORIZATION myuser;
CREATE SCHEMA myschema QUOTA 500 GB;            -- 模式配额（Redshift 特有）

-- 外部模式（查询 S3 / Glue / 联邦查询）
CREATE EXTERNAL SCHEMA ext_schema
FROM DATA CATALOG
DATABASE 'glue_db'
IAM_ROLE 'arn:aws:iam::123456789012:role/MyRole'
REGION 'us-east-1';

-- Redshift Spectrum 外部模式
CREATE EXTERNAL SCHEMA spectrum_schema
FROM DATA CATALOG
DATABASE 'spectrum_db'
IAM_ROLE 'arn:aws:iam::123456789012:role/MyRole'
CREATE EXTERNAL DATABASE IF NOT EXISTS;

-- 修改模式
ALTER SCHEMA myschema OWNER TO newowner;
ALTER SCHEMA myschema RENAME TO myschema_v2;
ALTER SCHEMA myschema QUOTA 1000 GB;

-- 删除模式
DROP SCHEMA myschema;
DROP SCHEMA myschema CASCADE;

-- 设置搜索路径
SET search_path TO myschema, public;
ALTER USER myuser SET search_path TO myschema, public;

-- ============================================================
-- 3. 用户管理
-- ============================================================

CREATE USER myuser PASSWORD 'Secret123!';

CREATE USER myuser
    PASSWORD 'Secret123!'
    CREATEDB                                    -- 允许创建数据库
    CONNECTION LIMIT 10
    VALID UNTIL '2026-12-31'
    SYSLOG ACCESS UNRESTRICTED;                 -- 系统日志访问

-- 超级用户
CREATE USER admin PASSWORD 'Secret123!' CREATEUSER;

-- 修改用户
ALTER USER myuser PASSWORD 'NewSecret456!';
ALTER USER myuser RENAME TO newuser;
ALTER USER myuser CONNECTION LIMIT 20;
ALTER USER myuser SET search_path TO myschema;

-- 删除用户
DROP USER myuser;

-- ============================================================
-- 4. 角色管理（Redshift 无独立 ROLE，通过 GROUP）
-- ============================================================

-- Redshift 使用 GROUP 而不是 ROLE
CREATE GROUP analysts;
CREATE GROUP developers;

ALTER GROUP analysts ADD USER myuser;
ALTER GROUP analysts DROP USER myuser;

DROP GROUP analysts;

-- Redshift 也支持 ROLE（较新版本）
CREATE ROLE analyst;
GRANT ROLE analyst TO myuser;

-- 系统角色
-- sys:superuser, sys:operator, sys:dba, sys:monitor

-- ============================================================
-- 5. 权限管理
-- ============================================================

-- 数据库权限
GRANT CREATE ON DATABASE myapp TO myuser;

-- 模式权限
GRANT USAGE ON SCHEMA myschema TO GROUP analysts;
GRANT CREATE ON SCHEMA myschema TO GROUP developers;
GRANT ALL ON SCHEMA myschema TO myuser;

-- 表权限
GRANT SELECT ON ALL TABLES IN SCHEMA myschema TO GROUP analysts;
GRANT SELECT, INSERT, UPDATE, DELETE ON myschema.users TO myuser;

-- 默认权限（新对象自动授权）
ALTER DEFAULT PRIVILEGES IN SCHEMA myschema
    GRANT SELECT ON TABLES TO GROUP analysts;

-- 收回权限
REVOKE SELECT ON myschema.users FROM myuser;

-- ============================================================
-- 6. 查询元数据
-- ============================================================

SELECT current_database(), current_schema(), current_user;

-- 列出数据库
SELECT datname, datdba, datconnlimit FROM pg_database;

-- 列出模式
SELECT nspname, nspowner FROM pg_namespace;

-- 列出用户
SELECT usename, usesysid, usesuper, valuntil FROM pg_user;

-- 列出组
SELECT groname, grolist FROM pg_group;

-- 查看权限
SELECT * FROM pg_tables WHERE schemaname = 'myschema';

-- Redshift 系统表
SELECT * FROM svv_users;
SELECT * FROM svv_roles;
SELECT * FROM svv_schema_privileges;
SELECT * FROM svv_relation_privileges;
