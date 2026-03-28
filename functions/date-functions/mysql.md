# MySQL: 日期函数

> 参考资料:
> - [MySQL 8.0 Reference Manual - Date and Time Functions](https://dev.mysql.com/doc/refman/8.0/en/date-and-time-functions.html)
> - [MySQL 8.0 Reference Manual - Date and Time Types](https://dev.mysql.com/doc/refman/8.0/en/date-and-time-types.html)

当前日期时间
```sql
SELECT NOW();                                -- 2024-01-15 10:30:00
SELECT CURRENT_TIMESTAMP;                    -- 同 NOW()
SELECT SYSDATE();                            -- 实际执行时间（NOW() 在语句开始时固定）
SELECT CURDATE();                            -- 2024-01-15
SELECT CURTIME();                            -- 10:30:00
SELECT UTC_TIMESTAMP();                      -- UTC 时间

-- 构造日期
SELECT MAKEDATE(2024, 100);                  -- 2024-04-09（第 100 天）
SELECT MAKETIME(10, 30, 0);                  -- 10:30:00
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');
```

日期加减
```sql
SELECT DATE_ADD('2024-01-15', INTERVAL 1 DAY);
SELECT DATE_ADD('2024-01-15', INTERVAL 3 MONTH);
SELECT DATE_ADD('2024-01-15 10:00:00', INTERVAL '1:30' HOUR_MINUTE);
SELECT DATE_SUB('2024-01-15', INTERVAL 1 YEAR);
SELECT '2024-01-15' + INTERVAL 7 DAY;         -- 简写
```

日期差
```sql
SELECT DATEDIFF('2024-12-31', '2024-01-01');   -- 365（天数）
SELECT TIMESTAMPDIFF(MONTH, '2024-01-01', '2024-06-15'); -- 5
SELECT TIMESTAMPDIFF(HOUR, '2024-01-01 00:00:00', '2024-01-02 12:00:00'); -- 36
SELECT TIMEDIFF('12:00:00', '10:30:00');       -- 01:30:00

-- 提取
SELECT YEAR('2024-01-15');                     -- 2024
SELECT MONTH('2024-01-15');                    -- 1
SELECT DAY('2024-01-15');                      -- 15
SELECT HOUR('10:30:45');                       -- 10
SELECT MINUTE('10:30:45');                     -- 30
SELECT SECOND('10:30:45');                     -- 45
SELECT EXTRACT(YEAR FROM '2024-01-15');
SELECT DAYOFWEEK('2024-01-15');                -- 2（1=周日）
SELECT DAYOFYEAR('2024-01-15');                -- 15
SELECT WEEKDAY('2024-01-15');                  -- 0（0=周一）
SELECT WEEK('2024-01-15');                     -- 3
```

格式化
```sql
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT DATE_FORMAT(NOW(), '%W, %M %d, %Y');    -- Monday, January 15, 2024
SELECT TIME_FORMAT('10:30:45', '%h:%i %p');    -- 10:30 AM
```

截断
```sql
SELECT DATE(NOW());                            -- 去掉时间部分
SELECT LAST_DAY('2024-02-15');                 -- 2024-02-29（月末）

-- Unix 时间戳
SELECT UNIX_TIMESTAMP();                       -- 当前时间戳
SELECT UNIX_TIMESTAMP('2024-01-15');           -- 指定时间的时间戳
SELECT FROM_UNIXTIME(1705276800);              -- 时间戳 → 日期时间
SELECT FROM_UNIXTIME(1705276800, '%Y-%m-%d');  -- 带格式化
```
