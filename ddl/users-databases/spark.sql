-- Spark SQL: 数据库、Catalog 与用户管理
--
-- 参考资料:
--   [1] Spark SQL Reference - DDL
--       https://spark.apache.org/docs/latest/sql-ref-syntax-ddl.html
--   [2] Spark SQL - Multi-Catalog Support
--       https://spark.apache.org/docs/latest/sql-data-sources-v2.html
--   [3] Databricks Unity Catalog
--       https://docs.databricks.com/en/data-governance/unity-catalog/index.html

-- ============================================================
-- 1. 命名空间层级: Catalog > Database > Table
-- ============================================================

-- Spark SQL 的三级命名空间（Spark 3.0+）:
--   catalog.database.table
--   默认 catalog:   spark_catalog（基于 Hive Metastore）
--   默认 database:  default
--   DATABASE 和 SCHEMA 是完全同义的关键字
--
-- 设计分析:
--   Spark 3.0 之前只有两级（database.table），与 Hive 一致。
--   三级命名空间的引入是为了支持可插拔 Catalog（如 Iceberg Catalog、Unity Catalog）。
--   这使得一条 SQL 可以跨数据源查询: SELECT * FROM hive.db.t1 JOIN iceberg.db.t2 ...
--
-- 对比:
--   MySQL:      schema = database（两级: database.table），无 Catalog 层
--   PostgreSQL: 三级（catalog.schema.table），但 catalog = 数据库实例，跨 Catalog 查询需 dblink
--   SQL Server: 三级（server.database.schema.table），跨 Server 需 Linked Server
--   Trino:      三级（catalog.schema.table），每个 Catalog 对应一个 Connector
--   BigQuery:   三级（project.dataset.table）
--   MaxCompute: 两级（project.schema.table，project 类似 Catalog）
--   Flink SQL:  三级（catalog.database.table），CatalogManager 管理多 Catalog
--
-- 对引擎开发者的启示:
--   三级命名空间已成为现代 SQL 引擎的标配。Trino 和 Spark 的 Catalog 抽象
--   特别值得参考——每个 Catalog 后面可以是完全不同的数据源。
--   如果你的引擎需要联邦查询能力，Catalog 层是必要的抽象。

-- ============================================================
-- 2. Database / Schema 管理
-- ============================================================

CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;
CREATE SCHEMA myapp;                            -- 完全等价

CREATE DATABASE myapp
    COMMENT '主应用数据库'
    LOCATION '/user/spark/warehouse/myapp'
    WITH DBPROPERTIES ('owner' = 'data_team', 'env' = 'prod');

-- 修改数据库
ALTER DATABASE myapp SET DBPROPERTIES ('env' = 'staging');
ALTER DATABASE myapp SET OWNER TO USER alice;   -- Spark 3.4+
ALTER DATABASE myapp SET LOCATION '/new/path/myapp';

-- 删除数据库
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp CASCADE;          -- 级联删除所有表
DROP DATABASE myapp RESTRICT;                   -- 非空则报错（默认行为）

-- 切换数据库
USE myapp;

-- 查看数据库
SHOW DATABASES;
SHOW DATABASES LIKE 'my*';
DESCRIBE DATABASE myapp;
DESCRIBE DATABASE EXTENDED myapp;

-- 设计分析:
--   Spark 的 DATABASE 本质上是 Hive Metastore 中的一个逻辑分组。
--   每个 DATABASE 对应一个 LOCATION（文件系统目录），该目录下存放所有 Managed Table 的数据。
--   CASCADE 删除会物理删除 Managed Table 的数据文件——这是一个危险操作。
--   External Table 的数据文件不受 CASCADE 影响。

-- ============================================================
-- 3. Catalog 管理（Spark 3.0+）
-- ============================================================

SHOW CATALOGS;                                  -- Spark 3.4+
USE CATALOG my_catalog;                         -- Spark 3.4+

SELECT current_database();
SELECT current_catalog();                       -- Spark 3.4+

