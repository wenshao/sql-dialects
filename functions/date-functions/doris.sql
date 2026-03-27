-- Apache Doris: 日期函数
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- 当前日期时间
SELECT NOW();                                -- 2024-01-15 10:30:00
SELECT CURRENT_TIMESTAMP();                  -- 同 NOW()
SELECT CURDATE();                            -- 2024-01-15
SELECT CURRENT_DATE();                       -- 同 CURDATE()
SELECT CURTIME();                            -- 10:30:00
SELECT UTC_TIMESTAMP();                      -- UTC 时间

-- 构造日期
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');
SELECT MAKEDATE(2024, 100);                  -- 2024-04-09（第 100 天）

-- 日期加减
SELECT DATE_ADD('2024-01-15', INTERVAL 1 DAY);
SELECT DATE_ADD('2024-01-15', INTERVAL 3 MONTH);
SELECT DATE_SUB('2024-01-15', INTERVAL 1 YEAR);
SELECT ADDDATE('2024-01-15', 7);             -- 加 7 天
SELECT TIMESTAMPADD(HOUR, 2, NOW());
SELECT YEARS_ADD('2024-01-15', 1);           -- Doris 特有
SELECT MONTHS_ADD('2024-01-15', 3);          -- Doris 特有
SELECT DAYS_ADD('2024-01-15', 7);            -- Doris 特有
SELECT HOURS_ADD(NOW(), 2);                  -- Doris 特有

-- 日期差
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
SELECT DAYOFWEEK('2024-01-15');                -- 2（1=周日）
SELECT DAYOFYEAR('2024-01-15');                -- 15
SELECT WEEKOFYEAR('2024-01-15');               -- 3
SELECT QUARTER('2024-06-15');                  -- 2

-- 格式化
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT DATE_FORMAT(NOW(), '%Y年%m月%d日');

-- 截断
SELECT DATE_TRUNC('month', NOW());             -- 月初
SELECT DATE_TRUNC('year', NOW());              -- 年初
SELECT DATE_TRUNC('day', NOW());               -- 当天零点
SELECT DATE_TRUNC('hour', NOW());              -- 整点

-- Unix 时间戳
SELECT UNIX_TIMESTAMP();                       -- 当前时间戳
SELECT UNIX_TIMESTAMP('2024-01-15');           -- 指定时间
SELECT FROM_UNIXTIME(1705276800);              -- 时间戳 -> 日期时间
SELECT FROM_UNIXTIME(1705276800, '%Y-%m-%d');

-- 月末
SELECT LAST_DAY('2024-02-15');                 -- 2024-02-29

-- 日期转星期名
SELECT DAYNAME('2024-01-15');                  -- Monday
SELECT MONTHNAME('2024-01-15');                -- January

-- 注意：Doris 兼容 MySQL 日期函数
-- 注意：额外支持 YEARS_ADD, MONTHS_ADD 等快捷函数
-- 注意：DATE_TRUNC 是常用的日期截断函数
