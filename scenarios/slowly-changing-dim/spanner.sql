-- Spanner: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Cloud Spanner - DML
--       https://cloud.google.com/spanner/docs/reference/standard-sql/dml-syntax

-- ============================================================
-- SCD Type 1: INSERT OR UPDATE（Spanner 特色语法）
-- ============================================================
INSERT OR UPDATE INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT customer_id, name, city, tier, CURRENT_DATE(), DATE '9999-12-31', TRUE
FROM stg_customer;

-- ============================================================
-- SCD Type 2: UPDATE + INSERT
-- ============================================================
UPDATE dim_customer SET expiry_date = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY), is_current = FALSE
WHERE is_current = TRUE
  AND customer_id IN (SELECT customer_id FROM stg_customer)
  AND customer_id IN (
    SELECT s.customer_id FROM stg_customer s
    JOIN dim_customer d ON s.customer_id = d.customer_id AND d.is_current = TRUE
    WHERE s.name != d.name OR s.city != d.city
);

INSERT INTO dim_customer (customer_key, customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT GENERATE_UUID(), s.customer_id, s.name, s.city, s.tier, CURRENT_DATE(), DATE '9999-12-31', TRUE
FROM stg_customer s
WHERE NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = TRUE);
