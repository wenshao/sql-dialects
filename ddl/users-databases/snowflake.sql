-- Snowflake: 数据库 / Schema / 用户管理
--
-- 参考资料:
--   [1] Snowflake SQL Reference - CREATE DATABASE
--       https://docs.snowflake.com/en/sql-reference/sql/create-database
--   [2] Snowflake SQL Reference - CREATE SCHEMA
--       https://docs.snowflake.com/en/sql-reference/sql/create-schema
--   [3] Snowflake SQL Reference - Access Control
--       https://docs.snowflake.com/en/user-guide/security-access-control-overview

-- ============================================================
-- 1. 三级命名空间: Database.Schema.Object
-- ============================================================

-- Snowflake 使用 Account > Database > Schema > Object 四层层次结构
-- 完全限定名: database_name.schema_name.object_name
SELECT * FROM analytics_db.public.users;

-- 创建数据库
CREATE DATABASE analytics_db;
CREATE DATABASE IF NOT EXISTS analytics_db
    DATA_RETENTION_TIME_IN_DAYS = 30
    COMMENT = 'Core analytics data warehouse';

-- 瞬态数据库（无 Fail-safe）
CREATE TRANSIENT DATABASE staging;

-- 创建 Schema
CREATE SCHEMA analytics_db.staging;
CREATE SCHEMA analytics_db.production
    WITH MANAGED ACCESS             -- 仅 schema owner 和被授权者可管理
    COMMENT = 'Production schema';

-- 设置当前上下文
USE DATABASE analytics_db;
USE SCHEMA staging;

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 Account 层: Snowflake 独有的顶层隔离
-- Account 是最顶层的隔离单元:
--   - 独立的 URL、用户体系、角色体系、计费
--   - 跨 Account 数据共享通过 Data Sharing（不复制数据）
--
-- 对比:
--   MySQL:       Server > Database > Table（Database = Schema）
--   PostgreSQL:  Cluster > Database > Schema > Table（跨 DB 不能 JOIN）
--   Oracle:      CDB > PDB > Schema > Table（多租户，12c+）
--   BigQuery:    Project > Dataset > Table（Dataset = Schema）
--   Redshift:    Cluster > Database > Schema > Table
--   Databricks:  Catalog > Schema > Table（Unity Catalog 三层）
--   MaxCompute:  Project > Schema > Table
--
-- 对引擎开发者的启示:
--   命名空间层次决定了多租户隔离粒度。
--   Snowflake Account 层提供最强隔离（独立存储/计算/网络）。
--   现代趋势: 三层命名空间 (Catalog + Schema + Object) 成为标配。

-- 2.2 Database CLONE: 零拷贝克隆整个数据库
CREATE DATABASE analytics_dev CLONE analytics_db;
-- 克隆整个数据库（所有 Schema、表、视图、存储过程等）
-- 基于 COW (Copy-on-Write)，秒级完成
-- 典型用途: 为开发/测试创建生产数据的完整副本
-- 类似 Git branch 概念但应用于数据库
--
-- 对比: 其他数据库无等价功能（需备份+恢复，耗时数小时/天）
--       Neon (PostgreSQL) 实现了类似的 Database Branching

-- ============================================================
-- 3. 用户与角色管理 (RBAC)
-- ============================================================

CREATE USER analyst_alice
    PASSWORD = 'StrongP@ss123'
    DEFAULT_ROLE = analyst_role
    DEFAULT_WAREHOUSE = analytics_wh
    DEFAULT_NAMESPACE = analytics_db.public
    MUST_CHANGE_PASSWORD = TRUE;

CREATE ROLE analyst_role;
CREATE ROLE data_engineer_role;

-- 角色层次
GRANT ROLE analyst_role TO ROLE data_engineer_role;
GRANT ROLE analyst_role TO USER analyst_alice;

-- 系统角色层次:
-- ACCOUNTADMIN > SECURITYADMIN > SYSADMIN > PUBLIC

-- ============================================================
-- 4. 权限管理与 FUTURE GRANTS
-- ============================================================

GRANT USAGE ON DATABASE analytics_db TO ROLE analyst_role;
GRANT USAGE ON SCHEMA analytics_db.public TO ROLE analyst_role;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics_db.public TO ROLE analyst_role;
GRANT USAGE ON WAREHOUSE analytics_wh TO ROLE analyst_role;

-- FUTURE GRANTS: 自动授权新对象（Snowflake 独有的运维利器）
GRANT SELECT ON FUTURE TABLES IN SCHEMA analytics_db.public TO ROLE analyst_role;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA analytics_db.public TO ROLE analyst_role;
-- 对比: PostgreSQL ALTER DEFAULT PRIVILEGES 类似 | MySQL 无等价功能

-- ============================================================
-- 5. Virtual Warehouse（计算资源）
-- ============================================================

CREATE WAREHOUSE analytics_wh
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 3
    SCALING_POLICY = 'STANDARD';

ALTER WAREHOUSE analytics_wh SET WAREHOUSE_SIZE = 'LARGE';
ALTER WAREHOUSE analytics_wh SUSPEND;
ALTER WAREHOUSE analytics_wh RESUME;

-- Warehouse 是三层架构的核心: 不同团队使用不同 Warehouse → 资源隔离 + 成本分摊
-- 对比: BigQuery 无 Warehouse（按扫描量计费） | Redshift 集群固定大小

-- ============================================================
-- 6. Data Sharing
-- ============================================================

CREATE SHARE analytics_share;
GRANT USAGE ON DATABASE analytics_db TO SHARE analytics_share;
GRANT SELECT ON TABLE analytics_db.public.users TO SHARE analytics_share;
ALTER SHARE analytics_share ADD ACCOUNTS = 'consumer_account';
-- 消费方: CREATE DATABASE shared_analytics FROM SHARE provider.analytics_share;

-- ============================================================
-- 7. 安全与治理
-- ============================================================

-- 网络策略
CREATE NETWORK POLICY office_only
    ALLOWED_IP_LIST = ('203.0.113.0/24')
    BLOCKED_IP_LIST = ('203.0.113.99');

-- 列级数据脱敏
CREATE MASKING POLICY email_mask AS (val STRING) RETURNS STRING ->
    CASE WHEN CURRENT_ROLE() IN ('ADMIN_ROLE') THEN val
    ELSE REGEXP_REPLACE(val, '.+@', '***@') END;
ALTER TABLE users ALTER COLUMN email SET MASKING POLICY email_mask;

-- 行访问策略
CREATE ROW ACCESS POLICY region_filter AS (region_val VARCHAR) RETURNS BOOLEAN ->
    CURRENT_ROLE() = 'ADMIN_ROLE' OR region_val = CURRENT_REGION();

-- ============================================================
-- 8. 元数据查询
-- ============================================================
SHOW DATABASES;
SHOW SCHEMAS IN DATABASE analytics_db;
SHOW USERS;
SHOW ROLES;
SHOW GRANTS TO ROLE analyst_role;
SELECT CURRENT_DATABASE(), CURRENT_SCHEMA(), CURRENT_ROLE(),
       CURRENT_USER(), CURRENT_WAREHOUSE();

-- 数据库删除与恢复
DROP DATABASE IF EXISTS staging;
UNDROP DATABASE staging;                  -- Time Travel 期内可恢复
