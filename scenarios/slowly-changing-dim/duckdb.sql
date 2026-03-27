-- DuckDB: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] DuckDB Documentation - INSERT ... ON CONFLICT
--       https://duckdb.org/docs/sql/statements/insert#on-conflict-clause
--   [2] DuckDB Documentation - UPDATE
--       https://duckdb.org/docs/sql/statements/update

-- ============================================================
-- 维度表
-- ============================================================
CREATE TABLE dim_customer (
    customer_key   INTEGER PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL UNIQUE,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date    DATE NOT NULL DEFAULT DATE '9999-12-31',
    is_current     BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE stg_customer (
    customer_id VARCHAR(20), name VARCHAR(100), city VARCHAR(100), tier VARCHAR(20)
);

-- ============================================================
-- SCD Type 1: INSERT ... ON CONFLICT
-- ============================================================
INSERT INTO dim_customer (customer_key, customer_id, name, city, tier)
SELECT ROW_NUMBER() OVER (), customer_id, name, city, tier FROM stg_customer
ON CONFLICT (customer_id) DO UPDATE SET
    name = EXCLUDED.name,
    city = EXCLUDED.city,
    tier = EXCLUDED.tier;

-- ============================================================
-- SCD Type 2: UPDATE + INSERT
-- ============================================================
UPDATE dim_customer AS t
SET    expiry_date = CURRENT_DATE - INTERVAL 1 DAY,
       is_current  = FALSE
FROM   stg_customer AS s
WHERE  t.customer_id = s.customer_id
  AND  t.is_current = TRUE
  AND  (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier);

INSERT INTO dim_customer (customer_key, customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT (SELECT COALESCE(MAX(customer_key), 0) FROM dim_customer) + ROW_NUMBER() OVER (),
       s.customer_id, s.name, s.city, s.tier,
       CURRENT_DATE, DATE '9999-12-31', TRUE
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d
    WHERE  d.customer_id = s.customer_id AND d.is_current = TRUE
);
