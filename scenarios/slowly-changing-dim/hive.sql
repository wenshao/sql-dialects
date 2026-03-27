-- Hive: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Hive Language Manual - MERGE (Hive 2.2+, ACID tables)
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DML#LanguageManualDML-Merge
--   [2] Hive Language Manual - ACID / Transactional Tables
--       https://cwiki.apache.org/confluence/display/Hive/Hive+Transactions

-- ============================================================
-- 维度表（ACID 表，支持 UPDATE/DELETE/MERGE）
-- ============================================================
CREATE TABLE dim_customer (
    customer_key   BIGINT,
    customer_id    STRING,
    name           STRING,
    city           STRING,
    tier           STRING,
    effective_date DATE,
    expiry_date    DATE,
    is_current     BOOLEAN
) STORED AS ORC
TBLPROPERTIES ('transactional' = 'true');

CREATE TABLE stg_customer (
    customer_id STRING, name STRING, city STRING, tier STRING
) STORED AS ORC;

-- ============================================================
-- SCD Type 1: 使用 MERGE（Hive 2.2+, ACID 表）
-- ============================================================
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET name = s.name, city = s.city, tier = s.tier
WHEN NOT MATCHED
    THEN INSERT VALUES (NULL, s.customer_id, s.name, s.city, s.tier,
                        CURRENT_DATE, DATE '9999-12-31', TRUE);

-- ============================================================
-- SCD Type 2: INSERT OVERWRITE + FULL OUTER JOIN（传统方式）
-- 适用于非 ACID 表
-- ============================================================
INSERT OVERWRITE TABLE dim_customer
SELECT
    CASE WHEN d.customer_id IS NULL THEN NULL ELSE d.customer_key END,
    COALESCE(s.customer_id, d.customer_id),
    COALESCE(s.name, d.name),
    COALESCE(s.city, d.city),
    COALESCE(s.tier, d.tier),
    CASE WHEN d.customer_id IS NULL OR (d.name <> s.name OR d.city <> s.city)
         THEN CURRENT_DATE ELSE d.effective_date END,
    DATE '9999-12-31',
    TRUE
FROM   dim_customer d
FULL OUTER JOIN stg_customer s ON d.customer_id = s.customer_id AND d.is_current = TRUE
UNION ALL
-- 保留旧版本（标记为过期）
SELECT customer_key, customer_id, name, city, tier,
       effective_date, DATE_SUB(CURRENT_DATE, 1), FALSE
FROM   dim_customer d
WHERE  d.is_current = TRUE
  AND  EXISTS (
    SELECT 1 FROM stg_customer s
    WHERE  s.customer_id = d.customer_id
      AND  (s.name <> d.name OR s.city <> d.city OR s.tier <> d.tier)
);
