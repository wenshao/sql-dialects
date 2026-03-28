-- Apache Doris: 日期函数
--
-- 参考资料:
--   [1] Doris Documentation - Date Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- ============================================================
-- 1. 当前日期时间
-- ============================================================
SELECT NOW(), CURRENT_TIMESTAMP(), CURDATE(), CURRENT_DATE();
SELECT CURTIME(), UTC_TIMESTAMP();

-- ============================================================
-- 2. 日期加减
-- ============================================================
SELECT DATE_ADD('2024-01-15', INTERVAL 1 DAY);
SELECT DATE_ADD('2024-01-15', INTERVAL 3 MONTH);
SELECT DATE_SUB('2024-01-15', INTERVAL 1 YEAR);
SELECT TIMESTAMPADD(HOUR, 2, NOW());

-- Doris 特有快捷函数
SELECT YEARS_ADD('2024-01-15', 1);
SELECT MONTHS_ADD('2024-01-15', 3);
SELECT DAYS_ADD('2024-01-15', 7);
SELECT HOURS_ADD(NOW(), 2);

-- ============================================================
-- 3. 日期差
-- ============================================================
SELECT DATEDIFF('2024-12-31', '2024-01-01');   -- 365 天
SELECT TIMESTAMPDIFF(MONTH, '2024-01-01', '2024-06-15');

-- ============================================================
-- 4. 提取
-- ============================================================
SELECT YEAR('2024-01-15'), MONTH('2024-01-15'), DAY('2024-01-15');
SELECT HOUR(NOW()), MINUTE(NOW()), SECOND(NOW());
SELECT DAYOFWEEK('2024-01-15'), DAYOFYEAR('2024-01-15');
SELECT WEEKOFYEAR('2024-01-15'), QUARTER('2024-06-15');

-- ============================================================
-- 5. 格式化
-- ============================================================
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

-- ============================================================
-- 6. DATE_TRUNC (分析引擎常用)
-- ============================================================
SELECT DATE_TRUNC('month', NOW());   -- 月初
SELECT DATE_TRUNC('year', NOW());    -- 年初
SELECT DATE_TRUNC('day', NOW());     -- 当天零点
SELECT DATE_TRUNC('hour', NOW());    -- 整点

-- 对比:
--   StarRocks:  date_trunc 完全相同(同源)
--   ClickHouse: toStartOfMonth/toStartOfDay(函数名不同)
--   BigQuery:   DATE_TRUNC / TIMESTAMP_TRUNC
--   MySQL:      无 DATE_TRUNC(需要 DATE_FORMAT + CAST 组合)

-- ============================================================
-- 7. Unix 时间戳
-- ============================================================
SELECT UNIX_TIMESTAMP();
SELECT UNIX_TIMESTAMP('2024-01-15');
SELECT FROM_UNIXTIME(1705276800);
SELECT FROM_UNIXTIME(1705276800, '%Y-%m-%d');

-- ============================================================
-- 8. 其他
-- ============================================================
SELECT LAST_DAY('2024-02-15');    -- 2024-02-29
SELECT DAYNAME('2024-01-15');     -- Monday
SELECT MONTHNAME('2024-01-15');   -- January
SELECT MAKEDATE(2024, 100);      -- 2024-04-09
