-- Snowflake: 日期时间类型
--
-- 参考资料:
--   [1] Snowflake SQL Reference - Date & Time Data Types
--       https://docs.snowflake.com/en/sql-reference/data-types-datetime
--   [2] Snowflake SQL Reference - Date & Time Functions
--       https://docs.snowflake.com/en/sql-reference/functions-date-time

-- DATE: 日期，0001-01-01 ~ 9999-12-31
-- TIME(p): 时间（无日期），精度 0~9，默认 9（纳秒）
-- TIMESTAMP_NTZ(p): 日期时间，无时区（默认的 TIMESTAMP 类型）
-- TIMESTAMP_LTZ(p): 日期时间，本地时区（使用会话时区）
-- TIMESTAMP_TZ(p): 日期时间，带时区偏移
-- TIMESTAMP: 默认为 TIMESTAMP_NTZ（可通过参数修改）

CREATE TABLE events (
    id           INTEGER,
    event_date   DATE,
    event_time   TIME,
    local_dt     TIMESTAMP_NTZ,           -- 无时区
    session_dt   TIMESTAMP_LTZ,           -- 本地时区
    created_at   TIMESTAMP_TZ             -- 带时区偏移
);

-- 三种 TIMESTAMP 区别:
-- TIMESTAMP_NTZ: 不存储时区，存什么取什么（"wall clock time"）
-- TIMESTAMP_LTZ: 存为 UTC，显示时转为会话时区
-- TIMESTAMP_TZ: 存储 UTC 值 + 时区偏移

-- TIMESTAMP 默认类型由参数控制:
-- ALTER SESSION SET TIMESTAMP_TYPE_MAPPING = 'TIMESTAMP_NTZ';  -- 默认

-- 获取当前时间
SELECT CURRENT_DATE();                    -- DATE
SELECT CURRENT_TIME();                    -- TIME
SELECT CURRENT_TIMESTAMP();              -- TIMESTAMP_LTZ
SELECT SYSDATE();                        -- TIMESTAMP_LTZ（真实时间）
SELECT LOCALTIMESTAMP();                 -- TIMESTAMP_NTZ

-- 构造日期时间
SELECT DATE_FROM_PARTS(2024, 1, 15);                          -- DATE
SELECT TIME_FROM_PARTS(10, 30, 0);                            -- TIME
SELECT TIMESTAMP_FROM_PARTS(2024, 1, 15, 10, 30, 0);         -- TIMESTAMP_NTZ
SELECT TIMESTAMP_NTZ_FROM_PARTS(2024, 1, 15, 10, 30, 0);
SELECT TIMESTAMP_TZ_FROM_PARTS(2024, 1, 15, 10, 30, 0, 0, 'Asia/Shanghai');

-- 日期加减
SELECT DATEADD(DAY, 7, '2024-01-15'::DATE);
SELECT DATEADD(MONTH, 3, CURRENT_DATE());
SELECT DATEADD(HOUR, 2, CURRENT_TIMESTAMP());
SELECT TIMESTAMPADD(MINUTE, 30, CURRENT_TIMESTAMP());

-- 日期差
SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31');    -- 365
SELECT DATEDIFF(MONTH, '2024-01-01', '2024-12-31');  -- 11
SELECT TIMESTAMPDIFF(HOUR, ts1, ts2);

-- 提取
SELECT EXTRACT(YEAR FROM CURRENT_DATE());
SELECT YEAR(CURRENT_DATE());              -- 快捷函数
SELECT MONTH(CURRENT_DATE());
SELECT DAY(CURRENT_DATE());
SELECT HOUR(CURRENT_TIMESTAMP());
SELECT DAYOFWEEK(CURRENT_DATE());         -- 0=周日
SELECT DAYOFYEAR(CURRENT_DATE());
SELECT WEEKOFYEAR(CURRENT_DATE());

-- 格式化
SELECT TO_CHAR(CURRENT_TIMESTAMP(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_VARCHAR(CURRENT_DATE(), 'YYYY/MM/DD');

-- 解析
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT TRY_TO_DATE('invalid');            -- 安全解析，失败返回 NULL

-- 截断
SELECT DATE_TRUNC('MONTH', CURRENT_TIMESTAMP());
SELECT DATE_TRUNC('YEAR', CURRENT_DATE());

-- 时区转换
SELECT CONVERT_TIMEZONE('UTC', 'Asia/Shanghai', CURRENT_TIMESTAMP());

-- 注意：三种 TIMESTAMP 类型是 Snowflake 的重要特性
-- 注意：默认 TIMESTAMP 类型可通过 TIMESTAMP_TYPE_MAPPING 参数修改
-- 注意：DATE 不包含时间部分
