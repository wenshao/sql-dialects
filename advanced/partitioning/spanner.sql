-- Google Cloud Spanner: 表分区策略
--
-- 参考资料:
--   [1] Spanner Documentation - Schema Design
--       https://cloud.google.com/spanner/docs/schema-design
--   [2] Spanner Documentation - Interleaved Tables
--       https://cloud.google.com/spanner/docs/schema-and-data-model#parent-child

-- Spanner 不使用传统分区
-- 使用自动分片（Split）和交错表（Interleaved Tables）

-- ============================================================
-- 自动分片（Split）
-- ============================================================

-- Spanner 按主键范围自动分片
-- 数据量增长时自动拆分，缩减时自动合并

CREATE TABLE orders (
    order_id INT64 NOT NULL, user_id INT64, amount NUMERIC, order_date DATE
) PRIMARY KEY (order_id);

-- 使用 UUID 或分散的键避免热点
-- 不推荐自增主键（导致写入热点）

-- ============================================================
-- 交错表（Interleaved Tables）
-- ============================================================

-- 父表
CREATE TABLE users (
    user_id INT64 NOT NULL, username STRING(100)
) PRIMARY KEY (user_id);

-- 子表（与父表物理共存）
CREATE TABLE user_orders (
    user_id INT64 NOT NULL, order_id INT64 NOT NULL, amount NUMERIC
) PRIMARY KEY (user_id, order_id),
  INTERLEAVE IN PARENT users ON DELETE CASCADE;

-- 交错表的数据与父表物理上存储在一起
-- 极大减少连接查询的跨节点通信

-- ============================================================
-- 分片管理（Spanner 自动处理）
-- ============================================================

-- 查看 Split 信息（通过 Cloud Console 的 Key Visualizer）
-- Spanner 自动管理分片的拆分和合并

-- ============================================================
-- 时间戳排序数据
-- ============================================================

-- 使用降序时间戳减少热点
CREATE TABLE events (
    user_id INT64 NOT NULL,
    event_time TIMESTAMP NOT NULL,
    data STRING(MAX)
) PRIMARY KEY (user_id, event_time DESC);

-- 注意：Spanner 不支持传统分区
-- 注意：数据按主键范围自动分片
-- 注意：交错表（INTERLEAVE IN PARENT）是 Spanner 的核心优化手段
-- 注意：避免单调递增主键以防止写入热点
-- 注意：Spanner 自动管理数据的分片和负载均衡
