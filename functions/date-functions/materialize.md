# Materialize: 日期函数 (Date and Time Functions)

> 参考资料:
> - [Materialize Documentation - Date and Time Functions](https://materialize.com/docs/sql/functions/numeric/)
> - [Materialize Documentation - Types](https://materialize.com/docs/sql/types/)
> - [PostgreSQL Documentation - Date/Time Functions](https://www.postgresql.org/docs/current/functions-datetime.html)
> - 说明: Materialize 基于 PostgreSQL 语法，日期函数与 PostgreSQL 高度兼容。
> - 流式计算场景中，时间函数有特殊的语义（如 mz_now() 基于系统时钟）。
> - ============================================================
> - 1. 获取当前时间
> - ============================================================

```sql
SELECT NOW();                                         -- 当前事务时间戳 (TIMESTAMPTZ)
SELECT CURRENT_TIMESTAMP;                             -- 同 NOW()，SQL 标准语法
SELECT CURRENT_DATE;                                  -- 当前日期 (DATE)
SELECT CURRENT_TIME;                                  -- 当前时间 (TIME)
SELECT mz_now();                                      -- Materialize 特有: 系统时钟时间戳
```

NOW() vs mz_now():
NOW() 在批查询中返回固定时间（查询开始时间）
mz_now() 在持续查询中始终返回系统时钟的当前时间
物化视图中推荐使用 mz_now() 进行实时计算

## 时间间隔 (INTERVAL)


```sql
SELECT INTERVAL '1 day';                              -- 1 day
SELECT INTERVAL '3 hours 30 minutes';                 -- 03:30:00
SELECT INTERVAL '1 year 2 months';                    -- 1 year 2 months
SELECT INTERVAL '2 weeks';                            -- 14 days
```

## 日期时间与 INTERVAL 运算

```sql
SELECT NOW() + INTERVAL '1 day';                      -- 明天此刻
SELECT NOW() - INTERVAL '3 hours';                    -- 3 小时前
SELECT CURRENT_DATE + INTERVAL '1 week';              -- 下周同日
```

## 日期差值计算


## AGE: 返回两个时间戳之间的"年龄"间隔

```sql
SELECT AGE(NOW(), '2024-01-01'::TIMESTAMPTZ);         -- 返回 INTERVAL
```

## 直接相减得到天数（DATE 类型）

```sql
SELECT '2024-12-31'::DATE - '2024-01-01'::DATE;      -- 365（天数）
```

## 提取 INTERVAL 中的特定部分

```sql
SELECT EXTRACT(DAY FROM AGE(NOW(), '2024-01-01'::TIMESTAMPTZ));
```

## 提取日期部分


```sql
SELECT EXTRACT(YEAR FROM NOW());                      -- 年份
SELECT EXTRACT(MONTH FROM NOW());                     -- 月份 (1-12)
SELECT EXTRACT(DAY FROM NOW());                       -- 日期
SELECT EXTRACT(HOUR FROM NOW());                      -- 小时
SELECT EXTRACT(DOW FROM NOW());                       -- 星期几 (0=Sunday, 6=Saturday)
SELECT EXTRACT(DOY FROM NOW());                       -- 一年中的第几天 (1-366)
SELECT EXTRACT(QUARTER FROM NOW());                   -- 季度 (1-4)
SELECT EXTRACT(WEEK FROM NOW());                      -- ISO 周数
```

## DATE_PART: EXTRACT 的函数形式

```sql
SELECT DATE_PART('hour', NOW());                      -- 小时
SELECT DATE_PART('epoch', NOW());                     -- Unix 时间戳（秒）
```

## 日期截断 (DATE_TRUNC)


```sql
SELECT DATE_TRUNC('hour', NOW());                     -- 截断到小时
SELECT DATE_TRUNC('day', NOW());                      -- 截断到天（当天 00:00:00）
SELECT DATE_TRUNC('month', NOW());                    -- 当月第一天
SELECT DATE_TRUNC('year', NOW());                     -- 当年第一天
SELECT DATE_TRUNC('week', NOW());                     -- 当周周一
SELECT DATE_TRUNC('quarter', NOW());                  -- 当季第一天
```

DATE_TRUNC 在时间窗口聚合中非常有用:
SELECT DATE_TRUNC('hour', event_time) AS hour_bucket, COUNT(*)
FROM events GROUP BY DATE_TRUNC('hour', event_time);

## 格式化输出 (TO_CHAR)


```sql
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');      -- '2024-01-15 10:30:00'
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD');                  -- '2024-01-15'
SELECT TO_CHAR(NOW(), 'Day, DD Month YYYY');          -- 'Monday  , 15 January  2024'
SELECT TO_CHAR(NOW(), 'IW (IYYY)');                   -- ISO 周数和年份
SELECT TO_CHAR(CURRENT_DATE, 'Mon DD, YYYY');         -- 'Jan 15, 2024'
```

常用格式码:
YYYY: 4位年份   MM: 2位月份   DD: 2位日期
HH24: 24小时    MI: 分钟      SS: 秒
Day: 星期全名   Month: 月份全名

## 日期解析 (TO_TIMESTAMP / TO_DATE)


```sql
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');  -- TIMESTAMPTZ
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');           -- DATE
SELECT TO_TIMESTAMP(1705286400);                      -- Unix 时间戳 → TIMESTAMPTZ
```

## 时区处理


```sql
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';            -- 转为指定时区
SELECT NOW() AT TIME ZONE 'UTC';                      -- 转为 UTC
SELECT NOW() AT TIME ZONE 'America/New_York';         -- 转为纽约时区
```

时区转换链:
TIMESTAMPTZ → AT TIME ZONE 'tz' → TIMESTAMP（去时区信息）
TIMESTAMP → AT TIME ZONE 'tz' → TIMESTAMPTZ（加上时区信息）

## EPOCH 转换


```sql
SELECT EXTRACT(EPOCH FROM NOW());                     -- → Unix 时间戳（浮点秒）
SELECT EXTRACT(EPOCH FROM NOW())::INTEGER;            -- → 整数秒
SELECT TO_TIMESTAMP(1705286400);                      -- Unix → TIMESTAMPTZ
```

## 生成时间序列


## generate_series: 生成连续时间序列

```sql
SELECT * FROM generate_series(
    '2024-01-01'::TIMESTAMPTZ,
    '2024-01-07'::TIMESTAMPTZ,
    INTERVAL '1 day'
);  -- 生成 2024-01-01 到 2024-01-07 每天一行
```

用途: 生成时间桶用于 LEFT JOIN 填充缺失时段
SELECT gs.bucket, COUNT(e.id)
FROM generate_series('2024-01-01', '2024-01-07', INTERVAL '1 day') AS gs(bucket)
LEFT JOIN events e ON DATE_TRUNC('day', e.event_time) = gs.bucket
GROUP BY gs.bucket;

## 物化视图中的时间函数


## 物化视图中使用时间函数会增量维护

```sql
CREATE MATERIALIZED VIEW hourly_stats AS
SELECT
    DATE_TRUNC('hour', event_time) AS hour_bucket,
    COUNT(*) AS event_count,
    COUNT(DISTINCT user_id) AS unique_users
FROM events
GROUP BY DATE_TRUNC('hour', event_time);
```

## 基于 mz_now() 的实时窗口

```sql
SELECT * FROM events
WHERE event_time > mz_now() - INTERVAL '1 hour';
```

## 版本演进与注意事项

Materialize 0.x: 基础日期函数（NOW/CURRENT_DATE/EXTRACT）
Materialize 0.7+: DATE_TRUNC, TO_CHAR, AT TIME ZONE
Materialize 0.9+: mz_now() 系统时钟函数
注意事项:
1. 日期函数与 PostgreSQL 语法高度兼容
2. 物化视图中使用日期函数，结果随源数据增量更新
3. mz_now() 是 Materialize 特有函数，用于流式时间窗口
4. generate_series 在持续查询中行为特殊（生成无限序列时需 LIMIT）
5. 时区转换在流式场景中需注意性能影响
