-- Trino: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Trino Documentation - MERGE
--       https://trino.io/docs/current/sql/merge.html
--   [2] Trino Documentation - UPDATE
--       https://trino.io/docs/current/sql/update.html
--   [3] Trino Documentation - INSERT
--       https://trino.io/docs/current/sql/insert.html
--   [4] Trino Documentation - Connector Support
--       https://trino.io/docs/current/connector.html

-- ============================================================
-- 1. 维度表结构
-- ============================================================

-- Trino 本身不存储数据，表结构取决于底层 connector（Hive, Iceberg, Delta Lake 等）
-- 以下以 Iceberg connector 为例
CREATE TABLE iceberg.dim.dim_customer (
    customer_key   BIGINT,
    customer_id    VARCHAR(20),
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE,
    expiry_date    DATE,
    is_current     BOOLEAN
);

CREATE TABLE iceberg.dim.stg_customer (
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
-- 3. SCD Type 1: MERGE（需要 connector 支持）
-- ============================================================

-- Trino 402+ 对 Iceberg/Delta Lake connector 支持 MERGE
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET name = s.name, city = s.city, tier = s.tier
WHEN NOT MATCHED
    THEN INSERT (customer_key, customer_id, name, city, tier, effective_date, expiry_date, is_current)
         VALUES (
             -- Trino 没有内置自增，使用 UUID 或 ROW_NUMBER 模拟
             CAST(RANDOM() * 1000000000 AS BIGINT),
             s.customer_id, s.name, s.city, s.tier,
             CURRENT_DATE, DATE '9999-12-31', TRUE
         );

-- 方法 2: DELETE + INSERT（适用于不支持 MERGE 的 connector）
DELETE FROM dim_customer
WHERE  customer_id IN (SELECT customer_id FROM stg_customer);

INSERT INTO dim_customer (customer_key, customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT CAST(RANDOM() * 1000000000 AS BIGINT),
       customer_id, name, city, tier, CURRENT_DATE, DATE '9999-12-31', TRUE
FROM   stg_customer;

-- ============================================================
-- 4. SCD Type 2: 两步操作（保留历史版本）
-- ============================================================

-- 步骤 1: 检测变化并标记当前行为过期
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET expiry_date = CURRENT_DATE - INTERVAL '1' DAY, is_current = FALSE;

-- 步骤 2: 插入新版本（变化的 + 新增的）
INSERT INTO dim_customer (customer_key, customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT CAST(RANDOM() * 1000000000 AS BIGINT),
       s.customer_id, s.name, s.city, s.tier,
       CURRENT_DATE, DATE '9999-12-31', TRUE
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = TRUE
);

-- ============================================================
-- 5. 验证查询
-- ============================================================

-- 查看当前活跃维度记录
SELECT customer_key, customer_id, name, city, tier, effective_date, is_current
FROM   dim_customer
WHERE  is_current = TRUE
ORDER  BY customer_id;

-- 查看某个客户的历史版本
SELECT customer_key, customer_id, name, city, tier, effective_date, expiry_date
FROM   dim_customer
WHERE  customer_id = 'C001'
ORDER  BY effective_date;

-- 跨 Catalog 查询（Trino 特色）
SELECT d.customer_id, d.name, d.tier, o.order_total
FROM   iceberg.dim.dim_customer d
JOIN   hive.sales.fact_orders o ON d.customer_id = o.customer_id
WHERE  d.is_current = TRUE;

-- ============================================================
-- 6. Trino 注意事项与最佳实践
-- ============================================================

-- 1. Trino 本身不存储数据，MERGE/UPDATE/DELETE 依赖底层 connector
-- 2. 支持 MERGE 的 connector: Iceberg, Delta Lake, Hive (ACID)
-- 3. 不支持 MERGE 的 connector: PostgreSQL, MySQL, etc.（使用分步操作）
-- 4. Trino 没有内置自增序列，建议使用 UUID 或应用层生成代理键
-- 5. Iceberg connector 推荐: 支持 ACID、Schema 演进、Time Travel
-- 6. 大规模 SCD 推荐使用 Iceberg + MERGE，利用 Iceberg 的增量写入能力
-- 7. Trino 适合作为湖仓一体的查询引擎，不建议直接作为 ETL 执行引擎
-- 8. 跨 Catalog JOIN 是 Trino 独特优势，适合联邦查询场景
