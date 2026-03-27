-- StarRocks: 索引
--
-- 参考资料:
--   [1] StarRocks - CREATE INDEX
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/table_bucket_part_index/CREATE_INDEX/
--   [2] StarRocks - Table Design
--       https://docs.starrocks.io/docs/table_design/table_types/

-- StarRocks 支持多种索引类型
-- 前缀索引自动创建，其他索引需要手动创建

-- ============================================================
-- 前缀索引（Prefix Index）—— 自动创建
-- ============================================================

-- StarRocks 自动为排序键（Key 列）创建前缀索引
-- 取前 36 字节的 Key 列作为索引
CREATE TABLE users (
    id       BIGINT NOT NULL,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255)
)
DUPLICATE KEY(id, username)                  -- 前缀索引基于 id, username
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- 注意：VARCHAR 列在前缀索引中只取前 20 字节
-- 建议：将高基数、短字段放在 Key 列前面

-- ============================================================
-- Bitmap 索引（低基数列优化）
-- ============================================================

-- 适合枚举值少的列（如 status, gender, region）
CREATE INDEX idx_status ON users (status) USING BITMAP;

-- 删除
DROP INDEX idx_status ON users;

-- ============================================================
-- Bloom Filter 索引（高基数列等值查询优化）
-- ============================================================

-- 通过表属性设置（不是 CREATE INDEX）
CREATE TABLE users (
    id       BIGINT,
    email    VARCHAR(255)
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
PROPERTIES ("bloom_filter_columns" = "email");

-- 修改 bloom filter 列
ALTER TABLE users SET ("bloom_filter_columns" = "email,username");

-- ============================================================
-- Rollup（预聚合索引 / 物化视图的前身）
-- ============================================================

-- 适合 Aggregate Key 模型，按不同维度预聚合
ALTER TABLE daily_stats ADD ROLLUP rollup_by_date (date, SUM(clicks));

-- 查看 Rollup
SHOW ALTER TABLE ROLLUP;
DESC daily_stats ALL;

-- 删除 Rollup
ALTER TABLE daily_stats DROP ROLLUP rollup_by_date;

-- ============================================================
-- 物化视图（3.0+ 推荐使用，替代 Rollup）
-- ============================================================

CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT order_date, user_id, SUM(amount) AS total
FROM orders
GROUP BY order_date, user_id;

-- 异步物化视图（2.4+）
CREATE MATERIALIZED VIEW mv_stats
REFRESH ASYNC EVERY (INTERVAL 1 HOUR) AS
SELECT dt, COUNT(*) AS cnt FROM orders GROUP BY dt;

-- ============================================================
-- 短键索引（Short Key Index）
-- ============================================================
-- 自动创建，基于排序键列的前缀
-- 每 1024 行记录一条索引
-- 通过属性修改粒度
CREATE TABLE t (id BIGINT, name VARCHAR(64))
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
PROPERTIES ("short_key" = "1");

-- 注意：StarRocks 没有 B-tree / Hash 传统索引
-- 注意：前缀索引自动创建，基于 Key 列
-- 注意：Bitmap 索引适合低基数列（<10000 不同值）
-- 注意：Bloom Filter 适合高基数列的等值查询
-- 注意：3.0+ 推荐物化视图替代 Rollup
