-- SQL Server: 日期时间类型
--
-- 参考资料:
--   [1] SQL Server T-SQL - Date and Time Types
--       https://learn.microsoft.com/en-us/sql/t-sql/data-types/date-transact-sql
--   [2] SQL Server T-SQL - datetime2
--       https://learn.microsoft.com/en-us/sql/t-sql/data-types/datetime2-transact-sql

-- DATE: 日期，3 字节，0001-01-01 ~ 9999-12-31（2008+）
-- TIME: 时间，3-5 字节，精度可达 100 纳秒（2008+）
-- DATETIME: 日期时间，8 字节，精度 3.33ms，1753-01-01 ~ 9999-12-31
-- DATETIME2: 日期时间，6-8 字节，精度可达 100 纳秒（2008+，推荐）
-- SMALLDATETIME: 日期时间，4 字节，精度 1 分钟
-- DATETIMEOFFSET: 带时区偏移，8-10 字节（2008+）

CREATE TABLE events (
    id         BIGINT NOT NULL IDENTITY(1,1) PRIMARY KEY,
    event_date DATE,                  -- 纯日期
    event_time TIME(3),               -- 毫秒精度
    created_at DATETIME2(6),          -- 微秒精度（推荐替代 DATETIME）
    updated_at DATETIMEOFFSET         -- 带时区
);

-- DATETIME vs DATETIME2:
-- DATETIME: 精度只有 3.33ms，范围从 1753 年
-- DATETIME2: 精度可达 100ns，范围从 0001 年，存储更小
-- 官方推荐使用 DATETIME2

-- 获取当前时间
SELECT GETDATE();                      -- DATETIME
SELECT GETUTCDATE();                   -- UTC DATETIME
SELECT SYSDATETIME();                  -- DATETIME2（更精确，2008+）
SELECT SYSUTCDATETIME();               -- UTC DATETIME2
SELECT SYSDATETIMEOFFSET();            -- DATETIMEOFFSET

-- 日期运算
SELECT DATEADD(DAY, 1, GETDATE());
SELECT DATEADD(HOUR, -2, GETDATE());
SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31');     -- 天数差
-- 2016+: DATEDIFF_BIG（避免 INT 溢出）
SELECT DATEDIFF_BIG(SECOND, '2000-01-01', GETDATE());

-- 格式化
SELECT FORMAT(GETDATE(), 'yyyy-MM-dd HH:mm:ss');       -- 2012+
SELECT CONVERT(VARCHAR, GETDATE(), 120);                -- 传统方式 'YYYY-MM-DD HH:MI:SS'
SELECT CONVERT(VARCHAR(10), GETDATE(), 23);             -- 'YYYY-MM-DD'

-- 提取部分
SELECT YEAR(GETDATE()), MONTH(GETDATE()), DAY(GETDATE());
SELECT DATEPART(HOUR, GETDATE());
SELECT DATENAME(WEEKDAY, GETDATE());                    -- 星期名称

-- 截断到天（无直接函数）
SELECT CAST(GETDATE() AS DATE);
-- 2022+: DATETRUNC
SELECT DATETRUNC(MONTH, GETDATE());
