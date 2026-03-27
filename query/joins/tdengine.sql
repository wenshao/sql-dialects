-- TDengine: JOIN
--
-- 参考资料:
--   [1] TDengine SQL Reference
--       https://docs.taosdata.com/taos-sql/
--   [2] TDengine Function Reference
--       https://docs.taosdata.com/taos-sql/function/

-- TDengine 的 JOIN 支持非常有限
-- 主要支持子表之间的 JOIN

-- ============================================================
-- 子表 JOIN（基于时间戳对齐）
-- ============================================================

-- 两个子表按时间戳 JOIN
SELECT a.ts, a.current, b.current
FROM d1001 a, d1002 b
WHERE a.ts = b.ts;

-- 带条件过滤
SELECT a.ts, a.current AS current_1, b.current AS current_2
FROM d1001 a, d1002 b
WHERE a.ts = b.ts AND a.ts >= '2024-01-01' AND a.ts < '2024-02-01';

-- ============================================================
-- 超级表 JOIN（3.0+）
-- ============================================================

-- 两个超级表 JOIN
SELECT a.ts, a.current, b.temperature
FROM meters a, sensors b
WHERE a.ts = b.ts AND a.location = b.site;

-- 超级表自 JOIN
SELECT a.ts, a.current AS current_1, b.current AS current_2
FROM meters a, meters b
WHERE a.ts = b.ts
    AND a.location = 'Beijing.Chaoyang'
    AND b.location = 'Beijing.Haidian';

-- ============================================================
-- 子查询 JOIN 替代
-- ============================================================

-- 使用子查询代替复杂 JOIN
SELECT ts, current FROM d1001
WHERE ts IN (
    SELECT ts FROM d1002 WHERE current > 12
);

-- ============================================================
-- 不支持的 JOIN
-- ============================================================

-- 不支持 LEFT JOIN / RIGHT JOIN / FULL OUTER JOIN
-- 不支持 CROSS JOIN
-- 不支持 NATURAL JOIN
-- 不支持 LATERAL JOIN
-- 不支持非等值 JOIN（只支持 a.ts = b.ts）
-- 不支持与普通表的 JOIN

-- ============================================================
-- 替代方案
-- ============================================================

-- 使用标签（TAG）过滤代替 JOIN
-- 标签数据在超级表中，无需 JOIN
SELECT AVG(current) FROM meters WHERE location = 'Beijing.Chaoyang';

-- 通过应用层实现 JOIN 逻辑
-- 分别查询两个表，在应用层合并结果

-- 注意：TDengine 的 JOIN 仅支持基于时间戳的等值连接
-- 注意：不支持 LEFT/RIGHT/FULL/CROSS JOIN
-- 注意：标签数据已内嵌在超级表中，减少了 JOIN 需求
-- 注意：3.0 版本改善了 JOIN 支持，但仍然有限
-- 注意：复杂 JOIN 建议在应用层实现
