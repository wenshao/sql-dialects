-- H2 Database: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] H2 Documentation - MERGE INTO
--       https://h2database.com/html/commands.html#merge_into
--   [2] H2 Documentation - Data Types
--       https://h2database.com/html/datatypes.html
--   [3] H2 Documentation - SELECT subquery in MERGE
--       https://h2database.com/html/commands.html#merge_into

-- ============================================================
-- 1. 维度表结构
-- ============================================================

CREATE TABLE dim_customer (
    customer_key   IDENTITY PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date    DATE NOT NULL DEFAULT DATE '9999-12-31',
    is_current     BOOLEAN NOT NULL DEFAULT TRUE,
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
-- 3. SCD Type 1: MERGE INTO（H2 特有语法）
-- ============================================================

-- H2 的 MERGE INTO ... KEY (...) 语法 (非 SQL:2003 标准)
-- 当 KEY 列匹配时自动执行 UPDATE，否则执行 INSERT
MERGE INTO dim_customer (customer_id, name, city, tier)
KEY (customer_id)
SELECT customer_id, name, city, tier FROM stg_customer;

-- SQL:2003 标准的 MERGE 语法 (H2 2.0+ 支持)
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET name = s.name, city = s.city, tier = s.tier
WHEN NOT MATCHED
    THEN INSERT (customer_id, name, city, tier)
         VALUES (s.customer_id, s.name, s.city, s.tier);

-- ============================================================
-- 4. SCD Type 2: UPDATE + INSERT（保留历史版本）
-- ============================================================

-- 步骤 1: 检测变化并标记当前行为过期
UPDATE dim_customer t
SET    t.expiry_date = CURRENT_DATE - 1, t.is_current = FALSE
WHERE  t.is_current = TRUE
  AND  EXISTS (
    SELECT 1 FROM stg_customer s
    WHERE  s.customer_id = t.customer_id
      AND  (s.name <> t.name OR s.city <> t.city OR s.tier <> t.tier)
);

-- 步骤 2: 插入新版本（变化的 + 新增的）
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, DATE '9999-12-31', TRUE
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d
    WHERE  d.customer_id = s.customer_id AND d.is_current = TRUE
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
-- 6. H2 注意事项与最佳实践
-- ============================================================

-- 1. MERGE ... KEY 语法是 H2 特有的简写形式，适合测试和原型开发
-- 2. H2 2.0+ 支持 SQL:2003 标准 MERGE 语法，推荐在生产环境中使用标准语法
-- 3. H2 的 IDENTITY 类型等价于 BIGINT AUTO_INCREMENT
-- 4. H2 日期运算使用 CURRENT_DATE - 1 而非 INTERVAL 语法（更简洁）
-- 5. 测试框架中 H2 常作为 PostgreSQL/MySQL 的替代
--    注意: MERGE ... KEY 语法在 PostgreSQL/MySQL 中不可用
-- 6. H2 不支持可写 CTE（WITH ... UPDATE ... RETURNING），SCD Type 2 必须分步执行
