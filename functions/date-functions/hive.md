# Hive: 日期函数

> 参考资料:
> - [1] Apache Hive - Date Functions
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-DateFunctions
> - [2] Apache Hive - Data Types
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types


## 1. 当前日期时间

```sql
SELECT CURRENT_DATE;                                          -- DATE (2.0+)
SELECT CURRENT_TIMESTAMP;                                    -- TIMESTAMP (2.0+)
SELECT UNIX_TIMESTAMP();                                     -- Unix 秒级时间戳
SELECT FROM_UNIXTIME(UNIX_TIMESTAMP());                      -- 转为字符串

```

## 2. 日期构造与转换

```sql
SELECT TO_DATE('2024-01-15 10:30:00');                        -- DATE (提取日期部分)
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);

```

Unix 时间戳互转

```sql
SELECT UNIX_TIMESTAMP('2024-01-15 10:00:00', 'yyyy-MM-dd HH:mm:ss');
SELECT FROM_UNIXTIME(1705312800);
SELECT FROM_UNIXTIME(1705312800, 'yyyy-MM-dd');

```

 设计分析: STRING 类型作为日期的主要载体
 Hive 的日期函数大多接受 STRING 参数（如 '2024-01-15'），内部自动解析。
 这源于 Schema-on-Read: 数据文件中的日期通常是字符串格式，
 Hive 在查询时隐式转换而非存储时强制类型。
 对比: PostgreSQL/MySQL 要求严格的 DATE/TIMESTAMP 类型，隐式转换更少。

## 3. 日期加减

```sql
SELECT DATE_ADD('2024-01-15', 7);                             -- 加 7 天
SELECT DATE_SUB('2024-01-15', 7);                             -- 减 7 天
SELECT ADD_MONTHS('2024-01-15', 3);                           -- 加 3 月
SELECT ADD_MONTHS('2024-01-31', 1);                           -- 2024-02-29（月末自动调整）

```

INTERVAL 表达式（1.2+）

```sql
SELECT CURRENT_TIMESTAMP + INTERVAL '1' DAY;
SELECT CURRENT_TIMESTAMP - INTERVAL '2' HOUR;
SELECT CURRENT_TIMESTAMP + INTERVAL '3' MONTH;

```

## 4. 日期差

```sql
SELECT DATEDIFF('2024-12-31', '2024-01-01');                  -- 365（天数差）
SELECT MONTHS_BETWEEN('2024-12-31', '2024-01-01');            -- 月数差（浮点数）

```

 限制: DATEDIFF 只返回天数差
 需要小时/分钟差: (UNIX_TIMESTAMP(ts1) - UNIX_TIMESTAMP(ts2)) / 3600
 对比: PostgreSQL 的 AGE() 返回完整的 INTERVAL

## 5. 日期部分提取

```sql
SELECT YEAR('2024-01-15');                                   -- 2024
SELECT MONTH('2024-01-15');                                  -- 1
SELECT DAY('2024-01-15');                                    -- 15
SELECT HOUR('2024-01-15 10:30:00');                          -- 10
SELECT MINUTE('2024-01-15 10:30:00');                        -- 30
SELECT SECOND('2024-01-15 10:30:00');                        -- 0
SELECT WEEKOFYEAR('2024-01-15');                             -- 第几周
SELECT DAYOFWEEK('2024-01-15');                              -- 周几 (2.2+)

```

EXTRACT 语法（SQL 标准，2.2+）

```sql
SELECT EXTRACT(YEAR FROM TIMESTAMP '2024-01-15 10:30:00');
SELECT EXTRACT(MONTH FROM TIMESTAMP '2024-01-15 10:30:00');

```

## 6. 日期格式化

