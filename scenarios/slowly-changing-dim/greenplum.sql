-- Greenplum: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] VMware Greenplum Documentation - INSERT
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-INSERT.html
--   [2] VMware Greenplum Documentation - UPDATE
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-UPDATE.html
--   [3] VMware Greenplum - PostgreSQL Compatibility
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/client_guides-intro-postgresql-compat.html
--   [4] Greenplum - Table Distribution Strategies
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-ddl-ddl-table.html

-- ============================================================
-- 1. 维度表结构
-- ============================================================

CREATE TABLE dim_customer (
    customer_key   SERIAL PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date    DATE NOT NULL DEFAULT '9999-12-31',
    is_current     BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at     TIMESTAMP DEFAULT NOW()
) DISTRIBUTED BY (customer_id);

CREATE TABLE stg_customer (
    customer_id VARCHAR(20),
    name        VARCHAR(100),
    city        VARCHAR(100),
    tier        VARCHAR(20)
) DISTRIBUTED BY (customer_id);

-- ============================================================
-- 2. 插入样本数据
-- ============================================================

INSERT INTO stg_customer (customer_id, name, city, tier) VALUES
    ('C001', 'Alice', 'Shanghai', 'Gold'),
    ('C002', 'Bob', 'Beijing', 'Silver'),
    ('C003', 'Charlie', 'Shenzhen', 'Bronze');

-- ============================================================
-- 3. SCD Type 1: INSERT ... ON CONFLICT（PostgreSQL 兼容）
-- ============================================================

-- Greenplum 7+ 支持 ON CONFLICT（基于 PostgreSQL 12 分支）
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON CONFLICT (customer_id)
DO UPDATE SET name = EXCLUDED.name, city = EXCLUDED.city,
              tier = EXCLUDED.tier, updated_at = NOW();

-- 方法 2: UPDATE + INSERT（兼容旧版本 Greenplum 6）
UPDATE dim_customer t
SET    name = s.name, city = s.city, tier = s.tier
FROM   stg_customer s
WHERE  t.customer_id = s.customer_id AND t.is_current = TRUE;

INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', TRUE
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id
);

-- ============================================================
-- 4. SCD Type 2: UPDATE + INSERT（保留历史版本）
-- ============================================================

-- 步骤 1: 检测变化并标记当前行为过期
UPDATE dim_customer AS t
SET    expiry_date = CURRENT_DATE - INTERVAL '1 day', is_current = FALSE
FROM   stg_customer AS s
WHERE  t.customer_id = s.customer_id AND t.is_current = TRUE
  AND  (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier);

-- 步骤 2: 插入新版本（变化的 + 新增的）
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', TRUE
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = TRUE
);

-- ============================================================
-- 5. 验证查询
-- ============================================================

-- 查看当前活跃维度记录
SELECT customer_key, customer_id, name, city, tier, effective_date, is_current
FROM   dim_customer
WHERE  is_current = TRUE
ORDER  BY customer_id;

-- 查看某个客户的历史版本
SELECT customer_key, customer_id, name, city, tier, effective_date, expiry_date
FROM   dim_customer
WHERE  customer_id = 'C001'
ORDER  BY effective_date;

-- ============================================================
-- 6. Greenplum 注意事项与最佳实践
-- ============================================================

-- 1. Greenplum 是 MPP 架构，选择正确的分布键至关重要
--    DISTRIBUTED BY (customer_id) 确保同一客户的记录在同一 segment
-- 2. Greenplum 7 基于 PostgreSQL 12，支持 ON CONFLICT
--    Greenplum 6 基于 PostgreSQL 9.4，不支持 ON CONFLICT
-- 3. Greenplum 支持 Append-Optimized 列存表，适合大维度表:
--    CREATE TABLE ... WITH (appendonly=true, orientation=column)
-- 4. 大规模 UPDATE 在 Greenplum 中开销较大（需重写整个分区）
--    推荐使用 CTAS 或外部表 + gpload 进行批量刷新
-- 5. Greenplum 不支持可写 CTE，SCD Type 2 必须分步执行
-- 6. 使用 EXPLAIN ANALYZE 分析查询计划，确保数据本地化
-- 7. 维度表建议选择复制分布（DISTRIBUTED REPLICATED）减少广播 JOIN
