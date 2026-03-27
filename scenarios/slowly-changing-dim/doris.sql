-- Apache Doris: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Apache Doris Documentation - Unique Key Model
--       https://doris.apache.org/docs/data-table/data-model#unique-model
--   [2] Apache Doris Documentation - INSERT INTO
--       https://doris.apache.org/docs/sql-manual/sql-statements/insert
--   [3] Apache Doris Documentation - UPDATE
--       https://doris.apache.org/docs/sql-manual/sql-statements/update
--   [4] Apache Doris Documentation - Duplicate Key Model
--       https://doris.apache.org/docs/data-table/data-model#duplicate-model

-- ============================================================
-- 1. 维度表结构
-- ============================================================

-- SCD Type 1: Unique Key 模型（自动覆盖旧值）
CREATE TABLE dim_customer (
    customer_id VARCHAR(20) NOT NULL COMMENT '业务键',
    name        VARCHAR(100) COMMENT '客户姓名',
    city        VARCHAR(100) COMMENT '城市',
    tier        VARCHAR(20) COMMENT '等级'
) UNIQUE KEY (customer_id)
DISTRIBUTED BY HASH(customer_id) BUCKETS 4
PROPERTIES (
    "replication_num" = "1"
);

-- SCD Type 2: Duplicate Key 模型（允许多版本记录）
CREATE TABLE dim_customer_scd2 (
    customer_key   BIGINT NOT NULL AUTO_INCREMENT COMMENT '代理键',
    customer_id    VARCHAR(20) NOT NULL COMMENT '业务键',
    name           VARCHAR(100) COMMENT '客户姓名',
    city           VARCHAR(100) COMMENT '城市',
    tier           VARCHAR(20) COMMENT '等级',
    effective_date DATE NOT NULL COMMENT '生效日期',
    expiry_date    DATE NOT NULL COMMENT '失效日期',
    is_current     TINYINT NOT NULL DEFAULT 1 COMMENT '是否当前: 1/0'
) DUPLICATE KEY (customer_key)
DISTRIBUTED BY HASH(customer_id) BUCKETS 4
PROPERTIES (
    "replication_num" = "1"
);

-- 源数据临时表
CREATE TABLE stg_customer (
    customer_id VARCHAR(20),
    name        VARCHAR(100),
    city        VARCHAR(100),
    tier        VARCHAR(20)
) DISTRIBUTED BY HASH(customer_id) BUCKETS 1
PROPERTIES ("replication_num" = "1");

-- ============================================================
-- 2. 插入样本数据
-- ============================================================

INSERT INTO stg_customer (customer_id, name, city, tier) VALUES
    ('C001', 'Alice', 'Shanghai', 'Gold'),
    ('C002', 'Bob', 'Beijing', 'Silver'),
    ('C003', 'Charlie', 'Shenzhen', 'Bronze');

-- ============================================================
-- 3. SCD Type 1: Unique Key 模型（自动覆盖）
-- ============================================================

-- Doris Unique Key 模型会自动保留相同 key 的最新值
-- 多次 INSERT 同一 customer_id 会被合并为最新记录
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer;

-- 也可以使用 Stream Load / Broker Load 批量导入
-- curl --location-trusted -u user:password -T data.csv \
--   http://fe_host:8030/api/db/dim_customer/_stream_load

-- ============================================================
-- 4. SCD Type 2: UPDATE + INSERT（保留历史版本）
-- ============================================================

-- 步骤 1: 标记已变化的记录为过期
UPDATE dim_customer_scd2
SET    expiry_date = DATE_SUB(CURDATE(), INTERVAL 1 DAY),
       is_current  = 0
WHERE  is_current = 1
  AND  customer_id IN (
    SELECT s.customer_id
    FROM   stg_customer s
    JOIN   dim_customer_scd2 d ON s.customer_id = d.customer_id
    WHERE  d.is_current = 1
      AND  (s.name <> d.name OR s.city <> d.city OR s.tier <> d.tier)
);

-- 步骤 2: 插入新版本（变化的 + 新增的）
INSERT INTO dim_customer_scd2 (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURDATE(), '9999-12-31', 1
FROM   stg_customer s
WHERE  EXISTS (
    SELECT 1 FROM dim_customer_scd2 d
    WHERE  d.customer_id = s.customer_id AND d.is_current = 0
      AND  d.expiry_date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
)
   OR NOT EXISTS (
    SELECT 1 FROM dim_customer_scd2 d WHERE d.customer_id = s.customer_id
);

-- ============================================================
-- 5. 验证查询
-- ============================================================

-- 查看当前活跃维度记录
SELECT customer_id, name, city, tier FROM dim_customer
UNION ALL
SELECT customer_id, name, city, tier FROM dim_customer_scd2 WHERE is_current = 1
ORDER BY customer_id;

-- 查看某个客户的历史版本
SELECT customer_key, customer_id, name, city, tier, effective_date, expiry_date
FROM   dim_customer_scd2
WHERE  customer_id = 'C001'
ORDER  BY effective_date;

-- ============================================================
-- 6. Doris 注意事项与最佳实践
-- ============================================================

-- 1. Unique Key 模型天然适合 SCD Type 1: 相同 key 自动保留最新值
-- 2. SCD Type 2 需使用 Duplicate Key 模型（允许多行同 key）
-- 3. Doris 的 UPDATE 操作会产生数据版本，频繁更新会影响 Compaction 性能
-- 4. 大批量数据推荐使用 Stream Load 而非 INSERT INTO
-- 5. DISTRIBUTED BY HASH(customer_id) 确保同一客户的记录在同一 BE 节点
-- 6. Doris 不支持 MERGE 语句，SCD Type 2 必须分步执行
-- 7. 建议定期执行 Cumulative Compaction 优化存储
-- 8. 对于实时更新场景，推荐使用 Doris 2.0+ 的 Partial Update 功能
