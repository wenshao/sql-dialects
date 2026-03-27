-- SQL Server: 日期函数
--
-- 参考资料:
--   [1] SQL Server T-SQL - Date and Time Functions
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/date-and-time-data-types-and-functions-transact-sql
--   [2] SQL Server T-SQL - DATEADD
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/dateadd-transact-sql

-- 当前日期时间
SELECT GETDATE();                                -- DATETIME
SELECT GETUTCDATE();                             -- UTC DATETIME
SELECT SYSDATETIME();                            -- DATETIME2（更精确，2008+）
SELECT SYSUTCDATETIME();                         -- UTC DATETIME2
SELECT SYSDATETIMEOFFSET();                      -- DATETIMEOFFSET
SELECT CURRENT_TIMESTAMP;                        -- 同 GETDATE()

-- 构造日期（2012+）
SELECT DATEFROMPARTS(2024, 1, 15);               -- 2024-01-15
SELECT TIMEFROMPARTS(10, 30, 0, 0, 0);           -- 10:30:00
SELECT DATETIME2FROMPARTS(2024, 1, 15, 10, 30, 0, 0, 0);
SELECT DATETIMEOFFSETFROMPARTS(2024, 1, 15, 10, 30, 0, 0, 8, 0, 0); -- +08:00
-- 传统方式
SELECT CONVERT(DATE, '2024-01-15');
SELECT CAST('2024-01-15' AS DATE);

-- 日期加减
SELECT DATEADD(DAY, 1, GETDATE());
SELECT DATEADD(MONTH, 3, GETDATE());
SELECT DATEADD(HOUR, -2, GETDATE());
SELECT DATEADD(MINUTE, 30, GETDATE());

-- 日期差
SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31');      -- 365
SELECT DATEDIFF(MONTH, '2024-01-01', '2024-06-15');     -- 5
SELECT DATEDIFF(HOUR, '2024-01-01', '2024-01-02');      -- 24
-- 2016+: DATEDIFF_BIG（避免 INT 溢出）
SELECT DATEDIFF_BIG(SECOND, '2000-01-01', GETDATE());

-- 提取
SELECT YEAR(GETDATE());
SELECT MONTH(GETDATE());
SELECT DAY(GETDATE());
SELECT DATEPART(HOUR, GETDATE());
SELECT DATEPART(MINUTE, GETDATE());
SELECT DATEPART(SECOND, GETDATE());
SELECT DATEPART(WEEKDAY, GETDATE());              -- 取决于 DATEFIRST 设置
SELECT DATEPART(DAYOFYEAR, GETDATE());
SELECT DATEPART(WEEK, GETDATE());
SELECT DATENAME(WEEKDAY, GETDATE());              -- 'Monday'
SELECT DATENAME(MONTH, GETDATE());                -- 'January'

-- 格式化
SELECT FORMAT(GETDATE(), 'yyyy-MM-dd HH:mm:ss');   -- 2012+
SELECT FORMAT(GETDATE(), 'dddd, MMMM dd, yyyy');
SELECT CONVERT(VARCHAR, GETDATE(), 120);            -- ISO 格式
SELECT CONVERT(VARCHAR(10), GETDATE(), 23);         -- yyyy-mm-dd
SELECT CONVERT(VARCHAR, GETDATE(), 108);            -- HH:MI:SS

-- 截断
SELECT CAST(GETDATE() AS DATE);                     -- 去掉时间
-- 2022+: DATETRUNC
SELECT DATETRUNC(MONTH, GETDATE());                 -- 月初
SELECT DATETRUNC(YEAR, GETDATE());                  -- 年初

-- 月末
SELECT EOMONTH(GETDATE());                          -- 2012+
SELECT EOMONTH(GETDATE(), 1);                        -- 下个月月末

-- 2016+: AT TIME ZONE
SELECT GETDATE() AT TIME ZONE 'China Standard Time';
SELECT SYSDATETIMEOFFSET() AT TIME ZONE 'UTC';

-- 判断是否是有效日期
SELECT ISDATE('2024-02-29');                        -- 1
SELECT ISDATE('2024-02-30');                        -- 0
-- 2012+: TRY_CONVERT（转换失败返回 NULL）
SELECT TRY_CONVERT(DATE, '2024-02-30');             -- NULL
