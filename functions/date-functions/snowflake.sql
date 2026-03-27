-- Snowflake: 日期函数
--
-- 参考资料:
--   [1] Snowflake SQL Reference - Date & Time Functions
--       https://docs.snowflake.com/en/sql-reference/functions-date-time
--   [2] Snowflake SQL Reference - Date & Time Types
--       https://docs.snowflake.com/en/sql-reference/data-types-datetime

-- 当前日期时间
SELECT CURRENT_DATE();                                   -- DATE
SELECT CURRENT_TIME();                                   -- TIME
SELECT CURRENT_TIMESTAMP();                             -- TIMESTAMP_LTZ
SELECT SYSDATE();                                       -- 真实当前时间
SELECT LOCALTIMESTAMP();                                -- TIMESTAMP_NTZ
SELECT GETDATE();                                       -- TIMESTAMP_LTZ（别名）

-- 构造
SELECT DATE_FROM_PARTS(2024, 1, 15);                     -- DATE
SELECT TIME_FROM_PARTS(10, 30, 0);                       -- TIME
SELECT TIMESTAMP_FROM_PARTS(2024, 1, 15, 10, 30, 0);    -- TIMESTAMP_NTZ
SELECT TIMESTAMP_NTZ_FROM_PARTS(2024, 1, 15, 10, 30, 0);
SELECT TIMESTAMP_LTZ_FROM_PARTS(2024, 1, 15, 10, 30, 0);
SELECT TIMESTAMP_TZ_FROM_PARTS(2024, 1, 15, 10, 30, 0, 0, 'Asia/Shanghai');
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT TRY_TO_DATE('invalid');                           -- 安全解析

-- 日期加减
SELECT DATEADD(DAY, 7, '2024-01-15'::DATE);
SELECT DATEADD(MONTH, 3, CURRENT_DATE());
SELECT DATEADD(HOUR, 2, CURRENT_TIMESTAMP());
SELECT TIMEADD(MINUTE, 30, CURRENT_TIME());
SELECT TIMESTAMPADD(SECOND, 60, CURRENT_TIMESTAMP());

-- 日期差
SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31');        -- 365
SELECT DATEDIFF(MONTH, '2024-01-01', '2024-12-31');      -- 11
SELECT DATEDIFF(YEAR, '2024-01-01', '2025-06-01');       -- 1
SELECT TIMEDIFF(HOUR, t1, t2);
SELECT TIMESTAMPDIFF(MINUTE, ts1, ts2);

-- 提取
SELECT EXTRACT(YEAR FROM CURRENT_DATE());                -- 2024
SELECT YEAR(CURRENT_DATE());                             -- 快捷函数
SELECT MONTH(CURRENT_DATE());
SELECT DAY(CURRENT_DATE());
SELECT DAYOFMONTH(CURRENT_DATE());
SELECT HOUR(CURRENT_TIMESTAMP());
SELECT MINUTE(CURRENT_TIMESTAMP());
SELECT SECOND(CURRENT_TIMESTAMP());
SELECT DAYOFWEEK(CURRENT_DATE());                        -- 0=周日
SELECT DAYOFWEEKISO(CURRENT_DATE());                     -- 1=周一
SELECT DAYOFYEAR(CURRENT_DATE());
SELECT WEEKOFYEAR(CURRENT_DATE());
SELECT WEEKISO(CURRENT_DATE());                          -- ISO 周数
SELECT QUARTER(CURRENT_DATE());

-- 格式化
SELECT TO_CHAR(CURRENT_TIMESTAMP(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(CURRENT_DATE(), 'YYYY/MM/DD');
SELECT TO_CHAR(CURRENT_TIMESTAMP(), 'DY, MON DD, YYYY');

-- 截断
SELECT DATE_TRUNC('MONTH', CURRENT_TIMESTAMP());
SELECT DATE_TRUNC('YEAR', CURRENT_DATE());
SELECT DATE_TRUNC('HOUR', CURRENT_TIMESTAMP());
SELECT DATE_TRUNC('WEEK', CURRENT_DATE());

-- 最后一天
SELECT LAST_DAY(CURRENT_DATE());                         -- 月最后一天
SELECT LAST_DAY(CURRENT_DATE(), 'YEAR');                 -- 年最后一天

-- 时区转换
SELECT CONVERT_TIMEZONE('UTC', 'Asia/Shanghai', CURRENT_TIMESTAMP());
SELECT CONVERT_TIMEZONE('Asia/Shanghai', CURRENT_TIMESTAMP());  -- 从会话时区转

-- Unix 时间戳
SELECT DATE_PART(EPOCH_SECOND, CURRENT_TIMESTAMP());
SELECT TO_TIMESTAMP(1705312800);                         -- 从 Unix 时间戳

-- 日期序列（使用表生成器）
SELECT seq4() AS idx,
       DATEADD(DAY, seq4(), '2024-01-01'::DATE) AS dt
FROM TABLE(GENERATOR(ROWCOUNT => 31));

-- 注意：快捷函数（YEAR/MONTH/DAY 等）是 Snowflake 特色
-- 注意：DAYOFWEEK 返回 0=周日（可通过 WEEK_START 参数修改）
-- 注意：TO_CHAR 格式符使用 Oracle 风格（YYYY-MM-DD HH24:MI:SS）
