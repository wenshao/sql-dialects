-- StarRocks: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] StarRocks Documentation - CREATE DATABASE
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/database/CREATE_DATABASE/
--   [2] StarRocks Documentation - CREATE USER
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/account-management/CREATE_USER/

-- ============================================================
-- StarRocks 兼容 MySQL 协议
-- 命名层级: cluster > database > table
-- 没有独立的 schema 层
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;

CREATE DATABASE myapp
PROPERTIES (
    'replication_num' = '3'                     -- 副本数
);

-- 修改数据库
ALTER DATABASE myapp SET PROPERTIES ('replication_num' = '2');
ALTER DATABASE myapp RENAME new_myapp;

-- 删除数据库
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;
DROP DATABASE myapp FORCE;

-- 恢复数据库
RECOVER DATABASE myapp;

-- 切换数据库
USE myapp;

SHOW DATABASES;

-- ============================================================
-- 2. 用户管理
-- ============================================================

CREATE USER 'myuser'@'%' IDENTIFIED BY 'secret123';
CREATE USER IF NOT EXISTS 'myuser' IDENTIFIED BY 'secret123';
CREATE USER 'myuser'@'10.0.0.%' IDENTIFIED BY 'secret123';

CREATE USER 'myuser' IDENTIFIED BY 'secret123'
    DEFAULT ROLE 'analyst';

-- 修改用户
ALTER USER 'myuser' IDENTIFIED BY 'newsecret';
SET PASSWORD FOR 'myuser' = PASSWORD('newsecret');

-- 删除用户
DROP USER 'myuser';

-- ============================================================
-- 3. 角色管理
-- ============================================================

CREATE ROLE analyst;
CREATE ROLE developer;

-- 系统角色: root, db_admin, cluster_admin, user_admin

GRANT analyst TO 'myuser'@'%';
SET DEFAULT ROLE analyst TO 'myuser';

REVOKE analyst FROM 'myuser'@'%';
DROP ROLE analyst;

-- ============================================================
-- 4. 权限管理
-- ============================================================

-- 全局权限
GRANT CREATE DATABASE ON CATALOG default_catalog TO 'myuser';

-- 数据库权限
GRANT ALL ON DATABASE myapp TO 'myuser';

-- 表权限
GRANT SELECT ON myapp.users TO 'myuser';
GRANT INSERT, DELETE ON myapp.users TO ROLE 'developer';

-- External Catalog 权限（StarRocks 3.0+）
GRANT USAGE ON CATALOG hive_catalog TO 'myuser';
GRANT SELECT ON ALL TABLES IN DATABASE hive_catalog.mydb TO ROLE 'analyst';

-- 查看权限
SHOW GRANTS FOR 'myuser';

-- 收回权限
REVOKE SELECT ON myapp.users FROM 'myuser';

-- ============================================================
-- 5. 资源管理
-- ============================================================

-- 资源组（StarRocks 2.2+）
CREATE RESOURCE GROUP rg_report
    TO (user='analyst', role='analyst', query_type in ('SELECT'))
    WITH (
        'cpu_core_limit' = '10',
        'mem_limit' = '30%',
        'concurrency_limit' = '20'
    );

ALTER RESOURCE GROUP rg_report
    WITH ('concurrency_limit' = '30');

DROP RESOURCE GROUP rg_report;

-- ============================================================
-- 6. Catalog 管理（StarRocks 3.0+ 多源查询）
-- ============================================================

CREATE EXTERNAL CATALOG hive_catalog
PROPERTIES (
    'type' = 'hive',
    'hive.metastore.uris' = 'thrift://metastore:9083'
);

CREATE EXTERNAL CATALOG iceberg_catalog
PROPERTIES (
    'type' = 'iceberg',
    'iceberg.catalog.type' = 'rest',
    'iceberg.catalog.uri' = 'http://rest-catalog:8181'
);

SET CATALOG hive_catalog;
DROP CATALOG hive_catalog;

SHOW CATALOGS;

-- ============================================================
-- 7. 查询元数据
-- ============================================================

SELECT DATABASE(), USER(), CURRENT_USER();

SHOW DATABASES;
SHOW GRANTS;
SHOW ROLES;

SELECT * FROM information_schema.schemata;
