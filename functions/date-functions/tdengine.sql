-- TDengine: 日期函数

-- 当前时间
SELECT NOW();

-- 时间加减（使用时间偏移语法）
-- ts + 1s, ts - 1m, ts + 1h, ts - 1d

SELECT ts + 1h FROM d1001;
SELECT ts - 1d FROM d1001;

-- TIMETRUNCATE（截断）
SELECT TIMETRUNCATE(ts, 1h) FROM d1001;       -- 截断到小时
SELECT TIMETRUNCATE(ts, 1d) FROM d1001;       -- 截断到天
SELECT TIMETRUNCATE(ts, 1m) FROM d1001;       -- 截断到分钟

-- TIMEDIFF（时间差）
SELECT TIMEDIFF(ts, '2024-01-01 00:00:00') FROM d1001;

-- TO_ISO8601（转 ISO 格式字符串）
SELECT TO_ISO8601(ts) FROM d1001;

-- TO_UNIXTIMESTAMP（字符串转 Unix 时间戳）
SELECT TO_UNIXTIMESTAMP('2024-01-15 10:30:00');

-- TIMEZONE（时区转换，3.0+）
SELECT TIMEZONE(ts, 'Asia/Shanghai') FROM d1001;

-- TODAY（今天 0 点）
SELECT TODAY();

-- ELAPSED（计算相邻行的时间间隔）
SELECT ELAPSED(ts) FROM d1001;                -- 默认微秒
SELECT ELAPSED(ts, 1s) FROM d1001;            -- 以秒为单位
SELECT ELAPSED(ts, 1m) FROM d1001;            -- 以分钟为单位

-- ============================================================
-- INTERVAL 降采样（日期函数的核心用法）
-- ============================================================

SELECT _WSTART, AVG(current) FROM d1001 INTERVAL(1h);
SELECT _WSTART, AVG(current) FROM d1001 INTERVAL(1d);
SELECT _WSTART, _WEND, COUNT(*) FROM d1001 INTERVAL(10m);

-- INTERVAL + FILL
SELECT _WSTART, AVG(current)
FROM d1001
INTERVAL(1h) FILL(LINEAR);

-- 注意：TDengine 日期函数较少但针对时序优化
-- 注意：INTERVAL 是时序降采样的核心
-- 注意：ELAPSED 计算时间间隔在 IoT 场景很有用
-- 注意：时间单位：a(ms), s, m, h, d, w, n(月), y(年)
