-- Databricks: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Databricks - Delta Lake MERGE
--       https://docs.databricks.com/delta/merge.html
--   [2] Databricks - SCD Type 2 Best Practices
--       https://docs.databricks.com/delta/merge.html#slowly-changing-data-scd-type-2

-- ============================================================
-- SCD Type 1: Delta MERGE
-- ============================================================
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name != s.name OR t.city != s.city OR t.tier != s.tier)
    THEN UPDATE SET t.name = s.name, t.city = s.city, t.tier = s.tier
WHEN NOT MATCHED
    THEN INSERT (customer_id, name, city, tier, effective_date, expiry_date, is_current)
         VALUES (s.customer_id, s.name, s.city, s.tier, current_date(), DATE '9999-12-31', TRUE);

-- ============================================================
-- SCD Type 2: Delta MERGE（Databricks 推荐模式）
-- ============================================================
-- 准备: 标记新版本行和关闭行
MERGE INTO dim_customer AS t
USING (
    -- 已变化的行 + 新增的行
    SELECT s.customer_id, s.name, s.city, s.tier, TRUE AS merge_key_match
    FROM stg_customer s JOIN dim_customer d
    ON s.customer_id = d.customer_id AND d.is_current = TRUE
    WHERE s.name != d.name OR s.city != d.city OR s.tier != d.tier
    UNION ALL
    -- 用于关闭旧版本的记录（不同 merge key 以触发 NOT MATCHED）
    SELECT s.customer_id, s.name, s.city, s.tier, FALSE
    FROM stg_customer s
) AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE AND s.merge_key_match = FALSE
WHEN MATCHED THEN
    UPDATE SET t.is_current = FALSE, t.expiry_date = current_date() - INTERVAL 1 DAY
WHEN NOT MATCHED THEN
    INSERT (customer_id, name, city, tier, effective_date, expiry_date, is_current)
    VALUES (s.customer_id, s.name, s.city, s.tier, current_date(), DATE '9999-12-31', TRUE);

-- Delta Lake Time Travel
-- SELECT * FROM dim_customer VERSION AS OF 3;
-- SELECT * FROM dim_customer TIMESTAMP AS OF '2024-06-01';
