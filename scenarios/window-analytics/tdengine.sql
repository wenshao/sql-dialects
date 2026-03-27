-- TDengine: 窗口函数实战分析
--
-- 参考资料:
--   [1] TDengine Documentation - Window Functions
--       https://docs.taosdata.com/reference/sql/select/#window-clause
--   [2] TDengine Documentation - Aggregate Functions
--       https://docs.taosdata.com/reference/sql/functions/

-- ============================================================
-- TDengine 是时序数据库，窗口模型与传统 SQL 不同
-- TDengine 使用时间窗口（INTERVAL, SLIDING, SESSION, STATE_WINDOW）
-- 不支持传统 OVER() 窗口函数（如 LAG, LEAD, RANK 等）
-- ============================================================

-- 假设超级表:
--   CREATE STABLE metrics (
--       ts TIMESTAMP, value DOUBLE, quality INT
--   ) TAGS (device_id NCHAR(50), region NCHAR(20));

-- ============================================================
-- 1. 移动平均（使用 INTERVAL + SLIDING）
-- ============================================================

-- 每小时平均值
SELECT _wstart, AVG(value) AS hourly_avg
FROM metrics
WHERE ts >= '2024-01-01' AND ts < '2024-02-01'
INTERVAL(1h);

-- 滑动窗口：7 天移动平均（每天滑动一次）
SELECT _wstart, AVG(value) AS ma_7d
FROM metrics
WHERE ts >= '2024-01-01' AND ts < '2024-02-01'
INTERVAL(7d) SLIDING(1d);

-- 30 天移动平均
SELECT _wstart, AVG(value) AS ma_30d
FROM metrics
WHERE ts >= '2024-01-01' AND ts < '2024-07-01'
INTERVAL(30d) SLIDING(1d);

-- 按设备分组的移动平均
SELECT _wstart, device_id, AVG(value) AS ma_7d
FROM metrics
WHERE ts >= '2024-01-01' AND ts < '2024-02-01'
PARTITION BY device_id
INTERVAL(7d) SLIDING(1d);

-- ============================================================
-- 2. 环比（使用 INTERVAL 后自连接）
-- ============================================================

-- 月度聚合
SELECT _wstart AS month_start, SUM(value) AS monthly_total
FROM metrics
WHERE ts >= '2023-01-01' AND ts < '2025-01-01'
INTERVAL(1n);                                   -- 1n = 1 个自然月

-- 日同比需要应用层计算或自连接
-- TDengine 不支持 LAG/LEAD

-- ============================================================
-- 3. 占比（使用子查询）
-- ============================================================

-- TDengine 不支持 OVER() 窗口函数
-- 使用子查询计算占比
SELECT device_id,
       SUM(value) AS device_total,
       SUM(value) * 100.0 / (SELECT SUM(value) FROM metrics
                              WHERE ts >= '2024-01-01' AND ts < '2024-02-01')
           AS pct_of_total
FROM metrics
WHERE ts >= '2024-01-01' AND ts < '2024-02-01'
GROUP BY device_id;

-- ============================================================
-- 4. 百分位数
-- ============================================================

-- TDengine 支持 PERCENTILE 和 APERCENTILE
SELECT device_id,
       PERCENTILE(value, 50) AS median_value,
       PERCENTILE(value, 25) AS p25,
       PERCENTILE(value, 75) AS p75,
       PERCENTILE(value, 90) AS p90,
       PERCENTILE(value, 99) AS p99
FROM metrics
WHERE ts >= '2024-01-01' AND ts < '2024-02-01'
GROUP BY device_id;

-- 近似百分位（大数据集推荐）
SELECT APERCENTILE(value, 50) AS approx_median,
       APERCENTILE(value, 99) AS approx_p99
FROM metrics
WHERE ts >= '2024-01-01' AND ts < '2024-02-01';

-- ============================================================
-- 5. 会话窗口（SESSION）
-- ============================================================

-- TDengine 内建 SESSION 窗口支持
-- 超过指定时间间隔则开始新会话
SELECT _wstart, _wend, _wduration,
       COUNT(*) AS event_count,
       AVG(value) AS avg_value,
       MAX(value) AS max_value
FROM metrics
WHERE ts >= '2024-01-01' AND ts < '2024-02-01'
SESSION(ts, 30m);                               -- 30 分钟间隔
-- _wstart: 会话开始时间
-- _wend: 会话结束时间
-- _wduration: 会话持续时间（毫秒）

-- 按设备的会话化
SELECT _wstart, _wend, device_id,
       COUNT(*) AS event_count,
       _wduration / 1000 AS duration_sec
FROM metrics
WHERE ts >= '2024-01-01' AND ts < '2024-02-01'
PARTITION BY device_id
SESSION(ts, 30m);

-- ============================================================
-- 6. 状态窗口（STATE_WINDOW）
-- ============================================================

-- 按状态分组（连续相同状态值为一组）
SELECT _wstart, _wend, _wduration,
       FIRST(value) AS first_val,
       LAST(value) AS last_val,
       COUNT(*) AS point_count
FROM metrics
WHERE ts >= '2024-01-01' AND ts < '2024-02-01'
STATE_WINDOW(quality);                          -- 按 quality 列的状态变化分组

-- ============================================================
-- 7. FIRST / LAST（TDengine 特有）
-- ============================================================

-- 每个设备的首末值
SELECT device_id,
       FIRST(value) AS first_value,
       FIRST(ts) AS first_time,
       LAST(value) AS last_value,
       LAST(ts) AS last_time
FROM metrics
WHERE ts >= '2024-01-01' AND ts < '2024-02-01'
GROUP BY device_id;

-- 每小时首末值
SELECT _wstart, device_id,
       FIRST(value) AS first_value,
       LAST(value) AS last_value
FROM metrics
WHERE ts >= '2024-01-01' AND ts < '2024-02-01'
PARTITION BY device_id
INTERVAL(1h);

-- ============================================================
-- 8. 差值计算（DIFF / DERIVATIVE）
-- ============================================================

-- DIFF: 相邻行差值（类似 LAG 的效果）
SELECT ts, value,
       DIFF(value) AS value_diff                -- 与前一行的差值
FROM metrics
WHERE device_id = 'device_001' AND ts >= '2024-01-01' AND ts < '2024-02-01';

-- DERIVATIVE: 导数（变化率）
SELECT ts,
       DERIVATIVE(value, 1s) AS rate_per_second  -- 每秒变化率
FROM metrics
WHERE device_id = 'device_001' AND ts >= '2024-01-01' AND ts < '2024-02-01';

-- SPREAD: 最大值与最小值的差
SELECT _wstart,
       SPREAD(value) AS value_range             -- MAX - MIN
FROM metrics
WHERE ts >= '2024-01-01' AND ts < '2024-02-01'
INTERVAL(1h);

-- ============================================================
-- 注意事项
-- ============================================================
-- TDengine 不支持传统 OVER() 窗口函数
-- 不支持 RANK, DENSE_RANK, ROW_NUMBER, NTILE
-- 不支持 LAG, LEAD（使用 DIFF 替代）
-- 不支持 PERCENT_RANK, CUME_DIST
-- TDengine 的窗口模型是时序优化的：
--   INTERVAL: 时间间隔窗口
--   SLIDING: 滑动窗口
--   SESSION: 会话窗口
--   STATE_WINDOW: 状态窗口
-- 使用 PARTITION BY 按标签分组
-- DIFF / DERIVATIVE 是时序数据特有的分析函数
