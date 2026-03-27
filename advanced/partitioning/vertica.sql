-- Vertica: 表分区策略
--
-- 参考资料:
--   [1] Vertica Documentation - Partitioning Tables
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/AdministratorsGuide/Partitions/PartitioningTables.htm

-- ============================================================
-- PARTITION BY
-- ============================================================

CREATE TABLE orders (
    id INT, user_id INT, amount NUMERIC, order_date DATE
) PARTITION BY YEAR(order_date);

CREATE TABLE logs (
    id INT, log_date DATE, message VARCHAR(4000)
) PARTITION BY log_date::DATE
  GROUP BY CALENDAR_HIERARCHY_DAY(log_date::DATE, 2, 2);
-- 自动按日、月、年分层

-- ============================================================
-- 分区管理
-- ============================================================

-- 手动分区组织
SELECT PARTITION_TABLE('public.orders');

-- 清除分区
SELECT PURGE_PARTITION('public.orders', '2023');

-- 移动分区到不同存储
SELECT MOVE_PARTITIONS_TO_TABLE('orders', '2023', '2023', 'orders_archive');

-- ============================================================
-- Projection 排序（替代传统分区）
-- ============================================================

CREATE PROJECTION orders_by_date AS
SELECT * FROM orders ORDER BY order_date, user_id
SEGMENTED BY HASH(user_id) ALL NODES;

-- 注意：Vertica 使用 Projection 和分区结合的方式
-- 注意：PARTITION BY 定义分区键
-- 注意：GROUP BY CALENDAR_HIERARCHY 创建分层分区
-- 注意：Projection 的排序顺序是性能优化的核心
-- 注意：MOVE_PARTITIONS_TO_TABLE 支持分区间数据移动
