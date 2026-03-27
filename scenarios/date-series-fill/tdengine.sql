-- TDengine: 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] TDengine Documentation - INTERVAL/FILL
--       https://docs.taosdata.com/taos-sql/interval/
--   [2] TDengine Documentation - INTERP
--       https://docs.taosdata.com/taos-sql/function/#interp

-- ============================================================
-- 准备数据
-- ============================================================

CREATE STABLE sensors (ts TIMESTAMP, value FLOAT) TAGS (device NCHAR(64));
CREATE TABLE sensor_001 USING sensors TAGS ('dev_001');
INSERT INTO sensor_001 VALUES
    ('2024-01-01 00:00:00', 10.5),
    ('2024-01-01 02:00:00', 11.2),
    ('2024-01-01 05:00:00', 12.1),
    ('2024-01-01 06:00:00', 9.8),
    ('2024-01-01 10:00:00', 13.4);

-- ============================================================
-- 1. INTERVAL + FILL —— TDengine 原生间隙填充
-- ============================================================

-- FILL(NULL) —— 缺失时段填 NULL
SELECT _wstart AS bucket, AVG(value) AS avg_val
FROM sensor_001
WHERE ts BETWEEN '2024-01-01 00:00:00' AND '2024-01-01 12:00:00'
INTERVAL(1h)
FILL(NULL);

-- FILL(VALUE, 0) —— 缺失时段填指定值
SELECT _wstart AS bucket, AVG(value) AS avg_val
FROM sensor_001
WHERE ts BETWEEN '2024-01-01 00:00:00' AND '2024-01-01 12:00:00'
INTERVAL(1h)
FILL(VALUE, 0);

-- ============================================================
-- 2. FILL(PREV) —— 前值填充（Last Observation Carried Forward）
-- ============================================================

SELECT _wstart AS bucket, AVG(value) AS avg_val
FROM sensor_001
WHERE ts BETWEEN '2024-01-01 00:00:00' AND '2024-01-01 12:00:00'
INTERVAL(1h)
FILL(PREV);

-- ============================================================
-- 3. FILL(NEXT) —— 后值填充
-- ============================================================

SELECT _wstart AS bucket, AVG(value) AS avg_val
FROM sensor_001
WHERE ts BETWEEN '2024-01-01 00:00:00' AND '2024-01-01 12:00:00'
INTERVAL(1h)
FILL(NEXT);

-- ============================================================
-- 4. FILL(LINEAR) —— 线性插值
-- ============================================================

SELECT _wstart AS bucket, AVG(value) AS avg_val
FROM sensor_001
WHERE ts BETWEEN '2024-01-01 00:00:00' AND '2024-01-01 12:00:00'
INTERVAL(1h)
FILL(LINEAR);

-- ============================================================
-- 5. INTERP 函数 —— 精确时间点插值
-- ============================================================

SELECT _irowts, INTERP(value) AS interp_val
FROM sensor_001
RANGE('2024-01-01 00:00:00', '2024-01-01 12:00:00')
EVERY(1h)
FILL(LINEAR);

-- INTERP + FILL(PREV)
SELECT _irowts, INTERP(value) AS interp_val
FROM sensor_001
RANGE('2024-01-01 00:00:00', '2024-01-01 12:00:00')
EVERY(1h)
FILL(PREV);

-- ============================================================
-- 6. 按设备分组的间隙填充
-- ============================================================

SELECT _wstart AS bucket, device, AVG(value) AS avg_val
FROM sensors
WHERE ts BETWEEN '2024-01-01 00:00:00' AND '2024-01-01 12:00:00'
PARTITION BY device
INTERVAL(1h)
FILL(PREV);

-- 注意：INTERVAL/FILL 是 TDengine 的核心时序功能
-- 注意：FILL 支持 NULL, PREV, NEXT, LINEAR, VALUE 五种模式
-- 注意：INTERP 用于精确时间点的值插值
-- 注意：TDengine 3.0 使用 PARTITION BY 替代 GROUP BY tags
-- 注意：INTERVAL 必须配合 WHERE 子句中的时间范围使用
