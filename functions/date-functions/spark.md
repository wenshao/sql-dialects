# Spark SQL: 日期函数 (Date Functions)

> 参考资料:
> - [1] Spark SQL - Datetime Functions
>   https://spark.apache.org/docs/latest/sql-ref-functions-builtin.html#date-and-timestamp-functions


## 1. 当前日期/时间

```sql
SELECT CURRENT_DATE();                                   -- DATE
SELECT CURRENT_DATE;                                     -- 无括号也可
SELECT CURRENT_TIMESTAMP();                              -- TIMESTAMP
SELECT NOW();                                            -- Spark 3.4+

```

## 2. 日期构造

```sql
SELECT MAKE_DATE(2024, 1, 15);                           -- Spark 3.0+
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);           -- Spark 3.0+
SELECT TO_DATE('2024-01-15', 'yyyy-MM-dd');
SELECT TO_DATE('15/01/2024', 'dd/MM/yyyy');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');

```

安全解析（失败返回 NULL）

```sql
SELECT TRY_TO_TIMESTAMP('invalid', 'yyyy-MM-dd');        -- NULL (Spark 3.4+)

```

日期字面量

```sql
SELECT DATE '2024-01-15';
SELECT TIMESTAMP '2024-01-15 10:30:00';

```

## 3. 日期算术

```sql
SELECT DATE_ADD(DATE '2024-01-15', 7);                   -- 加 7 天
SELECT DATE_SUB(DATE '2024-01-15', 7);                   -- 减 7 天
SELECT ADD_MONTHS(DATE '2024-01-15', 3);                 -- 加 3 月
SELECT DATE '2024-01-15' + INTERVAL 1 DAY;
SELECT DATE '2024-01-15' + INTERVAL 3 MONTH;
SELECT TIMESTAMP '2024-01-15 10:30:00' - INTERVAL 2 HOUR;

```

## 4. 日期差

```sql
SELECT DATEDIFF(DATE '2024-12-31', DATE '2024-01-01');   -- 365 (天数差)
SELECT MONTHS_BETWEEN(DATE '2024-12-31', DATE '2024-01-01'); -- 小数月差
SELECT TIMESTAMPDIFF(HOUR, TIMESTAMP '2024-01-15 10:00:00',
                          TIMESTAMP '2024-01-15 15:30:00');  -- 5 (Spark 3.3+)

```

 设计分析: DATEDIFF 的参数顺序
   Spark:      DATEDIFF(end, start) — 与 Hive 一致
   MySQL:      DATEDIFF(end, start) — 与 Spark 一致
   PostgreSQL: date_end - date_start（运算符方式）
   SQL Server: DATEDIFF(unit, start, end) — 参数顺序不同！
   迁移时参数顺序是常见的 bug 来源

## 5. 日期部分提取

```sql
SELECT YEAR(DATE '2024-01-15');                          -- 2024
SELECT MONTH(DATE '2024-01-15');                         -- 1
SELECT DAY(DATE '2024-01-15');                           -- 15
SELECT DAYOFWEEK(DATE '2024-01-15');                     -- 2 (1=Sunday!)
SELECT DAYOFYEAR(DATE '2024-01-15');                     -- 15
SELECT HOUR(TIMESTAMP '2024-01-15 10:30:00');            -- 10
SELECT MINUTE(TIMESTAMP '2024-01-15 10:30:00');          -- 30
SELECT SECOND(TIMESTAMP '2024-01-15 10:30:45');          -- 45
SELECT WEEKOFYEAR(DATE '2024-01-15');                    -- 3
SELECT QUARTER(DATE '2024-01-15');                       -- 1
SELECT EXTRACT(YEAR FROM DATE '2024-01-15');             -- SQL 标准语法

```

 注意: DAYOFWEEK 返回 1=Sunday，与 ISO 标准（1=Monday）不同
 对比: PostgreSQL 的 EXTRACT(DOW) 返回 0=Sunday
 迁移时务必注意星期起始日的差异

## 6. 日期截断