-- 可插拔 Catalog 架构:
-- Spark 通过配置注册多个 Catalog:
-- spark.sql.catalog.spark_catalog = org.apache.spark.sql.hive.HiveSessionCatalog
-- spark.sql.catalog.iceberg = org.apache.iceberg.spark.SparkCatalog
-- spark.sql.catalog.unity = com.databricks.sql.UnityCatalog
--
-- 之后在 SQL 中可以直接引用:
-- SELECT * FROM iceberg.db.events;
-- SELECT * FROM unity.schema.users;
--
-- 对比:
--   Trino:     每个 Catalog 在 etc/catalog/ 下有独立配置文件
--   Flink SQL: CatalogManager 管理多个 Catalog 实例
--   Spark:     通过 spark.sql.catalog.xxx 配置项注册

-- ============================================================
-- 4. 用户与权限: Spark SQL 没有内建权限系统
-- ============================================================

-- Spark SQL 本身不管理用户、角色和权限。
-- 这是其"计算引擎"定位的必然结果——安全由底层平台提供。
--
-- 权限管理方案（按推荐程度排序）:
--
-- 方案 1: Databricks Unity Catalog（最完善）
--   统一的三级命名空间权限管理
--   支持行级安全（Row Filter）、列级权限、数据脱敏（Column Masking）
--   与 Databricks 平台深度集成
--
-- 方案 2: Apache Ranger（开源 Hadoop 生态）
--   集中式策略管理，支持 Spark、Hive、HBase、Kafka 等
--   基于 Ranger Plugin 拦截 SQL 执行
--
-- 方案 3: Hive SQL Standard Authorization
--   通过 HiveServer2/Thrift Server 的 SQL 标准授权
--   支持 GRANT/REVOKE 语法
--
-- 方案 4: 存储层权限
--   HDFS ACL / S3 IAM Policy / ADLS RBAC
--   最底层的安全屏障，但粒度粗（文件/目录级别）
--
-- 对比:
--   MySQL:      内建完整的用户/角色/权限体系（CREATE USER / GRANT / REVOKE）
--   PostgreSQL: 内建完整权限体系 + 行级安全策略（RLS）
--   BigQuery:   依赖 Google Cloud IAM（类似 Spark 依赖外部平台）
--   Snowflake:  内建完整 RBAC + 行级安全 + 数据脱敏
--   Trino:      可插拔认证和授权（File-based / Ranger / OPA）

-- 如果 SQL Standard Authorization 已启用（Thrift Server）:
-- GRANT SELECT ON TABLE users TO USER alice;
-- REVOKE SELECT ON TABLE users FROM USER alice;
-- CREATE ROLE analyst;
-- GRANT ROLE analyst TO USER alice;
-- SHOW GRANT ON TABLE users;

-- ============================================================
-- 5. 常用配置（影响 SQL 行为）
-- ============================================================

SET spark.sql.catalogImplementation = hive;     -- 使用 Hive Metastore
SET spark.sql.shuffle.partitions = 200;          -- Shuffle 分区数
SET spark.sql.adaptive.enabled = true;           -- 启用 AQE
SET spark.sql.ansi.enabled = true;               -- 启用 ANSI 模式

-- 查看所有配置
SET -v;

-- 查看元数据
SHOW DATABASES;
SHOW TABLES IN myapp;
SHOW CREATE TABLE myapp.users;
DESCRIBE DATABASE EXTENDED myapp;

-- ============================================================
-- 6. 版本演进
-- ============================================================
-- Spark 1.0: DATABASE 管理（继承 Hive 语义）
-- Spark 2.0: 多 Database 支持完善
-- Spark 3.0: 可插拔 Catalog API（DataSource V2），三级命名空间
-- Spark 3.4: SHOW CATALOGS, USE CATALOG, current_catalog()
-- Spark 4.0: Catalog 级别的 Schema 绑定增强
--
-- 限制:
--   Spark SQL 本身不是数据库——数据库/表元数据存在 Hive Metastore 或其他 Catalog 中
--   无内建用户/角色/权限管理（依赖 Ranger、Unity Catalog 或存储层权限）
--   无内建审计日志（依赖 Spark History Server 或平台级审计）
--   跨 Catalog 查询的一致性不保证（不同 Catalog 可能有不同的事务语义）
