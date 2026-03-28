# KingbaseES (人大金仓): 日期函数 (Date and Time Functions)

> 参考资料:
> - [KingbaseES SQL Reference Manual](https://help.kingbase.com.cn/v8/index.html)
> - [KingbaseES Documentation - Date/Time Types](https://help.kingbase.com.cn/v8/developer/sql-reference/data-types/datetime.html)
> - [PostgreSQL Documentation - Date/Time Functions](https://www.postgresql.org/docs/current/functions-datetime.html)


## 说明: KingbaseES 是国产数据库，兼容 PostgreSQL 和 Oracle 双语法体系。

日期函数在 PG 模式和 Oracle 模式下有细微差异。

## 获取当前日期时间


```sql
SELECT NOW();                                         -- 当前事务时间戳 (TIMESTAMPTZ)
SELECT CURRENT_TIMESTAMP;                             -- 同 NOW()，SQL 标准语法
SELECT CURRENT_DATE;                                  -- 当前日期 (DATE)
SELECT CURRENT_TIME;                                  -- 当前时间 (TIMETZ)
SELECT LOCALTIME;                                     -- 当前本地时间 (TIME，无时区)
SELECT LOCALTIMESTAMP;                                -- 当前本地时间戳 (TIMESTAMP，无时区)
SELECT CLOCK_TIMESTAMP();                             -- 实时时钟（每次调用返回不同值）
```

NOW() vs CLOCK_TIMESTAMP():
NOW() 在事务中始终返回同一值（事务开始时间）
CLOCK_TIMESTAMP() 返回实际时钟时间（适合监控场景）
Oracle 兼容模式:

```sql
SELECT SYSDATE FROM DUAL;                             -- Oracle 风格的当前时间
SELECT SYSTIMESTAMP FROM DUAL;                        -- Oracle 风格的带时区时间戳
```

## 构造日期时间


## PostgreSQL 风格

```sql
SELECT MAKE_DATE(2024, 1, 15);                        -- 2024-01-15
SELECT MAKE_TIME(10, 30, 0);                          -- 10:30:00
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);        -- 2024-01-15 10:30:00
SELECT MAKE_TIMESTAMPTZ(2024, 1, 15, 10, 30, 0, 'Asia/Shanghai');
```

## 字符串解析

```sql
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');           -- DATE
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');  -- TIMESTAMPTZ
```

## Oracle 兼容模式

```sql
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM DUAL;
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;
```

## 日期加减运算


## INTERVAL 加减

```sql
SELECT '2024-01-15'::DATE + INTERVAL '1 day';         -- 2024-01-16
SELECT '2024-01-15'::DATE + INTERVAL '3 months';      -- 2024-04-15
SELECT NOW() - INTERVAL '2 hours 30 minutes';         -- 2.5 小时前
SELECT NOW() + INTERVAL '1 year 6 months';            -- 1.5 年后
```

## DATE + INTEGER = 天数加减

```sql
SELECT '2024-01-15'::DATE + 7;                        -- 2024-01-22（加 7 天）
SELECT '2024-01-15'::DATE - 7;                        -- 2024-01-08（减 7 天）
```

## Oracle 兼容: ADD_MONTHS

```sql
SELECT ADD_MONTHS(DATE '2024-01-15', 3) FROM DUAL;    -- 2024-04-15
SELECT ADD_MONTHS(DATE '2024-01-31', 1) FROM DUAL;    -- 2024-02-29（月末处理）
```

## 日期差值计算


## DATE 相减得到天数

```sql
SELECT '2024-12-31'::DATE - '2024-01-01'::DATE;      -- 365
```

## AGE: 返回"人类可读"的间隔

```sql
SELECT AGE('2024-12-31'::DATE, '2024-01-01'::DATE);  -- '11 mons 30 days'
SELECT AGE(NOW(), '2000-01-01'::DATE);                -- '24 years  ...'
```

## Oracle 兼容: MONTHS_BETWEEN

```sql
SELECT MONTHS_BETWEEN(DATE '2024-06-15', DATE '2024-01-01') FROM DUAL;
```

## 提取日期部分


## EXTRACT

```sql
SELECT EXTRACT(YEAR FROM NOW());                      -- 年份
SELECT EXTRACT(MONTH FROM NOW());                     -- 月份 (1-12)
SELECT EXTRACT(DAY FROM NOW());                       -- 日期
SELECT EXTRACT(DOW FROM NOW());                       -- 星期几 (0=Sunday)
SELECT EXTRACT(DOY FROM NOW());                       -- 一年中第几天
SELECT EXTRACT(QUARTER FROM NOW());                   -- 季度 (1-4)
SELECT EXTRACT(WEEK FROM NOW());                      -- ISO 周数
SELECT EXTRACT(EPOCH FROM NOW());                     -- Unix 时间戳（秒）
```

## DATE_PART: EXTRACT 的函数形式

```sql
SELECT DATE_PART('hour', NOW());                      -- 小时
SELECT DATE_PART('minute', NOW());                    -- 分钟
```

## Oracle 兼容: EXTRACT 同名函数可用

```sql
SELECT EXTRACT(YEAR FROM SYSDATE) FROM DUAL;
```

## 日期格式化 (TO_CHAR)


```sql
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');      -- '2024-01-15 10:30:00'
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD');                  -- '2024-01-15'
SELECT TO_CHAR(NOW(), 'Day, Month DD, YYYY');         -- 'Monday  , January    15, 2024'
SELECT TO_CHAR(NOW(), 'IW (IYYY)');                   -- ISO 周
SELECT TO_CHAR(NOW(), 'Mon DD, YYYY');                -- 'Jan 15, 2024'
```

常用格式码:
YYYY: 4位年份   MM: 2位月份   DD: 2位日期
HH24: 24小时    MI: 分钟      SS: 秒
Day: 星期全名   Month: 月份全名
FM: 去除前导零和空格（如 FMDD → '15' 而非 '15'）

## 日期截断 (DATE_TRUNC)


```sql
SELECT DATE_TRUNC('hour', NOW());                     -- 截断到小时
SELECT DATE_TRUNC('day', NOW());                      -- 当天 00:00:00
SELECT DATE_TRUNC('month', NOW());                    -- 当月第一天
SELECT DATE_TRUNC('year', NOW());                     -- 当年第一天
SELECT DATE_TRUNC('week', NOW());                     -- 当周周一
SELECT DATE_TRUNC('quarter', NOW());                  -- 当季第一天
```

## Oracle 兼容: TRUNC

```sql
SELECT TRUNC(SYSDATE, 'YYYY') FROM DUAL;              -- 当年第一天
SELECT TRUNC(SYSDATE, 'MM') FROM DUAL;                -- 当月第一天
SELECT TRUNC(SYSDATE, 'DD') FROM DUAL;                -- 当天零点
```

## 时区处理


```sql
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';            -- 转为指定时区
SELECT NOW() AT TIME ZONE 'UTC';                      -- 转为 UTC
SELECT NOW() AT TIME ZONE 'America/New_York';         -- 转为纽约时区
```

时区转换规则:
TIMESTAMPTZ → AT TIME ZONE 'tz' → TIMESTAMP（去时区信息）
TIMESTAMP → AT TIME ZONE 'tz' → TIMESTAMPTZ（加上时区信息）

## EPOCH 转换


```sql
SELECT EXTRACT(EPOCH FROM NOW());                     -- → Unix 时间戳（浮点秒）
SELECT EXTRACT(EPOCH FROM NOW())::INTEGER;            -- → 整数秒
SELECT TO_TIMESTAMP(1705286400);                      -- Unix → TIMESTAMPTZ
```

## 生成日期序列


```sql
SELECT generate_series(
    '2024-01-01'::DATE,
    '2024-01-31'::DATE,
    '1 day'::INTERVAL
);  -- 生成 2024-01-01 到 2024-01-31 每天一行
```

用途: 生成时间桶用于 LEFT JOIN 填充缺失日期
SELECT gs.bucket::DATE, COUNT(e.id)
FROM generate_series('2024-01-01', '2024-01-31', '1 day'::INTERVAL) AS gs(bucket)
LEFT JOIN events e ON e.event_date = gs.bucket::DATE
GROUP BY gs.bucket;

## 兼容模式差异总结


PostgreSQL 模式:
当前时间: NOW(), CURRENT_TIMESTAMP, CLOCK_TIMESTAMP()
解析:     TO_DATE(), TO_TIMESTAMP()
截断:     DATE_TRUNC()
加减:     INTERVAL 运算
无 DUAL 表
Oracle 模式:
当前时间: SYSDATE, SYSTIMESTAMP (FROM DUAL)
解析:     TO_DATE(), TO_TIMESTAMP() (FROM DUAL)
截断:     TRUNC()
加减:     ADD_MONTHS(), INTERVAL 运算
使用 DUAL 虚表

## 版本演进与注意事项

KingbaseES V8R2: PostgreSQL 兼容日期函数完备
KingbaseES V8R3: Oracle 兼容模式增强（SYSDATE, ADD_MONTHS, TRUNC）
KingbaseES V8R6: 时区处理改进
注意事项:
1. 日期函数与 PostgreSQL 高度兼容
2. Oracle 兼容模式需在初始化时选择，影响函数行为
3. SYSDATE 在 Oracle 模式下是关键字，PG 模式下不可用
4. 时区数据需定期更新（IANA 时区数据库）
5. 确保 COLLATION 和 LC_TIME 设置正确（影响 TO_CHAR 输出）