```sql
SELECT DATE_TRUNC('MONTH', TIMESTAMP '2024-01-15 10:30:00'); -- 2024-01-01 00:00:00
SELECT DATE_TRUNC('YEAR', CURRENT_TIMESTAMP);
SELECT DATE_TRUNC('HOUR', CURRENT_TIMESTAMP);
SELECT DATE_TRUNC('WEEK', CURRENT_TIMESTAMP);
SELECT TRUNC(DATE '2024-01-15', 'MM');                   -- 截断到月
SELECT TRUNC(DATE '2024-01-15', 'YEAR');                 -- 截断到年

```

## 7. 日期格式化

```sql
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy-MM-dd HH:mm:ss');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'EEEE, MMMM dd, yyyy');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'hh:mm a');

```

 Spark 使用 Java SimpleDateFormat/DateTimeFormatter 模式:
   yyyy: 4 位年（不是 YYYY！YYYY 是 week-based year）
   MM:   2 位月
   dd:   2 位日
   HH:   24 小时制，hh: 12 小时制
   mm:   分钟
   ss:   秒
   EEEE: 完整星期名
 对比: PostgreSQL 使用 'YYYY-MM-DD HH24:MI:SS' 模式——完全不同的格式字符串

## 8. Unix 时间戳

```sql
SELECT UNIX_TIMESTAMP();                                  -- 当前 epoch 秒数
SELECT UNIX_TIMESTAMP('2024-01-15', 'yyyy-MM-dd');
SELECT FROM_UNIXTIME(1705312200);
SELECT FROM_UNIXTIME(1705312200, 'yyyy-MM-dd HH:mm:ss');
SELECT TO_TIMESTAMP(1705312200);                         -- Spark 3.1+

```

 注意: Unix 时间戳单位是秒（不是毫秒）
 对比: JavaScript 和 Java 的时间戳通常是毫秒

## 9. 其他实用函数

```sql
SELECT LAST_DAY(DATE '2024-02-15');                      -- 2024-02-29
SELECT NEXT_DAY(DATE '2024-01-15', 'Monday');
SELECT DATE_FROM_UNIX_DATE(0);                           -- 1970-01-01
SELECT UNIX_DATE(DATE '2024-01-15');                     -- Spark 3.0+

```

时区转换

```sql
SELECT FROM_UTC_TIMESTAMP(TIMESTAMP '2024-01-15 10:00:00', 'Asia/Shanghai');
SELECT TO_UTC_TIMESTAMP(TIMESTAMP '2024-01-15 18:00:00', 'Asia/Shanghai');

```

日期序列生成（替代 generate_series）

```sql
SELECT EXPLODE(SEQUENCE(DATE '2024-01-01', DATE '2024-01-31', INTERVAL 1 DAY)) AS dt;
SELECT EXPLODE(SEQUENCE(DATE '2024-01-01', DATE '2024-12-31', INTERVAL 1 MONTH)) AS dt;

```

月度汇总示例

```sql
SELECT DATE_FORMAT(order_time, 'yyyy-MM') AS month,
       SUM(amount) AS monthly_total
FROM orders
GROUP BY DATE_FORMAT(order_time, 'yyyy-MM')
ORDER BY month;

```

## 10. 版本演进

Spark 2.0: 基本日期函数（继承 Hive）
Spark 3.0: MAKE_DATE, MAKE_TIMESTAMP, EXTRACT, UNIX_DATE
Spark 3.1: TO_TIMESTAMP(epoch)
Spark 3.3: TIMESTAMPDIFF
Spark 3.4: TRY_TO_TIMESTAMP, NOW(), SEQUENCE 改进

限制:
无 generate_series（使用 EXPLODE(SEQUENCE(...))）
日期模式使用 Java 格式（yyyy-MM-dd，不是 YYYY-MM-DD）
DAYOFWEEK 返回 1=Sunday（与 ISO 不一致）
MONTHS_BETWEEN 返回小数（不是整数月）
Unix 时间戳是秒级（不是毫秒）

