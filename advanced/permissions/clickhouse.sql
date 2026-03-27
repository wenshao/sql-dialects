-- ClickHouse: 权限管理
--
-- 参考资料:
--   [1] ClickHouse Documentation - Access Control
--       https://clickhouse.com/docs/en/operations/access-rights
--   [2] ClickHouse - RBAC (Role-Based Access Control)
--       https://clickhouse.com/docs/en/operations/access-rights#role-based-access-control

-- ============================================================
-- 1. 权限体系演进（对引擎开发者）
-- ============================================================

-- ClickHouse 的权限管理经历了从配置文件到 SQL 的演进:
--
-- 阶段 1 (2016-2020): 配置文件管理（users.xml）
-- 阶段 2 (20.5+): SQL 方式的 RBAC
--   需要在配置中启用: <access_management>1</access_management>

-- ============================================================
-- 2. 用户管理
-- ============================================================

CREATE USER analyst IDENTIFIED BY 'secure_password';
CREATE USER IF NOT EXISTS analyst IDENTIFIED WITH sha256_password BY 'pass';

CREATE USER etl_user
    IDENTIFIED WITH sha256_password BY 'pass'
    HOST IP '10.0.0.0/8'
    DEFAULT DATABASE analytics
    DEFAULT ROLE data_reader
    SETTINGS max_memory_usage = 10000000000;

ALTER USER analyst IDENTIFIED BY 'new_password';
ALTER USER analyst SETTINGS max_execution_time = 300;
DROP USER analyst;

-- ============================================================
-- 3. 角色管理（RBAC）
-- ============================================================

CREATE ROLE data_reader;
CREATE ROLE data_writer;
CREATE ROLE admin;

GRANT data_reader TO data_writer;    -- 角色继承
GRANT data_reader TO analyst;
SET DEFAULT ROLE data_reader TO analyst;

-- ============================================================
-- 4. 权限粒度
-- ============================================================

-- 数据库级
GRANT SELECT ON analytics.* TO data_reader;
GRANT INSERT ON analytics.* TO data_writer;

-- 表级
GRANT SELECT ON analytics.users TO analyst;

-- 列级（ClickHouse 独有的细粒度!）
GRANT SELECT(id, username, email) ON analytics.users TO analyst;

SHOW GRANTS FOR analyst;
REVOKE SELECT ON analytics.users FROM analyst;

-- ============================================================
-- 5. Quota（资源配额，ClickHouse 独有）
-- ============================================================

CREATE QUOTA monthly_limit
    FOR INTERVAL 1 MONTH
    MAX QUERIES 10000
    MAX RESULT_ROWS 1000000000
    MAX READ_ROWS 10000000000
    TO data_reader;

-- OLAP 查询资源消耗不可预测，Quota 是必需的安全网。

-- ============================================================
-- 6. Settings Profile + Row Policy
-- ============================================================

CREATE SETTINGS PROFILE restricted
    SETTINGS max_memory_usage = 10000000000, max_execution_time = 300
    TO data_reader;

CREATE ROW POLICY region_filter ON analytics.sales
    FOR SELECT USING region = 'APAC' TO analyst;

-- ============================================================
-- 7. 对比与引擎开发者启示
-- ============================================================
-- ClickHouse 权限的特色:
--   (1) 列级权限 → 比大多数数据库更细粒度
--   (2) Quota → 资源消耗控制，OLAP 引擎必需
--   (3) Settings Profile → 用户级查询设置限制
--   (4) Row Policy → 行级安全
--
-- 对引擎开发者的启示:
--   OLAP 引擎的权限不仅是"谁能做什么"，
--   更重要的是"谁能消耗多少资源"（Quota 应是核心组件）。
