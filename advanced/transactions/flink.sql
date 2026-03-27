-- Flink SQL: Transactions
--
-- 参考资料:
--   [1] Flink SQL Documentation
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/
--   [2] Flink SQL - Built-in Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/
--   [3] Flink SQL - Data Types
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/

-- Flink SQL does NOT support traditional database transactions
-- As a stream processing engine, Flink has a different consistency model:
-- Exactly-once processing with checkpointing

-- Flink's consistency guarantees:

-- 1. Checkpointing (distributed snapshots)
-- Flink periodically takes consistent snapshots of the entire pipeline state
-- On failure, it restores from the last checkpoint for exactly-once semantics

-- Configuration (via SET or flink-conf.yaml):
-- SET 'execution.checkpointing.interval' = '60s';
-- SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
-- SET 'execution.checkpointing.min-pause' = '30s';
-- SET 'execution.checkpointing.timeout' = '600s';

-- 2. Exactly-once sinks (transactional connectors)

-- JDBC sink with exactly-once (uses XA transactions)
CREATE TABLE jdbc_sink (
    id       BIGINT,
    username STRING,
    total    DECIMAL(10,2),
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/mydb',
    'table-name' = 'results',
    'sink.buffer-flush.interval' = '1s',
    'sink.buffer-flush.max-rows' = '1000'
);
-- JDBC sink with PK automatically uses upsert mode

-- Kafka sink with exactly-once
CREATE TABLE kafka_sink (
    user_id  BIGINT,
    event    STRING,
    ts       TIMESTAMP(3)
) WITH (
    'connector' = 'kafka',
    'topic' = 'output',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json',
    'sink.delivery-guarantee' = 'exactly-once',
    'sink.transactional-id-prefix' = 'flink-txn'
);
-- Requires Kafka transactions enabled on the broker

-- 3. Two-Phase Commit (2PC) protocol
-- Flink uses 2PC with checkpoints for exactly-once sinks:
-- Phase 1: Pre-commit (data buffered, not visible)
-- Phase 2: Commit (on checkpoint completion, data becomes visible)

-- 4. Idempotent sinks (at-least-once + deduplication = exactly-once)
-- JDBC/Elasticsearch sinks with PRIMARY KEY are naturally idempotent
CREATE TABLE es_sink (
    doc_id   STRING,
    content  STRING,
    PRIMARY KEY (doc_id) NOT ENFORCED
) WITH (
    'connector' = 'elasticsearch-7',
    'hosts' = 'http://localhost:9200',
    'index' = 'documents'
);
-- Retries on failure write the same key, achieving effective exactly-once

-- 5. Savepoints (manual consistent snapshots)
-- Savepoints are user-triggered checkpoints for planned operations:
-- flink savepoint <jobId>
-- flink stop --savepointPath <path> <jobId>
-- flink run -s <savepointPath> <job.jar>

-- 6. Batch mode (bounded streams)
-- In batch mode, the job runs to completion
-- Output is committed atomically at job completion
-- SET 'execution.runtime-mode' = 'BATCH';
INSERT INTO output_table
SELECT * FROM batch_source;

-- 7. End-to-end exactly-once pattern
-- Source (Kafka with committed offsets)
--   -> Flink (checkpointed state)
--     -> Sink (transactional commit)

CREATE TABLE source_events (
    event_id   BIGINT,
    user_id    BIGINT,
    event_time TIMESTAMP(3),
    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json',
    'scan.startup.mode' = 'group-offsets',
    'properties.enable.auto.commit' = 'false'
);

-- Processing + exactly-once output
INSERT INTO kafka_sink
SELECT user_id, event_type, event_time
FROM source_events
WHERE event_type = 'purchase';

-- Note: Flink has no BEGIN/COMMIT/ROLLBACK statements
-- Note: Consistency is achieved through checkpointing, not SQL transactions
-- Note: Exactly-once requires: source position tracking + checkpointing + transactional sink
-- Note: Savepoints allow stopping and resuming jobs without data loss
-- Note: JDBC sinks with PK use upsert mode (idempotent writes)
-- Note: Kafka exactly-once requires 'sink.delivery-guarantee' = 'exactly-once'
-- Note: Batch mode commits output atomically at job completion
-- Note: No isolation levels, no row-level locking, no SAVEPOINT SQL statement
