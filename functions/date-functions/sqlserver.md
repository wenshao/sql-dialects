# SQL Server: 日期函数

> 参考资料:
> - [SQL Server T-SQL - Date and Time Functions](https://learn.microsoft.com/en-us/sql/t-sql/functions/date-and-time-data-types-and-functions-transact-sql)

## 获取当前时间（多种精度和类型）

```sql
SELECT GETDATE();              -- DATETIME（精度 3.33ms，最常用）
SELECT GETUTCDATE();           -- UTC DATETIME
SELECT SYSDATETIME();          -- DATETIME2（精度 100ns，2008+，推荐）
SELECT SYSUTCDATETIME();       -- UTC DATETIME2
SELECT SYSDATETIMEOFFSET();    -- DATETIMEOFFSET（带时区偏移）
SELECT CURRENT_TIMESTAMP;      -- SQL 标准，等同 GETDATE()

-- 设计分析（对引擎开发者）:
--   SQL Server 有 6 种获取当前时间的方式——这是历史演进的结果。
--   GETDATE() 是最早的（SQL Server 6.0），返回精度只有 3.33ms 的 DATETIME。
--   SYSDATETIME() 是 2008 引入的改进，返回精度 100ns 的 DATETIME2。
--   横向对比:
--     PostgreSQL: NOW() / CURRENT_TIMESTAMP（微秒精度）
--     MySQL:      NOW() / CURRENT_TIMESTAMP（微秒精度，5.6.4+）
--     Oracle:     SYSDATE（秒级） / SYSTIMESTAMP（微秒 + 时区）
```

## 日期构造函数（2012+）

```sql
SELECT DATEFROMPARTS(2024, 1, 15);                              -- 2024-01-15
SELECT TIMEFROMPARTS(10, 30, 0, 0, 0);                          -- 10:30:00
SELECT DATETIME2FROMPARTS(2024, 1, 15, 10, 30, 0, 0, 0);       -- DATETIME2
SELECT DATETIMEOFFSETFROMPARTS(2024, 1, 15, 10, 30, 0, 0, 8, 0, 0); -- +08:00

-- 横向对比:
--   PostgreSQL: make_date(2024,1,15), make_timestamp(...)
--   MySQL:      无直接等价（使用 STR_TO_DATE）
--   Oracle:     TO_DATE('2024-01-15', 'YYYY-MM-DD')
--
-- 对引擎开发者的启示:
--   日期构造函数避免了字符串解析的歧义（'01/02/2024' 是 1月2日还是 2月1日？）
--   它们应该是引擎的内置功能，而非让用户依赖 CAST/CONVERT + 日期格式。
```

## 日期运算: DATEADD / DATEDIFF

```sql
SELECT DATEADD(DAY, 1, GETDATE());          -- 加 1 天
SELECT DATEADD(MONTH, 3, GETDATE());        -- 加 3 个月
SELECT DATEADD(HOUR, -2, GETDATE());        -- 减 2 小时

SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31');    -- 365
SELECT DATEDIFF(MONTH, '2024-01-01', '2024-06-15');  -- 5（只看月份差）

-- 2016+: DATEDIFF_BIG（避免 INT 溢出）
SELECT DATEDIFF_BIG(SECOND, '2000-01-01', GETDATE());
```

DATEDIFF 返回 INT（最大 ~21 亿秒 ≈ 68 年），跨越大时间范围会溢出

设计分析（对引擎开发者）:
  SQL Server 使用函数式日期运算: DATEADD(unit, n, date)
  PostgreSQL 使用运算符: date + INTERVAL '1 day'
  两种设计各有优劣:
    函数式: 显式、无歧义，但冗长
    运算符式: 简洁自然，但需要 INTERVAL 类型支持
  SQL Server 不支持 INTERVAL 类型——这是不支持 date + interval 语法的根本原因。

## 日期部分提取

```sql
SELECT YEAR(GETDATE()), MONTH(GETDATE()), DAY(GETDATE());
SELECT DATEPART(HOUR, GETDATE());
SELECT DATEPART(MINUTE, GETDATE());
SELECT DATEPART(WEEKDAY, GETDATE());         -- 取决于 SET DATEFIRST
SELECT DATEPART(DAYOFYEAR, GETDATE());
SELECT DATENAME(WEEKDAY, GETDATE());          -- 'Monday'（本地化名称）
SELECT DATENAME(MONTH, GETDATE());            -- 'January'
```

DATEPART vs DATENAME:
  DATEPART 返回 INT（数值）
  DATENAME 返回 NVARCHAR（名称字符串）

## 日期格式化: FORMAT vs CONVERT

FORMAT（2012+, 使用 .NET CLR）
```sql
SELECT FORMAT(GETDATE(), 'yyyy-MM-dd HH:mm:ss');
SELECT FORMAT(GETDATE(), 'dddd, MMMM dd, yyyy');
```

CONVERT + 样式码（传统方式，性能更好）
```sql
SELECT CONVERT(VARCHAR, GETDATE(), 120);          -- yyyy-mm-dd hh:mi:ss
SELECT CONVERT(VARCHAR(10), GETDATE(), 23);       -- yyyy-mm-dd
SELECT CONVERT(VARCHAR(10), GETDATE(), 101);      -- mm/dd/yyyy (美式)
SELECT CONVERT(VARCHAR(10), GETDATE(), 103);      -- dd/mm/yyyy (英式)
SELECT CONVERT(VARCHAR(10), GETDATE(), 112);      -- yyyymmdd
SELECT CONVERT(VARCHAR(30), GETDATE(), 126);      -- ISO 8601

-- 设计分析（对引擎开发者）:
--   FORMAT 函数基于 .NET CLR，性能比 CONVERT 慢 10-50x。
--   在逐行调用时（如 SELECT FORMAT(col,...) FROM 大表）性能问题尤为严重。
--   这是引擎设计的教训: 不要依赖外部运行时（CLR）实现高频函数。
--
--   CONVERT 的样式码设计也有问题: 120/23/101/103 这些数字毫无语义，
--   完全依赖记忆。PostgreSQL 的 TO_CHAR(date, 'YYYY-MM-DD') 更直观。
--
-- 对引擎开发者的启示:
--   日期格式化应该: (1) 使用格式字符串而非数字编码 (2) 原生实现而非依赖 CLR
```

## 日期截断

```sql
SELECT CAST(GETDATE() AS DATE);              -- 去掉时间部分

-- 2022+: DATETRUNC（SQL Server 最新添加）
SELECT DATETRUNC(MONTH, GETDATE());           -- 月初
SELECT DATETRUNC(YEAR, GETDATE());            -- 年初
SELECT DATETRUNC(HOUR, GETDATE());            -- 整点

-- 2022 之前的替代方案:
SELECT DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0);  -- 月初（经典 hack）
SELECT DATEADD(YEAR, DATEDIFF(YEAR, 0, GETDATE()), 0);    -- 年初

-- 横向对比:
--   PostgreSQL: date_trunc('month', now())（8.0+ 就支持）
--   MySQL:      DATE_FORMAT(now(), '%Y-%m-01')（间接方式）
--   Oracle:     TRUNC(SYSDATE, 'MM')
--
-- 对引擎开发者的启示: DATETRUNC 是高频需求，应该早期内置。
```

## 月末函数与时区

EOMONTH（2012+）
```sql
SELECT EOMONTH(GETDATE());          -- 当月月末
SELECT EOMONTH(GETDATE(), 1);       -- 下个月月末
SELECT EOMONTH(GETDATE(), -1);      -- 上个月月末

-- AT TIME ZONE（2016+）
SELECT GETDATE() AT TIME ZONE 'China Standard Time';
SELECT SYSDATETIMEOFFSET() AT TIME ZONE 'UTC';
```

AT TIME ZONE 使用 Windows 时区名称（不是 IANA 的 Asia/Shanghai）
这是 SQL Server 的独特选择——其他数据库使用 IANA 时区名称
横向对比:
  PostgreSQL: SET timezone = 'Asia/Shanghai'（IANA）
  MySQL:      SET time_zone = '+08:00' 或 'Asia/Shanghai'（IANA）

## 日期验证

```sql
SELECT ISDATE('2024-02-29');                  -- 1（有效）
SELECT ISDATE('2024-02-30');                  -- 0（无效）
SELECT TRY_CONVERT(DATE, '2024-02-30');       -- NULL（安全转换）
```
