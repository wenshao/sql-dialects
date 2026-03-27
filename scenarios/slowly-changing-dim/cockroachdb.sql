-- CockroachDB: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] CockroachDB Documentation - INSERT ON CONFLICT (UPSERT)
--       https://www.cockroachlabs.com/docs/stable/insert
--   [2] CockroachDB Documentation - UPDATE
--       https://www.cockroachlabs.com/docs/stable/update
--   [3] CockroachDB Documentation - Transactions
--       https://www.cockroachlabs.com/docs/stable/transactions
--   [4] CockroachDB - PostgreSQL Compatibility
--       https://www.cockroachlabs.com/docs/stable/postgresql-compatibility

-- ============================================================
-- 1. 维度表结构
-- ============================================================

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

-- CockroachDB 兼容 PostgreSQL 的 UPSERT 语法
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON CONFLICT (customer_id, is_current, effective_date)
DO UPDATE SET name = EXCLUDED.name, city = EXCLUDED.city,
              tier = EXCLUDED.tier, updated_at = NOW();

-- 方法 2: UPSERT 简写（CockroachDB 对单行操作的优化）
-- UPSERT 比 INSERT ON CONFLICT 更高效，因为它直接写入不先读
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
VALUES ('C001', 'Alice', 'Hangzhou', 'Platinum', CURRENT_DATE, '9999-12-31', TRUE)
ON CONFLICT (customer_id, is_current, effective_date)
DO UPDATE SET name = EXCLUDED.name, city = EXCLUDED.city, tier = EXCLUDED.tier;

-- ============================================================
-- 4. SCD Type 2: UPDATE + INSERT（保留历史版本）
-- ============================================================

-- 步骤 1: 检测变化并标记当前行为过期
UPDATE dim_customer AS t
SET    expiry_date = CURRENT_DATE - INTERVAL '1 day',
       is_current  = FALSE
FROM   stg_customer AS s
WHERE  t.customer_id = s.customer_id AND t.is_current = TRUE
  AND  (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier);

-- 步骤 2: 插入新版本（变化的 + 新增的）
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', TRUE
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

-- ============================================================
-- 6. CockroachDB 注意事项与最佳实践
-- ============================================================

-- 1. CockroachDB 高度兼容 PostgreSQL 语法，包括 ON CONFLICT
-- 2. CockroachDB 不支持可写 CTE（WITH ... DML ... RETURNING）
--    因此 SCD Type 2 必须分步执行，不能使用 PostgreSQL 的单语句方案
-- 3. 分布式事务使用 SERIAL 隔离级别（默认），保证强一致性
-- 4. SERIAL 类型在 CockroachDB 中生成有序唯一 ID（非自增）
-- 5. 对于高频写入场景，建议使用 UPSERT 代替 INSERT ON CONFLICT
-- 6. CockroachDB 的 RANGE 分片自动管理，无需手动指定分布键
-- 7. 大规模 ETL 操作建议使用批量导入（IMPORT）而非逐行 INSERT
-- 8. CockroachDB 支持 CHANGEFEED（CDC），可监听维度表变更
