-- TDengine: PIVOT / UNPIVOT（有限支持）
--
-- 参考资料:
--   [1] TDengine Documentation - SELECT
--       https://docs.tdengine.com/reference/sql/select/
--   [2] TDengine Documentation - Aggregate Functions
--       https://docs.tdengine.com/reference/sql/function/#aggregate-functions

-- ============================================================
-- 注意：TDengine 是时序数据库，不支持标准 PIVOT / UNPIVOT
-- 提供有限的行转列功能（通过聚合和超级表标签）
-- ============================================================

-- ============================================================
-- PIVOT: 使用超级表标签做隐式 PIVOT
-- ============================================================
-- TDengine 的超级表天然支持按标签分组
-- 每个子表对应一个设备，可将多设备数据按时间对齐

-- 查询多个子表数据（类似 PIVOT）
SELECT
    _wstart AS ts,
    AVG(CASE WHEN tbname = 'd1001' THEN current END) AS d1001_current,
    AVG(CASE WHEN tbname = 'd1002' THEN current END) AS d1002_current,
    AVG(CASE WHEN tbname = 'd1003' THEN current END) AS d1003_current
FROM meters
WHERE ts >= '2024-01-01' AND ts < '2024-02-01'
INTERVAL(1h)
ORDER BY ts;

-- ============================================================
-- PIVOT: 跨标签聚合
-- ============================================================
-- 按地区和时间交叉统计
SELECT
    _wstart AS ts,
    SUM(CASE WHEN location = 'Beijing' THEN current ELSE 0 END) AS beijing,
    SUM(CASE WHEN location = 'Shanghai' THEN current ELSE 0 END) AS shanghai,
    SUM(CASE WHEN location = 'Shenzhen' THEN current ELSE 0 END) AS shenzhen
FROM meters
WHERE ts >= '2024-01-01'
INTERVAL(1d)
ORDER BY ts;

-- ============================================================
-- UNPIVOT: UNION ALL
-- ============================================================
SELECT ts, 'temperature' AS metric, temperature AS value FROM sensor_data
UNION ALL
SELECT ts, 'humidity' AS metric, humidity AS value FROM sensor_data
UNION ALL
SELECT ts, 'pressure' AS metric, pressure AS value FROM sensor_data
ORDER BY ts;

-- ============================================================
-- 注意事项
-- ============================================================
-- TDengine 不支持原生 PIVOT/UNPIVOT 语法
-- 超级表的标签机制可实现部分 PIVOT 需求
-- CASE WHEN + INTERVAL 可做时序数据的行转列
-- UNION ALL 是 UNPIVOT 的唯一方法
-- 动态 PIVOT 需在客户端构建 SQL
-- 时序数据场景下，宽表（多列）比长表（多行）更常见
