-- PostgreSQL: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - INSERT ... ON CONFLICT (UPSERT)
--       https://www.postgresql.org/docs/current/sql-insert.html#SQL-ON-CONFLICT
--   [2] PostgreSQL Documentation - MERGE (PostgreSQL 15+)
--       https://www.postgresql.org/docs/15/sql-merge.html
--   [3] Kimball Group - SCD Types
--       https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/kimball-techniques/dimensional-modeling-techniques/

-- ============================================================
-- 维度表和源数据表
-- ============================================================
CREATE TABLE dim_customer (
    customer_key   SERIAL PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,      -- 业务键
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date    DATE NOT NULL DEFAULT '9999-12-31',
    is_current     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE stg_customer (
    customer_id    VARCHAR(20),
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20)
);

-- ============================================================
-- SCD Type 1: 直接覆盖（Overwrite）
-- 不保留历史，直接更新
-- ============================================================
-- 方法 1: INSERT ... ON CONFLICT (PostgreSQL 9.5+)
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON CONFLICT (customer_id)          -- 需要唯一索引/约束
DO UPDATE SET
    name       = EXCLUDED.name,
    city       = EXCLUDED.city,
    tier       = EXCLUDED.tier,
    updated_at = CURRENT_TIMESTAMP;

-- 方法 2: MERGE (PostgreSQL 15+)
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET
        name       = s.name,
        city       = s.city,
        tier       = s.tier,
        updated_at = CURRENT_TIMESTAMP
WHEN NOT MATCHED
    THEN INSERT (customer_id, name, city, tier)
         VALUES (s.customer_id, s.name, s.city, s.tier);

-- ============================================================
-- SCD Type 2: 版本化（Versioning with start/end dates）
-- 保留完整历史，新版本标记为当前
-- ============================================================
-- 步骤 1: 将已变化的当前记录标记为过期
UPDATE dim_customer AS t
SET    expiry_date = CURRENT_DATE - INTERVAL '1 day',
       is_current  = FALSE,
       updated_at  = CURRENT_TIMESTAMP
FROM   stg_customer AS s
WHERE  t.customer_id = s.customer_id
  AND  t.is_current = TRUE
  AND  (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier);

-- 步骤 2: 插入新版本
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier,
       CURRENT_DATE, '9999-12-31', TRUE
FROM   stg_customer s
WHERE  EXISTS (
    SELECT 1 FROM dim_customer d
    WHERE  d.customer_id = s.customer_id
      AND  d.is_current = FALSE
      AND  d.expiry_date = CURRENT_DATE - INTERVAL '1 day'
)
   OR NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id
);

-- ============================================================
-- SCD Type 2: 使用 MERGE（PostgreSQL 15+，单语句）
-- ============================================================
-- PostgreSQL 15 的 MERGE 不支持同一行多个动作，
-- 所以 SCD Type 2 仍需要两步（UPDATE + INSERT）或使用 CTE

-- 用 CTE 方式（推荐）
WITH changed AS (
    UPDATE dim_customer AS t
    SET    expiry_date = CURRENT_DATE - 1,
           is_current  = FALSE,
           updated_at  = CURRENT_TIMESTAMP
    FROM   stg_customer AS s
    WHERE  t.customer_id = s.customer_id
      AND  t.is_current = TRUE
      AND  (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    RETURNING t.customer_id
)
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier,
       CURRENT_DATE, '9999-12-31', TRUE
FROM   stg_customer s
WHERE  s.customer_id IN (SELECT customer_id FROM changed)
   OR  NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id);
