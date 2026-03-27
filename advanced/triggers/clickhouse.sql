-- ClickHouse: 触发器
--
-- 参考资料:
--   [1] ClickHouse - Materialized Views (INSERT trigger replacement)
--       https://clickhouse.com/docs/en/sql-reference/statements/create/view#materialized-view
--   [2] ClickHouse - MergeTree Engine Family
--       https://clickhouse.com/docs/en/engines/table-engines/mergetree-family

-- ============================================================
-- 1. ClickHouse 没有传统触发器（为什么）
-- ============================================================

-- ClickHouse 不支持 CREATE TRIGGER。原因:
--
-- (a) 批量写入模型:
--     触发器为逐行操作设计（FOR EACH ROW）。
--     ClickHouse 的 INSERT 是批量的（万-百万行/批次）。
--     逐行触发 = 每批触发百万次 → 写入吞吐量下降几个数量级。
--
-- (b) 不可变 data part:
--     BEFORE/AFTER UPDATE/DELETE 触发器需要就地修改数据。
--     ClickHouse 的 data part 不可变，没有 UPDATE/DELETE 的触发点。
--
-- (c) 异步 merge:
--     后台 merge 是 ClickHouse 的核心操作，但 merge 不应触发触发器。
--     如果 merge 触发触发器，会导致不可预测的副作用。

-- ============================================================
-- 2. 物化视图: ClickHouse 的"INSERT 触发器"
-- ============================================================

-- 物化视图在 INSERT 到基表时自动触发:
-- INSERT INTO raw_events → 物化视图的 SELECT 执行 → 结果写入目标表

CREATE TABLE raw_events (
    timestamp DateTime,
    user_id   UInt64,
    event     String,
    amount    Decimal(10,2)
) ENGINE = MergeTree() ORDER BY timestamp;

-- "触发器" 1: 实时聚合
CREATE MATERIALIZED VIEW mv_hourly_stats
ENGINE = SummingMergeTree() ORDER BY (hour, event)
AS SELECT
    toStartOfHour(timestamp) AS hour,
    event,
    count() AS event_count,
    sum(amount) AS total_amount
FROM raw_events GROUP BY hour, event;

-- "触发器" 2: 数据过滤/清洗
CREATE MATERIALIZED VIEW mv_errors TO error_events
AS SELECT timestamp, user_id, event, amount
FROM raw_events WHERE event LIKE '%error%';

-- "触发器" 3: 数据转发到不同表
CREATE MATERIALIZED VIEW mv_high_value TO vip_events
AS SELECT * FROM raw_events WHERE amount > 10000;

-- 一次 INSERT INTO raw_events 自动触发 3 个"触发器"!
-- 这比传统触发器更强大: 每个"触发器"可以有不同的存储引擎和排序键。

-- ============================================================
-- 3. 引擎特性替代触发器功能
-- ============================================================

-- 3.1 TTL 替代"定时删除触发器"
-- 不需要触发器来清理过期数据:
-- ALTER TABLE logs MODIFY TTL timestamp + INTERVAL 90 DAY DELETE;

-- 3.2 MATERIALIZED 列替代"计算列触发器"
-- 不需要 BEFORE INSERT 触发器来计算派生值:
-- CREATE TABLE events (
--     timestamp DateTime,
--     date Date MATERIALIZED toDate(timestamp),
--     hour UInt8 MATERIALIZED toHour(timestamp)
-- ) ENGINE = MergeTree() ORDER BY timestamp;

-- 3.3 CHECK 约束替代"验证触发器"
-- 不需要 BEFORE INSERT 触发器来验证数据:
-- CREATE TABLE users (
--     age UInt8,
--     CONSTRAINT chk_age CHECK age > 0 AND age < 200
-- ) ENGINE = MergeTree() ORDER BY id;

-- 3.4 ReplacingMergeTree 替代"去重触发器"
-- 不需要 BEFORE INSERT 触发器来检查重复:
-- CREATE TABLE users (...) ENGINE = ReplacingMergeTree(version) ORDER BY id;

-- ============================================================
-- 4. 对比与引擎开发者启示
-- ============================================================
-- ClickHouse 不支持触发器，但通过以下机制覆盖了大部分需求:
--   物化视图 → INSERT 触发器（实时聚合/过滤/转发）
--   TTL → 定时删除触发器
--   MATERIALIZED 列 → 计算列触发器
--   CHECK 约束 → 验证触发器
--   ReplacingMergeTree → 去重触发器
--
-- 对引擎开发者的启示:
--   OLAP 引擎不应该实现传统的 FOR EACH ROW 触发器。
--   物化视图（INSERT 触发的数据管道）是更好的抽象:
--   - 批量处理（一个 INSERT 批次触发一次）
--   - 可以有独立的存储引擎和排序键
--   - 多个物化视图可以从同一基表扇出
--   这本质上是嵌入式流处理引擎（类似 Kafka Streams）。
