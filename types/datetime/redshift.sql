-- Redshift: 日期时间类型
--
-- 参考资料:
--   [1] Redshift SQL Reference
--       https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html
--   [2] Redshift SQL Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html
--   [3] Redshift Data Types
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html

-- DATE: 日期，4713 BC ~ 294276 AD
-- TIMESTAMP: 日期时间（无时区），微秒精度
-- TIMESTAMPTZ: 日期时间（带时区），微秒精度
-- TIME: 时间（无日期），微秒精度
-- TIMETZ: 时间（带时区），微秒精度
-- INTERVAL: 时间间隔（有限支持）

CREATE TABLE events (
    id           BIGINT IDENTITY(1, 1),
    event_date   DATE,
    event_ts     TIMESTAMP,                  -- 无时区
    event_tstz   TIMESTAMPTZ,                -- 带时区
    event_time   TIME,                       -- 时间
    event_timetz TIMETZ                      -- 带时区的时间
);

-- 获取当前时间
SELECT GETDATE();                            -- TIMESTAMP（当前事务时间）
SELECT SYSDATE;                              -- TIMESTAMP（实际执行时间）
SELECT CURRENT_DATE;                         -- DATE
SELECT CURRENT_TIMESTAMP;                    -- TIMESTAMPTZ
SELECT TIMEOFDAY();                          -- 字符串形式的时间

-- 构造日期时间
SELECT DATE '2024-01-15';                    -- DATE 字面量
SELECT TIMESTAMP '2024-01-15 10:30:00';      -- TIMESTAMP 字面量
SELECT '2024-01-15'::DATE;                   -- 类型转换

-- 日期加减
SELECT DATEADD(DAY, 7, '2024-01-15'::DATE);
SELECT DATEADD(MONTH, 3, GETDATE());
SELECT DATEADD(HOUR, 2, GETDATE());
SELECT DATEADD(MINUTE, 30, GETDATE());

-- 也支持 INTERVAL 语法
SELECT GETDATE() + INTERVAL '7 days';
SELECT GETDATE() - INTERVAL '3 months';

-- 日期差
SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31');      -- 365
SELECT DATEDIFF(MONTH, '2024-01-01', '2024-12-31');    -- 11
SELECT DATEDIFF(HOUR, ts1, ts2) FROM events;

-- 提取
SELECT EXTRACT(YEAR FROM GETDATE());
SELECT EXTRACT(MONTH FROM GETDATE());
SELECT EXTRACT(DAY FROM GETDATE());
SELECT EXTRACT(HOUR FROM GETDATE());
SELECT EXTRACT(DOW FROM GETDATE());          -- 0=周日
SELECT EXTRACT(DOY FROM GETDATE());          -- 一年中的第几天
SELECT EXTRACT(EPOCH FROM GETDATE());        -- Unix 时间戳
SELECT DATE_PART('year', GETDATE());         -- 同 EXTRACT

-- 格式化
SELECT TO_CHAR(GETDATE(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(GETDATE(), 'Day, Month DD, YYYY');

-- 解析
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');

-- 截断
SELECT DATE_TRUNC('month', GETDATE());       -- 月初
SELECT DATE_TRUNC('year', GETDATE());        -- 年初
SELECT DATE_TRUNC('hour', GETDATE());        -- 整点

-- 时区转换
SELECT CONVERT_TIMEZONE('UTC', 'Asia/Shanghai', GETDATE());
SELECT CONVERT_TIMEZONE('US/Eastern', GETDATE());

-- LAST_DAY（月末日期）
SELECT LAST_DAY(GETDATE());

-- 月份相关
SELECT MONTHS_BETWEEN('2024-12-31', '2024-01-01');
SELECT ADD_MONTHS('2024-01-15'::DATE, 3);
SELECT NEXT_DAY('2024-01-15'::DATE, 'Monday');

-- 注意：Redshift 的 TIMESTAMP 精度为微秒（6 位小数）
-- 注意：GETDATE() 返回当前事务时间，SYSDATE 返回实际执行时间
-- 注意：TIMESTAMPTZ 在存储时转为 UTC
-- 注意：INTERVAL 支持有限（不支持 YEAR-MONTH 间隔）
-- 注意：时区名称来自 IANA 数据库
