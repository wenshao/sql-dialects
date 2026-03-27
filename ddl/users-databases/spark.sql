-- Spark SQL: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] Apache Spark Documentation - SQL Reference: DDL
--       https://spark.apache.org/docs/latest/sql-ref-syntax-ddl.html
--   [2] Apache Spark Documentation - Catalog API
--       https://spark.apache.org/docs/latest/api/sql/index.html

-- ============================================================
-- Spark SQL 命名层级（Spark 3.4+）:
--   catalog > database(schema) > object
-- DATABASE 和 SCHEMA 是同义词
-- 默认 catalog: spark_catalog
-- 默认 database: default
-- ============================================================

-- ============================================================
-- 1. Database / Schema 管理
-- ============================================================

CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;
CREATE SCHEMA myapp;                            -- 同义词

CREATE DATABASE myapp
    COMMENT 'Main application database'
    LOCATION '/user/spark/warehouse/myapp'
    WITH DBPROPERTIES ('owner' = 'data_team', 'env' = 'prod');

-- 修改数据库
ALTER DATABASE myapp SET DBPROPERTIES ('env' = 'staging');
ALTER DATABASE myapp SET OWNER TO USER alice;   -- Spark 3.4+
ALTER DATABASE myapp SET LOCATION '/new/path/myapp';

-- 删除数据库
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp CASCADE;
DROP DATABASE myapp RESTRICT;                   -- 非空则报错（默认）

-- 切换数据库
USE myapp;

-- 查看数据库
SHOW DATABASES;
SHOW DATABASES LIKE 'my*';
DESCRIBE DATABASE myapp;
DESCRIBE DATABASE EXTENDED myapp;

-- ============================================================
-- 2. Catalog 管理（Spark 3.0+）
-- ============================================================

-- 查看可用 catalog
SHOW CATALOGS;                                  -- Spark 3.4+

-- 切换 catalog
USE CATALOG my_catalog;                         -- Spark 3.4+

-- Spark 支持可插拔 catalog：
-- - spark_catalog: 默认（基于 Hive Metastore）
-- - 自定义 catalog（通过配置 spark.sql.catalog.xxx）

-- ============================================================
-- 3. 用户与权限
-- ============================================================

-- Spark SQL 本身没有内建的用户/角色/权限管理
-- 权限管理依赖底层系统：
-- 1. HDFS 文件权限
-- 2. Apache Ranger / Sentry
-- 3. Databricks Unity Catalog（Databricks 环境）
-- 4. 自定义 Catalog 插件

-- 如果连接 Hive Metastore，可使用 Hive 的授权机制
-- GRANT SELECT ON TABLE myapp.users TO USER alice;
-- REVOKE SELECT ON TABLE myapp.users FROM USER alice;

-- ============================================================
-- 4. 查询元数据
-- ============================================================

SELECT current_database();
SELECT current_catalog();                       -- Spark 3.4+

SHOW DATABASES;
SHOW TABLES IN myapp;
SHOW CREATE TABLE myapp.users;

DESCRIBE DATABASE EXTENDED myapp;

-- ============================================================
-- 5. 常用配置（通过 SparkSession 设置）
-- ============================================================

-- 默认数据库
SET spark.sql.catalogImplementation = hive;     -- 使用 Hive Metastore

-- SQL 语法中的配置
SET spark.sql.shuffle.partitions = 200;
SET spark.sql.adaptive.enabled = true;

-- 查看所有配置
SET -v;

-- 注意：Spark SQL 是计算引擎，不是独立数据库
-- 数据库/表元数据存储在 Hive Metastore 或其他 catalog 中
-- 数据存储在 HDFS / S3 / 本地文件系统
