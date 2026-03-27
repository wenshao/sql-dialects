-- TDengine: DELETE
--
-- 参考资料:
--   [1] TDengine SQL Reference
--       https://docs.taosdata.com/taos-sql/
--   [2] TDengine Function Reference
--       https://docs.taosdata.com/taos-sql/function/

-- TDengine 3.0+ 支持 DELETE 语句（2.x 不支持）

-- 按时间范围删除
DELETE FROM d1001 WHERE ts < '2024-01-01';
DELETE FROM d1001 WHERE ts BETWEEN '2024-01-01' AND '2024-01-31';

-- 删除超级表中所有子表的数据
DELETE FROM meters WHERE ts < '2024-01-01';

-- 带标签过滤删除
DELETE FROM meters WHERE ts < '2024-01-01' AND location = 'Beijing.Chaoyang';

-- ============================================================
-- 删除子表
-- ============================================================

DROP TABLE d1001;
DROP TABLE IF EXISTS d1001;

-- ============================================================
-- 删除超级表（同时删除所有子表）
-- ============================================================

DROP STABLE meters;
DROP STABLE IF EXISTS meters;

-- ============================================================
-- 删除数据库（删除所有数据）
-- ============================================================

DROP DATABASE power;
DROP DATABASE IF EXISTS power;

-- ============================================================
-- 数据保留（通过数据库 KEEP 参数）
-- ============================================================

-- 创建时设置数据保留
CREATE DATABASE power KEEP 365;   -- 保留 365 天

-- 修改保留时间
ALTER DATABASE power KEEP 730;

-- 超过 KEEP 天数的数据自动删除

-- ============================================================
-- 不支持的 DELETE 操作
-- ============================================================

-- 不支持按非时间列条件删除（仅时间 + 标签）
-- DELETE FROM d1001 WHERE current > 10;  -- 不支持

-- 不支持 TRUNCATE
-- TRUNCATE TABLE d1001;  -- 不支持

-- 不支持关联删除
-- DELETE FROM ... USING ...  -- 不支持

-- 注意：DELETE 只支持按时间范围和标签过滤删除
-- 注意：不支持按数据列条件删除
-- 注意：DROP TABLE 删除整个子表及其数据
-- 注意：数据保留由数据库的 KEEP 参数控制
-- 注意：TDengine 2.x 不支持 DELETE，需要 3.0+
