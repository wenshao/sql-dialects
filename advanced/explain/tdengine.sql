-- TDengine: 执行计划与查询分析
--
-- 参考资料:
--   [1] TDengine Documentation - EXPLAIN
--       https://docs.taosdata.com/taos-sql/explain/
--   [2] TDengine Documentation - Performance
--       https://docs.taosdata.com/operation/optimize/

-- ============================================================
-- EXPLAIN 基本用法（3.0+）
-- ============================================================

EXPLAIN SELECT * FROM meters WHERE ts > '2024-01-01' AND voltage > 220;

-- ============================================================
-- EXPLAIN ANALYZE（实际执行）
-- ============================================================

EXPLAIN ANALYZE SELECT * FROM meters
WHERE ts > NOW() - 1h AND voltage > 220;

-- 输出包含：
-- - 每个操作符的实际执行时间
-- - 扫描的数据块数
-- - 返回的行数

-- ============================================================
-- EXPLAIN VERBOSE
-- ============================================================

EXPLAIN VERBOSE SELECT * FROM meters
WHERE ts > NOW() - 1h AND voltage > 220;

-- ============================================================
-- 执行计划关键操作
-- ============================================================

-- Table Scan        子表扫描
-- STable Scan       超级表扫描
-- Merge             合并（多子表结果合并）
-- Sort              排序
-- Aggregate         聚合
-- Interval          时间窗口聚合
-- Session Window    会话窗口
-- State Window      状态窗口
-- Fill              填充（缺失数据填充）
-- Project           投影
-- Filter            过滤

-- ============================================================
-- 性能诊断
-- ============================================================

-- 查看正在执行的查询
SHOW QUERIES;

-- 终止查询
KILL QUERY query_id;

-- 查看连接信息
SHOW CONNECTIONS;

-- ============================================================
-- 时序数据优化要点
-- ============================================================

-- 1. 时间范围过滤：最重要的优化，减少扫描数据量
SELECT * FROM meters WHERE ts > NOW() - 1h;

-- 2. 子表过滤：通过 tag 过滤减少扫描的子表数
SELECT * FROM meters WHERE location = 'Beijing';

-- 3. 降采样查询：使用 INTERVAL 减少返回数据量
SELECT AVG(voltage), MAX(current)
FROM meters
WHERE ts > NOW() - 24h
INTERVAL(1h);

-- ============================================================
-- 数据库参数调优
-- ============================================================

-- 查看数据库参数
SHOW VARIABLES;

-- 缓存大小（影响查询性能）
-- cache: 数据块缓存大小
-- pages: 每个 vnode 的页面数

-- 注意：EXPLAIN 从 TDengine 3.0 开始支持
-- 注意：超级表（STable）查询会涉及多个子表的并行扫描和合并
-- 注意：时间范围过滤是时序查询最重要的优化
-- 注意：Tag 过滤可以减少需要扫描的子表数量
-- 注意：INTERVAL 窗口聚合是 TDengine 的核心查询模式
-- 注意：TDengine 针对时序数据的写入和查询做了特殊优化
