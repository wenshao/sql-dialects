-- BigQuery: 触发器
--
-- 参考资料:
--   [1] BigQuery - Scheduled Queries
--       https://cloud.google.com/bigquery/docs/scheduling-queries
--   [2] BigQuery SQL Reference - DDL
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language

-- BigQuery 不支持触发器
-- 使用以下替代方案实现类似功能

-- ============================================================
-- 替代方案 1: 调度查询（Scheduled Query）
-- ============================================================

-- 通过 BigQuery UI 或 API 创建定时执行的查询
-- 可以定时执行数据清洗、汇总、同步等操作

-- 示例：每天汇总订单数据
-- 在 BigQuery 控制台中设置 Schedule：
-- INSERT INTO daily_summary
-- SELECT
--     CURRENT_DATE() AS date,
--     COUNT(*) AS order_count,
--     SUM(amount) AS total_amount
-- FROM orders
-- WHERE DATE(order_date) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY);

-- ============================================================
-- 替代方案 2: Cloud Functions + Eventarc
-- ============================================================

-- 监听 BigQuery 数据变更事件
-- 使用 Eventarc 触发 Cloud Functions

-- 支持的事件类型：
-- google.cloud.bigquery.v2.JobService.InsertJob（作业完成时）
-- google.cloud.audit.log（审计日志事件）

-- Cloud Function 中可以执行：
-- 1. 数据验证
-- 2. 通知发送
-- 3. 级联更新其他表

-- ============================================================
-- 替代方案 3: BigQuery 变更数据捕获（CDC）
-- ============================================================

-- 使用 Change Data Capture 跟踪表的变更
-- 结合 Datastream 实现实时同步

-- ============================================================
-- 替代方案 4: 物化视图自动更新
-- ============================================================

-- 物化视图会自动增量更新，类似 AFTER INSERT 触发器的聚合逻辑
CREATE MATERIALIZED VIEW mv_daily_stats AS
SELECT
    DATE(order_date) AS order_day,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM orders
GROUP BY order_day;

-- ============================================================
-- 替代方案 5: 使用脚本在 DML 前后执行逻辑
-- ============================================================

BEGIN
    -- "BEFORE" 逻辑：验证数据
    IF (SELECT COUNT(*) FROM new_data WHERE amount < 0) > 0 THEN
        RAISE USING MESSAGE = 'Negative amounts not allowed';
    END IF;

    -- 主要 DML 操作
    INSERT INTO orders SELECT * FROM new_data;

    -- "AFTER" 逻辑：记录审计日志
    INSERT INTO audit_log (action, table_name, row_count, timestamp)
    SELECT 'INSERT', 'orders', COUNT(*), CURRENT_TIMESTAMP()
    FROM new_data;
END;

-- ============================================================
-- 替代方案 6: Pub/Sub + Dataflow
-- ============================================================

-- 使用 Pub/Sub 消息队列 + Dataflow 流处理
-- 实现实时的数据处理管道（类似触发器的实时响应）

-- 注意：BigQuery 不支持数据库级别的触发器
-- 注意：调度查询适合定时任务（分钟/小时/天级别）
-- 注意：Cloud Functions + Eventarc 适合事件驱动的实时响应
-- 注意：物化视图适合自动聚合计算
-- 注意：BigQuery 是分析型数据库，不是 OLTP 数据库
