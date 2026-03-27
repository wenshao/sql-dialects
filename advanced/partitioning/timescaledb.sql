-- TimescaleDB: 表分区策略
--
-- 参考资料:
--   [1] TimescaleDB Documentation - Hypertables
--       https://docs.timescale.com/timescaledb/latest/how-to-guides/hypertables/
--   [2] TimescaleDB Documentation - Chunks
--       https://docs.timescale.com/timescaledb/latest/how-to-guides/hypertables/about-hypertables/

-- ============================================================
-- 超表（Hypertable）—— 自动时间分区
-- ============================================================

-- 创建普通表
CREATE TABLE sensor_data (
    time TIMESTAMPTZ NOT NULL,
    device_id INT NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION
);

-- 转换为超表（自动按时间分区）
SELECT create_hypertable('sensor_data', 'time');

-- 指定 chunk 间隔
SELECT create_hypertable('sensor_data', 'time',
    chunk_time_interval => INTERVAL '1 day');

-- ============================================================
-- 多维分区（空间分区）
-- ============================================================

-- 按时间 + 设备分区
SELECT create_hypertable('sensor_data', 'time',
    partitioning_column => 'device_id',
    number_partitions => 4);

-- ============================================================
-- Chunk 管理
-- ============================================================

-- 查看 chunk 信息
SELECT chunk_name, range_start, range_end, is_compressed
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sensor_data'
ORDER BY range_start DESC;

-- 删除旧 chunk
SELECT drop_chunks('sensor_data', older_than => INTERVAL '90 days');

-- 移动 chunk 到不同表空间
SELECT move_chunk('_timescaledb_internal._hyper_1_1_chunk', 'archive_tablespace');

-- ============================================================
-- 压缩（分区级别）
-- ============================================================

ALTER TABLE sensor_data SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_id',
    timescaledb.compress_orderby = 'time DESC'
);

-- 压缩旧 chunk
SELECT compress_chunk(c.chunk_name)
FROM timescaledb_information.chunks c
WHERE c.hypertable_name = 'sensor_data'
  AND c.range_end < NOW() - INTERVAL '7 days'
  AND NOT c.is_compressed;

-- ============================================================
-- 数据保留策略
-- ============================================================

-- 自动删除旧数据
SELECT add_retention_policy('sensor_data', INTERVAL '90 days');

-- 自动压缩
SELECT add_compression_policy('sensor_data', INTERVAL '7 days');

-- 注意：TimescaleDB 的超表（Hypertable）自动按时间分区
-- 注意：每个 Chunk 是一个独立的 PostgreSQL 表
-- 注意：多维分区可以按时间 + 其他列同时分区
-- 注意：压缩策略按 Chunk 粒度操作
-- 注意：数据保留策略自动清理过期数据
-- 注意：Chunk 间隔是性能调优的关键参数
