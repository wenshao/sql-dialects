-- openGauss: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] openGauss Documentation - SQL Reference
--       https://docs.opengauss.org/
--   [2] openGauss Documentation - INSERT ON CONFLICT
--       https://docs.opengauss.org/en/docs/5.x/docs/Developerguide/insert.html
--   [3] openGauss - PostgreSQL Compatibility
--       https://docs.opengauss.org/en/docs/5.x/docs/Developerguide/sql-compatibility.html
--   [4] openGauss Documentation - MERGE INTO
--       https://docs.opengauss.org/en/docs/5.x/docs/Developerguide/merge-into.html

-- ============================================================
-- 1. 维度表结构
-- ============================================================

-- openGauss 兼容 PostgreSQL DDL/DML，并扩展了部分特性
CREATE TABLE dim_customer (
    customer_key   SERIAL PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date    DATE NOT NULL DEFAULT '9999-12-31',
    is_current     BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at     TIMESTAMP DEFAULT NOW(),
    UNIQUE (customer_id, is_current, effective_date)
);

CREATE TABLE stg_customer (
    customer_id VARCHAR(20),
    name        VARCHAR(100),
    city        VARCHAR(100),
    tier        VARCHAR(20)
);

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

-- openGauss 完全兼容 PostgreSQL 的 UPSERT 语法
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON CONFLICT (customer_id)
DO UPDATE SET name = EXCLUDED.name, city = EXCLUDED.city,
              tier = EXCLUDED.tier, updated_at = NOW();

-- 方法 2: MERGE INTO（openGauss 扩展语法，兼容 Oracle/Greenplum）
MERGE INTO dim_customer t
USING stg_customer s
ON (t.customer_id = s.customer_id AND t.is_current = TRUE)
WHEN MATCHED THEN
    UPDATE SET name = s.name, city = s.city, tier = s.tier
WHEN NOT MATCHED THEN
    INSERT (customer_id, name, city, tier, effective_date, expiry_date, is_current)
    VALUES (s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', TRUE);

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
-- 6. openGauss 注意事项与最佳实践
-- ============================================================

-- 1. openGauss 兼容 PostgreSQL 的 ON CONFLICT 和可写 CTE
-- 2. openGauss 额外支持 MERGE INTO（Oracle 兼容扩展）
-- 3. 支持 行级 安全策略 (RLS)，可用于维度表权限控制:
--    CREATE POLICY dim_customer_policy ON dim_customer USING (tenant_id = current_user);
-- 4. openGauss 支持 SQL 智能巡检和自动索引推荐
-- 5. 国产数据库信创场景主力产品，社区活跃度高
-- 6. 建议为 SCD Type 2 创建以下索引:
--    CREATE INDEX idx_customer_current ON dim_customer (customer_id, is_current);
-- 7. openGauss 支持增量物化视图，可辅助 SCD 维护:
--    CREATE INCREMENTAL MATERIALIZED VIEW mv_current_customer AS
--        SELECT * FROM dim_customer WHERE is_current = TRUE;
