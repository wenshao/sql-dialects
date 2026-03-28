# Trino: 日期函数

> 参考资料:
> - [Trino - Date and Time Functions](https://trino.io/docs/current/functions/datetime.html)
> - [Trino - Data Types](https://trino.io/docs/current/language/types.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

```sql
SELECT CURRENT_DATE;                                     -- DATE
SELECT CURRENT_TIME;                                     -- TIME WITH TIME ZONE
SELECT CURRENT_TIMESTAMP;                               -- TIMESTAMP WITH TIME ZONE
SELECT LOCALTIME;                                       -- TIME
SELECT LOCALTIMESTAMP;                                  -- TIMESTAMP
SELECT NOW();                                            -- TIMESTAMP WITH TIME ZONE

```

构造
```sql
SELECT DATE '2024-01-15';                                -- DATE 字面量
SELECT TIME '10:30:00';                                  -- TIME 字面量
SELECT TIMESTAMP '2024-01-15 10:30:00';                  -- TIMESTAMP 字面量
SELECT TIMESTAMP '2024-01-15 10:30:00 Asia/Shanghai';    -- WITH TIME ZONE
SELECT FROM_ISO8601_DATE('2024-01-15');
SELECT FROM_ISO8601_TIMESTAMP('2024-01-15T10:30:00Z');
SELECT DATE_PARSE('2024-01-15', '%Y-%m-%d');

```

日期加减
```sql
SELECT DATE '2024-01-15' + INTERVAL '7' DAY;
SELECT CURRENT_TIMESTAMP + INTERVAL '3' MONTH;
SELECT CURRENT_TIMESTAMP - INTERVAL '2' HOUR;
SELECT DATE_ADD('day', 7, DATE '2024-01-15');
SELECT DATE_ADD('month', 3, CURRENT_DATE);
SELECT DATE_ADD('hour', 2, CURRENT_TIMESTAMP);

```

日期差
```sql
SELECT DATE_DIFF('day', DATE '2024-01-01', DATE '2024-12-31');     -- 365
SELECT DATE_DIFF('month', DATE '2024-01-01', DATE '2024-12-31');  -- 11
SELECT DATE_DIFF('year', DATE '2024-01-01', DATE '2025-06-01');   -- 1
SELECT DATE_DIFF('hour', ts1, ts2);

```

提取
```sql
SELECT EXTRACT(YEAR FROM CURRENT_DATE);                  -- 2024
SELECT EXTRACT(MONTH FROM CURRENT_DATE);                 -- 1
SELECT EXTRACT(DAY FROM CURRENT_DATE);                   -- 15
SELECT EXTRACT(HOUR FROM CURRENT_TIMESTAMP);             -- 10
SELECT EXTRACT(MINUTE FROM CURRENT_TIMESTAMP);           -- 30
SELECT EXTRACT(SECOND FROM CURRENT_TIMESTAMP);           -- 0
SELECT EXTRACT(DOW FROM CURRENT_DATE);                   -- 1=周一
SELECT EXTRACT(DOY FROM CURRENT_DATE);                   -- 一年中第几天
SELECT EXTRACT(WEEK FROM CURRENT_DATE);                  -- ISO 周数
SELECT EXTRACT(QUARTER FROM CURRENT_DATE);               -- 季度
SELECT YEAR(CURRENT_DATE);                               -- 快捷函数
SELECT MONTH(CURRENT_DATE);
SELECT DAY(CURRENT_DATE);
SELECT HOUR(CURRENT_TIMESTAMP);
SELECT MINUTE(CURRENT_TIMESTAMP);
SELECT SECOND(CURRENT_TIMESTAMP);
SELECT DAY_OF_WEEK(CURRENT_DATE);                        -- 1=周一
SELECT DAY_OF_YEAR(CURRENT_DATE);

```

格式化
```sql
SELECT FORMAT_DATETIME(CURRENT_TIMESTAMP, 'yyyy-MM-dd HH:mm:ss');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, '%Y-%m-%d %H:%i:%s');  -- MySQL 兼容

```

解析
```sql
SELECT DATE_PARSE('2024-01-15 10:30:00', '%Y-%m-%d %H:%i:%s');
SELECT FROM_ISO8601_TIMESTAMP('2024-01-15T10:30:00+08:00');

```

截断
```sql
SELECT DATE_TRUNC('month', CURRENT_TIMESTAMP);           -- 月初
SELECT DATE_TRUNC('year', CURRENT_DATE);                 -- 年初
SELECT DATE_TRUNC('hour', CURRENT_TIMESTAMP);            -- 整点
SELECT DATE_TRUNC('week', CURRENT_DATE);                 -- 周初
SELECT DATE_TRUNC('quarter', CURRENT_DATE);              -- 季初

```

最后一天
```sql
SELECT LAST_DAY_OF_MONTH(DATE '2024-01-15');              -- 2024-01-31

```

时区转换
```sql
SELECT CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Shanghai';
SELECT WITH_TIMEZONE(TIMESTAMP '2024-01-15 10:00:00', 'UTC');

```

Unix 时间戳
```sql
SELECT TO_UNIXTIME(CURRENT_TIMESTAMP);                   -- 秒（DOUBLE）
SELECT FROM_UNIXTIME(1705312800);                        -- TIMESTAMP WITH TZ
SELECT FROM_UNIXTIME(1705312800, '%Y-%m-%d');             -- 格式化

```

日期序列
```sql
SELECT * FROM UNNEST(SEQUENCE(DATE '2024-01-01', DATE '2024-01-31', INTERVAL '1' DAY));
SELECT * FROM UNNEST(SEQUENCE(DATE '2024-01-01', DATE '2024-12-31', INTERVAL '1' MONTH));

```

人类可读间隔
```sql
SELECT HUMAN_READABLE_SECONDS(3661);                     -- '1 hour, 1 minute, 1 second'

```

**注意:** EXTRACT DOW 返回 1=周一（ISO 标准）
**注意:** 同时支持 FORMAT_DATETIME（Java 风格）和 DATE_FORMAT（MySQL 风格）
**注意:** SEQUENCE 函数可以生成日期/时间序列
