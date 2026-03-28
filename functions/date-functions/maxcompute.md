# MaxCompute (ODPS): 日期函数

> 参考资料:
> - [1] MaxCompute SQL - Date Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/date-functions
> - [2] MaxCompute Built-in Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/built-in-functions-overview


## 1. 当前日期时间


```sql
SELECT GETDATE();                           -- 返回 DATETIME（作业启动时间）
SELECT CURRENT_TIMESTAMP();                 -- 返回 TIMESTAMP（作业启动时间）

```

 注意: 批处理引擎中"当前时间"= 作业启动时间（不是行处理时间）

## 2. 日期加减: DATEADD（参数顺序陷阱!）


MaxCompute: DATEADD(date, delta, unit)

```sql
SELECT DATEADD(DATETIME '2024-01-15 10:00:00', 7, 'dd');    -- 加 7 天
SELECT DATEADD(DATETIME '2024-01-15 10:00:00', 3, 'mm');    -- 加 3 月
SELECT DATEADD(DATETIME '2024-01-15 10:00:00', 2, 'hh');    -- 加 2 小时
SELECT DATEADD(DATETIME '2024-01-15 10:00:00', -1, 'yyyy'); -- 减 1 年

```

参数顺序对比（最常见的迁移陷阱之一）:
MaxCompute: DATEADD(date, delta, unit)     -- 日期在前，单位在后
SQL Server: DATEADD(unit, delta, date)     -- 单位在前，日期在后
MySQL:      DATE_ADD(date, INTERVAL delta unit)  -- INTERVAL 语法
PostgreSQL: date + INTERVAL 'delta unit'         -- 运算符语法
BigQuery:   DATE_ADD(date, INTERVAL delta unit)  -- 类似 MySQL
Hive:       DATE_ADD(date, days)                 -- 只支持天数!

ADD_MONTHS: 加月（处理月末边界）

```sql
SELECT ADD_MONTHS(DATE '2024-01-31', 1);    -- 2024-02-29（闰年）
SELECT ADD_MONTHS(DATE '2024-03-31', -1);   -- 2024-02-29

```

## 3. 日期差: DATEDIFF


```sql
SELECT DATEDIFF(DATE '2024-12-31', DATE '2024-01-01', 'dd');  -- 365
SELECT DATEDIFF(DATE '2024-12-31', DATE '2024-01-01', 'mm');  -- 11
SELECT DATEDIFF(DATE '2025-01-01', DATE '2024-01-01', 'yyyy');-- 1

```

 DATEDIFF 参数顺序:
   MaxCompute: DATEDIFF(end, start, unit) → end - start
   SQL Server: DATEDIFF(unit, start, end) → end - start
   MySQL:      DATEDIFF(end, start) → 天数（只支持天数）
   PostgreSQL: end - start → INTERVAL 类型
   BigQuery:   DATE_DIFF(end, start, unit) → 整数

## 4. 提取日期部分


```sql
SELECT YEAR(DATE '2024-01-15');             -- 2024
SELECT MONTH(DATE '2024-01-15');            -- 1
SELECT DAY(DATE '2024-01-15');              -- 15
SELECT HOUR(DATETIME '2024-01-15 10:30:00');-- 10
SELECT MINUTE(DATETIME '2024-01-15 10:30:00');-- 30
SELECT SECOND(DATETIME '2024-01-15 10:30:00');-- 0
SELECT WEEKDAY(DATE '2024-01-15');          -- 周几（0=周日）
SELECT DAYOFYEAR(DATE '2024-01-15');        -- 15（一年中第几天）
SELECT WEEKOFYEAR(DATE '2024-01-15');       -- 第几周
SELECT LAST_DAY(DATE '2024-01-15');         -- 2024-01-31

```

 对比标准 SQL EXTRACT:
   标准 SQL:   EXTRACT(YEAR FROM date)
   MaxCompute: YEAR(date)（Hive 兼容，函数式）
   BigQuery:   EXTRACT(YEAR FROM date)（遵循标准）

## 5. 格式化与解析（两套格式码!）


TO_CHAR: Oracle 风格格式码

```sql
SELECT TO_CHAR(DATETIME '2024-01-15 10:30:00', 'yyyy-mm-dd hh:mi:ss');
```

格式码: yyyy=年, mm=月, dd=日, hh=时, mi=分, ss=秒

DATE_FORMAT: Java SimpleDateFormat 风格

