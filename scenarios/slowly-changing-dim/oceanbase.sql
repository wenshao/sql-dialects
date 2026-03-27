-- OceanBase: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] OceanBase Documentation - INSERT ON DUPLICATE KEY UPDATE
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn-1000000000157744
--   [2] OceanBase Documentation - UPDATE
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn-1000000000157749
--   [3] OceanBase Documentation - MySQL Compatibility
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn-1000000000218464
--   [4] Kimball Group - SCD Types
--       https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/

-- ============================================================
-- 1. 维度表结构
-- ============================================================

-- OceanBase MySQL 模式兼容 MySQL DDL/DML
CREATE TABLE dim_customer (
    customer_key   INT AUTO_INCREMENT PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date    DATE NOT NULL DEFAULT '9999-12-31',
    is_current     TINYINT NOT NULL DEFAULT 1,
    created_at     DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_customer_current (customer_id, is_current, effective_date)
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
-- 3. SCD Type 1: INSERT ... ON DUPLICATE KEY UPDATE
-- ============================================================

-- OceanBase 兼容 MySQL 的 UPSERT 语法
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    city = VALUES(city),
    tier = VALUES(tier);

-- 方法 2: UPDATE + JOIN（同 MySQL）
UPDATE dim_customer t
JOIN   stg_customer s ON t.customer_id = s.customer_id
SET    t.name = s.name, t.city = s.city, t.tier = s.tier
WHERE  t.is_current = 1;

-- 方法 3: REPLACE INTO（删除旧行再插入新行，谨慎使用）
-- REPLACE 会触发 DELETE + INSERT，可能影响自增主键和触发器
-- REPLACE INTO dim_customer (customer_id, name, city, tier)
-- SELECT customer_id, name, city, tier FROM stg_customer;

-- ============================================================
-- 4. SCD Type 2: UPDATE + INSERT（保留历史版本）
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
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', 1
FROM   stg_customer s
WHERE  EXISTS (
    SELECT 1 FROM dim_customer d
    WHERE  d.customer_id = s.customer_id AND d.is_current = 0
      AND  d.expiry_date = DATE_SUB(CURRENT_DATE, INTERVAL 1 DAY)
)
   OR NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id
);

-- ============================================================
-- 5. 验证查询
-- ============================================================

-- 查看当前活跃维度记录
SELECT customer_key, customer_id, name, city, tier, effective_date, is_current
FROM   dim_customer
WHERE  is_current = 1
ORDER  BY customer_id;

-- 查看某个客户的历史版本
SELECT customer_key, customer_id, name, city, tier, effective_date, expiry_date
FROM   dim_customer
WHERE  customer_id = 'C001'
ORDER  BY effective_date;

-- ============================================================
-- 6. OceanBase 注意事项与最佳实践
-- ============================================================

-- 1. OceanBase MySQL 模式高度兼容 MySQL 语法，可直接复用 MySQL ETL 脚本
-- 2. OceanBase 也支持 Oracle 模式（兼容 Oracle PL/SQL、MERGE 等）
-- 3. 分布式架构下，建议使用 HASH 分区优化大维度表
--    ALTER TABLE dim_customer PARTITION BY HASH(customer_id) PARTITIONS 16;
-- 4. ON DUPLICATE KEY UPDATE 性能优于 REPLACE INTO（避免 DELETE + INSERT 开销）
-- 5. OceanBase 支持多租户隔离，建议为 ETL 工作负载创建独立租户
-- 6. 使用 OceanBase CDC (LogProxy) 可实现增量抽取，辅助 SCD Type 2
-- 7. is_current 使用 TINYINT(1/0) 而非 BOOLEAN，符合 MySQL 兼容惯例
