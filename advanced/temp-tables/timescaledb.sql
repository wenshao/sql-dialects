-- TimescaleDB: 临时表与临时存储
--
-- 参考资料:
--   [1] TimescaleDB 基于 PostgreSQL，临时表语法相同
--       https://www.postgresql.org/docs/current/sql-createtable.html

-- ============================================================
-- CREATE TEMPORARY TABLE（继承自 PostgreSQL）
-- ============================================================

CREATE TEMP TABLE temp_sensor_data (
    time TIMESTAMPTZ, device_id INT, temperature DOUBLE PRECISION
);

CREATE TEMP TABLE temp_stats AS
SELECT device_id, AVG(temperature) AS avg_temp, MAX(temperature) AS max_temp
FROM sensor_data
WHERE time > NOW() - INTERVAL '1 day'
GROUP BY device_id;

-- ON COMMIT 行为
CREATE TEMP TABLE temp_tx (id INT, val NUMERIC)
ON COMMIT DELETE ROWS;

CREATE TEMP TABLE temp_session (id INT, val NUMERIC)
ON COMMIT PRESERVE ROWS;

-- ============================================================
-- UNLOGGED 表
-- ============================================================

CREATE UNLOGGED TABLE staging_sensor_data (
    time TIMESTAMPTZ NOT NULL, device_id INT, value DOUBLE PRECISION
);

-- ============================================================
-- CTE
-- ============================================================

WITH hourly_avg AS (
    SELECT time_bucket('1 hour', time) AS hour,
           device_id, AVG(temperature) AS avg_temp
    FROM sensor_data
    WHERE time > NOW() - INTERVAL '1 day'
    GROUP BY hour, device_id
)
SELECT * FROM hourly_avg WHERE avg_temp > 30;

-- 可写 CTE
WITH old_data AS (
    DELETE FROM sensor_data WHERE time < NOW() - INTERVAL '90 days' RETURNING *
)
INSERT INTO sensor_archive SELECT * FROM old_data;

-- ============================================================
-- 连续聚合（持久化的"临时"计算）
-- ============================================================

CREATE MATERIALIZED VIEW hourly_device_stats
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', time) AS bucket,
       device_id,
       AVG(temperature) AS avg_temp,
       MAX(temperature) AS max_temp
FROM sensor_data
GROUP BY bucket, device_id;

-- 注意：TimescaleDB 基于 PostgreSQL，临时表语法完全相同
-- 注意：连续聚合自动维护时序数据的聚合结果
-- 注意：UNLOGGED 表适合导入的中间数据
-- 注意：可写 CTE 适合数据归档操作
