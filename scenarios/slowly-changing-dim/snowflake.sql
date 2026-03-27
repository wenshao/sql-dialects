-- Snowflake: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Snowflake SQL Reference - MERGE
--       https://docs.snowflake.com/en/sql-reference/sql/merge
--   [2] Snowflake - Streams and Tasks (CDC)
--       https://docs.snowflake.com/en/user-guide/streams
--   [3] Snowflake - Time Travel
--       https://docs.snowflake.com/en/user-guide/data-time-travel

-- ============================================================
-- 维度表和源数据表
-- ============================================================
CREATE OR REPLACE TABLE dim_customer (
    customer_key   NUMBER AUTOINCREMENT,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE(),
    expiry_date    DATE NOT NULL DEFAULT '9999-12-31',
    is_current     BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE OR REPLACE TABLE stg_customer (
    customer_id VARCHAR(20), name VARCHAR(100), city VARCHAR(100), tier VARCHAR(20)
);

-- ============================================================
-- SCD Type 1: 使用 MERGE
-- ============================================================
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET t.name = s.name, t.city = s.city, t.tier = s.tier
WHEN NOT MATCHED
    THEN INSERT (customer_id, name, city, tier)
         VALUES (s.customer_id, s.name, s.city, s.tier);

-- ============================================================
-- SCD Type 2: MERGE + INSERT（两步）
-- ============================================================
-- 步骤 1: 关闭旧版本
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET t.expiry_date = DATEADD(DAY, -1, CURRENT_DATE()),
                    t.is_current  = FALSE;

-- 步骤 2: 插入新版本
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier,
       CURRENT_DATE(), '9999-12-31', TRUE
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d
    WHERE  d.customer_id = s.customer_id AND d.is_current = TRUE
);

-- ============================================================
-- Snowflake Stream（CDC 变更捕获，自动化 SCD）
-- ============================================================
CREATE OR REPLACE STREAM stg_customer_stream ON TABLE stg_customer;

-- Stream 自动跟踪表的 INSERT/UPDATE/DELETE
-- 可配合 Task 定时执行 SCD 逻辑

-- ============================================================
-- Snowflake Time Travel（内置时态查询）
-- ============================================================
-- 查询表在某个时间点的状态
SELECT * FROM dim_customer AT (TIMESTAMP => '2024-06-01 00:00:00'::TIMESTAMP);
-- 查询 1 小时前的状态
SELECT * FROM dim_customer AT (OFFSET => -3600);
