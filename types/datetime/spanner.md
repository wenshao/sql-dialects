# Spanner: 日期时间类型

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

```sql
CREATE TABLE Events (
    EventId   INT64 NOT NULL,
    EventDate DATE,
    CreatedAt TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
    UpdatedAt TIMESTAMP
) PRIMARY KEY (EventId);

```

Note: Only DATE and TIMESTAMP types (no TIME, DATETIME, TIMESTAMPTZ)
Note: TIMESTAMP is always stored in UTC with microsecond precision
Note: allow_commit_timestamp enables PENDING_COMMIT_TIMESTAMP()

Current date/time
```sql
SELECT CURRENT_DATE();                         -- DATE (note: parentheses required)
SELECT CURRENT_TIMESTAMP();                    -- TIMESTAMP

```

Date construction
```sql
SELECT DATE(2024, 1, 15);                     -- DATE from parts
SELECT TIMESTAMP('2024-01-15 10:30:00 UTC');   -- TIMESTAMP from string
SELECT TIMESTAMP('2024-01-15 10:30:00', 'Asia/Shanghai'); -- with timezone

```

INTERVAL (for arithmetic, not as column type)
```sql
SELECT DATE '2024-01-15' + INTERVAL 1 DAY;
SELECT DATE '2024-01-15' + INTERVAL 3 MONTH;
SELECT TIMESTAMP '2024-01-15 10:00:00 UTC' + INTERVAL 2 HOUR;

```

Date arithmetic
```sql
SELECT DATE_ADD(DATE '2024-01-15', INTERVAL 1 MONTH);
SELECT DATE_SUB(DATE '2024-01-15', INTERVAL 7 DAY);
SELECT TIMESTAMP_ADD(TIMESTAMP '2024-01-15 10:00:00 UTC', INTERVAL 30 MINUTE);
SELECT TIMESTAMP_SUB(TIMESTAMP '2024-01-15 10:00:00 UTC', INTERVAL 1 HOUR);

```

Date difference
```sql
SELECT DATE_DIFF(DATE '2024-12-31', DATE '2024-01-01', DAY);     -- 365
SELECT DATE_DIFF(DATE '2024-12-31', DATE '2024-01-01', MONTH);   -- 11
SELECT TIMESTAMP_DIFF(ts1, ts2, SECOND);

```

EXTRACT
```sql
SELECT EXTRACT(YEAR FROM DATE '2024-01-15');
SELECT EXTRACT(MONTH FROM CURRENT_DATE());
SELECT EXTRACT(DAYOFWEEK FROM DATE '2024-01-15');  -- 1=Sunday
SELECT EXTRACT(DAYOFYEAR FROM DATE '2024-01-15');

```

Truncation
```sql
SELECT DATE_TRUNC(DATE '2024-01-15', MONTH);        -- 2024-01-01
SELECT TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), HOUR);
SELECT TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), DAY);

```

Formatting
```sql
SELECT FORMAT_DATE('%Y-%m-%d', CURRENT_DATE());
SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S %Z', CURRENT_TIMESTAMP());

```

Parsing
```sql
SELECT PARSE_DATE('%Y-%m-%d', '2024-01-15');
SELECT PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %Z', '2024-01-15 10:00:00 UTC');

```

Time zone conversion
```sql
SELECT TIMESTAMP('2024-01-15 10:00:00', 'Asia/Shanghai');
SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', CURRENT_TIMESTAMP(), 'Asia/Shanghai');

```

Commit timestamps (Spanner-specific)
```sql
INSERT INTO Events (EventId, CreatedAt)
VALUES (1, PENDING_COMMIT_TIMESTAMP());
```

Exact server-side commit time, globally ordered

Stale reads (for lower latency, client API)
Exact staleness: read data as of 15 seconds ago
Bounded staleness: read data no older than 15 seconds
Configured at transaction level, not in SQL

Note: No TIME type; TIMESTAMP includes time
Note: TIMESTAMP is always UTC (no time zone variants)
Note: INTERVAL cannot be a column type (expressions only)
Note: PENDING_COMMIT_TIMESTAMP() for exact commit time
Note: Date/time functions are prefixed: DATE_*, TIMESTAMP_*
Note: Stale reads configured at transaction level for lower latency
