# ClickHouse: 日期函数

> 参考资料:
> - [1] ClickHouse - Date/Time Functions
>   https://clickhouse.com/docs/en/sql-reference/functions/date-time-functions
> - [2] ClickHouse - DateTime Data Type
>   https://clickhouse.com/docs/en/sql-reference/data-types/datetime


当前日期时间

```sql
SELECT now();                                            -- DateTime
SELECT now64();                                          -- DateTime64
SELECT today();                                          -- Date（当天）
SELECT yesterday();                                      -- Date（昨天）

```

构造

```sql
SELECT toDate('2024-01-15');                              -- Date
SELECT toDateTime('2024-01-15 10:30:00');                 -- DateTime
SELECT toDateTime64('2024-01-15 10:30:00.123', 3);        -- DateTime64
SELECT makeDate(2024, 1, 15);                             -- Date（22.1+）
SELECT makeDateTime(2024, 1, 15, 10, 30, 0);              -- DateTime（22.1+）

```

日期加减

```sql
SELECT toDate('2024-01-15') + 7;                          -- 加 7 天
SELECT toDate('2024-01-15') + INTERVAL 1 MONTH;
SELECT now() + INTERVAL 2 HOUR;
SELECT now() - INTERVAL 30 MINUTE;
SELECT addDays(today(), 7);
SELECT addWeeks(today(), 2);
SELECT addMonths(today(), 3);
SELECT addYears(today(), 1);
SELECT addHours(now(), 2);
SELECT addMinutes(now(), 30);
SELECT addSeconds(now(), 60);
SELECT subtractDays(today(), 1);
SELECT subtractMonths(today(), 6);

```

日期差

```sql
SELECT dateDiff('day', '2024-01-01', '2024-12-31');       -- 365
SELECT dateDiff('month', '2024-01-01', '2024-12-31');     -- 11
SELECT dateDiff('year', '2024-01-01', '2025-06-01');      -- 1
SELECT dateDiff('hour', now() - INTERVAL 3 HOUR, now());  -- 3
SELECT date_diff('second', ts1, ts2);
SELECT age('day', '2024-01-01', '2024-12-31');             -- 365（23.8+）

```

提取

```sql
SELECT toYear(now());                                    -- 2024
SELECT toMonth(now());                                   -- 1
SELECT toDayOfMonth(now());                              -- 15
SELECT toHour(now());                                    -- 10
SELECT toMinute(now());                                  -- 30
SELECT toSecond(now());                                  -- 0
SELECT toDayOfWeek(now());                               -- 1=周一
SELECT toDayOfYear(now());                               -- 15
SELECT toISOWeek(now());                                 -- ISO 周数
SELECT toISOYear(now());                                 -- ISO 年份
SELECT toQuarter(now());                                 -- 季度
SELECT toWeek(now());                                    -- 周数
SELECT toRelativeMonthNum(now());                        -- 相对月数（从 epoch）
SELECT toRelativeDayNum(now());                          -- 相对天数

```

格式化

```sql
SELECT formatDateTime(now(), '%Y-%m-%d %H:%M:%S');
SELECT formatDateTime(now(), '%F %T');                    -- 简写
SELECT toString(now());                                  -- 默认格式
SELECT dateName('month', now());                         -- 月份名（21.4+）

```

截断（toStartOf* 系列）

```sql
SELECT toStartOfYear(now());                             -- 年初
SELECT toStartOfQuarter(now());                          -- 季初
SELECT toStartOfMonth(now());                            -- 月初
SELECT toStartOfWeek(now());                             -- 周初（周日开始）
SELECT toMonday(now());                                  -- 本周一
SELECT toStartOfDay(now());                              -- 当天零点
SELECT toStartOfHour(now());                             -- 整点
SELECT toStartOfMinute(now());                           -- 整分
SELECT toStartOfSecond(now64());                         -- 整秒
SELECT toStartOfFiveMinutes(now());                      -- 5 分钟整
SELECT toStartOfTenMinutes(now());                       -- 10 分钟整
SELECT toStartOfFifteenMinutes(now());                   -- 15 分钟整

```

Unix 时间戳

```sql
SELECT toUnixTimestamp(now());                           -- 秒
SELECT toUnixTimestamp64Milli(now64(3));                  -- 毫秒
SELECT fromUnixTimestamp(1705312800);                    -- DateTime
SELECT toDateTime(1705312800);                           -- DateTime

```

时区转换

```sql
SELECT toTimezone(now(), 'Asia/Shanghai');
SELECT now('Asia/Shanghai');                             -- 指定时区的当前时间

```

注意：函数名使用驼峰命名法（toYear, toDayOfWeek 等）
注意：toStartOf* 系列是 ClickHouse 分析场景的核心函数
注意：toDayOfWeek 返回 1=周一（ISO 标准，与 MySQL 不同）
注意：formatDateTime 使用 strftime 风格

