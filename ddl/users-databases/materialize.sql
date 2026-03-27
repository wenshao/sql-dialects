-- Materialize: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] Materialize Documentation - CREATE DATABASE
--       https://materialize.com/docs/sql/create-database/
--   [2] Materialize Documentation - CREATE ROLE
--       https://materialize.com/docs/sql/create-role/

-- ============================================================
-- Materialize 兼容 PostgreSQL 协议
-- 命名层级: cluster > database > schema > object
-- 默认: materialize 数据库, public 模式
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;

-- 修改数据库
ALTER DATABASE myapp RENAME TO myapp_v2;
ALTER DATABASE myapp OWNER TO myuser;

-- 删除数据库
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp CASCADE;

-- 切换数据库（需要重新连接或 SET）
SET DATABASE = myapp;

-- ============================================================
-- 2. 模式管理
-- ============================================================

CREATE SCHEMA myschema;
CREATE SCHEMA IF NOT EXISTS myschema;

ALTER SCHEMA myschema RENAME TO myschema_v2;
ALTER SCHEMA myschema OWNER TO myuser;

DROP SCHEMA myschema;
DROP SCHEMA myschema CASCADE;

SET search_path = myschema, public;

-- ============================================================
-- 3. 角色管理
-- ============================================================

CREATE ROLE analyst;
CREATE ROLE developer LOGIN PASSWORD 'secret123';
CREATE ROLE myuser LOGIN SUPERUSER PASSWORD 'secret123';

-- 角色属性
CREATE ROLE limited_user
    LOGIN
    PASSWORD 'secret123'
    INHERIT;                                    -- 继承角色权限

ALTER ROLE analyst LOGIN;
ALTER ROLE myuser PASSWORD 'newsecret';
ALTER ROLE myuser RENAME TO newuser;

-- 角色继承
GRANT analyst TO myuser;
REVOKE analyst FROM myuser;

DROP ROLE analyst;

-- ============================================================
-- 4. 权限管理
-- ============================================================

GRANT USAGE ON DATABASE myapp TO analyst;
GRANT CREATE ON DATABASE myapp TO developer;

GRANT USAGE ON SCHEMA myschema TO analyst;
GRANT CREATE ON SCHEMA myschema TO developer;

GRANT SELECT ON TABLE myschema.users TO analyst;
GRANT ALL ON TABLE myschema.users TO developer;

-- Materialize 特有: CLUSTER 权限
GRANT USAGE ON CLUSTER my_cluster TO analyst;
GRANT CREATE ON CLUSTER my_cluster TO developer;

-- 默认权限
ALTER DEFAULT PRIVILEGES IN SCHEMA myschema
    GRANT SELECT ON TABLES TO analyst;

REVOKE SELECT ON TABLE myschema.users FROM analyst;

-- ============================================================
-- 5. Cluster 管理（Materialize 特有）
-- ============================================================

-- Cluster 是 Materialize 的计算资源单元
CREATE CLUSTER analytics SIZE = 'small';
CREATE CLUSTER analytics SIZE = 'medium', REPLICATION FACTOR = 2;

ALTER CLUSTER analytics SET (SIZE = 'large');

DROP CLUSTER analytics CASCADE;

-- 切换 cluster
SET CLUSTER = analytics;

SHOW CLUSTERS;

-- ============================================================
-- 6. 查询元数据
-- ============================================================

SELECT current_database(), current_schema(), current_role();

SHOW DATABASES;
SHOW SCHEMAS;
SHOW ROLES;
SHOW CLUSTERS;

SELECT * FROM mz_databases;
SELECT * FROM mz_schemas;
SELECT * FROM mz_roles;
SELECT * FROM mz_clusters;
