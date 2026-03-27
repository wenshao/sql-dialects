-- TDSQL: 日期函数 (Date and Time Functions)
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557
--   [3] MySQL 8.0 Reference Manual - Date and Time Functions
--       https://dev.mysql.com/doc/refman/8.0/en/date-and-time-functions.html
--
-- 说明: TDSQL 是腾讯云分布式数据库，日期函数与 MySQL 完全兼容。
--       分布式环境需注意时区一致性和分片间时间同步。

-- ============================================================
-- 1. 获取当前日期时间
-- ============================================================

SELECT NOW();                                         -- 当前日期时间 (YYYY-MM-DD hh:mm:ss)
SELECT CURRENT_TIMESTAMP;                             -- 同 NOW()，SQL 标准语法
SELECT SYSDATE();                                     -- 语句执行时的实际时间
SELECT CURDATE();                                     -- 当前日期 (YYYY-MM-DD)
SELECT CURTIME();                                     -- 当前时间 (hh:mm:ss)
SELECT UTC_TIMESTAMP();                              -- UTC 时间
SELECT UTC_DATE();                                    -- UTC 日期
SELECT UTC_TIME();                                    -- UTC 时间

-- NOW() vs SYSDATE():
--   NOW() 在语句开始时取值，整个语句内不变（replication-safe）
--   SYSDATE() 在函数调用时取值，同一语句内可能不同
--   推荐: 始终使用 NOW()，避免 SYSDATE() 导致的主从数据不一致

-- ============================================================
-- 2. 构造日期时间
-- ============================================================

SELECT MAKEDATE(2024, 100);                           -- '2024-04-09'（年份+天数）
SELECT MAKETIME(10, 30, 0);                           -- '10:30:00'
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');         -- 2024-01-15
SELECT STR_TO_DATE('15/01/2024', '%d/%m/%Y');         -- 2024-01-15
SELECT STR_TO_DATE('Jan 15, 2024', '%b %d, %Y');     -- 2024-01-15
SELECT TIMESTAMP('2024-01-15', '10:30:00');           -- '2024-01-15 10:30:00'

-- ============================================================
-- 3. 日期加减
-- ============================================================

SELECT DATE_ADD('2024-01-15', INTERVAL 1 DAY);        -- '2024-01-16'
SELECT DATE_ADD('2024-01-15', INTERVAL 3 MONTH);      -- '2024-04-15'
SELECT DATE_ADD('2024-01-15', INTERVAL 1 YEAR);       -- '2025-01-15'
SELECT DATE_ADD('2024-01-15', INTERVAL 2 HOUR);       -- '2024-01-15 02:00:00'
SELECT DATE_SUB('2024-01-15', INTERVAL 1 WEEK);       -- '2024-01-08'

-- 复合 INTERVAL
SELECT DATE_ADD('2024-01-15 10:30:00', INTERVAL '1:30' HOUR_MINUTE);  -- '2024-01-15 12:00:00'
SELECT DATE_ADD('2024-01-15', INTERVAL '1 2:30:00' DAY_SECOND);       -- '2024-01-16 02:30:00'

-- ============================================================
-- 4. 日期差值计算
-- ============================================================

SELECT DATEDIFF('2024-12-31', '2024-01-01');          -- 365（天数差）
SELECT TIMEDIFF('10:30:00', '08:00:00');              -- '02:30:00'（时间差）
SELECT TIMESTAMPDIFF(MONTH, '2024-01-01', '2024-06-15');  -- 5（月数差）
SELECT TIMESTAMPDIFF(DAY, '2024-01-01', '2024-06-15');    -- 165（天数差）
SELECT TIMESTAMPDIFF(HOUR, '2024-01-01', '2024-01-02');   -- 24（小时差）
SELECT PERIOD_DIFF(202406, 202401);                   -- 5（月份差，PYYYYMM 格式）

-- ============================================================
-- 5. 提取日期部分
-- ============================================================

