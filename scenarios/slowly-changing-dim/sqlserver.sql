-- SQL Server: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Microsoft Docs - MERGE
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/merge-transact-sql
--   [2] Microsoft Docs - System-Versioned Temporal Tables
--       https://learn.microsoft.com/en-us/sql/relational-databases/tables/temporal-tables
--   [3] Kimball Group - SCD Types

-- ============================================================
-- 维度表和源数据表
-- ============================================================
CREATE TABLE dim_customer (
    customer_key   INT IDENTITY(1,1) PRIMARY KEY,
    customer_id    NVARCHAR(20) NOT NULL,
    name           NVARCHAR(100),
    city           NVARCHAR(100),
    tier           NVARCHAR(20),
    effective_date DATE NOT NULL DEFAULT GETDATE(),
    expiry_date    DATE NOT NULL DEFAULT '9999-12-31',
    is_current     BIT NOT NULL DEFAULT 1,
    created_at     DATETIME2 DEFAULT GETDATE(),
    updated_at     DATETIME2 DEFAULT GETDATE()
);

CREATE TABLE stg_customer (
    customer_id    NVARCHAR(20),
    name           NVARCHAR(100),
    city           NVARCHAR(100),
    tier           NVARCHAR(20)
);

-- ============================================================
-- SCD Type 1: 直接覆盖（使用 MERGE）
-- ============================================================
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = 1
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET
        t.name       = s.name,
        t.city       = s.city,
        t.tier       = s.tier,
        t.updated_at = GETDATE()
WHEN NOT MATCHED BY TARGET
    THEN INSERT (customer_id, name, city, tier)
         VALUES (s.customer_id, s.name, s.city, s.tier);

-- ============================================================
-- SCD Type 2: 使用 MERGE + OUTPUT（SQL Server 特色，单语句）
-- ============================================================
-- 步骤 1 + 2 合一: MERGE + OUTPUT 插入新行
DECLARE @changes TABLE (action_type NVARCHAR(10), customer_id NVARCHAR(20),
                        name NVARCHAR(100), city NVARCHAR(100), tier NVARCHAR(20));

MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = 1
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET
        t.expiry_date = DATEADD(DAY, -1, GETDATE()),
        t.is_current  = 0,
        t.updated_at  = GETDATE()
WHEN NOT MATCHED BY TARGET
    THEN INSERT (customer_id, name, city, tier)
         VALUES (s.customer_id, s.name, s.city, s.tier)
OUTPUT $action, s.customer_id, s.name, s.city, s.tier
INTO @changes (action_type, customer_id, name, city, tier);

INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT customer_id, name, city, tier,
       CAST(GETDATE() AS DATE), '9999-12-31', 1
FROM   @changes
WHERE  action_type = 'UPDATE';

-- ============================================================
-- SCD: 系统版本化时态表（SQL Server 2016+）
-- 自动跟踪行的历史版本
-- ============================================================
CREATE TABLE dim_customer_temporal (
    customer_id    NVARCHAR(20) PRIMARY KEY,
    name           NVARCHAR(100),
    city           NVARCHAR(100),
    tier           NVARCHAR(20),
    valid_from     DATETIME2 GENERATED ALWAYS AS ROW START NOT NULL,
    valid_to       DATETIME2 GENERATED ALWAYS AS ROW END   NOT NULL,
    PERIOD FOR SYSTEM_TIME (valid_from, valid_to)
) WITH (SYSTEM_VERSIONING = ON (
    HISTORY_TABLE = dbo.dim_customer_temporal_history
));

-- 直接 UPDATE，历史自动保存到 history 表
UPDATE dim_customer_temporal
SET    city = N'Shenzhen', tier = N'Gold'
WHERE  customer_id = N'C001';

-- 查询历史版本
SELECT * FROM dim_customer_temporal
FOR SYSTEM_TIME ALL
WHERE customer_id = N'C001'
ORDER BY valid_from;

-- 查询某个时间点的快照
SELECT * FROM dim_customer_temporal
FOR SYSTEM_TIME AS OF '2024-06-01 00:00:00';
