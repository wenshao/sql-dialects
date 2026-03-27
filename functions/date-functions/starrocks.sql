-- StarRocks: 日期函数
--
-- 参考资料:
--   [1] StarRocks - Date Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/date-time-functions/
--   [2] StarRocks SQL Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/

-- 当前日期时间
SELECT CURRENT_DATE();                                   -- DATE
SELECT CURDATE();                                       -- DATE（别名）
SELECT NOW();                                            -- DATETIME
SELECT CURRENT_TIMESTAMP();                             -- DATETIME
SELECT CURTIME();                                       -- 时间字符串
SELECT UTC_TIMESTAMP();                                 -- UTC 时间

-- 构造
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS DATETIME);
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');
SELECT MAKEDATE(2024, 15);                               -- 第 15 天 -> 2024-01-15

-- 日期加减
SELECT DATE_ADD('2024-01-15', INTERVAL 7 DAY);
SELECT DATE_SUB('2024-01-15', INTERVAL 1 MONTH);
SELECT ADDDATE('2024-01-15', 7);                          -- 加 7 天
SELECT SUBDATE('2024-01-15', 7);                          -- 减 7 天
SELECT TIMESTAMPADD(HOUR, 2, NOW());
SELECT TIMESTAMPADD(MINUTE, 30, NOW());
SELECT MONTHS_ADD('2024-01-15', 3);                      -- 加 3 月
SELECT YEARS_ADD('2024-01-15', 1);                       -- 加 1 年

-- 日期差
SELECT DATEDIFF('2024-12-31', '2024-01-01');              -- 365（天数）
SELECT TIMESTAMPDIFF(MONTH, '2024-01-01', '2024-12-31');  -- 11
SELECT TIMESTAMPDIFF(HOUR, ts1, ts2);
SELECT TIMEDIFF('12:30:00', '10:00:00');                  -- 02:30:00

-- 提取
SELECT YEAR('2024-01-15');                                -- 2024
SELECT MONTH('2024-01-15');                               -- 1
SELECT DAY('2024-01-15');                                 -- 15
SELECT DAYOFMONTH('2024-01-15');                          -- 15
SELECT HOUR(NOW());                                      -- 10
SELECT MINUTE(NOW());                                    -- 30
SELECT SECOND(NOW());                                    -- 0
SELECT DAYOFWEEK('2024-01-15');                           -- 1=周日（MySQL 兼容）
SELECT DAYOFYEAR('2024-01-15');                           -- 15
SELECT WEEKOFYEAR('2024-01-15');                          -- 第几周
SELECT QUARTER('2024-01-15');                             -- 1

-- 格式化
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT DATE_FORMAT(NOW(), '%Y年%m月%d日');
SELECT TIME_FORMAT(NOW(), '%H:%i:%s');

-- 解析
SELECT STR_TO_DATE('15/01/2024', '%d/%m/%Y');
SELECT STR_TO_DATE('10:30:00', '%H:%i:%s');

-- 截断
SELECT DATE_TRUNC('month', NOW());                        -- 月初
SELECT DATE_TRUNC('year', NOW());                         -- 年初
SELECT DATE_TRUNC('day', NOW());                          -- 当天零点
SELECT DATE_TRUNC('hour', NOW());                         -- 整点
SELECT DATE_TRUNC('week', NOW());                         -- 周初

-- 最后一天
SELECT LAST_DAY('2024-01-15');                            -- 2024-01-31

-- Unix 时间戳
SELECT UNIX_TIMESTAMP();                                 -- 当前秒数
SELECT UNIX_TIMESTAMP('2024-01-15 10:00:00');
SELECT FROM_UNIXTIME(1705312800);                        -- DATETIME
SELECT FROM_UNIXTIME(1705312800, '%Y-%m-%d');             -- 格式化

-- 时间转换
SELECT CONVERT_TZ('2024-01-15 10:00:00', 'UTC', 'Asia/Shanghai');
SELECT UTC_TIMESTAMP();                                  -- UTC 当前时间

-- 日期判断
SELECT DAYNAME('2024-01-15');                             -- 'Monday'
SELECT MONTHNAME('2024-01-15');                           -- 'January'

-- 注意：与 MySQL 日期函数高度兼容
-- 注意：DATE_TRUNC 是 StarRocks 扩展（MySQL 没有）
-- 注意：DAYOFWEEK 返回 1=周日（MySQL 兼容）
-- 注意：格式符使用 MySQL 风格（%Y, %m, %d, %H, %i, %s）
