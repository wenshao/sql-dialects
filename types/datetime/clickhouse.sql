-- ClickHouse: 日期时间类型
--
-- 参考资料:
--   [1] ClickHouse - DateTime Data Types
--       https://clickhouse.com/docs/en/sql-reference/data-types/datetime
--   [2] ClickHouse - Date/Time Functions
--       https://clickhouse.com/docs/en/sql-reference/functions/date-time-functions

-- Date: 日期，2 字节，1970-01-01 ~ 2149-06-06
-- Date32: 日期，4 字节，1900-01-01 ~ 2299-12-31（21.9+）
-- DateTime: 日期时间，4 字节，精度秒，1970-01-01 ~ 2106-02-07
-- DateTime64(p[, tz]): 日期时间，8 字节，亚秒精度（18.13+）

CREATE TABLE events (
    id           UInt64,
    event_date   Date,                    -- 存储天数偏移
    full_date    Date32,                  -- 更大范围（21.9+）
    created_at   DateTime,                -- 秒精度
    precise_at   DateTime64(3),           -- 毫秒精度
    nanos_at     DateTime64(9, 'Asia/Shanghai')  -- 纳秒+时区
) ENGINE = MergeTree() ORDER BY event_date;

-- DateTime 可附带时区
CREATE TABLE t (
    ts DateTime('Asia/Shanghai')           -- 存储 UTC，显示转换
) ENGINE = MergeTree() ORDER BY ts;

-- 注意：Date 范围有限（从 1970 开始），需要旧日期用 Date32
-- DateTime 是 Unix 时间戳（秒），不支持 1970 之前
-- DateTime64 精度 p: 0=秒, 3=毫秒, 6=微秒, 9=纳秒

-- 获取当前时间
SELECT now();                              -- DateTime
SELECT now64();                            -- DateTime64
SELECT today();                            -- Date
SELECT yesterday();                        -- Date

-- 构造日期时间
SELECT toDate('2024-01-15');
SELECT toDateTime('2024-01-15 10:30:00');
SELECT toDateTime64('2024-01-15 10:30:00.123', 3);
SELECT makeDate(2024, 1, 15);              -- 22.1+
SELECT makeDateTime(2024, 1, 15, 10, 30, 0);

-- 日期加减
SELECT toDate('2024-01-15') + 7;           -- 加 7 天
SELECT toDate('2024-01-15') + INTERVAL 1 MONTH;
SELECT toDateTime('2024-01-15 10:00:00') + INTERVAL 2 HOUR;
SELECT addDays(toDate('2024-01-15'), 7);
SELECT addMonths(toDate('2024-01-15'), 3);
SELECT addHours(now(), 2);
SELECT subtractDays(now(), 1);

-- 日期差
SELECT dateDiff('day', '2024-01-01', '2024-12-31');   -- 365
SELECT dateDiff('month', '2024-01-01', '2024-12-31'); -- 11
SELECT date_diff('second', ts1, ts2);

-- 提取
SELECT toYear(now());
SELECT toMonth(now());
SELECT toDayOfMonth(now());
SELECT toHour(now());
SELECT toMinute(now());
SELECT toSecond(now());
SELECT toDayOfWeek(now());               -- 1=周一
SELECT toDayOfYear(now());
SELECT toISOWeek(now());

-- 格式化
SELECT formatDateTime(now(), '%Y-%m-%d %H:%M:%S');
SELECT toString(now());

-- 截断
SELECT toStartOfMonth(now());
SELECT toStartOfYear(now());
SELECT toStartOfDay(now());
SELECT toStartOfHour(now());
SELECT toStartOfMinute(now());
SELECT toStartOfWeek(now());              -- 周日开始
SELECT toMonday(now());                   -- 本周一

-- Unix 时间戳
SELECT toUnixTimestamp(now());
SELECT fromUnixTimestamp(1705312800);
SELECT toUnixTimestamp64Milli(now64(3));

-- 注意：ClickHouse 日期函数命名风格独特（toYear, toDayOfWeek 等）
-- 注意：Date 类型占 2 字节，非常紧凑适合分析
-- 注意：没有 INTERVAL 列类型，但支持 INTERVAL 表达式
