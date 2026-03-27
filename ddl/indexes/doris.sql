-- Apache Doris: 索引
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- Doris 支持多种索引类型
-- 前缀索引自动创建，其他索引需要手动创建

-- ============================================================
-- 前缀索引（Prefix Index）—— 自动创建
-- ============================================================

-- Doris 自动为排序键（Key 列）创建前缀索引
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
-- Bloom Filter 索引（高基数列等值查询优化）
-- ============================================================

-- 通过表属性设置
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
-- Bitmap 索引（低基数列优化）
-- ============================================================

-- 适合枚举值少的列（如 status, gender, region）
CREATE INDEX idx_status ON users (status) USING BITMAP;

-- 删除
DROP INDEX idx_status ON users;

-- ============================================================
-- 倒排索引（Inverted Index，2.0+）
-- ============================================================

-- 适合全文检索和等值查询
CREATE INDEX idx_bio ON users (bio) USING INVERTED;

-- 带分词器的倒排索引
CREATE INDEX idx_bio_cn ON users (bio) USING INVERTED
    PROPERTIES ("parser" = "chinese");

-- 英文分词
CREATE INDEX idx_bio_en ON users (bio) USING INVERTED
    PROPERTIES ("parser" = "english");

-- 建表时指定倒排索引
CREATE TABLE articles (
    id      BIGINT NOT NULL,
    title   VARCHAR(256),
    content STRING,
    INDEX idx_title (title) USING INVERTED,
    INDEX idx_content (content) USING INVERTED PROPERTIES ("parser" = "chinese")
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- ============================================================
-- N-Gram Bloom Filter 索引（2.0+，LIKE 查询优化）
-- ============================================================

CREATE INDEX idx_email_ngram ON users (email) USING NGRAM_BF
    PROPERTIES ("gram_size" = "3");

-- ============================================================
-- Rollup（预聚合索引）
-- ============================================================

-- 适合 Aggregate Key 模型，按不同维度预聚合
ALTER TABLE daily_stats ADD ROLLUP rollup_by_date (date, clicks);

-- 查看 Rollup
SHOW ALTER TABLE ROLLUP;
DESC daily_stats ALL;

-- 删除 Rollup
ALTER TABLE daily_stats DROP ROLLUP rollup_by_date;

-- ============================================================
-- 物化视图
-- ============================================================

CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT order_date, user_id, SUM(amount) AS total
FROM orders
GROUP BY order_date, user_id;

-- 异步物化视图（2.1+）
CREATE MATERIALIZED VIEW mv_stats
REFRESH COMPLETE ON SCHEDULE EVERY 1 HOUR AS
SELECT dt, COUNT(*) AS cnt FROM orders GROUP BY dt;

-- 注意：Doris 没有 B-tree / Hash 传统索引
-- 注意：前缀索引自动创建，基于 Key 列
-- 注意：Bitmap 索引适合低基数列（<10000 不同值）
-- 注意：Bloom Filter 适合高基数列的等值查询
-- 注意：倒排索引是 2.0+ 新增，功能强大
