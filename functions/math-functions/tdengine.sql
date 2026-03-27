-- TDengine: Math Functions
--
-- 参考资料:
--   [1] TDengine Documentation - Functions
--       https://docs.tdengine.com/reference/sql/function/

-- ============================================================
-- 基本数学函数
-- ============================================================
SELECT ABS(-42);                          -- 42
SELECT CEIL(4.3);                         -- 5
SELECT FLOOR(4.7);                        -- 4
SELECT ROUND(3.14159);                    -- 3            (仅整数舍入)
SELECT MOD(17, 5);                        -- 2
SELECT SQRT(144);                         -- 12
SELECT LOG(EXP(1));                       -- 1.0          (自然对数)
SELECT LOG(100, 10);                      -- 2            (指定底数)

-- ============================================================
-- TDengine 特有时序计算函数
-- ============================================================
-- DERIVATIVE: 计算时间序列的导数（变化率）
-- SELECT DERIVATIVE(value, 1s, 0) FROM meters;
-- 参数: 列名, 时间间隔, 是否忽略负值(0/1)

-- DIFF: 计算相邻行的差值
-- SELECT DIFF(value) FROM meters;
-- SELECT DIFF(value, 1) FROM meters;     -- 忽略负值

-- SPREAD: 计算极差（最大值 - 最小值）
-- SELECT SPREAD(value) FROM meters;

-- IRATE: 计算瞬时变化率
-- SELECT IRATE(value) FROM meters;

-- TWA: 时间加权平均值
-- SELECT TWA(value) FROM meters;

-- ============================================================
-- 聚合数学函数
-- ============================================================
-- SELECT AVG(temperature) FROM meters WHERE ts >= NOW - 1h;
-- SELECT SUM(power_usage) FROM meters GROUP BY device_id;
-- SELECT STDDEV(temperature) FROM meters GROUP BY device_id;
-- SELECT PERCENTILE(temperature, 95) FROM meters;
-- SELECT APERCENTILE(temperature, 95) FROM meters;  -- 近似百分位

-- ============================================================
-- 选择函数
-- ============================================================
-- SELECT MIN(temperature), MAX(temperature) FROM meters;
-- SELECT FIRST(temperature) FROM meters;            -- 最早时间的值
-- SELECT LAST(temperature) FROM meters;             -- 最新时间的值
-- SELECT TOP(temperature, 3) FROM meters;           -- 最大 3 个值
-- SELECT BOTTOM(temperature, 3) FROM meters;        -- 最小 3 个值

-- 注意：TDengine 面向时序数据，标准数学函数有限
-- 注意：提供时序计算特有函数（DERIVATIVE, DIFF, SPREAD, IRATE, TWA）
-- 注意：聚合函数丰富，支持 PERCENTILE, APERCENTILE 等
-- 限制：无三角函数（SIN, COS, TAN 等）
-- 限制：无 POWER, EXP, PI, SIGN 等
-- 限制：无位运算
-- 限制：无 GREATEST/LEAST
