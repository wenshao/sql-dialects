# OceanBase: 日期函数

> 参考资料:
> - [OceanBase SQL Reference (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase SQL Reference (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL Mode (same as MySQL)


Current time
```sql
SELECT NOW();
SELECT CURRENT_TIMESTAMP;
SELECT CURDATE();
SELECT CURTIME();
SELECT UTC_TIMESTAMP();

```

Date arithmetic
```sql
SELECT DATE_ADD('2024-01-15', INTERVAL 1 DAY);
SELECT DATE_ADD('2024-01-15', INTERVAL 3 MONTH);
SELECT DATE_SUB('2024-01-15', INTERVAL 1 YEAR);

```

Date diff
```sql
SELECT DATEDIFF('2024-12-31', '2024-01-01');
SELECT TIMESTAMPDIFF(MONTH, '2024-01-01', '2024-06-15');

```

Extract
```sql
SELECT YEAR('2024-01-15');
SELECT MONTH('2024-01-15');
SELECT DAY('2024-01-15');
SELECT EXTRACT(YEAR FROM '2024-01-15');

```

Formatting
```sql
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

```

Unix timestamp
```sql
SELECT UNIX_TIMESTAMP();
SELECT FROM_UNIXTIME(1705276800);

```

Day functions
```sql
SELECT DAYOFWEEK('2024-01-15');
SELECT DAYOFYEAR('2024-01-15');
SELECT LAST_DAY('2024-02-15');

```

## Oracle Mode


Current time
```sql
SELECT SYSDATE FROM DUAL;                    -- date + time
SELECT SYSTIMESTAMP FROM DUAL;               -- timestamp with timezone
SELECT CURRENT_DATE FROM DUAL;               -- session timezone date
SELECT CURRENT_TIMESTAMP FROM DUAL;          -- session timezone timestamp

```

Date arithmetic
```sql
SELECT SYSDATE + 1 FROM DUAL;               -- add 1 day
SELECT SYSDATE - 7 FROM DUAL;               -- subtract 7 days
SELECT SYSDATE + 1/24 FROM DUAL;            -- add 1 hour
SELECT SYSDATE + 1/1440 FROM DUAL;          -- add 1 minute

```

ADD_MONTHS
```sql
SELECT ADD_MONTHS(SYSDATE, 3) FROM DUAL;
SELECT ADD_MONTHS(SYSDATE, -6) FROM DUAL;   -- subtract 6 months

```

MONTHS_BETWEEN
```sql
SELECT MONTHS_BETWEEN(SYSDATE, DATE '2024-01-01') FROM DUAL;

```

EXTRACT
```sql
SELECT EXTRACT(YEAR FROM SYSDATE) FROM DUAL;
SELECT EXTRACT(MONTH FROM SYSDATE) FROM DUAL;
SELECT EXTRACT(DAY FROM SYSDATE) FROM DUAL;
SELECT EXTRACT(HOUR FROM SYSTIMESTAMP) FROM DUAL;

```

Formatting (TO_CHAR / TO_DATE / TO_TIMESTAMP)
```sql
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'Day, Month DD, YYYY') FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'DY') FROM DUAL;                -- abbreviated day name
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM DUAL;
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;

```

TRUNC (truncate date)
```sql
SELECT TRUNC(SYSDATE) FROM DUAL;              -- truncate to midnight
SELECT TRUNC(SYSDATE, 'MM') FROM DUAL;        -- truncate to first day of month
SELECT TRUNC(SYSDATE, 'YYYY') FROM DUAL;      -- truncate to first day of year
SELECT TRUNC(SYSDATE, 'Q') FROM DUAL;         -- truncate to first day of quarter
SELECT TRUNC(SYSDATE, 'IW') FROM DUAL;        -- truncate to ISO week start

```

ROUND (round date)
```sql
SELECT ROUND(SYSDATE) FROM DUAL;              -- round to nearest day
SELECT ROUND(SYSDATE, 'MM') FROM DUAL;        -- round to nearest month

```

NEXT_DAY / LAST_DAY
```sql
SELECT NEXT_DAY(SYSDATE, 'MONDAY') FROM DUAL;
SELECT LAST_DAY(SYSDATE) FROM DUAL;

```

NEW_TIME (timezone conversion)
```sql
SELECT NEW_TIME(SYSDATE, 'EST', 'PST') FROM DUAL;

```

Interval arithmetic (Oracle mode)
```sql
SELECT SYSTIMESTAMP + INTERVAL '1' HOUR FROM DUAL;
SELECT SYSTIMESTAMP - INTERVAL '30' MINUTE FROM DUAL;
SELECT SYSTIMESTAMP + INTERVAL '1-6' YEAR TO MONTH FROM DUAL;

```

NUMTODSINTERVAL / NUMTOYMINTERVAL
```sql
SELECT SYSDATE + NUMTODSINTERVAL(2, 'HOUR') FROM DUAL;
SELECT SYSDATE + NUMTOYMINTERVAL(3, 'MONTH') FROM DUAL;

```

Limitations:
MySQL mode: same as MySQL date functions
Oracle mode: TO_CHAR/TO_DATE instead of DATE_FORMAT/STR_TO_DATE
Oracle mode: TRUNC/ROUND for date truncation/rounding
Oracle mode: ADD_MONTHS, MONTHS_BETWEEN, NEXT_DAY
Oracle mode: interval arithmetic with INTERVAL literals
