-- ClickHouse: 索引
--
-- 参考资料:
--   [1] ClickHouse - Data Skipping Indexes
--       https://clickhouse.com/docs/en/sql-reference/statements/alter/skipping-index
--   [2] ClickHouse - Primary Keys
--       https://clickhouse.com/docs/en/guides/creating-tables#primary-keys

-- ClickHouse 没有传统的 B-tree 索引
-- 使用主键索引（稀疏索引）和数据跳过索引

-- ============================================================
-- 主键索引（稀疏索引 / Primary Key Index）
-- ============================================================

-- MergeTree 的 ORDER BY 定义了主键索引
CREATE TABLE users (
    id         UInt64,
    username   String,
    email      String,
    created_at DateTime
)
ENGINE = MergeTree()
ORDER BY id;                                -- 按 id 排序，自动建立稀疏索引

-- ORDER BY 和 PRIMARY KEY 可以不同
CREATE TABLE orders (
    id         UInt64,
    user_id    UInt64,
    order_date Date
)
ENGINE = MergeTree()
ORDER BY (user_id, order_date)              -- 排序键（决定数据存储顺序）
PRIMARY KEY user_id;                         -- 主键（稀疏索引的前缀）

-- 稀疏索引：每 index_granularity 行（默认 8192）记录一个索引条目
-- 不是每行一个索引条目，因此非常节省空间

-- ============================================================
-- 数据跳过索引（Data Skipping Indexes / Secondary Indexes）
-- ============================================================

-- minmax 索引（记录每个 granule 的最小最大值）
ALTER TABLE users ADD INDEX idx_age age TYPE minmax GRANULARITY 4;

-- set 索引（记录每个 granule 的唯一值集合）
ALTER TABLE users ADD INDEX idx_status status TYPE set(100) GRANULARITY 4;

-- bloom_filter（布隆过滤器，概率性判断值是否存在）
ALTER TABLE users ADD INDEX idx_email email TYPE bloom_filter(0.01) GRANULARITY 4;

-- tokenbf_v1（分词布隆过滤器，用于 LIKE 查询）
ALTER TABLE logs ADD INDEX idx_msg message TYPE tokenbf_v1(10240, 3, 0) GRANULARITY 4;

-- ngrambf_v1（N-gram 布隆过滤器，用于 LIKE '%substring%'）
ALTER TABLE logs ADD INDEX idx_msg_ngram message TYPE ngrambf_v1(4, 10240, 3, 0) GRANULARITY 4;

-- 建表时直接定义跳过索引
CREATE TABLE logs (
    timestamp DateTime,
    level     String,
    message   String,
    INDEX idx_level level TYPE set(10) GRANULARITY 4,
    INDEX idx_msg message TYPE tokenbf_v1(10240, 3, 0) GRANULARITY 4
)
ENGINE = MergeTree()
ORDER BY timestamp;

-- 删除跳过索引
ALTER TABLE users DROP INDEX idx_email;

-- 物化跳过索引（对已有数据生效）
ALTER TABLE users MATERIALIZE INDEX idx_email;
ALTER TABLE users MATERIALIZE INDEX idx_email IN PARTITION '202401';

-- ============================================================
-- 投影（Projection，20.12+）
-- ============================================================
-- 类似物化视图，按不同排序存储数据副本

ALTER TABLE orders ADD PROJECTION orders_by_date (
    SELECT * ORDER BY order_date
);

ALTER TABLE orders MATERIALIZE PROJECTION orders_by_date;

-- 建表时定义
CREATE TABLE orders (
    id         UInt64,
    user_id    UInt64,
    order_date Date,
    amount     Decimal(10,2),
    PROJECTION orders_by_date (SELECT * ORDER BY order_date),
    PROJECTION daily_totals (SELECT order_date, sum(amount) GROUP BY order_date)
)
ENGINE = MergeTree()
ORDER BY (user_id, id);

-- ============================================================
-- 全文索引（实验性，23.1+ inverted，24.1+ 更名为 full_text）
-- ============================================================

-- 倒排索引（24.1+ 使用 full_text，23.x 使用 inverted）
ALTER TABLE docs ADD INDEX idx_content content TYPE full_text GRANULARITY 1;

-- 注意：主键索引是稀疏索引，不保证唯一性
-- 注意：数据跳过索引帮助跳过不相关的 granule，不是定位具体行
-- 注意：GRANULARITY 指定索引覆盖多少个 granule
-- 注意：投影会增加存储空间，但可以显著加速特定查询模式
