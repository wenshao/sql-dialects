-- Vertica: 日期时间类型
--
-- 参考资料:
--   [1] Vertica SQL Reference
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm
--   [2] Vertica Functions
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm

-- DATE: 日期
-- TIME: 时间（不含日期），精度到微秒
-- TIME WITH TIME ZONE / TIMETZ: 带时区的时间
-- TIMESTAMP: 日期时间，精度到微秒
-- TIMESTAMP WITH TIME ZONE / TIMESTAMPTZ: 带时区的日期时间
-- INTERVAL: 时间间隔
-- INTERVAL DAY TO SECOND / INTERVAL YEAR TO MONTH

CREATE TABLE events (
    id         INT,
    event_date DATE,
    event_time TIME,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_tz TIMESTAMPTZ DEFAULT NOW(),
    duration   INTERVAL DAY TO SECOND
);

-- 获取当前时间
SELECT CURRENT_DATE;
SELECT CURRENT_TIME;
SELECT CURRENT_TIMESTAMP;
SELECT NOW();
SELECT LOCALTIME;
SELECT LOCALTIMESTAMP;
SELECT CLOCK_TIMESTAMP();                 -- 实际执行时间
SELECT GETDATE();                        -- Vertica 扩展
SELECT SYSDATE();

-- 构造日期时间
SELECT DATE '2024-01-15';
SELECT TIMESTAMP '2024-01-15 10:30:00';
SELECT TIMESTAMPTZ '2024-01-15 10:30:00+08:00';
SELECT INTERVAL '3 days 4 hours';
SELECT TO_TIMESTAMP('2024-01-15', 'YYYY-MM-DD');
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');

-- 日期加减
SELECT TIMESTAMPADD(DAY, 7, DATE '2024-01-15');
SELECT TIMESTAMPADD(MONTH, 3, CURRENT_DATE);
SELECT TIMESTAMPADD(HOUR, 2, CURRENT_TIMESTAMP);
SELECT ADD_MONTHS(DATE '2024-01-15', 3);
SELECT DATE '2024-01-15' + INTERVAL '7 days';

-- 日期差
SELECT DATEDIFF('day', DATE '2024-01-01', DATE '2024-12-31');    -- 365
SELECT DATEDIFF('month', DATE '2024-01-01', DATE '2024-12-31');  -- 11
SELECT TIMESTAMPDIFF(HOUR, TIMESTAMP '2024-01-01 00:00:00', TIMESTAMP '2024-01-02 12:00:00');
SELECT AGE_IN_MONTHS(DATE '2024-12-31', DATE '2024-01-01');

-- 提取
SELECT EXTRACT(YEAR FROM TIMESTAMP '2024-01-15 10:30:00');
SELECT EXTRACT(MONTH FROM CURRENT_DATE);
SELECT EXTRACT(DOW FROM DATE '2024-01-15');
SELECT EXTRACT(EPOCH FROM NOW());
SELECT DATE_PART('hour', NOW());
SELECT YEAR(DATE '2024-01-15');
SELECT MONTH(DATE '2024-01-15');
SELECT DAY(DATE '2024-01-15');

-- 格式化
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(NOW(), 'Day, DD Month YYYY');

-- 截断
SELECT DATE_TRUNC('month', NOW());
SELECT DATE_TRUNC('year', NOW());
SELECT DATE_TRUNC('hour', NOW());
SELECT TRUNC(NOW()::DATE);               -- 去掉时间部分

-- 时区
SET timezone = 'Asia/Shanghai';
SELECT NOW() AT TIME ZONE 'UTC';
SELECT NOW() AT TIME ZONE 'America/New_York';

-- 时间序列函数（Vertica 特有）
SELECT TS_FIRST_VALUE(value) OVER (ORDER BY ts) FROM sensor_data;
SELECT TS_LAST_VALUE(value) OVER (ORDER BY ts) FROM sensor_data;

-- 生成时间序列（TimeSeries 子句）
-- SELECT ts, value FROM sensor_data
-- TIMESERIES ts AS '1 hour' OVER (ORDER BY event_time);

-- 注意：Vertica 支持丰富的日期时间类型
-- 注意：TIMESTAMPTZ 推荐用于存储时间
-- 注意：Vertica 特有时间序列函数（TS_FIRST_VALUE 等）
-- 注意：TIMESERIES 子句用于时间序列填充
