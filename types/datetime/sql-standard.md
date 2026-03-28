# SQL 标准: 日期时间类型

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [Modern SQL - Temporal Features](https://modern-sql.com/feature/temporal)

SQL-86 (SQL1):
无日期时间类型

SQL-92 (SQL2):
DATE: 日期（YYYY-MM-DD）
TIME(p): 时间（HH:MM:SS），可选精度
TIME(p) WITH TIME ZONE: 时间（带时区偏移）
TIMESTAMP(p): 日期时间，可选精度
TIMESTAMP(p) WITH TIME ZONE: 日期时间（带时区偏移）
INTERVAL: 时间间隔

```sql
CREATE TABLE events (
    event_date   DATE,
    event_time   TIME(3),
    local_dt     TIMESTAMP(6),
    created_at   TIMESTAMP(6) WITH TIME ZONE
);
```

INTERVAL 两种形式（SQL-92）:
INTERVAL YEAR TO MONTH: 年月间隔
INTERVAL DAY TO SECOND: 天秒间隔
```sql
SELECT CURRENT_TIMESTAMP + INTERVAL '1' YEAR;
SELECT CURRENT_TIMESTAMP - INTERVAL '30' DAY;
```

SQL:1999 (SQL3):
无日期时间类型重大变化

SQL:2003:
无日期时间类型重大变化

SQL:2008:
无日期时间类型重大变化

SQL:2011:
增强了时间相关的系统信息函数

SQL:2016:
无日期时间类型重大变化

SQL:2023:
无日期时间类型重大变化

标准获取当前时间
```sql
SELECT CURRENT_DATE;                      -- DATE
SELECT CURRENT_TIME;                      -- TIME WITH TIME ZONE
SELECT CURRENT_TIMESTAMP;                -- TIMESTAMP WITH TIME ZONE
SELECT LOCALTIME;                        -- TIME（无时区）
SELECT LOCALTIMESTAMP;                   -- TIMESTAMP（无时区）
```

标准提取
```sql
SELECT EXTRACT(YEAR FROM CURRENT_DATE);
SELECT EXTRACT(MONTH FROM CURRENT_DATE);
SELECT EXTRACT(DAY FROM CURRENT_DATE);
SELECT EXTRACT(HOUR FROM CURRENT_TIMESTAMP);
```

标准类型转换
```sql
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('10:30:00' AS TIME);
SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);
```

- **注意：标准中没有 DATETIME 类型（MySQL/BigQuery 扩展）**
- **注意：标准 INTERVAL 语法较严格，各厂商扩展较多**
- **注意：标准中没有 Unix 时间戳函数**
- **注意：标准中没有 DATE_ADD / DATE_SUB 函数（使用 + / - INTERVAL）**
- **注意：标准中 EXTRACT 只定义了基本字段（YEAR/MONTH/DAY/HOUR/MINUTE/SECOND）**
