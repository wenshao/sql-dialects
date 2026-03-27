-- SQLite: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] SQLite Documentation - UPSERT
--       https://www.sqlite.org/lang_UPSERT.html
--   [2] SQLite Documentation - INSERT ... ON CONFLICT
--       https://www.sqlite.org/lang_conflict.html

-- ============================================================
-- 维度表和源数据表
-- ============================================================
CREATE TABLE dim_customer (
    customer_key   INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id    TEXT NOT NULL,
    name           TEXT,
    city           TEXT,
    tier           TEXT,
    effective_date TEXT NOT NULL DEFAULT (DATE('now')),
    expiry_date    TEXT NOT NULL DEFAULT '9999-12-31',
    is_current     INTEGER NOT NULL DEFAULT 1,
    created_at     TEXT DEFAULT (DATETIME('now')),
    updated_at     TEXT DEFAULT (DATETIME('now'))
);
CREATE UNIQUE INDEX uk_dim_cust ON dim_customer(customer_id) WHERE is_current = 1;

CREATE TABLE stg_customer (
    customer_id TEXT, name TEXT, city TEXT, tier TEXT
);

-- ============================================================
-- SCD Type 1: UPSERT（SQLite 3.24.0+）
-- ============================================================
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON CONFLICT (customer_id) WHERE is_current = 1
DO UPDATE SET
    name       = excluded.name,
    city       = excluded.city,
    tier       = excluded.tier,
    updated_at = DATETIME('now');

-- ============================================================
-- SCD Type 2: UPDATE + INSERT（SQLite 没有 MERGE）
-- ============================================================
-- 步骤 1
UPDATE dim_customer
SET    expiry_date = DATE('now', '-1 day'),
       is_current  = 0,
       updated_at  = DATETIME('now')
WHERE  customer_id IN (
    SELECT s.customer_id FROM stg_customer s
    JOIN   dim_customer d ON d.customer_id = s.customer_id
    WHERE  d.is_current = 1
      AND  (d.name <> s.name OR d.city <> s.city OR d.tier <> s.tier)
);

-- 步骤 2
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier,
       DATE('now'), '9999-12-31', 1
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d
    WHERE  d.customer_id = s.customer_id AND d.is_current = 1
);
