# CockroachDB: 日期函数

> 参考资料:
> - [CockroachDB - SQL Statements](https://www.cockroachlabs.com/docs/stable/sql-statements)
> - [CockroachDB - Functions and Operators](https://www.cockroachlabs.com/docs/stable/functions-and-operators)
> - [CockroachDB - Data Types](https://www.cockroachlabs.com/docs/stable/data-types)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

```sql
SELECT NOW();                                    -- TIMESTAMPTZ
SELECT CURRENT_TIMESTAMP;                        -- TIMESTAMPTZ (transaction start)
SELECT CLOCK_TIMESTAMP();                        -- actual execution time
SELECT CURRENT_DATE;                             -- DATE
SELECT CURRENT_TIME;                             -- TIMETZ
SELECT LOCALTIME;                                -- TIME
SELECT LOCALTIMESTAMP;                           -- TIMESTAMP

```

Construct dates
```sql
SELECT MAKE_DATE(2024, 1, 15);                   -- 2024-01-15
SELECT MAKE_TIME(10, 30, 0);                     -- 10:30:00
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);
SELECT MAKE_TIMESTAMPTZ(2024, 1, 15, 10, 30, 0, 'Asia/Shanghai');
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');

```

Date arithmetic (same as PostgreSQL)
```sql
SELECT '2024-01-15'::DATE + INTERVAL '1 day';
SELECT '2024-01-15'::DATE + INTERVAL '3 months';
SELECT '2024-01-15'::DATE + 7;                   -- add days
SELECT NOW() - INTERVAL '2 hours 30 minutes';

```

Date difference
```sql
SELECT '2024-12-31'::DATE - '2024-01-01'::DATE;  -- 365 (integer days)
SELECT AGE('2024-12-31', '2024-01-01');           -- interval
SELECT AGE(CURRENT_DATE);                         -- interval from birth to now

```

EXTRACT
```sql
SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(MONTH FROM NOW());
SELECT EXTRACT(DAY FROM NOW());
SELECT EXTRACT(HOUR FROM NOW());
SELECT EXTRACT(DOW FROM NOW());                   -- 0=Sunday
SELECT EXTRACT(DOY FROM NOW());
SELECT EXTRACT(EPOCH FROM NOW());                 -- Unix timestamp
SELECT EXTRACT(WEEK FROM NOW());                  -- ISO week
SELECT DATE_PART('year', NOW());                  -- same as EXTRACT

```

Formatting
```sql
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(NOW(), 'Day, Month DD, YYYY');
SELECT TO_CHAR(NOW(), 'HH12:MI AM');

```

Truncation
```sql
SELECT DATE_TRUNC('month', NOW());                -- month start
SELECT DATE_TRUNC('year', NOW());                 -- year start
SELECT DATE_TRUNC('hour', NOW());                 -- hour start
SELECT DATE_TRUNC('week', NOW());                 -- week start

```

Time zone conversion
```sql
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';
SELECT NOW() AT TIME ZONE 'UTC';
SELECT TIMEZONE('UTC', NOW());

```

Generate series
```sql
SELECT generate_series('2024-01-01'::DATE, '2024-01-31'::DATE, '1 day'::INTERVAL);
SELECT generate_series('2024-01-01'::DATE, '2024-12-31'::DATE, '1 month'::INTERVAL);

```

AS OF SYSTEM TIME (CockroachDB-specific)
```sql
SELECT * FROM users AS OF SYSTEM TIME '-10s';     -- 10 seconds ago
SELECT * FROM users AS OF SYSTEM TIME follower_read_timestamp();

```

experimental_strftime / experimental_strptime (CockroachDB-specific)
```sql
SELECT experimental_strftime(NOW(), '%Y-%m-%d');
SELECT experimental_strptime('2024-01-15', '%Y-%m-%d');

```

Note: Same date functions as PostgreSQL
Note: AS OF SYSTEM TIME for historical queries
Note: follower_read_timestamp() for consistent stale reads
Note: generate_series works for date/time ranges
Note: All IANA time zones supported
