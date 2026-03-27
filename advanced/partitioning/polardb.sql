-- PolarDB: 表分区策略
--
-- 参考资料:
--   [1] PolarDB MySQL Documentation
--       https://help.aliyun.com/document_detail/316280.html
--   [2] PolarDB PostgreSQL Documentation
--       https://help.aliyun.com/document_detail/172538.html

-- ============================================================
-- PolarDB MySQL 兼容版
-- ============================================================

CREATE TABLE orders (
    id BIGINT AUTO_INCREMENT, user_id BIGINT,
    amount DECIMAL(10,2), order_date DATE,
    PRIMARY KEY (id, order_date)
) PARTITION BY RANGE (YEAR(order_date)) (
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);

-- 支持 RANGE, LIST, HASH, KEY 分区

-- ============================================================
-- PolarDB PostgreSQL 兼容版
-- ============================================================

-- CREATE TABLE orders (
--     id BIGSERIAL, order_date DATE NOT NULL, amount NUMERIC
-- ) PARTITION BY RANGE (order_date);
--
-- CREATE TABLE orders_2024 PARTITION OF orders
--     FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

-- ============================================================
-- 分区管理（MySQL 兼容）
-- ============================================================

ALTER TABLE orders ADD PARTITION (PARTITION p2026 VALUES LESS THAN (2027));
ALTER TABLE orders DROP PARTITION p2024;

-- 注意：PolarDB 根据兼容模式使用不同的分区语法
-- 注意：MySQL 模式兼容 MySQL 分区功能
-- 注意：PostgreSQL 模式兼容 PostgreSQL 声明式分区
