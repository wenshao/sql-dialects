-- TDengine: 子查询
--
-- 参考资料:
--   [1] TDengine SQL Reference
--       https://docs.taosdata.com/taos-sql/
--   [2] TDengine Function Reference
--       https://docs.taosdata.com/taos-sql/function/

-- TDengine 支持基本的子查询，但有较多限制

-- ============================================================
-- FROM 子查询（最常用）
-- ============================================================

-- 基本子查询
SELECT * FROM (
    SELECT ts, AVG(current) AS avg_current
    FROM meters
    WHERE ts >= '2024-01-01' AND ts < '2024-02-01'
    INTERVAL(1h)
) WHERE avg_current > 10;

-- 嵌套聚合
SELECT AVG(avg_current) FROM (
    SELECT AVG(current) AS avg_current
    FROM meters
    INTERVAL(1h)
);

-- 按设备分组后再聚合
SELECT MAX(max_temp) FROM (
    SELECT location, MAX(temperature) AS max_temp
    FROM sensors
    GROUP BY location
);

-- ============================================================
-- WHERE 子查询（有限支持）
-- ============================================================

-- IN 子查询
SELECT * FROM d1001
WHERE ts IN (
    SELECT ts FROM d1002 WHERE current > 12
);

-- ============================================================
-- 嵌套时序查询
-- ============================================================

-- 先降采样再过滤
SELECT * FROM (
    SELECT ts, AVG(current) AS avg_val, MAX(voltage) AS max_vol
    FROM d1001
    WHERE ts >= '2024-01-01' AND ts < '2024-02-01'
    INTERVAL(1h)
) WHERE avg_val > 10 AND max_vol > 220;

-- 先聚合再排序
SELECT * FROM (
    SELECT location, AVG(current) AS avg_current, COUNT(*) AS cnt
    FROM meters
    WHERE ts >= '2024-01-01'
    GROUP BY location
) ORDER BY avg_current DESC;

-- ============================================================
-- 不支持的子查询
-- ============================================================

-- 不支持标量子查询
-- SELECT (SELECT MAX(current) FROM d1001) FROM d1002;  -- 不支持

-- 不支持 EXISTS / NOT EXISTS
-- SELECT * FROM d1001 WHERE EXISTS (SELECT 1 FROM d1002);  -- 不支持

-- 不支持关联子查询
-- 不支持 ANY / ALL / SOME

-- 不支持多层嵌套（仅支持一层子查询）
-- SELECT * FROM (SELECT * FROM (SELECT ...));  -- 不支持

-- 注意：TDengine 只支持一层子查询
-- 注意：主要用于先聚合再过滤的场景
-- 注意：不支持标量子查询、EXISTS、关联子查询
-- 注意：子查询中支持 INTERVAL、GROUP BY 等时序操作
-- 注意：复杂子查询建议在应用层实现
