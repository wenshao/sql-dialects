-- MaxCompute (ODPS): 约束
--
-- 参考资料:
--   [1] MaxCompute SQL - CREATE TABLE
--       https://help.aliyun.com/zh/maxcompute/user-guide/create-table-1
--   [2] MaxCompute SQL Overview
--       https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview

-- MaxCompute 的约束支持非常有限

-- ============================================================
-- NOT NULL
-- ============================================================

CREATE TABLE users (
    id       BIGINT NOT NULL,
    username STRING NOT NULL,
    email    STRING             -- 默认允许 NULL
);

-- ============================================================
-- PRIMARY KEY（仅事务表支持）
-- ============================================================

-- 事务表可以定义主键
CREATE TABLE users (
    id       BIGINT NOT NULL,
    username STRING NOT NULL,
    PRIMARY KEY (id)
) TBLPROPERTIES ('transactional' = 'true');

-- 非事务表不支持主键

-- ============================================================
-- DEFAULT
-- ============================================================

CREATE TABLE users (
    id       BIGINT NOT NULL,
    status   BIGINT DEFAULT 1,
    name     STRING DEFAULT 'unknown'
);

-- ============================================================
-- 不支持的约束
-- ============================================================

-- UNIQUE: 不支持
-- FOREIGN KEY: 不支持
-- CHECK: 不支持
-- EXCLUDE: 不支持

-- ============================================================
-- 数据质量保证的替代方案
-- ============================================================

-- 1. 在 SQL 中使用 DISTINCT 或 GROUP BY 去重
INSERT OVERWRITE TABLE users_clean
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn
    FROM users
) t WHERE rn = 1;

-- 2. 使用 DataWorks 数据质量规则
-- 3. 使用 MaxCompute 数据质量监控功能

-- ============================================================
-- 分区约束（隐式）
-- ============================================================

-- 分区列的值隐式地约束了数据的组织
CREATE TABLE orders (
    id     BIGINT,
    amount DECIMAL(10,2)
)
PARTITIONED BY (dt STRING, region STRING);

-- 分区列不能为 NULL
-- 分区列必须是 STRING 类型（推荐）

-- ============================================================
-- 表级属性约束
-- ============================================================

-- 生命周期约束
CREATE TABLE temp_data (id BIGINT) LIFECYCLE 7;  -- 7 天后自动删除

-- 注意：MaxCompute 是面向离线分析的引擎，约束支持有限
-- 注意：只有事务表支持 PRIMARY KEY
-- 注意：NOT NULL 是最主要的列级约束
-- 注意：数据完整性通常在 ETL 管道中保证
-- 注意：分区值有隐式的非空约束
