-- Apache Doris: 触发器
--
-- 参考资料:
--   [1] Doris Documentation
--       https://doris.apache.org/docs/sql-manual/sql-statements/

-- ============================================================
-- 1. 不支持触发器: OLAP 引擎的设计选择
-- ============================================================
-- Doris 不支持触发器。这与不支持存储过程的原因一致。
--
-- 设计理由:
--   触发器在每行 INSERT/UPDATE/DELETE 时执行——与批量导入冲突。
--   一次 Stream Load 可能写入 1000 万行——每行触发器 = 1000 万次调用。
--   OLAP 引擎的"触发器"等价物是:
--     物化视图(自动刷新) + Routine Load(Kafka 监听) + 外部调度
--
-- 对比:
--   StarRocks: 同样不支持(同源)
--   ClickHouse: 物化视图是 INSERT 触发器(MV 在 INSERT 时触发计算)
--   MySQL:     完整支持(BEFORE/AFTER INSERT/UPDATE/DELETE)
--   PostgreSQL: 最强(支持 INSTEAD OF、事件触发器、条件触发器)

-- ============================================================
-- 2. 替代方案
-- ============================================================

-- 方案一: Routine Load (Kafka 消费 → 类似 CDC 触发器)
-- CREATE ROUTINE LOAD db.my_load ON target_table
-- COLUMNS (id, username, email, action)
-- FROM KAFKA ("kafka_broker_list"="broker:9092", "kafka_topic"="changes");

-- 方案二: Flink CDC (实时同步 → binlog 触发器)
-- Flink CDC 监听上游 MySQL binlog → 实时写入 Doris

-- 方案三: 异步物化视图 (定时刷新 → 定时触发器)
-- CREATE MATERIALIZED VIEW mv_stats
-- REFRESH COMPLETE ON SCHEDULE EVERY 1 HOUR AS
-- SELECT dt, COUNT(*) AS cnt FROM orders GROUP BY dt;

-- 方案四: 外部调度 (Airflow/DolphinScheduler)

-- 方案五: 审计日志
-- Doris 自带审计日志插件，记录所有 SQL 操作:
-- SET GLOBAL audit_log_enabled = true;

-- 对引擎开发者的启示:
--   ClickHouse 的"MV 即触发器"是分析引擎的创新设计:
--     INSERT INTO source → 自动触发 MV 的 INSERT INTO target
--     本质上是管道(Pipeline)而非传统触发器
--     Doris/StarRocks 的同步 MV 类似，但不暴露触发器语义
