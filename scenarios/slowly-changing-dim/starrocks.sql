-- StarRocks: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] StarRocks Documentation - Primary Key Model
--       https://docs.starrocks.io/docs/table_design/table_types/primary_key_table/
--   [2] StarRocks Documentation - UPDATE
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/data-manipulation/UPDATE/

-- ============================================================
-- SCD Type 1: Primary Key 模型（自动覆盖）
-- ============================================================
CREATE TABLE dim_customer (
    customer_id VARCHAR(20),
    name        VARCHAR(100),
    city        VARCHAR(100),
    tier        VARCHAR(20)
) PRIMARY KEY (customer_id)
DISTRIBUTED BY HASH(customer_id) BUCKETS 1
PROPERTIES ("replication_num" = "1");

-- 直接插入，Primary Key 自动保留最新值
INSERT INTO dim_customer SELECT * FROM stg_customer;

-- ============================================================
-- SCD Type 2: UPDATE + INSERT
-- ============================================================
UPDATE dim_customer SET expiry_date = DATE_SUB(CURDATE(), INTERVAL 1 DAY), is_current = FALSE
WHERE is_current = TRUE AND customer_id IN (
    SELECT s.customer_id FROM stg_customer s JOIN dim_customer d
    ON s.customer_id = d.customer_id AND d.is_current = TRUE
    WHERE s.name <> d.name OR s.city <> d.city
);

INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT customer_id, name, city, tier, CURDATE(), '9999-12-31', TRUE FROM stg_customer s
WHERE NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = TRUE);
