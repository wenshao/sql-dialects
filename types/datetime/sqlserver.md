# SQL Server: 日期时间类型

> 参考资料:
> - [SQL Server T-SQL - Date and Time Types](https://learn.microsoft.com/en-us/sql/t-sql/data-types/date-transact-sql)

## 六种日期时间类型（SQL Server 类型最丰富）

DATE:           3 字节, 0001-01-01 ~ 9999-12-31（2008+, 纯日期）
TIME(n):        3-5 字节, 精度可达 100ns（2008+, 纯时间）
DATETIME:       8 字节, 1753-01-01 ~ 9999-12-31, 精度 3.33ms（旧式）
DATETIME2(n):   6-8 字节, 0001-01-01 ~ 9999-12-31, 精度 100ns（2008+, 推荐）
SMALLDATETIME:  4 字节, 1900-01-01 ~ 2079-06-06, 精度 1 分钟
DATETIMEOFFSET: 8-10 字节, 带时区偏移（2008+）

```sql
CREATE TABLE events (
    id         BIGINT IDENTITY(1,1) PRIMARY KEY,
    event_date DATE,                   -- 纯日期
    event_time TIME(3),                -- 毫秒精度
    created_at DATETIME2(6),           -- 微秒精度（推荐）
    updated_at DATETIMEOFFSET          -- 带时区偏移
);
```

## DATETIME vs DATETIME2（对引擎开发者）

DATETIME 是 SQL Server 最古老的时间类型，有严重的精度问题:
  精度只有 3.33ms（值被四舍五入到 .000, .003, .007 毫秒）
  范围从 1753 年开始（不是 0001 年）
  存储 8 字节

DATETIME2 是 2008 引入的改进:
  精度可达 100ns（DATETIME2(7) = 默认）
  范围从 0001 年开始
  DATETIME2(3) 只需 7 字节（比 DATETIME 的 8 字节更小）

设计分析:
  DATETIME 的 3.33ms 精度来自其内部存储格式:
  4 字节存日期（从 1900-01-01 的天数）+ 4 字节存时间（1/300 秒的计数）
  1/300 秒 = 3.33ms

  DATETIME2 使用变长存储: 3 字节日期 + 3-5 字节时间（取决于精度参数）
  这是更现代的设计——精度可调，存储更紧凑

横向对比:
  PostgreSQL: TIMESTAMP（微秒精度）, TIMESTAMPTZ（带时区, 推荐）
  MySQL:      DATETIME（微秒精度, 5.6.4+）, TIMESTAMP（带时区转换, 2038 问题）
  Oracle:     DATE（秒精度!）, TIMESTAMP（纳秒精度）

对引擎开发者的启示:
  DATETIME 的固定精度是过时设计。现代引擎应该:
  (1) 默认微秒精度（6 位小数）
  (2) 允许用户指定精度（0-9 位小数）
  (3) 内部使用变长编码节省空间

## DATETIMEOFFSET: 带时区偏移的时间戳

DATETIMEOFFSET 存储时间 + UTC 偏移（如 +08:00）
> **注意**: 存储的是偏移量（fixed offset），不是时区（named timezone）
偏移量不知道夏令时——'UTC+08:00' 总是 +08:00，不会因夏令时变化

```sql
DECLARE @dt DATETIMEOFFSET = '2024-01-15 10:30:00 +08:00';
SELECT @dt;                                    -- 2024-01-15 10:30:00.0000000 +08:00
SELECT SWITCHOFFSET(@dt, '+09:00');            -- 转换到 +09:00
SELECT @dt AT TIME ZONE 'UTC';                -- 转换到 UTC（2016+）
SELECT @dt AT TIME ZONE 'China Standard Time'; -- 使用 Windows 时区名称
```

设计分析:
  DATETIMEOFFSET 类似 PostgreSQL 的 TIMESTAMPTZ，但有区别:
  PostgreSQL: 内部存 UTC，显示时按会话时区转换（不保留原始偏移）
  SQL Server: 内部存值+偏移，保留原始偏移信息

  哪种更好？取决于需求:
  如果需要知道"用户当时的本地时间是几点"→ DATETIMEOFFSET（保留偏移）
  如果只需要"事件发生的绝对时间点"→ TIMESTAMPTZ（存 UTC）

## AT TIME ZONE: 时区转换（2016+）

无偏移的值 + AT TIME ZONE = 解释为该时区的本地时间
```sql
SELECT CAST('2024-07-01 12:00:00' AS DATETIME2) AT TIME ZONE 'Eastern Standard Time';
```

结果: 2024-07-01 12:00:00.0000000 -04:00（自动处理夏令时！）

SQL Server 使用 Windows 时区名称（不是 IANA）:
'China Standard Time'          → UTC+08:00
'Eastern Standard Time'        → UTC-05:00 / UTC-04:00（夏令时）
'Pacific Standard Time'        → UTC-08:00 / UTC-07:00（夏令时）

横向对比:
  PostgreSQL: SET timezone = 'Asia/Shanghai'（IANA 名称）
  MySQL:      SET time_zone = 'Asia/Shanghai'（IANA）或 '+08:00'

对引擎开发者的启示:
  使用 IANA 时区数据库（tz database）是行业标准。
  SQL Server 使用 Windows 时区是微软生态绑定的结果。
  新引擎应使用 IANA 时区名称。

## 获取当前时间

```sql
SELECT GETDATE();           -- DATETIME（最常用，精度 3.33ms）
SELECT SYSDATETIME();       -- DATETIME2（精度 100ns，推荐）
SELECT SYSUTCDATETIME();    -- UTC DATETIME2
SELECT SYSDATETIMEOFFSET(); -- DATETIMEOFFSET（含本地时区偏移）
```

## 日期运算

```sql
SELECT DATEADD(DAY, 1, GETDATE());
SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31');
SELECT DATEDIFF_BIG(SECOND, '2000-01-01', GETDATE());  -- 2016+（避免 INT 溢出）
```

2022+: DATETRUNC
```sql
SELECT DATETRUNC(MONTH, GETDATE());
```

格式化
```sql
SELECT FORMAT(GETDATE(), 'yyyy-MM-dd HH:mm:ss');  -- 2012+（CLR, 慢）
SELECT CONVERT(VARCHAR, GETDATE(), 120);            -- 传统方式（快）
```

## 版本演进

2000  : DATETIME, SMALLDATETIME（唯一选择）
2008  : DATE, TIME, DATETIME2, DATETIMEOFFSET（重大改进）
2012  : DATEFROMPARTS, EOMONTH, FORMAT
2016  : AT TIME ZONE, DATEDIFF_BIG
2022  : DATETRUNC
推荐: 新项目总是使用 DATETIME2 而非 DATETIME
