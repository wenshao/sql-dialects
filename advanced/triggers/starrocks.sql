-- StarRocks: 触发器
--
-- 参考资料:
--   [1] StarRocks SQL Reference
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/
--   [2] StarRocks Documentation
--       https://docs.starrocks.io/docs/

-- StarRocks 不支持触发器
-- 使用以下替代方案实现类似功能

-- ============================================================
-- 替代方案 1: 物化视图（最接近触发器的功能）
-- ============================================================

-- 同步物化视图（自动维护，类似 AFTER INSERT 触发器）
CREATE MATERIALIZED VIEW mv_user_order_stats AS
SELECT
    user_id,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount,
    MAX(order_date) AS last_order_date
FROM orders
GROUP BY user_id;

-- 查询 orders 时优化器可能自动使用物化视图

-- ============================================================
-- 替代方案 2: 异步物化视图（2.4+）
-- ============================================================

-- 定时自动刷新（类似定时触发器）
CREATE MATERIALIZED VIEW mv_daily_report
REFRESH ASYNC EVERY (INTERVAL 1 HOUR)
AS
SELECT
    order_date,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount,
    AVG(amount) AS avg_amount
FROM orders
GROUP BY order_date;

-- 手动刷新
REFRESH MATERIALIZED VIEW mv_daily_report;

-- 条件刷新（基于分区变更）
CREATE MATERIALIZED VIEW mv_orders_by_day
REFRESH ASYNC
PARTITION BY order_date
AS
SELECT order_date, user_id, SUM(amount) AS total
FROM orders
GROUP BY order_date, user_id;

-- ============================================================
-- 替代方案 3: Routine Load（自动数据加载）
-- ============================================================

-- 从 Kafka 自动加载数据（类似 INSERT 触发器的数据处理管道）
CREATE ROUTINE LOAD load_orders ON orders
COLUMNS (id, user_id, amount, order_date),
COLUMNS TERMINATED BY ','
PROPERTIES (
    "desired_concurrent_number" = "3",
    "max_error_number" = "100"
)
FROM KAFKA (
    "kafka_broker_list" = "kafka:9092",
    "kafka_topic" = "orders",
    "property.group.id" = "starrocks_group"
);

-- 查看加载状态
SHOW ROUTINE LOAD FOR load_orders;

-- 暂停/恢复
PAUSE ROUTINE LOAD FOR load_orders;
RESUME ROUTINE LOAD FOR load_orders;

-- ============================================================
-- 替代方案 4: Stream Load + 外部编排
-- ============================================================

-- 使用外部系统（如 Flink、Spark Streaming）处理数据
-- 然后通过 Stream Load 写入 StarRocks

-- curl --location-trusted -u user:pass \
--   -T data.csv \
--   -H "columns: id,user_id,amount" \
--   http://fe_host:8030/api/mydb/orders/_stream_load

-- ============================================================
-- 替代方案 5: INSERT INTO ... SELECT（ETL 管道）
-- ============================================================

-- 在主 DML 操作后手动执行聚合更新
-- 通常通过外部调度工具编排

-- 步骤 1: 加载新数据
INSERT INTO orders VALUES (...);

-- 步骤 2: 更新汇总表（手动"触发器"）
INSERT INTO user_summary
SELECT user_id, COUNT(*), SUM(amount)
FROM orders
WHERE order_date = CURDATE()
GROUP BY user_id;

-- ============================================================
-- 替代方案 6: Primary Key 模型的 Partial Update（3.0+）
-- ============================================================

-- Primary Key 模型支持部分列更新
-- 可以在 Stream Load 中实现"更新时自动维护某些列"

-- 注意：StarRocks 不支持行级触发器
-- 注意：同步物化视图是最接近触发器的功能
-- 注意：异步物化视图适合定时汇总场景
-- 注意：Routine Load 实现了自动化的数据摄入管道
-- 注意：复杂的触发器逻辑需要通过外部编排工具实现
