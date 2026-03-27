-- Flink SQL: 锁机制 (Locking)
--
-- 参考资料:
--   [1] Apache Flink Documentation - Streaming Concepts
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/concepts/overview/
--   [2] Apache Flink Documentation - SQL Statements
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/

-- ============================================================
-- Flink SQL 并发模型概述
-- ============================================================
-- Flink SQL 是流处理引擎的 SQL 接口:
-- 1. 不支持传统的锁机制
-- 2. 数据通过流处理管道持续流入
-- 3. 使用 changelog 语义处理更新
-- 4. 状态管理通过 Flink 的检查点机制实现
-- 5. 不支持事务 (BEGIN/COMMIT)

-- ============================================================
-- 流处理中的并发
-- ============================================================

-- Flink 通过并行度控制并发
-- SET 'parallelism.default' = '4';

-- 每个算子的并行实例独立处理数据分区
-- 不需要传统的锁机制

-- ============================================================
-- Connector 级别的一致性
-- ============================================================

-- Kafka 连接器: exactly-once 语义
CREATE TABLE orders (
    id      BIGINT,
    status  STRING,
    ts      TIMESTAMP(3),
    WATERMARK FOR ts AS ts - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'orders',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json',
    'properties.isolation.level' = 'read_committed'  -- 只读取已提交的消息
);

-- JDBC 连接器: 使用底层数据库的锁机制
CREATE TABLE orders_db (
    id      BIGINT,
    status  STRING
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/mydb',
    'table-name' = 'orders'
);

-- ============================================================
-- Exactly-Once 语义（通过检查点实现）
-- ============================================================

-- Flink 通过 checkpoint 实现 exactly-once
-- SET 'execution.checkpointing.interval' = '60s';
-- SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';

-- 两阶段提交 (2PC) sink 连接器:
-- Kafka, JDBC, Filesystem 等支持 exactly-once 写入

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 不支持 SELECT FOR UPDATE / FOR SHARE
-- 2. 不支持 LOCK TABLE
-- 3. 不支持传统事务
-- 4. 并发通过流处理并行度管理
-- 5. 一致性通过检查点和 exactly-once 语义保证
-- 6. 写入外部系统的一致性取决于 sink 连接器
