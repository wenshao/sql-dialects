-- Apache Doris: 数据库、Schema 与用户管理
--
-- 参考资料:
--   [1] Doris Documentation - CREATE DATABASE / USER
--       https://doris.apache.org/docs/sql-manual/sql-statements/

-- ============================================================
-- 1. 命名层级: FE 兼容 MySQL 协议
-- ============================================================
-- Doris 层级: cluster > database > table
-- 没有独立的 schema 层(与 MySQL 一致，database = schema)。
--
-- 对比:
--   StarRocks:  相同(同源，MySQL 协议兼容)
--   MySQL:      database = schema(可互换)
--   PostgreSQL: cluster > database > schema > table(多一层 schema)
--   ClickHouse: database > table(无 schema 层)
--   BigQuery:   project > dataset > table(dataset ≈ database)

-- ============================================================
-- 2. 数据库管理
-- ============================================================
CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;
CREATE DATABASE myapp PROPERTIES (
    'replication_allocation' = 'tag.location.default:3'
);

ALTER DATABASE myapp SET PROPERTIES (
    'replication_allocation' = 'tag.location.default:2'
);
ALTER DATABASE myapp RENAME new_myapp;

DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;
DROP DATABASE myapp FORCE;

-- 回收站恢复(Doris 独有)
RECOVER DATABASE myapp;

USE myapp;
SHOW DATABASES;

-- ============================================================
-- 3. 用户管理 (MySQL 兼容语法)
-- ============================================================
CREATE USER 'myuser'@'%' IDENTIFIED BY 'secret123';
CREATE USER 'myuser'@'10.0.0.%' IDENTIFIED BY 'secret123';
CREATE USER 'myuser' IDENTIFIED BY 'secret123' DEFAULT ROLE 'analyst';

ALTER USER 'myuser' IDENTIFIED BY 'newsecret';
SET PASSWORD FOR 'myuser' = PASSWORD('newsecret');
DROP USER 'myuser';

-- ============================================================
-- 4. 角色管理 (RBAC)
-- ============================================================
CREATE ROLE analyst;
CREATE ROLE developer;
-- 系统角色: admin, operator

GRANT analyst TO 'myuser'@'%';
SET DEFAULT ROLE analyst TO 'myuser'@'%';
REVOKE analyst FROM 'myuser'@'%';
DROP ROLE analyst;

-- ============================================================
-- 5. 权限管理
-- ============================================================
-- 全局权限
GRANT ADMIN_PRIV ON *.*.* TO 'myuser'@'%';

-- 数据库权限
GRANT SELECT_PRIV ON myapp.*.* TO 'myuser'@'%';
GRANT LOAD_PRIV ON myapp.*.* TO 'myuser'@'%';

-- 表权限
GRANT SELECT_PRIV ON myapp.users TO 'myuser'@'%';
GRANT ALTER_PRIV, LOAD_PRIV ON myapp.users TO 'myuser'@'%';

-- 角色权限
GRANT SELECT_PRIV ON myapp.*.* TO ROLE 'analyst';

-- Catalog 权限(2.0+)
GRANT USAGE_PRIV ON CATALOG hive_catalog TO 'myuser'@'%';

-- Workload Group 权限(2.1+)
GRANT USAGE_PRIV ON WORKLOAD GROUP 'normal' TO 'myuser'@'%';

SHOW GRANTS FOR 'myuser'@'%';
REVOKE SELECT_PRIV ON myapp.*.* FROM 'myuser'@'%';

-- ============================================================
-- 6. Workload Group (2.0+，资源隔离)
-- ============================================================
CREATE WORKLOAD GROUP 'rg_report' PROPERTIES (
    'cpu_share' = '1024',
    'memory_limit' = '30%',
    'max_concurrency' = '10'
);

-- 设计分析:
--   Workload Group 是 Doris 的资源隔离方案。
--   对比 StarRocks 的 Resource Group: 功能类似，语法差异。
--   对比 BigQuery 的 Reservation: 更精细的资源管理。
--   对比 Snowflake 的 Warehouse: 独立计算资源(更彻底的隔离)。

-- ============================================================
-- 7. Row Policy (2.1+，行级权限)
-- ============================================================
-- CREATE ROW POLICY policy_name ON db.table
-- AS RESTRICTIVE TO 'user'
-- USING (city = 'Beijing');
--
-- 对比: StarRocks 不支持行级权限。这是 Doris 的差异化功能。

-- ============================================================
-- 8. 查询元数据
-- ============================================================
SELECT DATABASE(), USER(), CURRENT_USER();
SHOW DATABASES;
SHOW TABLES FROM myapp;
SHOW GRANTS;
SHOW ROLES;
SELECT * FROM information_schema.schemata;
