-- TimescaleDB: 分页
--
-- 参考资料:
--   [1] TimescaleDB API Reference
--       https://docs.timescale.com/api/latest/
--   [2] TimescaleDB Hyperfunctions
--       https://docs.timescale.com/api/latest/hyperfunctions/

-- TimescaleDB 继承 PostgreSQL 全部分页语法

-- LIMIT / OFFSET
SELECT * FROM sensor_data ORDER BY time DESC LIMIT 10 OFFSET 20;

-- 仅 LIMIT
SELECT * FROM sensor_data ORDER BY time DESC LIMIT 10;

-- FETCH FIRST（SQL 标准语法）
SELECT * FROM sensor_data ORDER BY time DESC FETCH FIRST 10 ROWS ONLY;
SELECT * FROM sensor_data ORDER BY time DESC OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- 窗口函数分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY time DESC) AS rn
    FROM sensor_data
) t
WHERE rn BETWEEN 21 AND 30;

-- 游标分页（Keyset Pagination，推荐大数据量使用）
SELECT * FROM sensor_data
WHERE time < '2024-01-15 10:00:00+08'
ORDER BY time DESC
LIMIT 10;

-- 复合游标分页
SELECT * FROM sensor_data
WHERE (time, sensor_id) < ('2024-01-15 10:00:00+08', 5)
ORDER BY time DESC, sensor_id DESC
LIMIT 10;

-- ============================================================
-- 时序分页特有模式
-- ============================================================

-- 按时间范围分页（最适合时序数据）
SELECT * FROM sensor_data
WHERE time >= '2024-01-15' AND time < '2024-01-16'
ORDER BY time
LIMIT 100;

-- time_bucket 分页
SELECT time_bucket('1 hour', time) AS bucket,
       AVG(temperature) AS avg_temp
FROM sensor_data
WHERE time > NOW() - INTERVAL '7 days'
GROUP BY bucket
ORDER BY bucket DESC
LIMIT 24 OFFSET 0;

-- 每个传感器的最新 N 条
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY sensor_id ORDER BY time DESC) AS rn
    FROM sensor_data
) t WHERE rn <= 5;

-- 注意：时序数据建议使用时间范围分页（而非 OFFSET）
-- 注意：游标分页在大数据量下性能远优于 OFFSET
-- 注意：完全兼容 PostgreSQL 的分页语法
-- 注意：FETCH FIRST 是 SQL 标准语法
