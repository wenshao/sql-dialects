-- MaxCompute (ODPS): 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] MaxCompute SQL - MERGE INTO (MaxCompute 2.0+)
--       https://help.aliyun.com/document_detail/73775.html

-- ============================================================
-- 维度表和源数据表
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
-- SCD Type 1: MERGE INTO（MaxCompute 2.0+）
-- ============================================================
MERGE INTO dim_customer t
USING stg_customer s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city)
    THEN UPDATE SET
        t.name = s.name,
        t.city = s.city,
        t.tier = s.tier
WHEN NOT MATCHED
    THEN INSERT VALUES (
        NULL, s.customer_id, s.name, s.city, s.tier,
        GETDATE(), '9999-12-31', TRUE
    );

-- ============================================================
-- SCD Type 2: INSERT OVERWRITE（传统全量重写方式）
-- ============================================================
-- 步骤 1: 标记变化行为过期，保留未变化行
-- 步骤 2: 插入新版本记录
INSERT OVERWRITE TABLE dim_customer
-- 未变化的记录（保持原样）
SELECT customer_key, customer_id, name, city, tier,
       effective_date, expiry_date, is_current
FROM   dim_customer
WHERE  NOT (is_current = TRUE
            AND customer_id IN (
                SELECT s.customer_id FROM stg_customer s
                JOIN dim_customer d ON s.customer_id = d.customer_id
                    AND d.is_current = TRUE
                WHERE s.name <> d.name OR s.city <> d.city
            ))
UNION ALL
-- 已变化的旧记录（标记过期）
SELECT d.customer_key, d.customer_id, d.name, d.city, d.tier,
       d.effective_date, GETDATE(), FALSE
FROM   dim_customer d
JOIN   stg_customer s ON d.customer_id = s.customer_id
WHERE  d.is_current = TRUE AND (d.name <> s.name OR d.city <> s.city)
UNION ALL
-- 新版本记录
SELECT NULL, s.customer_id, s.name, s.city, s.tier,
       GETDATE(), '9999-12-31', TRUE
FROM   stg_customer s
JOIN   dim_customer d ON s.customer_id = d.customer_id
    AND d.is_current = TRUE
WHERE  s.name <> d.name OR s.city <> d.city;

-- 注意：MaxCompute 不支持行级 UPDATE/DELETE（非事务表）
-- 注意：SCD Type 2 需要 INSERT OVERWRITE 全量重写
-- 注意：MERGE INTO 仅 MaxCompute 2.0+ 支持
-- 注意：GETDATE() 返回当前日期时间
-- 限制：无 UPDATE ... FROM 语法
-- 限制：全量重写在大表上性能可能较差
