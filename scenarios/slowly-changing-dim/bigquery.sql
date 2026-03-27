-- BigQuery: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] BigQuery SQL Reference - MERGE
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax#merge_statement
--   [2] BigQuery - Building a Data Warehouse
--       https://cloud.google.com/bigquery/docs/data-warehouse

-- ============================================================
-- 维度表和源数据表
-- ============================================================
CREATE TABLE mydataset.dim_customer (
    customer_key   INT64,
    customer_id    STRING NOT NULL,
    name           STRING,
    city           STRING,
    tier           STRING,
    effective_date DATE NOT NULL,
    expiry_date    DATE NOT NULL,
    is_current     BOOL NOT NULL
);

CREATE TABLE mydataset.stg_customer (
    customer_id STRING, name STRING, city STRING, tier STRING
);

-- ============================================================
-- SCD Type 1: 使用 MERGE
-- ============================================================
MERGE INTO mydataset.dim_customer AS t
USING mydataset.stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET
        t.name = s.name,
        t.city = s.city,
        t.tier = s.tier
WHEN NOT MATCHED
    THEN INSERT (customer_key, customer_id, name, city, tier, effective_date, expiry_date, is_current)
         VALUES (GENERATE_UUID(), s.customer_id, s.name, s.city, s.tier,
                 CURRENT_DATE(), DATE '9999-12-31', TRUE);

-- ============================================================
-- SCD Type 2: 使用 MERGE（BigQuery 支持单行多动作的变通方式）
-- ============================================================
-- BigQuery MERGE 不允许同一行执行多个动作
-- 方案: 分两步执行

-- 步骤 1: 关闭旧版本
MERGE INTO mydataset.dim_customer AS t
USING mydataset.stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET
        t.expiry_date = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY),
        t.is_current  = FALSE;

-- 步骤 2: 插入新版本
INSERT INTO mydataset.dim_customer
SELECT GENERATE_UUID(), s.customer_id, s.name, s.city, s.tier,
       CURRENT_DATE(), DATE '9999-12-31', TRUE
FROM   mydataset.stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM mydataset.dim_customer d
    WHERE  d.customer_id = s.customer_id AND d.is_current = TRUE
);
