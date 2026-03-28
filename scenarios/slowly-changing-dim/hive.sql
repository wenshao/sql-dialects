-- Hive: 缓慢变化维度 (SCD - Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Apache Hive - MERGE
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DML#LanguageManualDML-Merge
--   [2] Apache Hive - ACID Transactions
--       https://cwiki.apache.org/confluence/display/Hive/Hive+Transactions

-- ============================================================
-- 1. 表结构
-- ============================================================
CREATE TABLE dim_customer (
    customer_key   BIGINT,
    customer_id    STRING,
    name           STRING,
    city           STRING,
    tier           STRING,
    effective_date DATE,
    expiry_date    DATE,
    is_current     BOOLEAN
) STORED AS ORC TBLPROPERTIES ('transactional' = 'true');

CREATE TABLE stg_customer (
    customer_id STRING, name STRING, city STRING, tier STRING
) STORED AS ORC;

-- ============================================================
-- 2. SCD Type 1: MERGE 直接覆盖 (ACID 表, 2.2+)
-- ============================================================
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier) THEN
    UPDATE SET name = s.name, city = s.city, tier = s.tier
WHEN NOT MATCHED THEN
    INSERT VALUES (NULL, s.customer_id, s.name, s.city, s.tier,
                   CURRENT_DATE, DATE '9999-12-31', TRUE);

-- ============================================================
-- 3. SCD Type 2: INSERT OVERWRITE (非 ACID 表, 推荐)
-- ============================================================
-- Type 2: 保留历史记录，旧记录关闭，新记录打开
INSERT OVERWRITE TABLE dim_customer
-- 不变的行: 保持原样
SELECT customer_key, customer_id, name, city, tier,
       effective_date, expiry_date, is_current
FROM dim_customer d
WHERE NOT EXISTS (
    SELECT 1 FROM stg_customer s
    WHERE s.customer_id = d.customer_id AND d.is_current = TRUE
)
UNION ALL
-- 变更的旧记录: 关闭
SELECT d.customer_key, d.customer_id, d.name, d.city, d.tier,
       d.effective_date, CURRENT_DATE AS expiry_date, FALSE AS is_current
FROM dim_customer d
JOIN stg_customer s ON d.customer_id = s.customer_id
WHERE d.is_current = TRUE
  AND (d.name <> s.name OR d.city <> s.city OR d.tier <> s.tier)
UNION ALL
-- 变更的新记录: 打开
SELECT NULL, s.customer_id, s.name, s.city, s.tier,
       CURRENT_DATE, DATE '9999-12-31', TRUE
FROM stg_customer s
JOIN dim_customer d ON d.customer_id = s.customer_id
WHERE d.is_current = TRUE
  AND (d.name <> s.name OR d.city <> s.city OR d.tier <> s.tier)
UNION ALL
-- 全新的客户
SELECT NULL, s.customer_id, s.name, s.city, s.tier,
       CURRENT_DATE, DATE '9999-12-31', TRUE
FROM stg_customer s
WHERE NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id);

-- 设计分析: INSERT OVERWRITE SCD Type 2
-- 优点: 不需要 ACID 表，所有 Hive 版本都支持; 幂等性
-- 缺点: 需要全量重写维度表（即使只有少量变更）

-- ============================================================
-- 4. SCD Type 3: 添加列保存前值
-- ============================================================
-- Type 3: 只保留一层历史（前值）
-- ALTER TABLE dim_customer ADD COLUMNS (prev_city STRING, prev_tier STRING);
-- 用 MERGE 或 INSERT OVERWRITE 更新前值列

-- ============================================================
-- 5. 跨引擎对比: SCD 实现
-- ============================================================
-- 引擎          SCD Type 1        SCD Type 2               推荐方式
-- MySQL         UPDATE             INSERT + UPDATE           触发器/存储过程
-- PostgreSQL    UPDATE             INSERT + UPDATE           MERGE(15+)
-- Oracle        MERGE              MERGE                    MERGE(最成熟)
-- Hive(ACID)    MERGE              MERGE                    MERGE(2.2+)
-- Hive(非ACID)  INSERT OVERWRITE   INSERT OVERWRITE(全量)   INSERT OVERWRITE
-- Spark/Delta   MERGE              MERGE                    Delta Lake MERGE
-- BigQuery      MERGE              MERGE                    MERGE

-- ============================================================
-- 6. 对引擎开发者的启示
-- ============================================================
-- 1. SCD 是数仓的核心操作: 大数据引擎必须高效支持 MERGE
-- 2. INSERT OVERWRITE 是非 ACID 环境下 SCD 的唯一选择:
--    全量重写维度表，代价随维度表大小线性增长
-- 3. MERGE 大幅简化了 SCD Type 2: 一条语句完成关闭旧记录+打开新记录
-- 4. Delta Lake/Iceberg 的 MERGE 是 Hive ACID MERGE 的现代替代:
--    性能更好（不需要 Compaction），事务保证更强
