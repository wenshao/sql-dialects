-- TimescaleDB: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] TimescaleDB 基于 PostgreSQL，完全兼容其 JSON 函数
--       https://www.postgresql.org/docs/current/functions-json.html
--   [2] PostgreSQL Documentation - jsonb_array_elements
--       https://www.postgresql.org/docs/current/functions-json.html

-- ============================================================
-- 与 PostgreSQL 完全相同的 JSON 处理方式
-- ============================================================
CREATE TABLE sensor_events (
    ts   TIMESTAMPTZ NOT NULL,
    data JSONB NOT NULL
);
SELECT create_hypertable('sensor_events', 'ts');

-- 提取 JSON 字段
SELECT ts,
       data->>'sensor_id'              AS sensor_id,
       (data->>'temperature')::DOUBLE PRECISION AS temperature
FROM   sensor_events;

-- jsonb_array_elements 展开数组
SELECT ts, reading->>'type' AS reading_type, (reading->>'value')::NUMERIC AS value
FROM   sensor_events,
       LATERAL jsonb_array_elements(data->'readings') AS reading;
