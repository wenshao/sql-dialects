-- SQLite: 日期函数
--
-- 参考资料:
--   [1] SQLite Documentation - Date and Time Functions
--       https://www.sqlite.org/lang_datefunc.html
--   [2] SQLite Documentation - Core Functions
--       https://www.sqlite.org/lang_corefunc.html

-- 5 个核心函数：date(), time(), datetime(), julianday(), strftime()
-- 3.38.0+: unixepoch()

-- 当前日期时间
SELECT datetime('now');                          -- UTC
SELECT datetime('now', 'localtime');             -- 本地时间
SELECT date('now');                              -- 日期
SELECT time('now');                              -- 时间
SELECT julianday('now');                         -- 儒略日
SELECT unixepoch('now');                         -- Unix 时间戳（3.38.0+）
SELECT strftime('%s', 'now');                    -- Unix 时间戳（TEXT 类型）

-- 日期加减（用修饰符）
SELECT datetime('now', '+1 day');
SELECT datetime('now', '-3 months');
SELECT datetime('now', '+2 hours', '+30 minutes');
SELECT date('now', '+1 year', 'start of month');  -- 明年这个月的月初
SELECT date('now', 'start of year');              -- 今年年初
SELECT date('now', 'start of month', '+1 month', '-1 day'); -- 本月月末

-- 日期差
SELECT julianday('2024-12-31') - julianday('2024-01-01');  -- 365.0（天数）
SELECT CAST((julianday('2024-12-31') - julianday('2024-01-01')) AS INTEGER); -- 365

-- 提取（全部通过 strftime）
SELECT strftime('%Y', 'now');                    -- 年
SELECT strftime('%m', 'now');                    -- 月
SELECT strftime('%d', 'now');                    -- 日
SELECT strftime('%H', 'now');                    -- 时
SELECT strftime('%M', 'now');                    -- 分
SELECT strftime('%S', 'now');                    -- 秒
SELECT strftime('%w', 'now');                    -- 星期几（0=周日）
SELECT strftime('%j', 'now');                    -- 一年中的第几天
SELECT strftime('%W', 'now');                    -- 一年中的第几周

-- 格式化
SELECT strftime('%Y-%m-%d %H:%M:%S', 'now');
SELECT strftime('%Y/%m/%d', '2024-01-15');

-- Unix 时间戳互转
SELECT datetime(1705276800, 'unixepoch');                   -- → 日期时间
SELECT datetime(1705276800, 'unixepoch', 'localtime');      -- → 本地时间
SELECT strftime('%s', '2024-01-15 10:30:00');                -- → 时间戳

-- 注意：所有日期函数都返回 TEXT 类型
-- 注意：没有专门的 EXTRACT()、DATEADD()、DATEDIFF() 函数
-- 注意：不支持时区名称，只支持 'localtime' 和 'utc' 修饰符
