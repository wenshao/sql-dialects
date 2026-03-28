# Azure Synapse: 日期函数

> 参考资料:
> - [Synapse SQL Features](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)
> - [Synapse T-SQL Differences](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


当前日期时间
```sql
SELECT GETDATE();                                    -- DATETIME
SELECT GETUTCDATE();                                 -- DATETIME（UTC）
SELECT SYSDATETIME();                                -- DATETIME2（高精度）
SELECT SYSUTCDATETIME();                             -- DATETIME2（UTC）
SELECT SYSDATETIMEOFFSET();                          -- DATETIMEOFFSET
SELECT CURRENT_TIMESTAMP;                            -- DATETIME
```


构造日期
```sql
SELECT CAST('2024-01-15' AS DATE);
SELECT DATEFROMPARTS(2024, 1, 15);
SELECT DATETIME2FROMPARTS(2024, 1, 15, 10, 30, 0, 0, 3);
SELECT DATETIMEOFFSETFROMPARTS(2024, 1, 15, 10, 30, 0, 0, 8, 0, 3);
SELECT TIMEFROMPARTS(10, 30, 0, 0, 3);
```


日期加减
```sql
SELECT DATEADD(DAY, 7, '2024-01-15');
SELECT DATEADD(MONTH, 3, GETDATE());
SELECT DATEADD(YEAR, 1, GETDATE());
SELECT DATEADD(HOUR, 2, GETDATE());
SELECT DATEADD(MINUTE, 30, SYSDATETIME());
```


日期差
```sql
SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31');    -- 365
SELECT DATEDIFF(MONTH, '2024-01-01', '2024-12-31');  -- 11
SELECT DATEDIFF(YEAR, '2024-01-01', '2025-12-31');   -- 1
SELECT DATEDIFF_BIG(SECOND, '2000-01-01', GETDATE()); -- 大值安全
```


提取
```sql
SELECT YEAR(GETDATE());
SELECT MONTH(GETDATE());
SELECT DAY(GETDATE());
SELECT DATEPART(HOUR, SYSDATETIME());
SELECT DATEPART(MINUTE, SYSDATETIME());
SELECT DATEPART(SECOND, SYSDATETIME());
SELECT DATEPART(WEEKDAY, GETDATE());                 -- 1=周日（取决于 DATEFIRST）
SELECT DATEPART(DAYOFYEAR, GETDATE());
SELECT DATEPART(WEEK, GETDATE());
SELECT DATEPART(QUARTER, GETDATE());
SELECT DATENAME(MONTH, GETDATE());                   -- 'January' 等
SELECT DATENAME(WEEKDAY, GETDATE());                 -- 'Monday' 等
```


月末
```sql
SELECT EOMONTH(GETDATE());                           -- 当月月末
SELECT EOMONTH(GETDATE(), 1);                        -- 下月月末
SELECT EOMONTH(GETDATE(), -1);                       -- 上月月末
```


格式化
```sql
SELECT CONVERT(NVARCHAR, GETDATE(), 120);            -- YYYY-MM-DD HH:MI:SS
SELECT CONVERT(NVARCHAR, GETDATE(), 101);            -- MM/DD/YYYY
SELECT CONVERT(NVARCHAR, GETDATE(), 103);            -- DD/MM/YYYY
SELECT CONVERT(NVARCHAR, GETDATE(), 112);            -- YYYYMMDD
-- FORMAT 在专用池中可能不可用
```


截断（没有 DATE_TRUNC，用 DATEADD + DATEDIFF）
```sql
SELECT DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0);  -- 月初
SELECT DATEADD(YEAR, DATEDIFF(YEAR, 0, GETDATE()), 0);    -- 年初
SELECT DATEADD(HOUR, DATEDIFF(HOUR, 0, GETDATE()), 0);    -- 整点
SELECT DATEADD(DAY, DATEDIFF(DAY, 0, GETDATE()), 0);      -- 日初
```


时区转换
```sql
SELECT SYSDATETIMEOFFSET() AT TIME ZONE 'China Standard Time';
SELECT SWITCHOFFSET(SYSDATETIMEOFFSET(), '+08:00');
```


日期验证
```sql
SELECT ISDATE('2024-01-15');                          -- 1（有效日期）
SELECT ISDATE('invalid');                             -- 0
```


安全转换
```sql
SELECT TRY_CAST('2024-01-15' AS DATE);
SELECT TRY_CONVERT(DATETIME2, 'invalid');             -- 返回 NULL
```


日期序列（用递归 CTE）
```sql
WITH dates AS (
    SELECT CAST('2024-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM dates WHERE d < '2024-01-31'
)
SELECT d FROM dates
OPTION (MAXRECURSION 365);
```


注意：推荐使用 DATETIME2 替代旧的 DATETIME
注意：没有 DATE_TRUNC，需要 DATEADD + DATEDIFF 模拟
注意：DATEDIFF_BIG 避免 INT 溢出
注意：DATEPART(WEEKDAY, ...) 结果取决于 SET DATEFIRST 设置
注意：时区名称使用 Windows 时区名（不是 IANA）
注意：FORMAT 函数在 Synapse 专用池中可能不可用
