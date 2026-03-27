-- TimescaleDB: INSERT
--
-- 参考资料:
--   [1] TimescaleDB API Reference
--       https://docs.timescale.com/api/latest/
--   [2] TimescaleDB Hyperfunctions
--       https://docs.timescale.com/api/latest/hyperfunctions/

-- TimescaleDB 继承 PostgreSQL 全部 INSERT 语法
-- 超级表插入自动路由到对应的 chunk

-- 单行插入
INSERT INTO sensor_data (time, sensor_id, temperature, humidity)
VALUES (NOW(), 1, 23.5, 65.0);

-- 多行插入（批量插入推荐）
INSERT INTO sensor_data (time, sensor_id, temperature, humidity) VALUES
    ('2024-01-15 10:00:00+08', 1, 23.5, 65.0),
    ('2024-01-15 10:01:00+08', 1, 23.6, 64.8),
    ('2024-01-15 10:02:00+08', 2, 22.1, 70.2);

-- 从查询结果插入
INSERT INTO sensor_data_archive (time, sensor_id, temperature, humidity)
SELECT time, sensor_id, temperature, humidity
FROM sensor_data
WHERE time < NOW() - INTERVAL '90 days';

-- RETURNING 子句
INSERT INTO sensor_data (time, sensor_id, temperature)
VALUES (NOW(), 1, 25.0)
RETURNING *;

-- CTE + INSERT
WITH new_readings AS (
    SELECT generate_series(
        NOW() - INTERVAL '1 hour',
        NOW(),
        INTERVAL '1 minute'
    ) AS time
)
INSERT INTO sensor_data (time, sensor_id, temperature)
SELECT time, 1, 20.0 + random() * 10
FROM new_readings;

-- ON CONFLICT（UPSERT）
INSERT INTO sensor_data (time, sensor_id, temperature)
VALUES ('2024-01-15 10:00:00+08', 1, 24.0)
ON CONFLICT (time, sensor_id) DO UPDATE
SET temperature = EXCLUDED.temperature;

-- ON CONFLICT DO NOTHING
INSERT INTO sensor_data (time, sensor_id, temperature)
VALUES ('2024-01-15 10:00:00+08', 1, 24.0)
ON CONFLICT DO NOTHING;

-- COPY 批量加载（性能最佳）
-- COPY sensor_data FROM '/path/to/data.csv' CSV HEADER;

-- 指定时区的时间戳
INSERT INTO sensor_data (time, sensor_id, temperature)
VALUES ('2024-01-15 10:00:00 Asia/Shanghai', 1, 23.5);

-- JSONB 数据
INSERT INTO events (time, event_type, payload)
VALUES (NOW(), 'login', '{"user": "alice", "ip": "192.168.1.1"}'::JSONB);

-- 注意：大批量插入推荐使用 COPY 或批量 INSERT
-- 注意：TimescaleDB 自动将数据路由到正确的 chunk
-- 注意：压缩的 chunk 不能直接 INSERT，需先解压
-- 注意：完全兼容 PostgreSQL 的 INSERT 语法
