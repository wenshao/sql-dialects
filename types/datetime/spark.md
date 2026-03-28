# Spark SQL: 日期时间类型 (Date/Time Types)

> 参考资料:
> - [1] Spark SQL - Data Types
>   https://spark.apache.org/docs/latest/sql-ref-datatypes.html
> - [2] Spark SQL - Datetime Patterns
>   https://spark.apache.org/docs/latest/sql-ref-datetime-pattern.html


## 1. 类型概览

DATE:          日历日期（epoch 以来的天数），范围 0001-01-01 ~ 9999-12-31
TIMESTAMP:     日期+时间+session时区，微秒精度
TIMESTAMP_NTZ: 日期+时间，无时区（Spark 3.4+）
INTERVAL:      时间间隔（3.2+ 区分 YEAR-MONTH 和 DAY-TIME）
无 TIME 类型: Spark 不支持纯时间类型（用 STRING 或 TIMESTAMP 替代）


```sql
CREATE TABLE events (
    id         BIGINT,
    event_date DATE,
    created_at TIMESTAMP,                        -- 带 session 时区
    updated_at TIMESTAMP_NTZ                     -- 无时区（3.4+）
) USING PARQUET;

```

## 2. TIMESTAMP vs TIMESTAMP_NTZ 的设计决策


 TIMESTAMP（默认）:
   存储: 内部存储 UTC 微秒数
   读取: 按 session timezone 转换显示
   适用: 全球化系统、跨时区数据

 TIMESTAMP_NTZ（3.4+）:
   存储: 存储字面时间值，不做时区转换
   读取: 存什么显示什么
   适用: 业务时间（订单时间、预约时间）

 对比:
   PostgreSQL: TIMESTAMP vs TIMESTAMPTZ（推荐总是用 TIMESTAMPTZ）
   MySQL:      DATETIME（无时区）vs TIMESTAMP（UTC 存储+session 转换）
   Oracle:     TIMESTAMP vs TIMESTAMP WITH TIME ZONE vs TIMESTAMP WITH LOCAL TIME ZONE
   BigQuery:   DATETIME（无时区）vs TIMESTAMP（有时区）

 对引擎开发者的启示:
   至少需要两种时间类型: 带时区和不带时区。
   Spark 直到 3.4 才补齐 TIMESTAMP_NTZ——说明这一缺失造成了长期的用户困惑。
   推荐: 内部存 UTC + 显示时转换（PostgreSQL 的做法）。

## 3. 字面量与构造

```sql
SELECT DATE '2024-01-15';
SELECT TIMESTAMP '2024-01-15 10:30:00';
SELECT MAKE_DATE(2024, 1, 15);                           -- 3.0+
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);           -- 3.0+
SELECT TO_DATE('2024-01-15', 'yyyy-MM-dd');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT CURRENT_DATE(), CURRENT_TIMESTAMP(), NOW();       -- NOW() 3.4+

```

## 4. 日期算术

```sql
SELECT DATE_ADD(DATE '2024-01-15', 7);
SELECT DATE_SUB(DATE '2024-01-15', 7);
SELECT ADD_MONTHS(DATE '2024-01-15', 3);
SELECT DATE '2024-01-15' + INTERVAL 1 DAY;
SELECT TIMESTAMP '2024-01-15 10:30:00' - INTERVAL 2 HOURS;

```

日期差

```sql
SELECT DATEDIFF(DATE '2024-12-31', DATE '2024-01-01');   -- 365 天
SELECT MONTHS_BETWEEN(DATE '2024-12-31', DATE '2024-01-01'); -- 小数月
SELECT TIMESTAMPDIFF(HOUR, TIMESTAMP '2024-01-15 10:00:00',
                          TIMESTAMP '2024-01-15 15:30:00');  -- 3.3+

```

## 5. 提取与截断

```sql
SELECT YEAR(DATE '2024-01-15'), MONTH(DATE '2024-01-15'), DAY(DATE '2024-01-15');
SELECT DAYOFWEEK(DATE '2024-01-15');                     -- 2 (1=Sunday!)
SELECT DAYOFYEAR(DATE '2024-01-15');                     -- 15
SELECT HOUR(TIMESTAMP '2024-01-15 10:30:00');
SELECT QUARTER(DATE '2024-01-15');
SELECT EXTRACT(YEAR FROM DATE '2024-01-15');             -- SQL 标准

SELECT DATE_TRUNC('MONTH', TIMESTAMP '2024-01-15 10:30:00');
SELECT TRUNC(DATE '2024-01-15', 'MM');

```

 DAYOFWEEK 返回 1=Sunday 是重要的行为差异:
   Spark/MySQL: 1=Sunday, 2=Monday, ..., 7=Saturday
   PostgreSQL:  EXTRACT(DOW) 0=Sunday, 1=Monday
   ISO 标准:    1=Monday, 7=Sunday

## 6. 格式化与解析

```sql
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy-MM-dd HH:mm:ss');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'EEEE, MMMM dd, yyyy');
SELECT FROM_UNIXTIME(1705312200, 'yyyy-MM-dd HH:mm:ss');
SELECT UNIX_TIMESTAMP();
SELECT UNIX_TIMESTAMP('2024-01-15', 'yyyy-MM-dd');

```

 Spark 使用 Java 格式模式:
   yyyy = 年, MM = 月, dd = 日, HH = 24h, mm = 分, ss = 秒
   注意: YYYY 是 week-based year（与 yyyy 不同!），这是常见 bug 来源
 对比: PostgreSQL 使用 'YYYY-MM-DD HH24:MI:SS' 模式

## 7. 时区处理

```sql
SELECT FROM_UTC_TIMESTAMP(TIMESTAMP '2024-01-15 10:00:00', 'Asia/Shanghai');
SELECT TO_UTC_TIMESTAMP(TIMESTAMP '2024-01-15 18:00:00', 'Asia/Shanghai');

```

## 8. INTERVAL 类型（Spark 3.2+）

```sql
SELECT INTERVAL '1' YEAR;
SELECT INTERVAL '2' MONTH;
SELECT INTERVAL '3' DAY;
SELECT INTERVAL '4' HOUR;
SELECT INTERVAL '1-6' YEAR TO MONTH;                    -- 1 年 6 月
SELECT INTERVAL '3 04:30:00' DAY TO SECOND;              -- 3 天 4 时 30 分

```

## 9. 日期序列生成

```sql
SELECT EXPLODE(SEQUENCE(DATE '2024-01-01', DATE '2024-01-31', INTERVAL 1 DAY));
SELECT EXPLODE(SEQUENCE(DATE '2024-01-01', DATE '2024-12-01', INTERVAL 1 MONTH));

```

## 10. 版本演进

- **Spark 2.0**: DATE, TIMESTAMP, 基本日期函数
- **Spark 3.0**: MAKE_DATE, MAKE_TIMESTAMP, EXTRACT
- **Spark 3.2**: INTERVAL 子类型（YEAR-MONTH / DAY-TIME）
- **Spark 3.3**: TIMESTAMPDIFF
- **Spark 3.4**: TIMESTAMP_NTZ, TRY_TO_TIMESTAMP, NOW()
- **Spark 4.0**: 时区处理改进

> **限制**: 
无 TIME 类型（用 STRING 或 TIMESTAMP 存纯时间）
日期格式使用 Java 模式（yyyy-MM-dd，不是 YYYY-MM-DD）
DAYOFWEEK 返回 1=Sunday（与 ISO 不一致）
- **TIMESTAMP 精度**: 微秒（不是纳秒——对比 ClickHouse 支持纳秒）
无 generate_series（使用 EXPLODE(SEQUENCE(...))）
