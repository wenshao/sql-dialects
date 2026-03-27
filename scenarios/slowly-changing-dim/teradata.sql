-- Teradata: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Teradata Vantage - SQL Data Manipulation Language
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Data-Manipulation-Language
--   [2] Teradata Vantage - Temporal Table Support
--       https://docs.teradata.com/r/Teradata-VantageTM-Temporal-Table-Support
--   [3] Teradata - MERGE INTO Syntax
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Data-Manipulation-Language/Statement-Syntax/MERGE
--   [4] Kimball Group - SCD Types Overview
--       https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/

-- ============================================================
-- 1. 维度表结构
-- ============================================================

CREATE TABLE dim_customer (
    customer_key   INTEGER GENERATED ALWAYS AS IDENTITY,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date    DATE NOT NULL DEFAULT DATE '9999-12-31',
    is_current     CHAR(1) NOT NULL DEFAULT 'Y',
    PRIMARY KEY (customer_key)
);

CREATE TABLE stg_customer (
    customer_id VARCHAR(20),
    name        VARCHAR(100),
    city        VARCHAR(100),
    tier        VARCHAR(20)
);

-- ============================================================
-- 2. 插入样本数据
-- ============================================================

INSERT INTO stg_customer (customer_id, name, city, tier) VALUES
    ('C001', 'Alice', 'Shanghai', 'Gold'),
    ('C002', 'Bob', 'Beijing', 'Silver'),
    ('C003', 'Charlie', 'Shenzhen', 'Bronze');

-- ============================================================
-- 3. SCD Type 1: MERGE INTO
-- ============================================================

-- Teradata 原生支持 SQL:2003 MERGE 语法
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = 'Y'
WHEN MATCHED THEN
    UPDATE SET name = s.name, city = s.city, tier = s.tier
WHEN NOT MATCHED THEN
    INSERT (customer_id, name, city, tier, effective_date, expiry_date, is_current)
    VALUES (s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, DATE '9999-12-31', 'Y');

-- 方法 2: UPDATE + INSERT（适用于需要精确控制的场景）
UPDATE dim_customer FROM stg_customer s
SET    name = s.name, city = s.city, tier = s.tier
WHERE  dim_customer.customer_id = s.customer_id
  AND  dim_customer.is_current = 'Y';

INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, 'Y'
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id
);

-- ============================================================
-- 4. SCD Type 2: MERGE + INSERT（保留历史版本）
-- ============================================================

-- 步骤 1: 标记已变化的记录为过期
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = 'Y'
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET expiry_date = CURRENT_DATE - 1, is_current = 'N';

-- 步骤 2: 插入新版本（变化的 + 新增的）
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, DATE '9999-12-31', 'Y'
FROM   stg_customer s
WHERE  EXISTS (
    SELECT 1 FROM dim_customer d
    WHERE  d.customer_id = s.customer_id AND d.is_current = 'N'
      AND  d.expiry_date = CURRENT_DATE - 1
)
   OR NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id
);

-- ============================================================
-- 5. Teradata 时态表（原生 SCD Type 2 支持）
-- ============================================================

-- Teradata 原生支持 ANSI 时态表，自动管理版本
CREATE TABLE dim_customer_temporal (
    customer_id  VARCHAR(20) NOT NULL,
    name         VARCHAR(100),
    city         VARCHAR(100),
    tier         VARCHAR(20),
    valid_start  DATE NOT NULL,
    valid_end    DATE NOT NULL,
    PERIOD FOR valid_period (valid_start, valid_end)
) PRIMARY INDEX (customer_id);

-- 时态查询: 查看某个时间点的维度状态
SELECT * FROM dim_customer_temporal
WHERE  customer_id = 'C001'
  AND  valid_period CONTAINS DATE '2024-06-01';

-- ============================================================
-- 6. 验证查询
-- ============================================================

-- 查看当前活跃维度记录
SELECT customer_key, customer_id, name, city, tier, effective_date, is_current
FROM   dim_customer
WHERE  is_current = 'Y'
ORDER  BY customer_id;

-- 查看某个客户的历史版本
SELECT customer_key, customer_id, name, city, tier, effective_date, expiry_date
FROM   dim_customer
WHERE  customer_id = 'C001'
ORDER  BY effective_date;

-- ============================================================
-- 7. Teradata 注意事项与最佳实践
-- ============================================================

-- 1. Teradata MERGE 是高性能实现，利用 MPP 并行处理
-- 2. PRIMARY INDEX 选择 customer_id 而非 customer_key 以优化 JOIN
-- 3. Teradata 时态表是原生 SCD Type 2 方案，推荐新项目使用
-- 4. GENERATED ALWAYS AS IDENTITY 在 Teradata 16.20+ 可用
-- 5. 大表 ETL 推荐使用 TPT (Teradata Parallel Transporter)
-- 6. MERGE 的 USING 子句支持子查询，可在 MERGE 中实现复杂过滤
-- 7. SET TABLE vs MULTISET TABLE: 维度表建议使用 SET TABLE 避免重复行
