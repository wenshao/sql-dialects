-- Oracle: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Oracle Documentation - MERGE
--       https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/MERGE.html
--   [2] Oracle Documentation - Flashback Query
--       https://docs.oracle.com/en/database/oracle/oracle-database/19/adfns/flashback.html
--   [3] Kimball Group - SCD Types

-- ============================================================
-- 维度表和源数据表
-- ============================================================
CREATE TABLE dim_customer (
    customer_key   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id    VARCHAR2(20) NOT NULL,
    name           VARCHAR2(100),
    city           VARCHAR2(100),
    tier           VARCHAR2(20),
    effective_date DATE DEFAULT SYSDATE NOT NULL,
    expiry_date    DATE DEFAULT DATE '9999-12-31' NOT NULL,
    is_current     CHAR(1) DEFAULT 'Y' NOT NULL CHECK (is_current IN ('Y','N')),
    created_at     TIMESTAMP DEFAULT SYSTIMESTAMP,
    updated_at     TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE TABLE stg_customer (
    customer_id    VARCHAR2(20),
    name           VARCHAR2(100),
    city           VARCHAR2(100),
    tier           VARCHAR2(20)
);

-- ============================================================
-- SCD Type 1: 直接覆盖（使用 MERGE）
-- ============================================================
MERGE INTO dim_customer t
USING stg_customer s
ON (t.customer_id = s.customer_id AND t.is_current = 'Y')
WHEN MATCHED THEN
    UPDATE SET t.name       = s.name,
               t.city       = s.city,
               t.tier       = s.tier,
               t.updated_at = SYSTIMESTAMP
    WHERE  t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier
WHEN NOT MATCHED THEN
    INSERT (customer_id, name, city, tier)
    VALUES (s.customer_id, s.name, s.city, s.tier);

-- ============================================================
-- SCD Type 2: 使用 MERGE（两步）
-- ============================================================
-- 步骤 1: 关闭旧版本
MERGE INTO dim_customer t
USING stg_customer s
ON (t.customer_id = s.customer_id AND t.is_current = 'Y')
WHEN MATCHED THEN
    UPDATE SET t.expiry_date = SYSDATE - 1,
               t.is_current  = 'N',
               t.updated_at  = SYSTIMESTAMP
    WHERE  t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier;

-- 步骤 2: 插入新版本
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier,
       SYSDATE, DATE '9999-12-31', 'Y'
FROM   stg_customer s
WHERE  EXISTS (
    SELECT 1 FROM dim_customer d
    WHERE  d.customer_id = s.customer_id
      AND  d.is_current = 'N'
      AND  d.expiry_date = SYSDATE - 1
)
   OR NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id
);
COMMIT;

-- ============================================================
-- Oracle Flashback（查询历史数据快照，类似时态表）
-- ============================================================
-- 查询 1 小时前的数据
SELECT * FROM dim_customer AS OF TIMESTAMP SYSTIMESTAMP - INTERVAL '1' HOUR;

-- Flashback Version Query（查看某行的所有变化）
SELECT customer_id, name, city, tier,
       VERSIONS_STARTTIME, VERSIONS_ENDTIME, VERSIONS_OPERATION
FROM   dim_customer
       VERSIONS BETWEEN TIMESTAMP SYSTIMESTAMP - INTERVAL '1' DAY AND SYSTIMESTAMP
WHERE  customer_id = 'C001';
