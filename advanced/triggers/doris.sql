-- Apache Doris: 触发器
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- Doris 不支持触发器

-- ============================================================
-- 替代方案
-- ============================================================

-- 方案一：使用 Routine Load 监听数据变更
-- Routine Load 从 Kafka 持续消费数据
-- 上游系统将变更事件发送到 Kafka，Doris 自动消费

-- CREATE ROUTINE LOAD db.my_load ON target_table
-- COLUMNS (id, username, email, action)
-- FROM KAFKA (
--     "kafka_broker_list" = "broker:9092",
--     "kafka_topic" = "change_events"
-- );

-- 方案二：使用 Flink CDC 实时同步
-- Flink CDC 监听上游数据库的 binlog
-- 实时将变更同步到 Doris

-- 方案三：在应用层实现触发器逻辑
-- 在应用代码中，数据变更前后执行相应的逻辑

-- 方案四：使用物化视图自动刷新
-- 2.1+ 异步物化视图支持定时/事件驱动刷新
-- CREATE MATERIALIZED VIEW mv_stats
-- REFRESH COMPLETE ON SCHEDULE EVERY 1 HOUR AS
-- SELECT dt, COUNT(*) AS cnt FROM orders GROUP BY dt;

-- 方案五：使用调度工具定期执行 SQL
-- Apache Airflow / DolphinScheduler
-- 定时执行数据清洗、聚合等任务

-- 审计日志替代方案
-- Doris 自带审计日志功能
-- 通过 audit_log 插件记录所有 SQL 操作
-- SET GLOBAL audit_log_enabled = true;

-- 注意：Doris 不支持触发器
-- 注意：分析型数据库通常不需要触发器（ETL 流程替代）
-- 注意：推荐使用 Flink CDC / Routine Load 实现实时数据同步
-- 注意：物化视图可以替代部分触发器场景
