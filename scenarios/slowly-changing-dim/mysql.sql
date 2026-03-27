-- MySQL: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - INSERT ... ON DUPLICATE KEY UPDATE
--       https://dev.mysql.com/doc/refman/8.0/en/insert-on-duplicate.html
--   [2] MySQL 8.0 Reference Manual - Multi-table UPDATE
--       https://dev.mysql.com/doc/refman/8.0/en/update.html
--   [3] Kimball Group - SCD Types

-- ============================================================
-- 维度表和源数据表
-- ============================================================
CREATE TABLE dim_customer (
    customer_key   INT AUTO_INCREMENT PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    expiry_date    DATE NOT NULL DEFAULT '9999-12-31',
    is_current     TINYINT NOT NULL DEFAULT 1,
    created_at     DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_customer_current (customer_id, is_current, effective_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE stg_customer (
    customer_id    VARCHAR(20),
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================
-- SCD Type 1: 直接覆盖
-- ============================================================
-- 方法 1: INSERT ... ON DUPLICATE KEY UPDATE
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    city = VALUES(city),
    tier = VALUES(tier);

-- 方法 2: UPDATE + INSERT（不存在时插入）
UPDATE dim_customer t
JOIN   stg_customer s ON t.customer_id = s.customer_id
SET    t.name = s.name,
       t.city = s.city,
       t.tier = s.tier
WHERE  t.is_current = 1;

INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT s.customer_id, s.name, s.city, s.tier
FROM   stg_customer s
LEFT JOIN dim_customer t ON t.customer_id = s.customer_id
WHERE  t.customer_id IS NULL;

-- ============================================================
-- SCD Type 2: 版本化
-- MySQL 没有 MERGE 语句，需要分步执行
-- ============================================================
-- 步骤 1: 标记已变化的记录为过期
UPDATE dim_customer t
JOIN   stg_customer s ON t.customer_id = s.customer_id
SET    t.expiry_date = DATE_SUB(CURRENT_DATE, INTERVAL 1 DAY),
       t.is_current  = 0
WHERE  t.is_current = 1
  AND  (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier);

-- 步骤 2: 插入新版本（变化的 + 新增的）
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier,
       CURRENT_DATE, '9999-12-31', 1
FROM   stg_customer s
WHERE  EXISTS (
    SELECT 1 FROM dim_customer d
    WHERE  d.customer_id = s.customer_id
      AND  d.is_current = 0
      AND  d.expiry_date = DATE_SUB(CURRENT_DATE, INTERVAL 1 DAY)
)
   OR NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id
);
