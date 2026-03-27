-- Flink SQL: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] Apache Flink Documentation - CREATE DATABASE
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/create/#create-database
--   [2] Apache Flink Documentation - CREATE CATALOG
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/create/#create-catalog

-- ============================================================
-- Flink SQL 命名层级: catalog > database > table
-- 默认 catalog: default_catalog（内存）
-- 默认 database: default_database
-- Flink 是流处理引擎，不管理用户/权限
-- ============================================================

-- ============================================================
-- 1. Catalog 管理
-- ============================================================

-- 内存 Catalog（默认）
CREATE CATALOG my_catalog
WITH (
    'type' = 'generic_in_memory'
);

-- Hive Catalog（持久化元数据）
CREATE CATALOG hive_catalog
WITH (
    'type' = 'hive',
    'hive-conf-dir' = '/etc/hive/conf',
    'default-database' = 'mydb'
);

-- JDBC Catalog（连接外部数据库）
CREATE CATALOG pg_catalog
WITH (
    'type' = 'jdbc',
    'default-database' = 'mydb',
    'username' = 'flink',
    'password' = 'secret',
    'base-url' = 'jdbc:postgresql://host:5432'
);

-- Iceberg Catalog
CREATE CATALOG iceberg_catalog
WITH (
    'type' = 'iceberg',
    'catalog-type' = 'hive',
    'uri' = 'thrift://metastore:9083',
    'warehouse' = 's3://bucket/warehouse'
);

-- 切换 catalog
USE CATALOG hive_catalog;

-- 查看 catalog
SHOW CATALOGS;
SHOW CURRENT CATALOG;

-- 删除 catalog
DROP CATALOG my_catalog;

-- ============================================================
-- 2. Database 管理
-- ============================================================

CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;

CREATE DATABASE myapp
    COMMENT 'Main application database'
    WITH ('owner' = 'data_team');

-- 修改数据库
ALTER DATABASE myapp SET ('owner' = 'new_team');

-- 删除数据库
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp CASCADE;

-- 切换数据库
USE myapp;

-- 查看
SHOW DATABASES;
SHOW CURRENT DATABASE;

-- ============================================================
-- 3. 用户与权限
-- ============================================================

-- Flink SQL 没有内建的用户/权限管理
-- 它是计算引擎，不是数据库
-- 安全性依赖：
-- 1. 底层存储系统的权限（Hive, Kafka, etc.）
-- 2. Flink 集群的安全配置（Kerberos）
-- 3. Flink SQL Gateway 的认证

-- ============================================================
-- 4. 查询元数据
-- ============================================================

SHOW CATALOGS;
SHOW CURRENT CATALOG;
SHOW DATABASES;
SHOW CURRENT DATABASE;
SHOW TABLES;
SHOW VIEWS;
SHOW FUNCTIONS;

-- 查看建表语句
SHOW CREATE TABLE my_table;

-- 注意：Flink SQL 是流批一体的计算引擎
-- Catalog 定义了元数据存储方式
-- Database 是逻辑分组
-- 不管理用户、角色、权限
