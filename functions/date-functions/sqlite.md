# SQLite: 日期函数

> 参考资料:
> - [SQLite Documentation - Date and Time Functions](https://www.sqlite.org/lang_datefunc.html)

## 核心日期函数（5 个函数覆盖所有需求）

SQLite 只有 5 个日期函数（vs MySQL 的 50+）:
```sql
SELECT date('now');                    -- '2024-01-15'
SELECT time('now');                    -- '10:30:00'
SELECT datetime('now');                -- '2024-01-15 10:30:00'
SELECT julianday('now');               -- 2460324.9375（儒略日）
SELECT strftime('%Y-%m-%d', 'now');    -- '2024-01-15'

-- strftime 格式化（最灵活）:
SELECT strftime('%Y', 'now');          -- 年
SELECT strftime('%m', 'now');          -- 月
SELECT strftime('%d', 'now');          -- 日
SELECT strftime('%H:%M:%S', 'now');    -- 时:分:秒
SELECT strftime('%w', 'now');          -- 星期几（0=周日）
SELECT strftime('%W', 'now');          -- 第几周
SELECT strftime('%j', 'now');          -- 第几天
SELECT strftime('%s', 'now');          -- Unix 时间戳
```

## 修饰符（Modifiers）: 日期计算的核心机制

SQLite 的日期计算通过修饰符链实现（而非独立函数）:
```sql
SELECT datetime('now', '+1 day');              -- 明天
SELECT datetime('now', '-2 hours');            -- 2 小时前
SELECT datetime('now', '+1 month');            -- 一个月后
SELECT datetime('now', '+1 year', '-1 day');   -- 明年的昨天（修饰符可串联）
SELECT datetime('now', 'start of month');      -- 本月第一天
SELECT datetime('now', 'start of year');       -- 本年第一天
SELECT datetime('now', 'start of day');        -- 今天 00:00:00
SELECT datetime('now', 'weekday 0');           -- 下一个周日
SELECT datetime('now', 'localtime');           -- UTC → 本地时间
SELECT datetime('now', 'utc');                 -- 本地时间 → UTC

-- 组合计算:
SELECT datetime('now', 'start of month', '+1 month', '-1 day');
-- → 本月最后一天

SELECT datetime('now', '-1 month', 'start of month');
```

→ 上个月第一天

设计分析:
  修饰符链是 SQLite 独特的日期计算方式。
  对比 MySQL: DATE_ADD(date, INTERVAL 1 DAY)
  对比 PostgreSQL: date + INTERVAL '1 day'
  对比 BigQuery: DATE_ADD(date, INTERVAL 1 DAY)
  SQLite 的修饰符更像管道操作（date | +1 day | start of month）

## 日期差计算

天数差:
```sql
SELECT julianday('2024-12-31') - julianday('2024-01-01');  -- 365.0

-- 秒数差:
SELECT strftime('%s', '2024-01-15 12:00:00') - strftime('%s', '2024-01-15 10:00:00');
```

→ 7200（2 小时 = 7200 秒）

月数差（需要手动计算）:
SQLite 没有 DATEDIFF 函数!
需要: (year2 - year1) * 12 + (month2 - month1)

## Unix 时间戳操作

当前时间戳
```sql
SELECT strftime('%s', 'now');                       -- '1705312200'

-- 时间戳转日期
SELECT datetime(1705312200, 'unixepoch');            -- UTC
SELECT datetime(1705312200, 'unixepoch', 'localtime'); -- 本地时间

-- 3.38.0+: unixepoch() 函数
SELECT unixepoch('now');                             -- 整数时间戳
```

## 对比与引擎开发者启示

SQLite 日期函数的设计:
  (1) 只有 5 个核心函数 → 极简
  (2) 修饰符链 → 灵活的日期计算管道
  (3) 无专用日期类型 → TEXT/INTEGER/REAL 存储
  (4) 无 DATEDIFF → 手动计算

对引擎开发者的启示:
  修饰符链是优雅的设计（5 个函数 + 修饰符 > 50 个独立函数）。
  但缺少 DATEDIFF 和 DATE_TRUNC 是实际使用的痛点。
  嵌入式引擎应至少提供: 日期差计算 + 日期截断 + 格式化。
