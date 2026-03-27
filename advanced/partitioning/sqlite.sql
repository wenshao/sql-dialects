-- SQLite: 表分区策略
--
-- 参考资料:
--   [1] SQLite Documentation
--       https://www.sqlite.org/docs.html

-- SQLite 不支持表分区
-- 替代方案：

-- ============================================================
-- 手动分表（应用层分区）
-- ============================================================

-- 按时间创建多个表
CREATE TABLE orders_2023 (
    id INTEGER PRIMARY KEY, user_id INTEGER,
    amount REAL, order_date TEXT
);
CREATE TABLE orders_2024 (
    id INTEGER PRIMARY KEY, user_id INTEGER,
    amount REAL, order_date TEXT
);
CREATE TABLE orders_2025 (
    id INTEGER PRIMARY KEY, user_id INTEGER,
    amount REAL, order_date TEXT
);

-- 使用 UNION ALL 查询
SELECT * FROM orders_2024
UNION ALL
SELECT * FROM orders_2025
WHERE order_date >= '2024-06-01';

-- ============================================================
-- 使用视图模拟分区表
-- ============================================================

CREATE VIEW orders AS
SELECT * FROM orders_2023
UNION ALL
SELECT * FROM orders_2024
UNION ALL
SELECT * FROM orders_2025;

-- ============================================================
-- ATTACH DATABASE（文件级分区）
-- ============================================================

-- 按数据库文件分离数据
ATTACH DATABASE 'orders_2024.db' AS db2024;
ATTACH DATABASE 'orders_2025.db' AS db2025;

-- 跨库查询
SELECT * FROM db2024.orders
UNION ALL
SELECT * FROM db2025.orders;

-- ============================================================
-- 索引替代分区裁剪
-- ============================================================

-- 使用复合索引实现类似分区裁剪的效果
CREATE INDEX idx_orders_date ON orders_2024(order_date);

-- 注意：SQLite 不支持表分区
-- 注意：手动分表是最常用的替代方案
-- 注意：ATTACH DATABASE 可以实现文件级的数据分离
-- 注意：视图 + UNION ALL 可以模拟分区表
-- 注意：对于嵌入式使用场景，简单的索引通常就够了
