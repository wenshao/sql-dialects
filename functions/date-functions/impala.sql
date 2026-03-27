-- Apache Impala: 日期函数
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- 当前日期时间
SELECT NOW();                                -- TIMESTAMP
SELECT CURRENT_TIMESTAMP();                  -- 同 NOW()
SELECT CURRENT_DATE();                       -- 日期字符串
SELECT UTC_TIMESTAMP();                      -- UTC 时间

-- 构造日期
SELECT CAST('2024-01-15' AS TIMESTAMP);
SELECT CAST('2024-01-15' AS DATE);
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT TO_DATE('2024-01-15', 'yyyy-MM-dd');

-- 日期加减
SELECT DATE_ADD(CAST('2024-01-15' AS TIMESTAMP), 7);
SELECT DATE_ADD(CAST('2024-01-15' AS TIMESTAMP), INTERVAL 1 MONTH);
SELECT DATE_ADD(CAST('2024-01-15' AS TIMESTAMP), INTERVAL 2 HOURS);
SELECT DATE_SUB(CAST('2024-01-15' AS TIMESTAMP), 7);
SELECT ADDDATE('2024-01-15', 7);
SELECT SUBDATE('2024-01-15', 7);
SELECT MONTHS_ADD('2024-01-15', 3);
SELECT MONTHS_SUB('2024-01-15', 3);
SELECT YEARS_ADD('2024-01-15', 1);
SELECT YEARS_SUB('2024-01-15', 1);
SELECT DAYS_ADD('2024-01-15', 7);
SELECT DAYS_SUB('2024-01-15', 7);

-- 日期差
SELECT DATEDIFF(CAST('2024-12-31' AS TIMESTAMP), CAST('2024-01-01' AS TIMESTAMP));
-- 返回天数
SELECT MONTHS_BETWEEN('2024-06-15', '2024-01-01');  -- 5.x

-- 提取
SELECT YEAR('2024-01-15');
SELECT MONTH('2024-01-15');
SELECT DAY('2024-01-15');
SELECT DAYOFMONTH('2024-01-15');             -- 同 DAY
SELECT HOUR(NOW());
SELECT MINUTE(NOW());
SELECT SECOND(NOW());
SELECT DAYOFWEEK('2024-01-15');              -- 1=周日
SELECT DAYOFYEAR('2024-01-15');
SELECT WEEKOFYEAR('2024-01-15');
SELECT QUARTER('2024-06-15');                -- 2
SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(MONTH FROM CAST('2024-01-15' AS TIMESTAMP));

-- 格式化
SELECT FROM_TIMESTAMP(NOW(), 'yyyy-MM-dd HH:mm:ss');
SELECT DATE_FORMAT(NOW(), 'yyyy-MM-dd');
-- 注意：使用 Java SimpleDateFormat 格式

-- 截断
SELECT TRUNC(NOW(), 'YEAR');                 -- 年初
SELECT TRUNC(NOW(), 'MONTH');                -- 月初
SELECT TRUNC(NOW(), 'DD');                   -- 当天零点
SELECT TRUNC(NOW(), 'HH');                   -- 整点

-- Unix 时间戳
SELECT UNIX_TIMESTAMP();
SELECT UNIX_TIMESTAMP('2024-01-15 10:00:00');
SELECT UNIX_TIMESTAMP('2024-01-15', 'yyyy-MM-dd');
SELECT FROM_UNIXTIME(1705276800);
SELECT FROM_UNIXTIME(1705276800, 'yyyy-MM-dd');

-- 时区转换
SELECT FROM_UTC_TIMESTAMP(NOW(), 'Asia/Shanghai');
SELECT TO_UTC_TIMESTAMP(NOW(), 'Asia/Shanghai');

-- 最后一天
SELECT LAST_DAY(CAST('2024-02-15' AS TIMESTAMP));    -- 2024-02-29
SELECT NEXT_DAY(CAST('2024-01-15' AS TIMESTAMP), 'Monday');

-- 日期名
SELECT DAYNAME('2024-01-15');                -- Monday
SELECT MONTHNAME('2024-01-15');              -- January

-- 注意：Impala 日期函数与 Hive 兼容
-- 注意：格式化使用 Java SimpleDateFormat（yyyy-MM-dd 而非 %Y-%m-%d）
-- 注意：时区通过 FROM_UTC_TIMESTAMP / TO_UTC_TIMESTAMP 转换
