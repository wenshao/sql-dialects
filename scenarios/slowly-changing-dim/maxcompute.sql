-- MaxCompute (ODPS): 缓慢变化维度 (SCD)
--
-- 参考资料:
--   [1] MaxCompute SQL - MERGE INTO
--       https://help.aliyun.com/zh/maxcompute/user-guide/merge-into

-- ============================================================
-- 1. 维度表和源数据表
-- ============================================================

CREATE TABLE IF NOT EXISTS dim_customer (
    customer_key   BIGINT,
    customer_id    STRING,
    name           STRING,
    city           STRING,
    tier           STRING,
    effective_date STRING,
    expiry_date    STRING,
    is_current     BOOLEAN
);

CREATE TABLE IF NOT EXISTS stg_customer (
    customer_id    STRING,
    name           STRING,
    city           STRING,
    tier           STRING
);

-- ============================================================
-- 2. SCD Type 1: MERGE INTO（事务表，最简洁）
-- ============================================================

-- Type 1: 直接覆盖，不保留历史
MERGE INTO dim_customer t
USING stg_customer s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city)
    THEN UPDATE SET
        t.name = s.name, t.city = s.city, t.tier = s.tier
WHEN NOT MATCHED
    THEN INSERT VALUES (
        NULL, s.customer_id, s.name, s.city, s.tier,
        TO_CHAR(GETDATE(), 'yyyy-MM-dd'), '9999-12-31', TRUE
    );

-- MERGE 要求 dim_customer 是事务表:
-- CREATE TABLE dim_customer (..., PRIMARY KEY (customer_key))
-- TBLPROPERTIES ('transactional' = 'true');

-- ============================================================
-- 3. SCD Type 2: INSERT OVERWRITE（普通表，全量重写）
-- ============================================================

-- Type 2: 保留所有历史版本
-- 步骤: 保留未变化行 + 过期已变化行 + 插入新版本行

INSERT OVERWRITE TABLE dim_customer
-- 未变化的记录（保持原样）
SELECT customer_key, customer_id, name, city, tier,
       effective_date, expiry_date, is_current
FROM dim_customer
WHERE NOT (is_current = TRUE
    AND customer_id IN (
        SELECT s.customer_id FROM stg_customer s
        JOIN dim_customer d ON s.customer_id = d.customer_id
            AND d.is_current = TRUE
        WHERE s.name <> d.name OR s.city <> d.city
    ))
UNION ALL
-- 已变化的旧记录（标记过期）
SELECT d.customer_key, d.customer_id, d.name, d.city, d.tier,
       d.effective_date, TO_CHAR(GETDATE(), 'yyyy-MM-dd'), FALSE
FROM dim_customer d
JOIN stg_customer s ON d.customer_id = s.customer_id
WHERE d.is_current = TRUE AND (d.name <> s.name OR d.city <> s.city)
UNION ALL
-- 新版本记录
SELECT NULL, s.customer_id, s.name, s.city, s.tier,
       TO_CHAR(GETDATE(), 'yyyy-MM-dd'), '9999-12-31', TRUE
FROM stg_customer s
JOIN dim_customer d ON s.customer_id = d.customer_id AND d.is_current = TRUE
WHERE s.name <> d.name OR s.city <> d.city
UNION ALL
-- 全新客户
SELECT NULL, s.customer_id, s.name, s.city, s.tier,
       TO_CHAR(GETDATE(), 'yyyy-MM-dd'), '9999-12-31', TRUE
FROM stg_customer s
LEFT ANTI JOIN dim_customer d ON s.customer_id = d.customer_id;

-- SCD Type 2 的复杂性分析:
--   普通表无 UPDATE → 必须重写全表
--   三路 UNION ALL: 未变化 + 过期旧版 + 新版本 + 全新记录
--   大维度表（千万行+）: 每天全量重写可能耗时较长
--   事务表 MERGE 更简洁但需要额外的行级操作

-- ============================================================
-- 4. SCD Type 2: MERGE（事务表，更简洁）
-- ============================================================

-- 步骤 1: 过期已变化的记录
MERGE INTO dim_customer t
USING stg_customer s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city)
    THEN UPDATE SET
        t.expiry_date = TO_CHAR(GETDATE(), 'yyyy-MM-dd'),
        t.is_current = FALSE;

-- 步骤 2: 插入新版本
INSERT INTO dim_customer
SELECT NULL, s.customer_id, s.name, s.city, s.tier,
       TO_CHAR(GETDATE(), 'yyyy-MM-dd'), '9999-12-31', TRUE
FROM stg_customer s
LEFT ANTI JOIN dim_customer d
    ON s.customer_id = d.customer_id AND d.is_current = TRUE;

-- 注意: 这不是原子操作（两个独立语句），可能需要在 Script Mode 中执行

-- ============================================================
-- 5. 横向对比与引擎开发者启示
-- ============================================================

-- SCD 实现方式:
--   MaxCompute 普通表: INSERT OVERWRITE 全量重写（复杂但通用）
--   MaxCompute 事务表: MERGE INTO（简洁但需要事务表）
--   Hive:              同 MaxCompute（INSERT OVERWRITE 为主）
--   BigQuery:           MERGE INTO（所有表支持 DML）
--   Snowflake:          MERGE INTO + STREAMS（变更捕获）
--   Delta Lake:         MERGE INTO + Change Data Feed

-- 对引擎开发者:
-- 1. SCD Type 2 是数据仓库的核心操作 — MERGE 是最佳工具
-- 2. 普通表的 INSERT OVERWRITE SCD 非常复杂 — 事务表简化了 10 倍
-- 3. Snowflake STREAMS 的变更捕获思路值得借鉴 — 自动识别变化记录
-- 4. SCD 操作应优化为增量处理 — 避免每天全量重写大维度表
