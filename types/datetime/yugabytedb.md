# YugabyteDB: 日期时间类型

> 参考资料:
> - [YugabyteDB YSQL Reference](https://docs.yugabyte.com/stable/api/ysql/)
> - [YugabyteDB PostgreSQL Compatibility](https://docs.yugabyte.com/stable/explore/ysql-language-features/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

```sql
CREATE TABLE events (
    id           BIGSERIAL PRIMARY KEY,
    event_date   DATE,
    event_time   TIME,
    event_timetz TIMETZ,
    local_dt     TIMESTAMP,                    -- without time zone
    created_at   TIMESTAMPTZ DEFAULT now()     -- with time zone (recommended)
);

```

TIMESTAMPTZ recommended (stores UTC, converts on display)

INTERVAL
```sql
SELECT INTERVAL '1 year 2 months 3 days 4 hours';
SELECT now() + INTERVAL '7 days';
SELECT now() - INTERVAL '2 hours 30 minutes';

```

Current date/time (same as PostgreSQL)
```sql
SELECT NOW();                                  -- TIMESTAMPTZ
SELECT CURRENT_TIMESTAMP;                      -- TIMESTAMPTZ (transaction time)
SELECT CLOCK_TIMESTAMP();                      -- actual execution time
SELECT CURRENT_DATE;                           -- DATE
SELECT CURRENT_TIME;                           -- TIMETZ
SELECT LOCALTIME;                              -- TIME
SELECT LOCALTIMESTAMP;                         -- TIMESTAMP

```

Date construction (same as PostgreSQL)
```sql
SELECT MAKE_DATE(2024, 1, 15);
SELECT MAKE_TIME(10, 30, 0);
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);
SELECT MAKE_TIMESTAMPTZ(2024, 1, 15, 10, 30, 0, 'Asia/Shanghai');
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');

```

Date arithmetic (same as PostgreSQL)
```sql
SELECT '2024-01-15'::DATE + INTERVAL '1 month';
SELECT '2024-01-15'::DATE + 7;                 -- add 7 days
SELECT NOW() - INTERVAL '2 hours';
SELECT '2024-12-31'::DATE - '2024-01-01'::DATE; -- 365 (integer days)
SELECT AGE('2024-12-31', '2024-01-01');         -- interval

```

EXTRACT (same as PostgreSQL)
```sql
SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(MONTH FROM NOW());
SELECT EXTRACT(DAY FROM NOW());
SELECT EXTRACT(HOUR FROM NOW());
SELECT EXTRACT(DOW FROM NOW());                -- 0=Sunday
SELECT EXTRACT(DOY FROM NOW());                -- day of year
SELECT EXTRACT(EPOCH FROM NOW());              -- Unix timestamp
SELECT DATE_PART('year', NOW());               -- same as EXTRACT

```

Truncation
```sql
SELECT DATE_TRUNC('month', NOW());
SELECT DATE_TRUNC('year', NOW());
SELECT DATE_TRUNC('hour', NOW());

```

Formatting
```sql
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(NOW(), 'Day, Month DD, YYYY');
SELECT TO_CHAR(NOW(), 'HH12:MI AM');

```

Time zone conversion
```sql
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';
SELECT NOW() AT TIME ZONE 'UTC';

```

Generate series
```sql
SELECT generate_series('2024-01-01'::DATE, '2024-01-31'::DATE, '1 day'::INTERVAL);
SELECT generate_series('2024-01-01'::DATE, '2024-12-31'::DATE, '1 month'::INTERVAL);

```

Note: Same date/time types as PostgreSQL
Note: TIMESTAMPTZ recommended over TIMESTAMP
Note: Transaction timestamps are consistent across distributed nodes
Note: clock_timestamp() reflects actual wall clock time
Note: Based on PostgreSQL 11.2 date/time implementation
Note: All IANA time zones supported
