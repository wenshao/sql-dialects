-- ClickHouse: Views
--
-- 参考资料:
--   [1] ClickHouse Documentation - CREATE VIEW
--       https://clickhouse.com/docs/en/sql-reference/statements/create/view
--   [2] ClickHouse Documentation - Materialized View
--       https://clickhouse.com/docs/en/sql-reference/statements/create/view#materialized-view
--   [3] ClickHouse Documentation - LIVE VIEW (Experimental)
--       https://clickhouse.com/docs/en/sql-reference/statements/create/view#live-view

-- ============================================
-- 普通视图 (Normal View)
-- ============================================
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- CREATE OR REPLACE VIEW
CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- IF NOT EXISTS
CREATE VIEW IF NOT EXISTS active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- ============================================
-- 物化视图 (Materialized View)
-- ClickHouse 物化视图是触发器式的：数据插入基表时自动增量更新
-- ============================================

-- 基本物化视图（数据存储在隐式创建的内部表）
CREATE MATERIALIZED VIEW mv_order_summary
ENGINE = SummingMergeTree()
ORDER BY user_id
AS
SELECT user_id, count() AS order_count, sum(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 指定目标表的物化视图
CREATE TABLE order_summary_target (
    user_id    UInt64,
    order_count UInt64,
    total_amount Decimal(18,2)
) ENGINE = SummingMergeTree()
ORDER BY user_id;

CREATE MATERIALIZED VIEW mv_order_summary_to_target
TO order_summary_target
AS
SELECT user_id, count() AS order_count, sum(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 使用 AggregatingMergeTree 的物化视图（更精确的聚合）
CREATE MATERIALIZED VIEW mv_user_stats
ENGINE = AggregatingMergeTree()
ORDER BY user_id
AS
SELECT
    user_id,
    countState() AS order_count,       -- 聚合状态函数
    sumState(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 查询聚合状态需要使用 Merge 函数
-- SELECT user_id, countMerge(order_count), sumMerge(total_amount)
-- FROM mv_user_stats GROUP BY user_id;

-- POPULATE：创建时回填历史数据（注意：期间插入的数据可能丢失）
CREATE MATERIALIZED VIEW mv_backfill
ENGINE = SummingMergeTree()
ORDER BY user_id
POPULATE
AS
SELECT user_id, count() AS cnt
FROM orders
GROUP BY user_id;

-- 物化视图关键特性：
-- 1. 增量更新：只处理新插入的数据
-- 2. 不自动刷新全量数据
-- 3. 一张表可以有多个物化视图
-- 4. 物化视图的引擎可以与基表不同

-- ============================================
-- LIVE VIEW（实验性，22.x+）
-- 类似物化视图但结果缓存在内存中
-- ============================================
-- SET allow_experimental_live_view = 1;
-- CREATE LIVE VIEW lv_user_count AS
-- SELECT count() FROM users;
-- WATCH lv_user_count;    -- 实时订阅变更

-- ============================================
-- 可更新视图
-- ClickHouse 视图不可直接更新
-- ============================================
-- 替代方案：直接操作基表

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP VIEW mv_order_summary;        -- 物化视图也用 DROP VIEW

-- 注意：ClickHouse 不支持 WITH CHECK OPTION
-- 注意：物化视图删除后，其内部存储表也会被删除（除非使用 TO 语法指向外部表）
-- 注意：物化视图不支持 ALTER VIEW，需要 DROP + CREATE
