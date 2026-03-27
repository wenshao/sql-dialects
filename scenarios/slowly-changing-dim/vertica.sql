-- Vertica: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Vertica Documentation - MERGE
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Statements/MERGE.htm

-- ============================================================
-- SCD Type 1: MERGE
-- ============================================================
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city)
    THEN UPDATE SET t.name = s.name, t.city = s.city, t.tier = s.tier
WHEN NOT MATCHED
    THEN INSERT (customer_id, name, city, tier)
         VALUES (s.customer_id, s.name, s.city, s.tier);

-- ============================================================
-- SCD Type 2: 两步操作
-- ============================================================
MERGE INTO dim_customer AS t USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city)
    THEN UPDATE SET expiry_date = CURRENT_DATE - 1, is_current = FALSE;

INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', TRUE
FROM stg_customer s
WHERE NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = TRUE);
COMMIT;
