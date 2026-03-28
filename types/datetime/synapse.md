# Azure Synapse: 日期时间类型

> 参考资料:
> - [Synapse SQL Features](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)
> - [Synapse T-SQL Differences](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


DATE: 日期，0001-01-01 ~ 9999-12-31
TIME(p): 时间，精度 0~7（默认 7，100 纳秒）
DATETIME2(p): 日期时间，精度 0~7（推荐，替代 DATETIME）
DATETIMEOFFSET(p): 日期时间 + 时区偏移，精度 0~7
DATETIME: 日期时间，精度 3.33 毫秒（旧类型）
SMALLDATETIME: 日期时间，精度 1 分钟（旧类型）

```sql
CREATE TABLE events (
    id           BIGINT IDENTITY(1, 1),
    event_date   DATE,
    event_time   TIME(3),                    -- 毫秒精度
    event_dt     DATETIME2(3),               -- 推荐（毫秒精度）
    event_dto    DATETIMEOFFSET(3),           -- 带时区偏移
    legacy_dt    DATETIME,                   -- 旧类型，避免使用
    legacy_sdt   SMALLDATETIME               -- 旧类型，避免使用
);
```


获取当前时间
```sql
SELECT GETDATE();                            -- DATETIME
SELECT GETUTCDATE();                         -- DATETIME（UTC）
SELECT SYSDATETIME();                        -- DATETIME2
SELECT SYSUTCDATETIME();                     -- DATETIME2（UTC）
SELECT SYSDATETIMEOFFSET();                  -- DATETIMEOFFSET
SELECT CURRENT_TIMESTAMP;                    -- DATETIME
```


构造日期时间
```sql
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS DATETIME2);
SELECT DATEFROMPARTS(2024, 1, 15);
SELECT DATETIME2FROMPARTS(2024, 1, 15, 10, 30, 0, 0, 3);
SELECT DATETIMEOFFSETFROMPARTS(2024, 1, 15, 10, 30, 0, 0, 8, 0, 3);
```


日期加减
```sql
SELECT DATEADD(DAY, 7, '2024-01-15');
SELECT DATEADD(MONTH, 3, GETDATE());
SELECT DATEADD(HOUR, 2, SYSDATETIME());
SELECT DATEADD(MINUTE, 30, SYSDATETIME());
```


日期差
```sql
SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31');      -- 365
SELECT DATEDIFF(MONTH, '2024-01-01', '2024-12-31');    -- 11
SELECT DATEDIFF_BIG(SECOND, '2024-01-01', '2024-12-31'); -- 大值安全
```


提取
```sql
SELECT YEAR(GETDATE());
SELECT MONTH(GETDATE());
SELECT DAY(GETDATE());
SELECT DATEPART(HOUR, SYSDATETIME());
SELECT DATEPART(MINUTE, SYSDATETIME());
SELECT DATEPART(WEEKDAY, GETDATE());         -- 1=周日（取决于 DATEFIRST）
SELECT DATEPART(DAYOFYEAR, GETDATE());
SELECT DATENAME(MONTH, GETDATE());           -- 月份名称
SELECT DATENAME(WEEKDAY, GETDATE());         -- 星期名称
SELECT EOMONTH(GETDATE());                   -- 月末日期
SELECT EOMONTH(GETDATE(), 1);                -- 下月月末
```


格式化
```sql
SELECT FORMAT(SYSDATETIME(), 'yyyy-MM-dd HH:mm:ss');
SELECT FORMAT(SYSDATETIME(), 'dddd, MMMM dd, yyyy');
SELECT CONVERT(NVARCHAR, GETDATE(), 120);    -- YYYY-MM-DD HH:MI:SS
SELECT CONVERT(NVARCHAR, GETDATE(), 101);    -- MM/DD/YYYY
```


解析
```sql
SELECT CAST('2024-01-15' AS DATE);
SELECT TRY_CAST('2024-01-15' AS DATE);       -- 安全转换
SELECT CONVERT(DATETIME2, '2024-01-15 10:30:00');
SELECT TRY_CONVERT(DATETIME2, 'invalid');    -- 返回 NULL
```


截断（没有 DATE_TRUNC，用 DATEADD + DATEDIFF 模拟）
截断到月初
```sql
SELECT DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0);
-- 截断到年初
SELECT DATEADD(YEAR, DATEDIFF(YEAR, 0, GETDATE()), 0);
-- 截断到小时
SELECT DATEADD(HOUR, DATEDIFF(HOUR, 0, SYSDATETIME()), 0);
```


时区转换
```sql
SELECT SWITCHOFFSET(SYSDATETIMEOFFSET(), '+08:00');
SELECT TODATETIMEOFFSET(SYSDATETIME(), '+08:00');
-- AT TIME ZONE（SQL Server 2016+ 语法）
SELECT SYSDATETIME() AT TIME ZONE 'China Standard Time';
SELECT SYSDATETIMEOFFSET() AT TIME ZONE 'Pacific Standard Time';
```


注意：推荐使用 DATETIME2 替代旧的 DATETIME
注意：DATETIME 精度只有 3.33 毫秒，DATETIME2 最高 100 纳秒
注意：Synapse 专用池不支持所有 SQL Server 日期函数
注意：FORMAT 函数在 Synapse 专用池中可能不可用
注意：时区名称使用 Windows 时区名（非 IANA）
注意：DATEDIFF_BIG 用于大值场景（避免溢出）
