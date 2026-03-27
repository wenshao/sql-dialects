-- 达梦 (Dameng): 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] 达梦数据库 SQL 参考手册 - MERGE
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/
--   [2] 达梦兼容 Oracle MERGE 语法

-- ============================================================
-- SCD Type 1: MERGE（兼容 Oracle）
-- ============================================================
MERGE INTO dim_customer t
USING stg_customer s ON (t.customer_id = s.customer_id AND t.is_current = 'Y')
WHEN MATCHED THEN UPDATE SET t.name = s.name, t.city = s.city, t.tier = s.tier
    WHERE t.name <> s.name OR t.city <> s.city
WHEN NOT MATCHED THEN INSERT (customer_id, name, city, tier)
    VALUES (s.customer_id, s.name, s.city, s.tier);

-- ============================================================
-- SCD Type 2: 两步操作
-- ============================================================
MERGE INTO dim_customer t USING stg_customer s
ON (t.customer_id = s.customer_id AND t.is_current = 'Y')
WHEN MATCHED THEN UPDATE SET t.expiry_date = SYSDATE - 1, t.is_current = 'N'
    WHERE t.name <> s.name OR t.city <> s.city;

INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, SYSDATE, DATE '9999-12-31', 'Y'
FROM stg_customer s
WHERE NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = 'Y');
COMMIT;
