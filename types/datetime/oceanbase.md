# OceanBase: 日期时间类型

> 参考资料:
> - [OceanBase SQL Reference (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase SQL Reference (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL Mode (same as MySQL)


DATE, TIME, DATETIME, TIMESTAMP, YEAR

```sql
CREATE TABLE events (
    id         BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_date DATE,
    event_time TIME(3),
    created_at DATETIME(6),
    updated_at TIMESTAMP(6)
);

```

DATETIME vs TIMESTAMP (same as MySQL)
Default value and ON UPDATE (same as MySQL)
```sql
CREATE TABLE t (
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

```

Current time functions (same as MySQL)
```sql
SELECT NOW();
SELECT CURRENT_TIMESTAMP;
SELECT CURDATE();
SELECT CURTIME();
SELECT UTC_TIMESTAMP();

```

Date arithmetic (same as MySQL)
```sql
SELECT DATE_ADD(NOW(), INTERVAL 1 DAY);
SELECT DATEDIFF('2024-12-31', '2024-01-01');
SELECT TIMESTAMPDIFF(HOUR, '2024-01-01', NOW());

```

Date formatting (same as MySQL)
```sql
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');

```

## Oracle Mode


DATE: stores date AND time (unlike MySQL DATE which is date-only)
Oracle DATE includes hours, minutes, seconds (no sub-second precision)
TIMESTAMP: date+time with fractional seconds
TIMESTAMP WITH TIME ZONE: date+time with timezone info
TIMESTAMP WITH LOCAL TIME ZONE: converts to session timezone
INTERVAL YEAR TO MONTH: duration in years and months
INTERVAL DAY TO SECOND: duration in days, hours, minutes, seconds

```sql
CREATE TABLE events (
    id           NUMBER NOT NULL,
    event_date   DATE,                                    -- includes time!
    created_at   TIMESTAMP(6),                            -- with microseconds
    with_tz      TIMESTAMP(6) WITH TIME ZONE,             -- stores timezone
    local_tz     TIMESTAMP(6) WITH LOCAL TIME ZONE,       -- converts to session tz
    duration_ym  INTERVAL YEAR(3) TO MONTH,               -- e.g., '2-6' (2 years 6 months)
    duration_ds  INTERVAL DAY(3) TO SECOND(6)             -- e.g., '3 12:30:00.000000'
);

```

Current time functions (Oracle mode)
```sql
SELECT SYSDATE FROM DUAL;                                -- current date+time
SELECT SYSTIMESTAMP FROM DUAL;                           -- current timestamp with tz
SELECT CURRENT_DATE FROM DUAL;                           -- session timezone date
SELECT CURRENT_TIMESTAMP FROM DUAL;                      -- session timezone timestamp

```

Date arithmetic (Oracle mode)
```sql
SELECT SYSDATE + 1 FROM DUAL;                           -- add 1 day
SELECT SYSDATE - 7 FROM DUAL;                           -- subtract 7 days
SELECT ADD_MONTHS(SYSDATE, 3) FROM DUAL;                -- add 3 months
SELECT MONTHS_BETWEEN(SYSDATE, DATE '2024-01-01') FROM DUAL;

```

Date extraction
```sql
SELECT EXTRACT(YEAR FROM SYSDATE) FROM DUAL;
SELECT EXTRACT(MONTH FROM SYSDATE) FROM DUAL;

```

Date formatting (Oracle mode, TO_CHAR / TO_DATE)
```sql
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM DUAL;
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;

```

Date truncation (Oracle mode)
```sql
SELECT TRUNC(SYSDATE) FROM DUAL;              -- truncate to day
SELECT TRUNC(SYSDATE, 'MM') FROM DUAL;        -- truncate to month
SELECT TRUNC(SYSDATE, 'YYYY') FROM DUAL;      -- truncate to year

```

NEXT_DAY / LAST_DAY (Oracle mode)
```sql
SELECT NEXT_DAY(SYSDATE, 'MONDAY') FROM DUAL;
SELECT LAST_DAY(SYSDATE) FROM DUAL;

```

Limitations:
MySQL mode: same as MySQL date/time types
Oracle mode: DATE includes time (differs from MySQL DATE)
Oracle mode: TIMESTAMP WITH TIME ZONE supported
Oracle mode: INTERVAL types supported
Timezone handling consistent across distributed nodes
