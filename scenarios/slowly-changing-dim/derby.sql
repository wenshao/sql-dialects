-- Derby: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Apache Derby - 不支持 MERGE
--       https://db.apache.org/derby/docs/10.16/ref/

-- ============================================================
-- SCD Type 1: UPDATE + INSERT（Derby 不支持 MERGE/UPSERT）
-- ============================================================
UPDATE dim_customer SET name = (SELECT s.name FROM stg_customer s WHERE s.customer_id = dim_customer.customer_id),
                        city = (SELECT s.city FROM stg_customer s WHERE s.customer_id = dim_customer.customer_id)
WHERE customer_id IN (SELECT customer_id FROM stg_customer) AND is_current = 1;

INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT s.customer_id, s.name, s.city, s.tier FROM stg_customer s
WHERE NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id);

-- ============================================================
-- SCD Type 2: UPDATE + INSERT
-- ============================================================
UPDATE dim_customer SET expiry_date = CURRENT_DATE - 1 DAY, is_current = 0
WHERE is_current = 1 AND customer_id IN (
    SELECT s.customer_id FROM stg_customer s
    JOIN dim_customer d ON d.customer_id = s.customer_id AND d.is_current = 1
    WHERE s.name <> d.name OR s.city <> d.city
);

INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, DATE('9999-12-31'), 1
FROM stg_customer s
WHERE NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = 1);