```sql
SELECT DATE_FORMAT('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT DATE_FORMAT('2024-01-15', 'yyyy/MM/dd');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyyMMdd');

```

 格式字符串使用 Java SimpleDateFormat 风格:
 yyyy: 四位年份    MM: 两位月份    dd: 两位日期
 HH: 24小时制      mm: 分钟        ss: 秒
 对比: PostgreSQL 使用 TO_CHAR(ts, 'YYYY-MM-DD')
 对比: MySQL 使用 DATE_FORMAT(ts, '%Y-%m-%d')

## 7. 日期截断与边界

```sql
SELECT TRUNC('2024-01-15', 'MM');                            -- 月初 → 2024-01-01
SELECT TRUNC('2024-01-15', 'YY');                            -- 年初 → 2024-01-01
SELECT TRUNC('2024-01-15', 'Q');                             -- 季初 → 2024-01-01
SELECT LAST_DAY('2024-01-15');                               -- 月末 → 2024-01-31
SELECT NEXT_DAY('2024-01-15', 'MO');                         -- 下一个周一

```

## 8. 时区处理

```sql
SELECT FROM_UTC_TIMESTAMP('2024-01-15 10:00:00', 'Asia/Shanghai');  -- UTC → 本地
SELECT TO_UTC_TIMESTAMP('2024-01-15 18:00:00', 'Asia/Shanghai');    -- 本地 → UTC

```

 设计分析: Hive 的时区处理很弱
 Hive 的 TIMESTAMP 类型不带时区信息（类似 MySQL 的 DATETIME）。
 FROM_UTC_TIMESTAMP / TO_UTC_TIMESTAMP 是仅有的时区转换函数。
 Hive 3.0+ 引入了 TIMESTAMPLOCALTZ（带本地时区的时间戳），但使用不广泛。
 对比: PostgreSQL 有 TIMESTAMPTZ（推荐总是使用）
 对比: BigQuery 的 TIMESTAMP 总是 UTC，DATETIME 不带时区

## 9. 跨引擎对比: 日期函数

 功能          Hive              MySQL             PostgreSQL       BigQuery
 当前时间      CURRENT_TIMESTAMP NOW()             NOW()            CURRENT_TIMESTAMP
 日期加天      DATE_ADD(d, n)    DATE_ADD(d,INV n) d + INTERVAL'n d' DATE_ADD(d, INTERVAL n DAY)
 日期差(天)    DATEDIFF(a,b)     DATEDIFF(a,b)     a - b            DATE_DIFF(a,b,DAY)
 格式化        DATE_FORMAT(Java) DATE_FORMAT(%)    TO_CHAR          FORMAT_TIMESTAMP
 Unix互转      UNIX_TIMESTAMP    UNIX_TIMESTAMP    EXTRACT(EPOCH)   UNIX_SECONDS
 时区转换      FROM_UTC_TS       CONVERT_TZ        AT TIME ZONE     TIMESTAMP(ts, zone)
 日期截断      TRUNC             无                 DATE_TRUNC       DATE_TRUNC

## 10. 已知限制

### 1. 无 TIME 类型: Hive 只有 DATE 和 TIMESTAMP，无法表示纯时间

### 2. 无毫秒/微秒精度函数: DATEDIFF 只到天级，TIMESTAMP 虽然支持纳秒但函数不支持

### 3. 时区支持弱: 只有 FROM_UTC/TO_UTC 两个函数

### 4. 格式字符串是 Java 风格: 与 PostgreSQL(TO_CHAR)/MySQL(%) 不同

### 5. DATEDIFF 参数顺序: Hive 是 DATEDIFF(end, start)，某些引擎相反


## 11. 对引擎开发者的启示

### 1. 日期函数的参数顺序是迁移的常见陷阱: DATEDIFF(a,b) 在不同引擎中的参数顺序不一致

### 2. STRING 自动解析为日期是好的用户体验: 降低了类型转换的负担

### 3. INTERVAL 语法应该是一等公民: Hive 1.2+ 的 INTERVAL 支持晚于很多引擎

### 4. 时区处理应该内置: Hive 的时区支持不足是常见的用户抱怨

