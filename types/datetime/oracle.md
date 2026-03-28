# Oracle: 日期时间类型

> 参考资料:
> - [Oracle SQL Language Reference - Datetime Data Types](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Data-Types.html)

## 日期时间类型概览

DATE:                          日期+时间（精确到秒），7 字节
TIMESTAMP(p):                  日期+时间（可达纳秒），7-11 字节
TIMESTAMP WITH TIME ZONE:      带时区信息
TIMESTAMP WITH LOCAL TIME ZONE: 存储转为数据库时区，读取转为会话时区
INTERVAL YEAR TO MONTH:        年月间隔
INTERVAL DAY TO SECOND:        日秒间隔

```sql
CREATE TABLE events (
    id         NUMBER(19) GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_date DATE,                                 -- 精确到秒
    created_at TIMESTAMP(6),                         -- 微秒精度
    updated_at TIMESTAMP WITH TIME ZONE,
    local_time TIMESTAMP WITH LOCAL TIME ZONE
);
```

## Oracle DATE 的独特设计

Oracle 的 DATE 包含时间部分! 这是与其他数据库最大的差异。

横向对比:
  Oracle:     DATE = 日期 + 时间（到秒）
  PostgreSQL: DATE = 仅日期，TIMESTAMP = 日期+时间
  MySQL:      DATE = 仅日期，DATETIME = 日期+时间
  SQL Server: DATE = 仅日期，DATETIME2 = 日期+时间

迁移陷阱:
  Oracle DATE 列迁移到其他数据库时，需要用 TIMESTAMP 而非 DATE。
  WHERE date_col = DATE '2024-01-15' 在 Oracle 中只匹配"当天 00:00:00"
  要匹配整天: WHERE date_col >= DATE '2024-01-15'
             AND date_col < DATE '2024-01-16'
  或: WHERE TRUNC(date_col) = DATE '2024-01-15'

## 获取当前时间

```sql
SELECT SYSDATE FROM DUAL;                      -- DATE（服务器时间，无括号!）
SELECT SYSTIMESTAMP FROM DUAL;                 -- TIMESTAMP WITH TZ（服务器）
SELECT CURRENT_DATE FROM DUAL;                 -- DATE（会话时区）
SELECT CURRENT_TIMESTAMP FROM DUAL;            -- TIMESTAMP WITH TZ（会话时区）

-- SYSDATE vs CURRENT_DATE:
--   SYSDATE 返回操作系统时间（不受会话时区影响）
--   CURRENT_DATE 返回会话时区的时间
--   多时区应用应使用 CURRENT_TIMESTAMP
```

## 日期算术（Oracle 独特的数值语义）

DATE + NUMBER = DATE（数字 1 = 1 天）
```sql
SELECT SYSDATE + 1 FROM DUAL;                  -- 明天
SELECT SYSDATE + 1/24 FROM DUAL;               -- + 1 小时
SELECT SYSDATE + INTERVAL '1' DAY FROM DUAL;   -- 等价

-- DATE - DATE = NUMBER（天数差，可以是小数!）
SELECT SYSDATE - TO_DATE('2024-01-01', 'YYYY-MM-DD') FROM DUAL;
```

INTERVAL 类型
```sql
SELECT SYSDATE + INTERVAL '3' MONTH FROM DUAL;
SELECT ADD_MONTHS(SYSDATE, 6) FROM DUAL;
SELECT MONTHS_BETWEEN(SYSDATE, TO_DATE('2024-01-01', 'YYYY-MM-DD')) FROM DUAL;
```

横向对比:
  Oracle:     date1 - date2 → NUMBER（天数）
  PostgreSQL: timestamp1 - timestamp2 → INTERVAL
  MySQL:      TIMESTAMPDIFF(SECOND, t1, t2) → INTEGER
  SQL Server: DATEDIFF(day, d1, d2) → INTEGER

## 日期提取与格式化

```sql
SELECT EXTRACT(YEAR FROM SYSDATE) FROM DUAL;
SELECT EXTRACT(MONTH FROM SYSDATE) FROM DUAL;
SELECT EXTRACT(DAY FROM SYSDATE) FROM DUAL;

SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM DUAL;
SELECT TO_TIMESTAMP('2024-01-15 10:30:00.123', 'YYYY-MM-DD HH24:MI:SS.FF3') FROM DUAL;
```

## TRUNC / ROUND（日期截断与四舍五入）

```sql
SELECT TRUNC(SYSDATE) FROM DUAL;               -- 当天 00:00:00
SELECT TRUNC(SYSDATE, 'MM') FROM DUAL;         -- 月初
SELECT TRUNC(SYSDATE, 'YYYY') FROM DUAL;       -- 年初
SELECT TRUNC(SYSDATE, 'Q') FROM DUAL;          -- 季初
SELECT TRUNC(SYSDATE, 'DAY') FROM DUAL;        -- 本周起始日

SELECT LAST_DAY(SYSDATE) FROM DUAL;            -- 本月最后一天
SELECT NEXT_DAY(SYSDATE, 'MONDAY') FROM DUAL;  -- 下一个周一
```

## TIMESTAMP WITH LOCAL TIME ZONE（Oracle 独有）

三种时间戳类型的设计对比:
  TIMESTAMP:                  无时区信息（存什么就是什么）
  TIMESTAMP WITH TIME ZONE:   存储时区偏移（如 +08:00）或时区名称
  TIMESTAMP WITH LOCAL TIME ZONE: 存储时自动转为数据库时区（DBTIMEZONE）,
                                  读取时自动转为会话时区（SESSIONTIMEZONE）

WITH LOCAL TIME ZONE 是 Oracle 独有的设计:
  适合全球化应用: 数据库统一存 UTC，用户看到的是本地时间。
  类似 PostgreSQL 的 TIMESTAMPTZ 行为，但实现不同。

## NLS_DATE_FORMAT 的陷阱

Oracle 日期隐式转换依赖 NLS_DATE_FORMAT:
```sql
SELECT * FROM t WHERE date_col = '2024-01-15';
```

上面的 '2024-01-15' 会被 NLS_DATE_FORMAT 隐式转换。
如果 NLS_DATE_FORMAT = 'DD-MON-RR'，上面的 SQL 会报错!

最佳实践: 永远使用显式转换:
```sql
SELECT * FROM t WHERE date_col = TO_DATE('2024-01-15', 'YYYY-MM-DD');
```

或 ANSI 日期字面量: WHERE date_col = DATE '2024-01-15';

## 时区转换

```sql
SELECT FROM_TZ(CAST(SYSDATE AS TIMESTAMP), 'UTC')
    AT TIME ZONE 'Asia/Shanghai' FROM DUAL;
```

## 对引擎开发者的总结

1. Oracle DATE 包含时间是最大的迁移陷阱，新引擎应区分 DATE 和 TIMESTAMP。
2. DATE + NUMBER 的算术语义简单直观，但与 SQL 标准不同。
### TIMESTAMP WITH LOCAL TIME ZONE 是优秀的设计: 存储 UTC、显示本地时间。

4. NLS_DATE_FORMAT 影响隐式转换是 Bug 来源，新引擎应避免日期隐式转换。
5. TRUNC 对日期的操作（截断到月/年/季/周）是高频需求，内置支持很有价值。
