# Trino: 日期时间类型

> 参考资料:
> - [Trino - Data Types](https://trino.io/docs/current/language/types.html)
> - [Trino - Date and Time Functions](https://trino.io/docs/current/functions/datetime.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

```sql
CREATE TABLE events (
    id           BIGINT,
    event_date   DATE,
    event_time   TIME(3),                 -- 毫秒精度
    local_dt     TIMESTAMP(6),            -- 微秒精度，无时区
    created_at   TIMESTAMP(6) WITH TIME ZONE  -- 微秒精度，带时区
);

```

TIMESTAMP vs TIMESTAMP WITH TIME ZONE:
TIMESTAMP: 不含时区，表示"日历时间"
TIMESTAMP WITH TIME ZONE: 带时区偏移，表示绝对时间点

获取当前时间
```sql
SELECT CURRENT_DATE;                      -- DATE
SELECT CURRENT_TIME;                      -- TIME WITH TIME ZONE
SELECT CURRENT_TIMESTAMP;                -- TIMESTAMP WITH TIME ZONE
SELECT LOCALTIME;                        -- TIME
SELECT LOCALTIMESTAMP;                   -- TIMESTAMP

```

构造日期时间
```sql
SELECT DATE '2024-01-15';                 -- DATE 字面量
SELECT TIME '10:30:00';                   -- TIME 字面量
SELECT TIMESTAMP '2024-01-15 10:30:00';   -- TIMESTAMP 字面量
SELECT TIMESTAMP '2024-01-15 10:30:00 Asia/Shanghai';  -- WITH TIME ZONE

```

日期加减
```sql
SELECT DATE '2024-01-15' + INTERVAL '7' DAY;
SELECT TIMESTAMP '2024-01-15 10:00:00' + INTERVAL '3' MONTH;
SELECT CURRENT_TIMESTAMP - INTERVAL '2' HOUR;
SELECT DATE_ADD('day', 7, DATE '2024-01-15');
SELECT DATE_ADD('month', 3, CURRENT_DATE);

```

日期差
```sql
SELECT DATE_DIFF('day', DATE '2024-01-01', DATE '2024-12-31');    -- 365
SELECT DATE_DIFF('month', DATE '2024-01-01', DATE '2024-12-31'); -- 11

```

提取
```sql
SELECT EXTRACT(YEAR FROM CURRENT_DATE);
SELECT EXTRACT(MONTH FROM CURRENT_DATE);
SELECT EXTRACT(DAY FROM CURRENT_DATE);
SELECT EXTRACT(HOUR FROM CURRENT_TIMESTAMP);
SELECT EXTRACT(DOW FROM CURRENT_DATE);    -- 1=周一
SELECT EXTRACT(DOY FROM CURRENT_DATE);    -- 一年中的第几天
SELECT YEAR(CURRENT_DATE);               -- 快捷函数
SELECT MONTH(CURRENT_DATE);
SELECT DAY(CURRENT_DATE);

```

格式化
```sql
SELECT FORMAT_DATETIME(CURRENT_TIMESTAMP, 'yyyy-MM-dd HH:mm:ss');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, '%Y-%m-%d %H:%i:%s');  -- MySQL 兼容

```

解析
```sql
SELECT DATE_PARSE('2024-01-15', '%Y-%m-%d');
SELECT FROM_ISO8601_TIMESTAMP('2024-01-15T10:30:00Z');
SELECT FROM_ISO8601_DATE('2024-01-15');

```

截断
```sql
SELECT DATE_TRUNC('month', CURRENT_TIMESTAMP);
SELECT DATE_TRUNC('year', CURRENT_DATE);

```

时区转换
```sql
SELECT CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Shanghai';
SELECT WITH_TIMEZONE(TIMESTAMP '2024-01-15 10:00:00', 'UTC');

```

Unix 时间戳
```sql
SELECT TO_UNIXTIME(CURRENT_TIMESTAMP);
SELECT FROM_UNIXTIME(1705312800);

```

**注意:** 精度最高到皮秒（p=12）
**注意:** INTERVAL 有两种：YEAR TO MONTH 和 DAY TO SECOND
**注意:** 底层精度取决于 Connector
