-- SQLite: 日期时间类型
--
-- 参考资料:
--   [1] SQLite Documentation - Date and Time Functions
--       https://www.sqlite.org/lang_datefunc.html
--   [2] SQLite Documentation - Datatypes
--       https://www.sqlite.org/datatype3.html

-- SQLite 没有专门的日期时间类型，使用以下三种存储方式：
-- TEXT: ISO 8601 格式 'YYYY-MM-DD HH:MM:SS.SSS'
-- REAL: Julian day number（儒略日）
-- INTEGER: Unix 时间戳（秒）

CREATE TABLE events (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    event_date TEXT,                  -- '2024-01-15'
    created_at TEXT,                  -- '2024-01-15 10:30:00'
    updated_at INTEGER               -- 1705312200 (Unix timestamp)
);

-- 获取当前时间
SELECT datetime('now');               -- UTC 时间
SELECT datetime('now', 'localtime');  -- 本地时间
SELECT date('now');                   -- 当前日期
SELECT time('now');                   -- 当前时间
SELECT strftime('%s', 'now');         -- Unix 时间戳（TEXT 类型）

-- 日期运算
SELECT datetime('now', '+1 day');
SELECT datetime('now', '-2 hours', '+30 minutes');
SELECT datetime('2024-01-15', '+1 month', 'start of month');  -- 2024-02-01
SELECT julianday('2024-12-31') - julianday('2024-01-01');     -- 天数差

-- 格式化
SELECT strftime('%Y-%m-%d %H:%M:%S', 'now');
SELECT strftime('%Y', 'now');         -- 提取年份
SELECT strftime('%m', 'now');         -- 提取月份
SELECT strftime('%w', 'now');         -- 星期几 (0=周日)

-- Unix 时间戳互转
SELECT datetime(1705312200, 'unixepoch');           -- 时间戳 → 日期时间
SELECT datetime(1705312200, 'unixepoch', 'localtime'); -- 时间戳 → 本地时间
SELECT strftime('%s', '2024-01-15 10:30:00');       -- 日期时间 → 时间戳
