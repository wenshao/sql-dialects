-- Doris: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Apache Doris Documentation - Unique Key Model
--       https://doris.apache.org/docs/data-table/data-model#unique-model
--   [2] Apache Doris Documentation - INSERT INTO
--       https://doris.apache.org/docs/sql-manual/sql-statements/insert

-- ============================================================
-- SCD Type 1: Unique Key 模型（自动覆盖）
-- ============================================================
CREATE TABLE dim_customer (
    customer_id VARCHAR(20),
    name        VARCHAR(100),
    city        VARCHAR(100),
    tier        VARCHAR(20)
) UNIQUE KEY (customer_id)
DISTRIBUTED BY HASH(customer_id) BUCKETS 1
PROPERTIES ("replication_num" = "1");

-- 直接插入，Unique Key 自动保留最新值
INSERT INTO dim_customer SELECT * FROM stg_customer;

-- ============================================================
-- SCD Type 2: UPDATE + INSERT
-- ============================================================
UPDATE dim_customer SET expiry_date = DATE_SUB(CURDATE(), INTERVAL 1 DAY), is_current = 0
WHERE is_current = 1
  AND customer_id IN (SELECT customer_id FROM stg_customer);

INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT customer_id, name, city, tier, CURDATE(), '9999-12-31', 1 FROM stg_customer;
