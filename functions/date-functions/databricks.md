# Databricks SQL: 日期函数

> 参考资料:
> - [Databricks SQL Language Reference](https://docs.databricks.com/en/sql/language-manual/index.html)
> - [Databricks SQL - Built-in Functions](https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html)
> - [Delta Lake Documentation](https://docs.delta.io/latest/index.html)


当前日期时间
```sql
SELECT current_date();                                -- DATE
SELECT current_timestamp();                           -- TIMESTAMP
SELECT now();                                         -- TIMESTAMP（同上）
```


构造日期
```sql
SELECT DATE '2024-01-15';
SELECT TIMESTAMP '2024-01-15 10:30:00';
SELECT MAKE_DATE(2024, 1, 15);
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);
SELECT TO_DATE('2024-01-15', 'yyyy-MM-dd');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT TO_TIMESTAMP('Jan 15, 2024', 'MMM dd, yyyy');
```


日期加减
```sql
SELECT DATE_ADD('2024-01-15', 7);                     -- 加 7 天
SELECT DATE_SUB('2024-01-15', 7);                     -- 减 7 天
SELECT DATEADD(MONTH, 3, '2024-01-15');
SELECT DATEADD(YEAR, 1, current_date());
SELECT DATEADD(HOUR, 2, current_timestamp());
SELECT ADD_MONTHS('2024-01-15', 3);
SELECT current_date() + INTERVAL 7 DAYS;
SELECT current_timestamp() - INTERVAL '3' MONTHS;
```


日期差
```sql
SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31');    -- 365
SELECT DATEDIFF(MONTH, '2024-01-01', '2024-12-31');  -- 11
SELECT DATEDIFF(YEAR, '2024-01-01', '2025-12-31');   -- 1
SELECT MONTHS_BETWEEN('2024-12-31', '2024-01-01');   -- 11.97
```


提取
```sql
SELECT YEAR('2024-01-15');
SELECT MONTH('2024-01-15');
SELECT DAY('2024-01-15');
SELECT DAYOFMONTH('2024-01-15');                      -- 同 DAY
SELECT HOUR(current_timestamp());
SELECT MINUTE(current_timestamp());
SELECT SECOND(current_timestamp());
SELECT DAYOFWEEK('2024-01-15');                       -- 1=周日
SELECT DAYOFYEAR('2024-01-15');
SELECT WEEKOFYEAR('2024-01-15');
SELECT QUARTER('2024-01-15');
SELECT EXTRACT(YEAR FROM current_date());
SELECT EXTRACT(EPOCH FROM current_timestamp());
```


格式化
```sql
SELECT DATE_FORMAT(current_timestamp(), 'yyyy-MM-dd HH:mm:ss');
SELECT DATE_FORMAT(current_timestamp(), 'EEEE, MMMM dd, yyyy');
SELECT DATE_FORMAT(current_timestamp(), 'yyyy/MM/dd');
```


截断
```sql
SELECT DATE_TRUNC('MONTH', current_timestamp());     -- 月初
SELECT DATE_TRUNC('YEAR', current_date());           -- 年初
SELECT DATE_TRUNC('HOUR', current_timestamp());      -- 整点
SELECT DATE_TRUNC('WEEK', current_date());           -- 周一
SELECT TRUNC(current_date(), 'MM');                  -- 月初
```


时区转换
```sql
SELECT FROM_UTC_TIMESTAMP(current_timestamp(), 'Asia/Shanghai');
SELECT TO_UTC_TIMESTAMP('2024-01-15 10:30:00', 'Asia/Shanghai');
```


月末
```sql
SELECT LAST_DAY('2024-01-15');                        -- 2024-01-31
```


下一个星期几
```sql
SELECT NEXT_DAY('2024-01-15', 'Monday');
```


Unix 时间戳
```sql
SELECT UNIX_TIMESTAMP();                              -- 当前秒数
SELECT UNIX_TIMESTAMP('2024-01-15', 'yyyy-MM-dd');
SELECT UNIX_MILLIS(current_timestamp());              -- 毫秒
SELECT UNIX_MICROS(current_timestamp());              -- 微秒
SELECT FROM_UNIXTIME(1705276800);                     -- 秒 → TIMESTAMP
SELECT TIMESTAMP_MILLIS(1705276800000);               -- 毫秒 → TIMESTAMP
SELECT TIMESTAMP_MICROS(1705276800000000);            -- 微秒 → TIMESTAMP
```


日期序列生成
```sql
SELECT EXPLODE(SEQUENCE(DATE '2024-01-01', DATE '2024-01-31', INTERVAL 1 DAY)) AS d;
SELECT EXPLODE(SEQUENCE(DATE '2024-01-01', DATE '2024-12-01', INTERVAL 1 MONTH)) AS d;
```


安全转换
```sql
SELECT TRY_TO_TIMESTAMP('invalid');                   -- 返回 NULL
SELECT TRY_CAST('2024-01-15' AS DATE);
```


注意：日期格式使用 Java SimpleDateFormat 模式
注意：SEQUENCE + EXPLODE 用于生成日期序列
注意：时区名称使用 IANA 数据库
注意：UNIX_TIMESTAMP 返回秒，UNIX_MILLIS 返回毫秒
注意：DATE_TRUNC 支持 YEAR/MONTH/WEEK/DAY/HOUR/MINUTE/SECOND
注意：TIMESTAMP 精度为微秒
