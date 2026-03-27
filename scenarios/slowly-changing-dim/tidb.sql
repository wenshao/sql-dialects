-- TiDB: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] TiDB 兼容 MySQL 语法
--       https://docs.pingcap.com/tidb/stable/sql-statement-replace

-- ============================================================
-- SCD Type 1: INSERT ... ON DUPLICATE KEY UPDATE
-- ============================================================
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON DUPLICATE KEY UPDATE
    name = VALUES(name), city = VALUES(city), tier = VALUES(tier);

-- ============================================================
-- SCD Type 2: UPDATE + INSERT（同 MySQL）
-- ============================================================
-- 步骤 1: 标记过期
UPDATE dim_customer t
JOIN   stg_customer s ON t.customer_id = s.customer_id
SET    t.expiry_date = DATE_SUB(CURRENT_DATE, INTERVAL 1 DAY), t.is_current = 0
WHERE  t.is_current = 1
  AND  (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier);

-- 步骤 2: 插入新版本
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', 1
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = 1
);
