-- ClickHouse: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] ClickHouse Documentation - ReplacingMergeTree
--       https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree
--   [2] ClickHouse Documentation - CollapsingMergeTree
--       https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/collapsingmergetree
--   [3] ClickHouse Documentation - VersionedCollapsingMergeTree
--       https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/versionedcollapsingmergetree

-- ============================================================
-- 注意: ClickHouse 没有 UPDATE/MERGE 语句（传统意义上的）
-- 使用引擎特性来实现 SCD 模式
-- ============================================================

-- ============================================================
-- SCD Type 1: ReplacingMergeTree（推荐）
-- 后台自动合并，保留最新版本
-- ============================================================
CREATE TABLE dim_customer (
    customer_id    String,
    name           String,
    city           String,
    tier           String,
    updated_at     DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY customer_id;

-- 直接插入新数据，旧数据在后台合并时被替换
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer;

-- 查询时用 FINAL 确保去重（或使用子查询）
SELECT * FROM dim_customer FINAL;
-- 或
SELECT * FROM dim_customer WHERE (customer_id, updated_at) IN (
    SELECT customer_id, MAX(updated_at) FROM dim_customer GROUP BY customer_id
);

-- ============================================================
-- SCD Type 2: VersionedCollapsingMergeTree
-- 保留所有版本，用 sign 标记有效/失效
-- ============================================================
CREATE TABLE dim_customer_scd2 (
    customer_id    String,
    name           String,
    city           String,
    tier           String,
    effective_date Date DEFAULT today(),
    expiry_date    Date DEFAULT '9999-12-31',
    sign           Int8,        -- 1: 有效, -1: 失效
    version        UInt32
) ENGINE = VersionedCollapsingMergeTree(sign, version)
ORDER BY (customer_id, effective_date);

-- 关闭旧版本（插入 sign=-1 的记录）+ 插入新版本（sign=1）
INSERT INTO dim_customer_scd2
SELECT customer_id, name, city, tier,
       effective_date, today() - 1, -1, version  -- 关闭旧版本
FROM   dim_customer_scd2 FINAL
WHERE  customer_id IN (SELECT customer_id FROM stg_customer)
  AND  sign = 1;

INSERT INTO dim_customer_scd2
SELECT customer_id, name, city, tier,
       today(), '9999-12-31', 1, 1 + (
           SELECT max(version) FROM dim_customer_scd2
           WHERE customer_id = s.customer_id
       )
FROM   stg_customer s;