SELECT YEAR('2024-01-15');                            -- 2024
SELECT MONTH('2024-01-15');                           -- 1
SELECT DAY('2024-01-15');                             -- 15
SELECT HOUR('10:30:45');                              -- 10
SELECT MINUTE('10:30:45');                            -- 30
SELECT SECOND('10:30:45');                            -- 45
SELECT DAYOFWEEK('2024-01-15');                       -- 2 (1=Sunday, 2=Monday, ...)
SELECT DAYOFYEAR('2024-01-15');                       -- 15
SELECT WEEKDAY('2024-01-15');                         -- 0 (0=Monday, 6=Sunday)
SELECT WEEK('2024-01-15');                            -- 2（ISO 周数）
SELECT QUARTER('2024-04-15');                         -- 2
SELECT EXTRACT(YEAR_MONTH FROM '2024-01-15');         -- 202401
SELECT YEARWEEK('2024-01-15');                        -- 202402（年份+周数）

-- ============================================================
-- 6. 日期格式化
-- ============================================================

SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');       -- '2024-01-15 10:30:00'
SELECT DATE_FORMAT(NOW(), '%d/%m/%Y');                -- '15/01/2024'
SELECT DATE_FORMAT(NOW(), '%W, %M %d, %Y');           -- 'Monday, January 15, 2024'
SELECT DATE_FORMAT(NOW(), '%Y年%m月%d日');              -- '2024年01月15日'
SELECT TIME_FORMAT('10:30:45', '%H:%i:%s');           -- '10:30:45'
SELECT TIME_FORMAT('10:30:45', '%h:%i %p');           -- '10:30 AM'

-- 常用格式码:
--   %Y: 4位年份    %m: 2位月份    %d: 2位日期
--   %H: 24小时    %h: 12小时     %i: 分钟    %s: 秒
--   %W: 星期名    %M: 月名       %p: AM/PM

-- ============================================================
-- 7. 日期截断与月末计算
-- ============================================================

SELECT DATE(NOW());                                   -- 截取日期部分
SELECT LAST_DAY('2024-02-15');                        -- '2024-02-29'（闰年）
SELECT LAST_DAY('2024-01-15');                        -- '2024-01-31'
SELECT DAY(LAST_DAY('2024-02-15'));                   -- 29（当月天数）

-- ============================================================
-- 8. Unix 时间戳转换
-- ============================================================

SELECT UNIX_TIMESTAMP();                              -- 当前 Unix 时间戳（秒）
SELECT UNIX_TIMESTAMP('2024-01-15 10:30:00');        -- 指定时间的 Unix 时间戳
SELECT FROM_UNIXTIME(1705276800);                    -- '2024-01-15 02:00:00'
SELECT FROM_UNIXTIME(1705276800, '%Y-%m-%d');        -- '2024-01-15'（自定义格式）

-- ============================================================
-- 9. 分布式环境注意事项
-- ============================================================

-- 1. 时区一致性: 各分片必须配置相同时区（建议使用 UTC，应用层转换）
--    SHOW VARIABLES LIKE 'time_zone';
--    SET time_zone = '+00:00';  -- 统一 UTC
--
-- 2. NOW() 在主从复制中是安全的（binlog 记录时间戳）
--    SYSDATE() 不安全（可能导致主从数据不一致）
--
-- 3. 分片键不推荐使用日期字段（容易导致热点分片）
--
-- 4. 时间范围查询可能涉及跨分片扫描，注意性能
--
-- 5. 分布式事务中的时间戳由全局时钟服务（GTS）统一分配
--    确保事务提交顺序与时间顺序一致

-- ============================================================
-- 10. 版本兼容性
-- ============================================================
-- MySQL 5.7 / TDSQL: 基础日期函数完备
-- MySQL 8.0 / TDSQL: 精度更高的 fractional seconds 支持
--   确认 TDSQL 底层 MySQL 版本以确定可用功能范围
-- 建议: 使用标准 SQL 语法（EXTRACT、INTERVAL）以保持可移植性
