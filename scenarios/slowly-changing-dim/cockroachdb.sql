-- CockroachDB: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] CockroachDB 兼容 PostgreSQL 语法
--       https://www.cockroachlabs.com/docs/stable/merge

-- ============================================================
-- SCD Type 1: INSERT ... ON CONFLICT（PostgreSQL 兼容）
-- ============================================================
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON CONFLICT (customer_id)
DO UPDATE SET name = EXCLUDED.name, city = EXCLUDED.city, tier = EXCLUDED.tier;

-- ============================================================
-- SCD Type 2: UPDATE + INSERT
-- ============================================================
-- 步骤 1: 标记过期
UPDATE dim_customer AS t
SET    expiry_date = CURRENT_DATE - INTERVAL '1 day', is_current = FALSE
FROM   stg_customer AS s
WHERE  t.customer_id = s.customer_id AND t.is_current = TRUE
  AND  (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier);

-- 步骤 2: 插入新版本
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', TRUE
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = TRUE
);
