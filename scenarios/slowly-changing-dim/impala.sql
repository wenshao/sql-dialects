-- Impala: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Impala Documentation - UPSERT (Kudu tables only)
--       https://impala.apache.org/docs/build/html/topics/impala_upsert.html
--   [2] Impala Documentation - INSERT OVERWRITE
--       https://impala.apache.org/docs/build/html/topics/impala_insert.html

-- ============================================================
-- SCD Type 1: UPSERT（仅 Kudu 表）
-- ============================================================
UPSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer;

-- ============================================================
-- SCD Type 2: INSERT OVERWRITE（HDFS/Parquet 表）
-- Impala 不支持 UPDATE/MERGE（非 Kudu 表），需要全量重写
-- ============================================================
INSERT OVERWRITE TABLE dim_customer
SELECT * FROM dim_customer d
WHERE  NOT EXISTS (SELECT 1 FROM stg_customer s WHERE s.customer_id = d.customer_id AND d.is_current = TRUE)
UNION ALL
SELECT NULL, s.customer_id, s.name, s.city, s.tier, from_unixtime(unix_timestamp()), '9999-12-31', TRUE
FROM stg_customer s;
