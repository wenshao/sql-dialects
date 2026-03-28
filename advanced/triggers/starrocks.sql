-- StarRocks: 触发器
--
-- 参考资料:
--   [1] StarRocks Documentation
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/

-- ============================================================
-- 1. 不支持触发器 (与 Doris 相同)
-- ============================================================
-- 替代方案与 Doris 完全一致。

-- ============================================================
-- 2. 替代方案
-- ============================================================

-- 方案一: Routine Load (Kafka 消费)
-- CREATE ROUTINE LOAD db.my_load ON target_table
-- FROM KAFKA ("kafka_broker_list"="broker:9092", "kafka_topic"="changes");

-- 方案二: Pipe 持续加载 (3.2+，StarRocks 独有)
-- CREATE PIPE my_pipe AS INSERT INTO target
-- SELECT * FROM FILES('path'='s3://bucket/data/');
-- 自动监控新文件 → 类似"文件到达触发器"

-- 方案三: 异步物化视图
-- CREATE MATERIALIZED VIEW mv_stats
-- REFRESH ASYNC EVERY (INTERVAL 1 HOUR) AS
-- SELECT dt, COUNT(*) FROM orders GROUP BY dt;

-- 方案四: Flink CDC (上游 binlog 触发)

-- 方案五: 外部调度 (Airflow)

-- ============================================================
-- 3. StarRocks vs Doris 触发器替代差异
-- ============================================================
-- StarRocks 独有: Pipe 持续加载(3.2+)——自动监控文件变更
-- Doris 独有:     审计日志插件(audit_log)——记录 SQL 操作
--
-- 对引擎开发者的启示:
--   Pipe/Snowpipe 模式是云原生数据加载的趋势:
--     对象存储新文件 → 自动检测 → 自动加载 → 自动去重
--   这比传统触发器更适合 OLAP 场景(批量、异步、容错)。
