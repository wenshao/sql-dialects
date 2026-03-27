-- Spark SQL: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Delta Lake - MERGE INTO
--       https://docs.delta.io/latest/delta-update.html#upsert-into-a-table-using-merge
--   [2] Apache Iceberg - MERGE INTO
--       https://iceberg.apache.org/docs/latest/spark-writes/#merge-into
--   [3] Spark SQL Reference - MERGE
--       https://spark.apache.org/docs/latest/sql-ref-syntax-dml-merge-into.html

-- ============================================================
-- Delta Lake: SCD Type 1（MERGE INTO）
-- ============================================================
MERGE INTO delta.dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET t.name = s.name, t.city = s.city, t.tier = s.tier
WHEN NOT MATCHED
    THEN INSERT (customer_id, name, city, tier, effective_date, expiry_date, is_current)
         VALUES (s.customer_id, s.name, s.city, s.tier,
                 current_date(), DATE '9999-12-31', TRUE);

-- ============================================================
-- Delta Lake: SCD Type 2（两步 MERGE）
-- ============================================================
-- 准备变更数据
CREATE OR REPLACE TEMPORARY VIEW staged_updates AS
SELECT s.customer_id, s.name, s.city, s.tier,
       TRUE AS is_new_version
FROM   stg_customer s
JOIN   dim_customer t ON s.customer_id = t.customer_id AND t.is_current = TRUE
WHERE  s.name <> t.name OR s.city <> t.city OR s.tier <> t.tier
UNION ALL
SELECT customer_id, name, city, tier, FALSE
FROM   stg_customer
WHERE  customer_id NOT IN (SELECT customer_id FROM dim_customer);

-- 合并：关闭旧版本 + 插入新版本
MERGE INTO delta.dim_customer AS t
USING (
    SELECT customer_id, name, city, tier, is_new_version,
           current_date() AS effective_date,
           DATE '9999-12-31' AS expiry_date,
           TRUE AS is_current
    FROM staged_updates
    UNION ALL
    SELECT NULL, NULL, NULL, NULL, NULL,
           NULL, DATE_SUB(current_date(), 1), FALSE
) AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE AND s.is_new_version IS NULL
WHEN MATCHED THEN UPDATE SET t.expiry_date = s.expiry_date, t.is_current = FALSE
WHEN NOT MATCHED AND s.is_new_version IS NOT NULL THEN
    INSERT (customer_id, name, city, tier, effective_date, expiry_date, is_current)
    VALUES (s.customer_id, s.name, s.city, s.tier, s.effective_date, s.expiry_date, TRUE);

-- ============================================================
-- Delta Lake Time Travel
-- ============================================================
-- SELECT * FROM delta.dim_customer VERSION AS OF 5;
-- SELECT * FROM delta.dim_customer TIMESTAMP AS OF '2024-06-01';
