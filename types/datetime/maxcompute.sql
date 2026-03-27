-- MaxCompute (ODPS): 日期时间类型
--
-- 参考资料:
--   [1] MaxCompute SQL - Data Types
--       https://help.aliyun.com/zh/maxcompute/user-guide/data-types-1
--   [2] MaxCompute - Date Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/date-functions

-- DATETIME: 日期时间，精度到毫秒，0000-01-01 ~ 9999-12-31（1.0+）
-- DATE: 日期，0001-01-01 ~ 9999-12-31（2.0+）
-- TIMESTAMP: 日期时间，精度到纳秒（2.0+）

CREATE TABLE events (
    id           BIGINT,
    event_date   DATE,                    -- 2.0+
    created_at   DATETIME,                -- 1.0+ 精度毫秒
    precise_at   TIMESTAMP                -- 2.0+ 精度纳秒
);

-- 注意：1.0 只有 DATETIME 和 STRING 处理时间
-- 2.0 新数据类型需要开启：set odps.sql.type.system.odps2 = true;

-- DATETIME vs TIMESTAMP:
-- DATETIME: 精度到毫秒，范围更广
-- TIMESTAMP: 精度到纳秒，与 Hive 兼容

-- 获取当前时间
SELECT GETDATE();                         -- DATETIME 当前时间
SELECT CURRENT_TIMESTAMP();              -- TIMESTAMP 当前时间

-- 构造日期时间
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS DATETIME);
SELECT TO_DATE('2024-01-15 10:30:00', 'yyyy-mm-dd hh:mi:ss');

-- 日期加减
SELECT DATEADD(DATETIME '2024-01-15 10:00:00', 7, 'dd');      -- 加 7 天
SELECT DATEADD(DATETIME '2024-01-15 10:00:00', 3, 'mm');      -- 加 3 月
SELECT DATEADD(CURRENT_TIMESTAMP(), 2, 'hh');                  -- 加 2 小时

-- 日期差
SELECT DATEDIFF(DATE '2024-12-31', DATE '2024-01-01', 'dd');   -- 365
SELECT DATEDIFF(DATE '2024-12-31', DATE '2024-01-01', 'mm');   -- 11

-- 提取
SELECT YEAR(DATE '2024-01-15');           -- 2024
SELECT MONTH(DATE '2024-01-15');          -- 1
SELECT DAY(DATE '2024-01-15');            -- 15
SELECT HOUR(DATETIME '2024-01-15 10:30:00');
SELECT MINUTE(DATETIME '2024-01-15 10:30:00');
SELECT SECOND(DATETIME '2024-01-15 10:30:00');
SELECT WEEKDAY(DATE '2024-01-15');        -- 周几
SELECT DAYOFYEAR(DATE '2024-01-15');      -- 第几天

-- 格式化
SELECT TO_CHAR(DATETIME '2024-01-15 10:30:00', 'yyyy-mm-dd hh:mi:ss');
SELECT DATE_FORMAT(DATETIME '2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');

-- 截断
SELECT TRUNC(DATETIME '2024-01-15 10:30:00', 'mm');  -- 月初
SELECT TRUNC(DATETIME '2024-01-15 10:30:00', 'dd');  -- 当天零点

-- Unix 时间戳
SELECT UNIX_TIMESTAMP(DATETIME '2024-01-15 10:00:00');
SELECT FROM_UNIXTIME(1705312800);

-- 注意：没有时区支持（所有时间视为本地时间）
-- 注意：DATE 类型不能直接与 DATETIME 比较，需要转换
