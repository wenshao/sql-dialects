-- MaxCompute (ODPS): 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] MaxCompute SQL - MERGE INTO (MaxCompute 2.0+)
--       https://help.aliyun.com/document_detail/73775.html

-- ============================================================
-- SCD Type 1: MERGE INTO
-- ============================================================
MERGE INTO dim_customer t
USING stg_customer s ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city)
    THEN UPDATE SET t.name = s.name, t.city = s.city, t.tier = s.tier
WHEN NOT MATCHED
    THEN INSERT VALUES (s.customer_id, s.name, s.city, s.tier, GETDATE(), '9999-12-31', TRUE);

-- ============================================================
-- SCD Type 2: INSERT OVERWRITE（传统方式）
-- ============================================================
INSERT OVERWRITE TABLE dim_customer
SELECT * FROM dim_customer WHERE NOT (is_current = TRUE AND customer_id IN (SELECT customer_id FROM stg_customer WHERE name <> (SELECT name FROM dim_customer d2 WHERE d2.customer_id = stg_customer.customer_id AND d2.is_current = TRUE)))
UNION ALL
SELECT customer_id, name, city, tier, GETDATE(), '9999-12-31', TRUE FROM stg_customer;
