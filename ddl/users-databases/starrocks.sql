-- StarRocks: 数据库、Schema 与用户管理
--
-- 参考资料:
--   [1] StarRocks Documentation - CREATE DATABASE / USER
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/

-- ============================================================
-- 1. 命名层级: MySQL 协议兼容
-- ============================================================
-- 层级: cluster > database > table (与 Doris 相同)。
-- 无独立 schema 层。database = schema(MySQL 兼容)。

-- ============================================================
-- 2. 数据库管理
-- ============================================================
CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;

ALTER DATABASE myapp RENAME new_myapp;

DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;
DROP DATABASE myapp FORCE;

-- 回收站恢复
RECOVER DATABASE myapp;

USE myapp;
SHOW DATABASES;

-- ============================================================
-- 3. 用户管理
-- ============================================================
CREATE USER 'myuser'@'%' IDENTIFIED BY 'secret123';
CREATE USER 'myuser'@'10.0.0.%' IDENTIFIED BY 'secret123';

ALTER USER 'myuser' IDENTIFIED BY 'newsecret';
SET PASSWORD FOR 'myuser' = PASSWORD('newsecret');
DROP USER 'myuser';

-- ============================================================
-- 4. 角色管理 (RBAC)
-- ============================================================
CREATE ROLE analyst;
CREATE ROLE developer;

GRANT analyst TO 'myuser'@'%';
SET DEFAULT ROLE analyst TO 'myuser'@'%';
REVOKE analyst FROM 'myuser'@'%';
DROP ROLE analyst;

-- ============================================================
-- 5. 权限管理
-- ============================================================
GRANT SELECT ON myapp.* TO 'myuser'@'%';
GRANT INSERT ON myapp.* TO 'myuser'@'%';
GRANT ALL ON myapp.* TO 'myuser'@'%';

-- 表级权限
GRANT SELECT ON myapp.users TO 'myuser'@'%';
GRANT ALTER ON myapp.users TO 'myuser'@'%';

-- External Catalog 权限(2.3+)
GRANT USAGE ON CATALOG hive_catalog TO 'myuser'@'%';

SHOW GRANTS FOR 'myuser'@'%';
REVOKE SELECT ON myapp.* FROM 'myuser'@'%';

-- ============================================================
-- 6. Resource Group (资源隔离)
-- ============================================================
CREATE RESOURCE GROUP rg_report TO (user='myuser')
WITH ('cpu_core_limit'='10', 'mem_limit'='30%');

-- 设计分析:
--   StarRocks Resource Group vs Doris Workload Group:
--     语法差异: StarRocks 用 RESOURCE GROUP，Doris 用 WORKLOAD GROUP
--     功能类似: CPU/内存/并发控制
--
-- 对比:
--   Snowflake: Virtual Warehouse(独立计算资源，最彻底的隔离)
--   BigQuery:  Reservation + Assignment(Slot 级别隔离)

-- ============================================================
-- 7. StarRocks vs Doris 用户管理差异
-- ============================================================
-- 权限语法:
--   StarRocks: GRANT SELECT ON db.* TO user
--   Doris:     GRANT SELECT_PRIV ON db.*.* TO user
--   (StarRocks 更接近 SQL 标准，Doris 保留了 _PRIV 后缀)
--
-- 行级权限:
--   Doris 2.1+: 支持 Row Policy(行级权限)
--   StarRocks:   不支持行级权限
--
-- 对引擎开发者的启示:
--   MySQL 协议兼容让 Doris/StarRocks 可以使用现有 MySQL 工具和驱动。
--   但权限模型的差异(Doris 用 _PRIV 后缀)说明协议兼容 != 语法兼容。
--   迁移时需要注意 GRANT 语法的差异。

-- ============================================================
-- 8. 查询元数据
-- ============================================================
SELECT DATABASE(), USER(), CURRENT_USER();
SHOW DATABASES;
SHOW TABLES FROM myapp;
SHOW GRANTS;
SHOW ROLES;
SELECT * FROM information_schema.schemata;
