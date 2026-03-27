-- Teradata: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Teradata Documentation - MERGE
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Data-Manipulation-Language
--   [2] Teradata Documentation - Temporal Tables
--       https://docs.teradata.com/r/Teradata-VantageTM-Temporal-Table-Support

-- ============================================================
-- SCD Type 1: MERGE
-- ============================================================
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = 'Y'
WHEN MATCHED THEN UPDATE SET name = s.name, city = s.city, tier = s.tier
WHEN NOT MATCHED THEN INSERT VALUES (s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, DATE '9999-12-31', 'Y');

-- ============================================================
-- Teradata 时态表（原生支持）
-- ============================================================
CREATE TABLE dim_customer_temporal (
    customer_id VARCHAR(20) NOT NULL,
    name        VARCHAR(100),
    city        VARCHAR(100),
    valid_start DATE NOT NULL,
    valid_end   DATE NOT NULL,
    PERIOD FOR valid_period (valid_start, valid_end)
) PRIMARY INDEX (customer_id);

-- 时态查询
SELECT * FROM dim_customer_temporal
WHERE customer_id = 'C001'
  AND valid_period CONTAINS DATE '2024-06-01';
