-- Apache Flink SQL: Error Handling
--
-- 参考资料:
--   [1] Apache Flink Documentation
--       https://nightlies.apache.org/flink/flink-docs-stable/

-- ============================================================
-- Flink SQL 不支持服务端错误处理
-- ============================================================
-- Flink SQL 是流处理引擎，不支持存储过程或异常处理

-- ============================================================
-- 应用层替代方案: Java/Scala
-- ============================================================
-- try {
--     tEnv.executeSql("INSERT INTO output_table SELECT * FROM input_table");
-- } catch (TableException e) {
--     logger.error("Flink SQL error: " + e.getMessage());
-- }

-- ============================================================
-- Flink 容错机制
-- ============================================================
-- Flink 通过 Checkpoint/Savepoint 实现容错
-- 配置重启策略：
-- SET 'restart-strategy' = 'fixed-delay';
-- SET 'restart-strategy.fixed-delay.attempts' = '3';
-- SET 'restart-strategy.fixed-delay.delay' = '10s';

-- 注意：Flink 的容错通过 Checkpoint 机制实现
-- 注意：应用层错误处理通过 Java/Scala API
-- 限制：无 SQL 级别的错误处理语法