```sql
SELECT DATE_FORMAT(DATETIME '2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
```

格式码: yyyy=年, MM=月, dd=日, HH=24时, mm=分, ss=秒

陷阱: 'mm' 在两个函数中含义不同!
TO_CHAR 中 mm = 月份
DATE_FORMAT 中 mm = 分钟，MM = 月份
混用会导致难以排查的数据错误

TO_DATE: 解析字符串为 DATETIME

```sql
SELECT TO_DATE('2024-01-15 10:30:00', 'yyyy-mm-dd hh:mi:ss');
SELECT TO_DATE('20240115', 'yyyymmdd');
SELECT TO_DATE('2024/01/15', 'yyyy/mm/dd');

```

## 6. 截断


```sql
SELECT TRUNC(DATETIME '2024-01-15 10:30:00', 'yyyy'); -- 年初
SELECT TRUNC(DATETIME '2024-01-15 10:30:00', 'mm');   -- 月初
SELECT TRUNC(DATETIME '2024-01-15 10:30:00', 'dd');   -- 当天零点
SELECT TRUNC(DATETIME '2024-01-15 10:30:00', 'hh');   -- 整点

```

 TRUNC 在 ETL 中的价值:
   TRUNC(event_time, 'dd'): 将事件时间截断到天 → 用于日聚合
   TRUNC(event_time, 'hh'): 截断到小时 → 用于小时聚合
   对比:
     PostgreSQL: DATE_TRUNC('day', timestamp)
     BigQuery:   TIMESTAMP_TRUNC(timestamp, DAY)
     MySQL:      无直接等价（需要 DATE() 或 DATE_FORMAT）

## 7. Unix 时间戳互转


```sql
SELECT UNIX_TIMESTAMP();                    -- 当前 Unix 秒数
SELECT UNIX_TIMESTAMP(DATETIME '2024-01-15 10:00:00');
SELECT FROM_UNIXTIME(1705312800);           -- 返回 DATETIME
SELECT FROM_UNIXTIME(1705312800, 'yyyy-MM-dd HH:mm:ss');

```

日期验证

```sql
SELECT ISDATE('2024-01-15', 'yyyy-mm-dd');  -- TRUE/FALSE

```

## 8. 分区日期处理（MaxCompute 高频模式）


分区键通常是 STRING 格式的日期: '20240115'
需要在 STRING 和 DATE 之间频繁转换

STRING → DATE

```sql
SELECT TO_DATE('20240115', 'yyyymmdd');

```

DATE → 分区格式 STRING

```sql
SELECT TO_CHAR(GETDATE(), 'yyyymmdd');      -- '20240115'

```

计算"昨天"的分区键

```sql
SELECT TO_CHAR(DATEADD(GETDATE(), -1, 'dd'), 'yyyymmdd');

```

 DataWorks 调度中的日期变量:
   ${bizdate}: 业务日期（通常是 T-1）
   ${yyyymmdd}: 当前日期
   这些变量在调度时替换，不是 SQL 运行时计算

## 9. 横向对比: 日期函数


 DATEADD 参数顺序:
MaxCompute: (date, delta, unit)     | SQL Server: (unit, delta, date)
MySQL:      DATE_ADD(date, INTERVAL)| PostgreSQL: date + INTERVAL

 格式化:
   MaxCompute: TO_CHAR + DATE_FORMAT（两套格式码）
   PostgreSQL: TO_CHAR（自成一体的格式码）
   MySQL:      DATE_FORMAT（%Y-%m-%d 格式码）
   BigQuery:   FORMAT_TIMESTAMP（%Y-%m-%d 格式码）

 时区:
MaxCompute: 无时区支持              | PostgreSQL: AT TIME ZONE
BigQuery:   TIMESTAMP 函数支持时区   | Snowflake: CONVERT_TIMEZONE

## 10. 对引擎开发者的启示


### 1. DATEADD/DATEDIFF 参数顺序应与生态主流一致（减少迁移陷阱）

### 2. 格式化函数应统一格式码体系（两套格式码是维护负担）

### 3. INTERVAL 类型比函数式 DATEADD 更灵活（PostgreSQL 的方案更优）

### 4. 分区日期处理（STRING↔DATE 转换）在数仓引擎中使用频率极高

### 5. 时区支持是国际化数据分析的刚需 — 不应缺席

### 6. DATE_TRUNC/TRUNC 在聚合分析中使用频率极高 — 性能值得优化

