-- Apache Derby: 表分区策略
--
-- 参考资料:
--   [1] Derby Documentation
--       https://db.apache.org/derby/docs/

-- Derby 不支持表分区
-- 替代方案：

-- ============================================================
-- 手动分表
-- ============================================================

CREATE TABLE orders_2024 (
    id BIGINT NOT NULL, user_id BIGINT, amount DECIMAL(10,2), order_date DATE
);

-- 视图统一查询
CREATE VIEW orders AS
SELECT * FROM orders_2023
UNION ALL
SELECT * FROM orders_2024;

-- ============================================================
-- 索引优化
-- ============================================================

CREATE INDEX idx_date ON orders_2024(order_date);

-- 注意：Derby 不支持表分区
-- 注意：作为嵌入式数据库，通常不需要分区
-- 注意：手动分表和索引是主要的替代方案
