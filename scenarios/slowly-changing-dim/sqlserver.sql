-- SQL Server: 缓慢变化维度（SCD）+ 时态表
--
-- 参考资料:
--   [1] SQL Server - Temporal Tables
--       https://learn.microsoft.com/en-us/sql/relational-databases/tables/temporal-tables
--   [2] SQL Server - MERGE
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/merge-transact-sql

-- ============================================================
-- 维度表
-- ============================================================
CREATE TABLE dim_customer (
    customer_key   INT IDENTITY(1,1) PRIMARY KEY,
    customer_id    NVARCHAR(20) NOT NULL,
    name           NVARCHAR(100),
    city           NVARCHAR(100),
    tier           NVARCHAR(20),
    effective_date DATE DEFAULT GETDATE(),
    expiry_date    DATE DEFAULT '9999-12-31',
    is_current     BIT DEFAULT 1
);
CREATE TABLE stg_customer (
    customer_id NVARCHAR(20), name NVARCHAR(100),
    city NVARCHAR(100), tier NVARCHAR(20)
);

-- ============================================================
-- 1. SCD Type 1: 直接覆盖
-- ============================================================
MERGE INTO dim_customer AS t
USING stg_customer AS s ON t.customer_id = s.customer_id AND t.is_current = 1
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET t.name = s.name, t.city = s.city, t.tier = s.tier
WHEN NOT MATCHED BY TARGET
    THEN INSERT (customer_id, name, city, tier)
         VALUES (s.customer_id, s.name, s.city, s.tier);

-- ============================================================
-- 2. SCD Type 2: MERGE + OUTPUT（SQL Server 独有的单语句方案）
-- ============================================================
DECLARE @changes TABLE (action_type NVARCHAR(10), customer_id NVARCHAR(20),
                        name NVARCHAR(100), city NVARCHAR(100), tier NVARCHAR(20));

MERGE INTO dim_customer AS t
USING stg_customer AS s ON t.customer_id = s.customer_id AND t.is_current = 1
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET t.expiry_date = DATEADD(DAY, -1, GETDATE()),
                    t.is_current = 0
WHEN NOT MATCHED BY TARGET
    THEN INSERT (customer_id, name, city, tier)
         VALUES (s.customer_id, s.name, s.city, s.tier)
OUTPUT $action, s.customer_id, s.name, s.city, s.tier
INTO @changes;

-- 插入变更行的新版本
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, is_current)
SELECT customer_id, name, city, tier, CAST(GETDATE() AS DATE), 1
FROM @changes WHERE action_type = 'UPDATE';

-- 设计分析（对引擎开发者）:
--   MERGE + OUTPUT 是 SQL Server 实现 SCD Type 2 的独有方案:
--   一条 MERGE 完成: 关闭旧版本（UPDATE） + 新客户（INSERT）
--   OUTPUT 捕获变更信息，然后第二条 INSERT 创建新版本。
--
--   MERGE 的已知问题（SQL Server 特有）:
--   MERGE 在 SQL Server 中有多个已知 Bug（死锁、数据不一致等）。
--   多位 Microsoft MVP 建议避免 MERGE，改用 UPDATE + INSERT 两步操作。
--   但在 SCD 场景中，MERGE + OUTPUT 的简洁性仍然有吸引力。

-- ============================================================
-- 3. 时态表（Temporal Tables, 2016+）: SCD 的终极解决方案
-- ============================================================

-- 系统版本化时态表自动跟踪行的所有历史版本
CREATE TABLE dim_customer_temporal (
    customer_id NVARCHAR(20) PRIMARY KEY,
    name        NVARCHAR(100),
    city        NVARCHAR(100),
    tier        NVARCHAR(20),
    valid_from  DATETIME2 GENERATED ALWAYS AS ROW START NOT NULL,
    valid_to    DATETIME2 GENERATED ALWAYS AS ROW END   NOT NULL,
    PERIOD FOR SYSTEM_TIME (valid_from, valid_to)
) WITH (SYSTEM_VERSIONING = ON (
    HISTORY_TABLE = dbo.dim_customer_temporal_history
));

-- 直接 UPDATE——历史自动保存到 history 表（无需任何额外代码！）
UPDATE dim_customer_temporal SET city = N'Shenzhen', tier = N'Gold'
WHERE customer_id = N'C001';

-- 查询历史版本
SELECT * FROM dim_customer_temporal
FOR SYSTEM_TIME ALL WHERE customer_id = N'C001' ORDER BY valid_from;

-- 查询某个时间点的快照
SELECT * FROM dim_customer_temporal
FOR SYSTEM_TIME AS OF '2024-06-01 00:00:00';

-- 查询某个时间范围内的变更
SELECT * FROM dim_customer_temporal
FOR SYSTEM_TIME FROM '2024-01-01' TO '2024-12-31';

-- 设计分析（对引擎开发者）:
--   时态表是 SQL:2011 标准特性，SQL Server 是最早完整实现的主流数据库（2016）。
--   它从根本上解决了 SCD 问题——引擎自动维护历史版本。
--
-- 横向对比:
--   PostgreSQL: 无原生时态表（需要触发器模拟或使用 temporal_tables 扩展）
--   MySQL:      不支持时态表
--   Oracle:     Flashback Data Archive（类似功能但不同实现）
--   MariaDB:    10.3+ 支持系统版本化表（WITH SYSTEM VERSIONING）
--
-- 对引擎开发者的启示:
--   时态表的实现核心: UPDATE/DELETE 时自动将旧行写入 history 表。
--   这需要在 DML 执行路径中注入额外的写操作——对引擎代码有侵入性。
--   FOR SYSTEM_TIME 查询需要优化器支持跨两个表的谓词下推。
--   这是一个非常有价值的特性——数据审计和合规是企业客户的刚需。
