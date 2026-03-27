-- Impala: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Impala Documentation - UPSERT (Kudu tables only)
--       https://impala.apache.org/docs/build/html/topics/impala_upsert.html
--   [2] Impala Documentation - INSERT OVERWRITE
--       https://impala.apache.org/docs/build/html/topics/impala_insert.html

-- ============================================================
-- 维度表（Kudu 表支持行级操作）
-- ============================================================
CREATE TABLE dim_customer_kudu (
    customer_key   BIGINT,
    customer_id    STRING,
    name           STRING,
    city           STRING,
    tier           STRING,
    effective_date STRING,
    expiry_date    STRING DEFAULT '9999-12-31',
    is_current     BOOLEAN DEFAULT TRUE,
    PRIMARY KEY (customer_key)
)
STORED AS KUDU;

-- ============================================================
-- SCD Type 1: UPSERT（仅 Kudu 表）
-- ============================================================
-- UPSERT 插入新行或更新已有行（基于主键）
UPSERT INTO dim_customer_kudu (customer_key, customer_id, name, city, tier)
SELECT customer_id, customer_id, name, city, tier FROM stg_customer;

-- Kudu 表也支持行级 UPDATE
UPDATE dim_customer_kudu
SET    name = s.name,
       city = s.city,
       tier = s.tier
FROM   dim_customer_kudu d
JOIN   stg_customer s ON d.customer_id = s.customer_id
WHERE  d.is_current = TRUE
  AND  (d.name <> s.name OR d.city <> s.city);

-- ============================================================
-- SCD Type 2: Kudu 表（支持行级操作）
-- ============================================================
-- 步骤 1: 标记变化行为过期
UPDATE dim_customer_kudu
SET    expiry_date = from_unixtime(unix_timestamp()),
       is_current  = FALSE
FROM   dim_customer_kudu d
JOIN   stg_customer s ON d.customer_id = s.customer_id
WHERE  d.is_current = TRUE
  AND  (d.name <> s.name OR d.city <> s.city);

-- 步骤 2: 插入新版本记录
INSERT INTO dim_customer_kudu
SELECT NULL, s.customer_id, s.name, s.city, s.tier,
       from_unixtime(unix_timestamp()), '9999-12-31', TRUE
FROM   stg_customer s;

-- ============================================================
-- SCD Type 2: INSERT OVERWRITE（HDFS/Parquet 表）
-- Impala 不支持 UPDATE/MERGE（非 Kudu 表），需要全量重写
-- ============================================================
INSERT OVERWRITE TABLE dim_customer
-- 未变化的记录
SELECT * FROM dim_customer d
WHERE  NOT EXISTS (
    SELECT 1 FROM stg_customer s
    WHERE  s.customer_id = d.customer_id AND d.is_current = TRUE
      AND  (s.name <> d.name OR s.city <> d.city)
)
UNION ALL
-- 已变化的旧记录（标记过期）
SELECT d.customer_key, d.customer_id, d.name, d.city, d.tier,
       d.effective_date, from_unixtime(unix_timestamp()), FALSE
FROM   dim_customer d
JOIN   stg_customer s ON d.customer_id = s.customer_id
WHERE  d.is_current = TRUE AND (d.name <> s.name OR d.city <> s.city)
UNION ALL
-- 新版本记录
SELECT NULL, s.customer_id, s.name, s.city, s.tier,
       from_unixtime(unix_timestamp()), '9999-12-31', TRUE
FROM   stg_customer s
JOIN   dim_customer d ON s.customer_id = d.customer_id
    AND d.is_current = TRUE
WHERE  s.name <> d.name OR s.city <> d.city;

-- 注意：Kudu 表支持 UPSERT, UPDATE, DELETE（行级操作）
-- 注意：HDFS/Parquet 表不支持行级操作，需 INSERT OVERWRITE
-- 注意：UPSERT 仅适用于 Kudu 存储引擎
-- 限制：无 MERGE INTO 语法
-- 限制：非 Kudu 表需全量重写实现 SCD
