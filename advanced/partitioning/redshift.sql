-- Amazon Redshift: 表分区策略
--
-- 参考资料:
--   [1] AWS Documentation - Distribution Styles
--       https://docs.aws.amazon.com/redshift/latest/dg/c_choosing_dist_sort.html
--   [2] AWS Documentation - Sort Keys
--       https://docs.aws.amazon.com/redshift/latest/dg/t_Sorting_data.html

-- Redshift 没有传统分区，使用分布键和排序键

-- ============================================================
-- 分布键（Distribution Key）
-- ============================================================

-- HASH 分布（按列分布到各节点）
CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2), order_date DATE
) DISTSTYLE KEY DISTKEY(user_id)
  SORTKEY(order_date);

-- ALL 分布（复制到每个节点）
CREATE TABLE regions (
    id INT, name VARCHAR(100), code VARCHAR(10)
) DISTSTYLE ALL;

-- EVEN 分布（轮询分布）
CREATE TABLE logs (
    id BIGINT, message VARCHAR(4000), log_date DATE
) DISTSTYLE EVEN SORTKEY(log_date);

-- AUTO 分布（Redshift 自动选择）
CREATE TABLE auto_data (
    id BIGINT, data VARCHAR(1000)
) DISTSTYLE AUTO;

-- ============================================================
-- 排序键（Sort Key）
-- ============================================================

-- 复合排序键
CREATE TABLE events (
    id BIGINT, event_date DATE, event_type VARCHAR(50), data VARCHAR(4000)
) SORTKEY(event_date, event_type);

-- 交错排序键（Interleaved Sort Key）
CREATE TABLE multi_filter (
    id BIGINT, col_a INT, col_b INT, col_c INT
) INTERLEAVED SORTKEY(col_a, col_b, col_c);

-- AUTO 排序键
CREATE TABLE auto_sorted (
    id BIGINT, data VARCHAR(1000), created_at TIMESTAMP
) SORTKEY AUTO;

-- ============================================================
-- 排序键裁剪（类似分区裁剪）
-- ============================================================

-- 排序键上的过滤条件实现 Zone Map 裁剪
SELECT * FROM orders WHERE order_date = '2024-06-15';
-- Redshift 通过 Zone Map（块级 MIN/MAX）跳过不匹配的数据块

-- ============================================================
-- 数据块管理
-- ============================================================

-- VACUUM 重新排序数据
VACUUM SORT ONLY orders;
VACUUM FULL orders;

-- ANALYZE 更新统计信息
ANALYZE orders;

-- 注意：Redshift 没有传统分区，使用分布键和排序键
-- 注意：排序键通过 Zone Map 实现类似分区裁剪的效果
-- 注意：DISTSTYLE KEY 按列的哈希值分布数据到各节点
-- 注意：DISTSTYLE ALL 适合小型维度表
-- 注意：交错排序键（INTERLEAVED）适合多列等概率过滤
-- 注意：VACUUM 重新排序数据以保持排序键的效果
