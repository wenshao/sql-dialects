-- SQL 标准: 日期函数
--
-- 参考资料:
--   [1] ISO/IEC 9075 SQL Standard
--       https://www.iso.org/standard/76583.html
--   [2] Modern SQL - by Markus Winand
--       https://modern-sql.com/
--   [3] Modern SQL - Temporal Features
--       https://modern-sql.com/feature/temporal

-- SQL-92 (SQL2):
-- CURRENT_DATE: 当前日期
-- CURRENT_TIME: 当前时间（带时区）
-- CURRENT_TIMESTAMP: 当前日期时间（带时区）
-- EXTRACT: 提取日期/时间部分
-- CAST: 类型转换

SELECT CURRENT_DATE;                                     -- DATE
SELECT CURRENT_TIME;                                     -- TIME WITH TIME ZONE
SELECT CURRENT_TIMESTAMP;                               -- TIMESTAMP WITH TIME ZONE

-- EXTRACT（SQL-92）
SELECT EXTRACT(YEAR FROM CURRENT_DATE);
SELECT EXTRACT(MONTH FROM CURRENT_DATE);
SELECT EXTRACT(DAY FROM CURRENT_DATE);
SELECT EXTRACT(HOUR FROM CURRENT_TIMESTAMP);
SELECT EXTRACT(MINUTE FROM CURRENT_TIMESTAMP);
SELECT EXTRACT(SECOND FROM CURRENT_TIMESTAMP);
SELECT EXTRACT(TIMEZONE_HOUR FROM CURRENT_TIMESTAMP);    -- 时区偏移（小时）
SELECT EXTRACT(TIMEZONE_MINUTE FROM CURRENT_TIMESTAMP);  -- 时区偏移（分钟）

-- INTERVAL 运算（SQL-92）
SELECT CURRENT_DATE + INTERVAL '7' DAY;
SELECT CURRENT_TIMESTAMP - INTERVAL '2' HOUR;
SELECT CURRENT_DATE + INTERVAL '3' MONTH;
SELECT CURRENT_TIMESTAMP + INTERVAL '1' YEAR;

-- INTERVAL 类型（SQL-92）
-- INTERVAL YEAR TO MONTH
-- INTERVAL DAY TO SECOND
SELECT INTERVAL '1-6' YEAR TO MONTH;                    -- 1 年 6 个月
SELECT INTERVAL '3 04:30:00' DAY TO SECOND;             -- 3 天 4 小时 30 分

-- 类型转换（SQL-92）
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('10:30:00' AS TIME);
SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);

-- SQL:1999 (SQL3):
-- LOCALTIME: 当前时间（无时区）
-- LOCALTIMESTAMP: 当前日期时间（无时区）
SELECT LOCALTIME;                                        -- TIME
SELECT LOCALTIMESTAMP;                                  -- TIMESTAMP

-- SQL:2003:
-- 无日期函数重大变化

-- SQL:2008:
-- 无日期函数重大变化

-- SQL:2011:
-- 无日期函数重大变化

-- SQL:2016:
-- 无日期函数重大变化

-- SQL:2023:
-- 无日期函数重大变化

-- 注意：标准中没有 DATE_ADD / DATE_SUB 函数（使用 + / - INTERVAL）
-- 注意：标准中没有 DATEDIFF / DATE_DIFF 函数
-- 注意：标准中没有 DATE_TRUNC 函数
-- 注意：标准中没有 TO_CHAR / FORMAT_DATETIME 格式化函数
-- 注意：标准中没有 Unix 时间戳函数
-- 注意：标准中没有 NOW() 函数（使用 CURRENT_TIMESTAMP）
-- 注意：标准中 EXTRACT 只定义了 YEAR/MONTH/DAY/HOUR/MINUTE/SECOND/TIMEZONE_*
-- 注意：实际使用中大多数日期函数都是各厂商扩展
