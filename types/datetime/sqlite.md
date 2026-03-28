# SQLite: 日期时间类型

> 参考资料:
> - [SQLite Documentation - Date and Time Functions](https://www.sqlite.org/lang_datefunc.html)
> - [SQLite Documentation - Datatypes](https://www.sqlite.org/datatype3.html)

## SQLite 没有专用的日期时间类型（为什么）

SQLite 没有 DATE、TIME、DATETIME、TIMESTAMP 类型。
日期时间存储为 TEXT、REAL 或 INTEGER:

(a) TEXT: ISO 8601 字符串  → '2024-01-15 10:30:00'
(b) REAL: Julian Day 数字  → 2460324.4375
(c) INTEGER: Unix 时间戳   → 1705312200

为什么没有专用类型?
SQLite 只有 5 种存储类（NULL/INTEGER/REAL/TEXT/BLOB）。
添加 DATE/TIME 类型会增加存储类的数量，违反极简设计原则。
日期时间函数可以操作以上 3 种格式，不需要专用存储类型。

## 三种存储方式对比

```sql
CREATE TABLE events (
    id          INTEGER PRIMARY KEY,
    -- 方式 1: TEXT（最常用，可读性最好）
    created_text TEXT DEFAULT (datetime('now')),
    -- 方式 2: INTEGER（Unix 时间戳，节省空间）
    created_unix INTEGER DEFAULT (strftime('%s', 'now')),
    -- 方式 3: REAL（Julian Day，适合日期计算）
    created_jd   REAL DEFAULT (julianday('now'))
);
```

推荐: TEXT 格式（ISO 8601）
  优点: 可读性好，可以用字符串比较排序
  缺点: 占空间较多（19-23 字节 vs INTEGER 的 8 字节）

推荐: INTEGER（Unix 时间戳）用于高性能场景
  优点: 紧凑（8 字节），排序/比较快
  缺点: 可读性差，2038 年问题（32位系统）

## 日期时间函数

获取当前时间（不同格式）
```sql
SELECT datetime('now');              -- '2024-01-15 10:30:00'
SELECT date('now');                  -- '2024-01-15'
SELECT time('now');                  -- '10:30:00'
SELECT strftime('%s', 'now');        -- '1705312200'（Unix 时间戳）
SELECT julianday('now');             -- 2460324.4375

-- 时间计算
SELECT datetime('now', '+1 day');
SELECT datetime('now', '-2 hours');
SELECT datetime('now', '+1 month', 'start of month');
SELECT datetime('now', 'weekday 0');  -- 下一个周日
```

格式化
```sql
SELECT strftime('%Y-%m-%d %H:%M', '2024-01-15 10:30:00');
SELECT strftime('%W', '2024-01-15');  -- 第几周
```

Unix 时间戳转换
```sql
SELECT datetime(1705312200, 'unixepoch');           -- UTC
SELECT datetime(1705312200, 'unixepoch', 'localtime'); -- 本地时间
```

## 时区处理（SQLite 的局限）

SQLite 的日期函数默认使用 UTC。
可以用 'localtime' 和 'utc' 修饰符转换:
```sql
SELECT datetime('now');                  -- UTC
SELECT datetime('now', 'localtime');     -- 本地时间
SELECT datetime('2024-01-15', 'utc');    -- 本地时间转 UTC

-- 局限: 没有 TIMESTAMP WITH TIME ZONE 类型。
-- 不能存储时区信息（不知道 '2024-01-15 10:30:00' 是哪个时区）。
-- 最佳实践: 始终存储 UTC，应用层转换时区。
```

## 对比与引擎开发者启示

SQLite 日期时间的设计:
- (1) 无专用类型 → TEXT/INTEGER/REAL 三选一
- (2) 函数丰富 → datetime()/strftime() 覆盖大部分需求
- (3) 无时区类型 → 存 UTC + 应用层转换
- (4) 三种格式互操作 → 函数可以解析任意格式

对比:
- **MySQL**: DATETIME / TIMESTAMP（带时区转换）
- **PostgreSQL**: TIMESTAMP / TIMESTAMPTZ（最完善的时区支持）
- **ClickHouse**: DateTime / DateTime64（纳秒精度）
- **BigQuery**: DATETIME / TIMESTAMP / DATE / TIME（4 种类型）

对引擎开发者的启示:
  - SQLite 证明了"无专用日期类型 + 强大的日期函数"是可行的方案。
  - 但缺少时区支持是明显的不足。
- **现代引擎至少需要**: TIMESTAMP WITH TIME ZONE + 纳秒精度。
