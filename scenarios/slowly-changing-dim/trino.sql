-- Trino: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Trino Documentation - MERGE
--       https://trino.io/docs/current/sql/merge.html
--   [2] Trino Documentation - DML
--       https://trino.io/docs/current/sql/update.html

-- ============================================================
-- SCD Type 1: MERGE（Trino 对部分 connector 支持 MERGE）
-- ============================================================
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city)
    THEN UPDATE SET name = s.name, city = s.city, tier = s.tier
WHEN NOT MATCHED
    THEN INSERT (customer_id, name, city, tier, effective_date, expiry_date, is_current)
         VALUES (s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, DATE '9999-12-31', TRUE);

-- ============================================================
-- SCD Type 2: 两步操作
-- ============================================================
-- 注意: MERGE/UPDATE/DELETE 支持取决于 connector（Hive, Delta, Iceberg）
MERGE INTO dim_customer AS t USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city)
    THEN UPDATE SET expiry_date = CURRENT_DATE - INTERVAL '1' DAY, is_current = FALSE;

INSERT INTO dim_customer
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, DATE '9999-12-31', TRUE
FROM stg_customer s
WHERE NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = TRUE);
