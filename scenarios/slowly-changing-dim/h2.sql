-- H2: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] H2 Documentation - MERGE
--       https://h2database.com/html/commands.html#merge_into

-- ============================================================
-- SCD Type 1: MERGE INTO（H2 语法）
-- ============================================================
MERGE INTO dim_customer (customer_id, name, city, tier)
KEY (customer_id)
SELECT customer_id, name, city, tier FROM stg_customer;

-- ============================================================
-- SCD Type 2: UPDATE + INSERT
-- ============================================================
UPDATE dim_customer t SET t.expiry_date = CURRENT_DATE - 1, t.is_current = FALSE
WHERE t.is_current = TRUE
  AND EXISTS (SELECT 1 FROM stg_customer s WHERE s.customer_id = t.customer_id
              AND (s.name <> t.name OR s.city <> t.city));

INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, DATE '9999-12-31', TRUE
FROM stg_customer s
WHERE NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = TRUE);
