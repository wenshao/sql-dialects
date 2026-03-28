-- Apache Doris: 缓慢变化维度
--
-- 参考资料:
--   [1] Doris - Unique Key Model
--       https://doris.apache.org/docs/data-table/data-model

-- ============================================================
-- 1. SCD Type 1: Unique Key 模型(自动覆盖)
-- ============================================================
CREATE TABLE dim_customer (
    customer_id VARCHAR(20) NOT NULL,
    name VARCHAR(100), city VARCHAR(100), tier VARCHAR(20)
) UNIQUE KEY(customer_id) DISTRIBUTED BY HASH(customer_id) BUCKETS 4
PROPERTIES ("replication_num" = "1");

INSERT INTO dim_customer SELECT customer_id, name, city, tier FROM stg_customer;
-- Unique Key: 相同 customer_id 自动覆盖旧行。

-- ============================================================
-- 2. SCD Type 2: Duplicate Key 模型(多版本)
-- ============================================================
CREATE TABLE dim_customer_scd2 (
    customer_key BIGINT NOT NULL AUTO_INCREMENT,
    customer_id VARCHAR(20) NOT NULL,
    name VARCHAR(100), city VARCHAR(100), tier VARCHAR(20),
    effective_date DATE NOT NULL, expiry_date DATE NOT NULL,
    is_current TINYINT NOT NULL DEFAULT 1
) DUPLICATE KEY(customer_key) DISTRIBUTED BY HASH(customer_id) BUCKETS 4
PROPERTIES ("replication_num" = "1");

-- 步骤 1: 标记过期
UPDATE dim_customer_scd2 SET expiry_date = DATE_SUB(CURDATE(), INTERVAL 1 DAY), is_current = 0
WHERE is_current = 1 AND customer_id IN (
    SELECT s.customer_id FROM stg_customer s JOIN dim_customer_scd2 d
    ON s.customer_id = d.customer_id
    WHERE d.is_current = 1 AND (s.name <> d.name OR s.city <> d.city)
);

-- 步骤 2: 插入新版本
INSERT INTO dim_customer_scd2 (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT customer_id, name, city, tier, CURDATE(), '9999-12-31', 1 FROM stg_customer s
WHERE NOT EXISTS (SELECT 1 FROM dim_customer_scd2 d WHERE d.customer_id = s.customer_id AND d.is_current = 1);

-- Doris 不支持 MERGE，SCD Type 2 必须分步执行。
-- 大批量推荐 Stream Load。
