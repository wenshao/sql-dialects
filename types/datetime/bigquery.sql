-- BigQuery: 日期时间类型
--
-- 参考资料:
--   [1] BigQuery SQL Reference - Data Types (Date/Time)
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#date_type
--   [2] BigQuery SQL Reference - Date Functions
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/date_functions

-- DATE: 日期，0001-01-01 ~ 9999-12-31
-- TIME: 时间（无日期），00:00:00 ~ 23:59:59.999999
-- DATETIME: 日期时间（无时区），类似 TIMESTAMP WITHOUT TIME ZONE
-- TIMESTAMP: 日期时间（带时区），存储为 UTC 微秒

CREATE TABLE events (
    id           INT64,
    event_date   DATE,
    event_time   TIME,
    local_dt     DATETIME,                -- 无时区（类似民用时间）
    created_at   TIMESTAMP                -- 带时区（UTC 微秒，推荐）
);

-- DATETIME vs TIMESTAMP:
-- DATETIME: 不含时区信息，表示"日历上的时间"
-- TIMESTAMP: 自动存为 UTC，查询时可转换时区（推荐用于记录事件时间）

-- INTERVAL: 时间间隔（用于日期运算，不能作为列类型）
SELECT DATETIME '2024-01-15' + INTERVAL 1 DAY;
SELECT TIMESTAMP '2024-01-15 10:00:00 UTC' + INTERVAL 3 HOUR;

-- 获取当前时间
SELECT CURRENT_DATE();                    -- DATE（注意：有括号）
SELECT CURRENT_TIME();                    -- TIME
SELECT CURRENT_DATETIME();               -- DATETIME
SELECT CURRENT_TIMESTAMP();              -- TIMESTAMP

-- 构造日期时间
SELECT DATE(2024, 1, 15);                -- DATE
SELECT TIME(10, 30, 0);                  -- TIME
SELECT DATETIME(2024, 1, 15, 10, 30, 0); -- DATETIME
SELECT TIMESTAMP('2024-01-15 10:30:00', 'Asia/Shanghai'); -- TIMESTAMP

-- 日期加减
SELECT DATE_ADD(DATE '2024-01-15', INTERVAL 1 MONTH);
SELECT DATE_SUB(DATE '2024-01-15', INTERVAL 7 DAY);
SELECT DATETIME_ADD(DATETIME '2024-01-15 10:00:00', INTERVAL 2 HOUR);
SELECT TIMESTAMP_ADD(TIMESTAMP '2024-01-15 10:00:00 UTC', INTERVAL 30 MINUTE);

-- 日期差
SELECT DATE_DIFF(DATE '2024-12-31', DATE '2024-01-01', DAY);     -- 365
SELECT DATE_DIFF(DATE '2024-12-31', DATE '2024-01-01', MONTH);   -- 11
SELECT DATETIME_DIFF(dt1, dt2, HOUR);
SELECT TIMESTAMP_DIFF(ts1, ts2, SECOND);

-- 提取
SELECT EXTRACT(YEAR FROM DATE '2024-01-15');
SELECT EXTRACT(MONTH FROM CURRENT_DATE());
SELECT EXTRACT(DAYOFWEEK FROM DATE '2024-01-15');   -- 1=周日
SELECT EXTRACT(DAYOFYEAR FROM DATE '2024-01-15');

-- 截断
SELECT DATE_TRUNC(DATE '2024-01-15', MONTH);        -- 2024-01-01
SELECT DATETIME_TRUNC(CURRENT_DATETIME(), HOUR);
SELECT TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), DAY);

-- 格式化
SELECT FORMAT_DATE('%Y-%m-%d', CURRENT_DATE());
SELECT FORMAT_DATETIME('%Y-%m-%d %H:%M:%S', CURRENT_DATETIME());
SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S %Z', CURRENT_TIMESTAMP());

-- 解析
SELECT PARSE_DATE('%Y-%m-%d', '2024-01-15');
SELECT PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %Z', '2024-01-15 10:00:00 UTC');

-- 时区转换
SELECT TIMESTAMP('2024-01-15 10:00:00', 'Asia/Shanghai');
SELECT DATETIME(TIMESTAMP '2024-01-15 10:00:00 UTC', 'Asia/Shanghai');

-- 注意：DATETIME 和 TIMESTAMP 是不同类型，不能直接比较
-- 注意：所有日期时间函数按类型分组（DATE_*, DATETIME_*, TIMESTAMP_*）
