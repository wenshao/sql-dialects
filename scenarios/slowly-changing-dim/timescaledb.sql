-- TimescaleDB: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] TimescaleDB Documentation - Hypertable
--       https://docs.timescale.com/api/latest/hypertable/
--   [2] TimescaleDB Documentation - PostgreSQL Compatibility
--       https://docs.timescale.com/use-timescale/latest/compression/
--   [3] PostgreSQL Documentation - INSERT ON CONFLICT
--       https://www.postgresql.org/docs/current/sql-insert.html#SQL-ON-CONFLICT
--   [4] PostgreSQL Documentation - MERGE (15+)
--       https://www.postgresql.org/docs/15/sql-merge.html

-- ============================================================
-- 1. 维度表结构
-- ============================================================

-- TimescaleDB 完全兼容 PostgreSQL DDL/DML
CREATE TABLE dim_customer (
    customer_key   SERIAL PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date    DATE NOT NULL DEFAULT '9999-12-31',
    is_current     BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at     TIMESTAMP DEFAULT NOW(),
    UNIQUE (customer_id, is_current, effective_date)
);

-- 可选: 将维度表转为 Hypertable（按 effective_date 分片，适合大规模维度）
-- SELECT create_hypertable('dim_customer', 'effective_date');
-- 注意: 维度表通常不大，使用普通 PostgreSQL 表即可
-- Hypertable 更适合事实表

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
-- 3. SCD Type 1: INSERT ... ON CONFLICT（PostgreSQL 兼容）
-- ============================================================

-- TimescaleDB 完全兼容 PostgreSQL UPSERT 语法
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON CONFLICT (customer_id)
DO UPDATE SET name = EXCLUDED.name, city = EXCLUDED.city,
              tier = EXCLUDED.tier, updated_at = NOW();

-- 方法 2: MERGE（PostgreSQL 15+ / TimescaleDB 兼容）
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET name = s.name, city = s.city, tier = s.tier
WHEN NOT MATCHED
    THEN INSERT (customer_id, name, city, tier)
         VALUES (s.customer_id, s.name, s.city, s.tier);

-- ============================================================
-- 4. SCD Type 2: 可写 CTE 版本化（PostgreSQL 最佳方式）
-- ============================================================

-- TimescaleDB 继承了 PostgreSQL 的可写 CTE 能力
-- 使用可写 CTE 在单语句中原子完成 SCD Type 2:
WITH changed AS (
    UPDATE dim_customer AS t
    SET expiry_date = CURRENT_DATE - 1, is_current = FALSE
    FROM stg_customer AS s
    WHERE t.customer_id = s.customer_id AND t.is_current = TRUE
      AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    RETURNING t.customer_id
)
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE
FROM stg_customer s
WHERE s.customer_id IN (SELECT customer_id FROM changed)
   OR NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id);

-- ============================================================
-- 5. TimescaleDB 特色: 时序数据关联维度
-- ============================================================

-- 创建事实表（Hypertable，按时间分片）
CREATE TABLE fact_orders (
    time         TIMESTAMPTZ NOT NULL,
    order_id     BIGINT,
    customer_id  VARCHAR(20),
    amount       NUMERIC(10, 2)
);
SELECT create_hypertable('fact_orders', 'time');

-- 关联维度查询（点时间查询: 某个时刻的维度状态）
SELECT f.time, f.order_id, d.name, d.city, d.tier
FROM   fact_orders f
JOIN   dim_customer d ON f.customer_id = d.customer_id
WHERE  f.time BETWEEN d.effective_date AND d.expiry_date
  AND  f.time > NOW() - INTERVAL '30 days'
ORDER  BY f.time DESC;

-- ============================================================
-- 6. 验证查询
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

-- ============================================================
-- 7. TimescaleDB 注意事项与最佳实践
-- ============================================================

-- 1. TimescaleDB 是 PostgreSQL 扩展，100% 兼容 PostgreSQL 语法
-- 2. 维度表通常使用普通 PostgreSQL 表（非 Hypertable）
-- 3. 事实表使用 Hypertable，按时间自动分片
-- 4. 可写 CTE 让 SCD Type 2 成为单语句原子操作（PostgreSQL 独有）
-- 5. 查询维度时可利用 PostgreSQL 的范围类型:
--    CREATE INDEX idx_valid_period ON dim_customer
--        USING GIST (customer_id, daterange(effective_date, expiry_date));
-- 6. TimescaleDB 支持连续聚合 (Continuous Aggregate)，
--    可预计算维度关联结果，加速分析查询
-- 7. 利用 TimescaleDB 压缩功能优化历史维度存储:
--    SELECT add_compression_policy('dim_customer', INTERVAL '90 days');
