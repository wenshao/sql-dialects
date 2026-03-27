-- Vertica: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] Vertica Documentation - CREATE SCHEMA
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Statements/CREATESCHEMA.htm
--   [2] Vertica Documentation - CREATE USER
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Statements/CREATEUSER.htm

-- ============================================================
-- Vertica 命名层级: cluster > database > schema > object
-- 一个集群只有一个数据库（admintools 创建）
-- 通过 schema 组织数据
-- 默认 schema: public
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

-- Vertica 数据库通过 admintools 创建（非 SQL）
-- $ admintools -t create_db -s host1,host2,host3 -d mydb -p password

-- 一个 Vertica 集群 = 一个数据库
-- 不能通过 SQL 创建/删除数据库

-- ============================================================
-- 2. 模式管理
-- ============================================================

CREATE SCHEMA myschema;
CREATE SCHEMA IF NOT EXISTS myschema;
CREATE SCHEMA myschema AUTHORIZATION myuser;
CREATE SCHEMA myschema DEFAULT INCLUDE SCHEMA PRIVILEGES;

-- 修改模式
ALTER SCHEMA myschema OWNER TO newowner;
ALTER SCHEMA myschema RENAME TO myschema_v2;

-- 删除模式
DROP SCHEMA myschema;
DROP SCHEMA myschema CASCADE;                   -- 级联删除

-- 设置搜索路径
SET SEARCH_PATH TO myschema, public;
ALTER USER myuser SET SEARCH_PATH TO myschema, public;

SHOW SEARCH_PATH;

-- ============================================================
-- 3. 用户管理
-- ============================================================

CREATE USER myuser IDENTIFIED BY 'secret123';

CREATE USER myuser IDENTIFIED BY 'secret123'
    DEFAULT ROLE analyst
    SEARCH_PATH myschema, public
    RESOURCE POOL general
    MEMORYCAP '4G'
    TEMPSPACECAP '2G'
    RUNTIMECAP '00:30:00';                      -- 查询超时 30 分钟

-- 修改用户
ALTER USER myuser IDENTIFIED BY 'newsecret';
ALTER USER myuser DEFAULT ROLE developer;
ALTER USER myuser RENAME TO newuser;
ALTER USER myuser RESOURCE POOL dashboard_pool;
ALTER USER myuser ACCOUNT LOCK;
ALTER USER myuser ACCOUNT UNLOCK;

-- 删除用户
DROP USER myuser;
DROP USER myuser CASCADE;

-- ============================================================
-- 4. 角色管理
-- ============================================================

CREATE ROLE analyst;
CREATE ROLE developer;

GRANT analyst TO myuser;
ALTER USER myuser DEFAULT ROLE analyst;

-- 角色继承
GRANT analyst TO developer;

-- 系统角色：DBADMIN, PSEUDOSUPERUSER, DBDUSER, PUBLIC

SET ROLE analyst;

REVOKE analyst FROM myuser;
DROP ROLE analyst;

-- ============================================================
-- 5. 权限管理
-- ============================================================

-- 模式权限
GRANT USAGE ON SCHEMA myschema TO myuser;
GRANT CREATE ON SCHEMA myschema TO developer;
GRANT ALL ON SCHEMA myschema TO myuser;

-- 表权限
GRANT SELECT ON myschema.users TO analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA myschema TO analyst;
GRANT INSERT, UPDATE, DELETE ON myschema.users TO developer;

-- 列权限
GRANT SELECT (id, username) ON myschema.users TO myuser;

-- 资源池权限
GRANT USAGE ON RESOURCE POOL dashboard_pool TO analyst;

-- 收回权限
REVOKE SELECT ON myschema.users FROM analyst;

-- ============================================================
-- 6. 资源池
-- ============================================================

CREATE RESOURCE POOL dashboard_pool
    MEMORYSIZE '4G'
    MAXMEMORYSIZE '8G'
    MAXCONCURRENCY 10
    RUNTIMECAP '00:05:00'
    PRIORITY 5;

ALTER RESOURCE POOL dashboard_pool MAXCONCURRENCY 20;
DROP RESOURCE POOL dashboard_pool;

-- ============================================================
-- 7. 查询元数据
-- ============================================================

SELECT CURRENT_USER(), CURRENT_SCHEMA();

SELECT * FROM v_catalog.schemata;
SELECT * FROM v_catalog.users;
SELECT * FROM v_catalog.roles;
SELECT * FROM v_catalog.grants WHERE grantee = 'myuser';
SELECT * FROM v_catalog.resource_pools;

-- 使用 INFORMATION_SCHEMA
SELECT schema_name FROM information_schema.schemata;
