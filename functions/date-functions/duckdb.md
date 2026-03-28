# DuckDB: 日期函数

> 参考资料:
> - [DuckDB - SQL Reference](https://duckdb.org/docs/sql/introduction)
> - [DuckDB - Functions](https://duckdb.org/docs/sql/functions/overview)
> - [DuckDB - Data Types](https://duckdb.org/docs/sql/data_types/overview)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

```sql
SELECT CURRENT_DATE;                                  -- DATE
SELECT CURRENT_TIMESTAMP;                             -- TIMESTAMPTZ
SELECT NOW();                                         -- TIMESTAMPTZ
SELECT TODAY();                                       -- DATE (DuckDB-specific)

```

Date construction
```sql
SELECT MAKE_DATE(2024, 1, 15);                        -- 2024-01-15
SELECT MAKE_TIME(10, 30, 0);                          -- 10:30:00
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);       -- 2024-01-15 10:30:00

```

Parsing
```sql
SELECT STRPTIME('2024-01-15', '%Y-%m-%d');            -- TIMESTAMP
SELECT STRPTIME('15/01/2024 10:30', '%d/%m/%Y %H:%M');
SELECT '2024-01-15'::DATE;                            -- Direct cast
SELECT '2024-01-15 10:30:00'::TIMESTAMP;

```

Try parsing (returns NULL on failure, DuckDB-specific)
```sql
SELECT TRY_STRPTIME('invalid', '%Y-%m-%d');           -- NULL

```

Date arithmetic
```sql
SELECT DATE '2024-01-15' + INTERVAL 1 DAY;
SELECT DATE '2024-01-15' + INTERVAL '3 months';
SELECT DATE '2024-01-15' + 7;                         -- Add 7 days (integer)
SELECT NOW() - INTERVAL '2 hours 30 minutes';
SELECT DATE '2024-12-31' - DATE '2024-01-01';         -- 365 (integer days)

```

Date difference functions
```sql
SELECT DATE_DIFF('day', DATE '2024-01-01', DATE '2024-12-31');    -- 365
SELECT DATE_DIFF('month', DATE '2024-01-01', DATE '2024-12-31'); -- 11
SELECT DATE_DIFF('year', DATE '2020-01-01', DATE '2024-01-01');  -- 4
SELECT DATE_DIFF('hour', TIMESTAMP '2024-01-01', TIMESTAMP '2024-01-02'); -- 24
SELECT DATEDIFF('day', DATE '2024-01-01', DATE '2024-12-31');    -- Alias

```

AGE function
```sql
SELECT AGE(DATE '2024-12-31', DATE '2024-01-01');     -- INTERVAL: 11 months 30 days

```

Date part addition
```sql
SELECT DATE_ADD(DATE '2024-01-15', INTERVAL 7 DAY);
SELECT DATE_SUB(DATE '2024-01-15', INTERVAL 3 MONTH);

```

Extraction
```sql
SELECT EXTRACT(YEAR FROM DATE '2024-01-15');          -- 2024
SELECT EXTRACT(MONTH FROM DATE '2024-01-15');         -- 1
SELECT EXTRACT(DAY FROM DATE '2024-01-15');           -- 15
SELECT EXTRACT(DOW FROM DATE '2024-01-15');           -- 1 (Monday; 0=Sunday, 6=Saturday)
SELECT EXTRACT(DOY FROM DATE '2024-01-15');           -- 15
SELECT EXTRACT(WEEK FROM DATE '2024-01-15');          -- 3 (ISO week)
SELECT EXTRACT(EPOCH FROM TIMESTAMP '2024-01-15');    -- Unix timestamp

```

Convenience extraction functions (DuckDB-specific)
```sql
SELECT YEAR(DATE '2024-01-15');                       -- 2024
SELECT MONTH(DATE '2024-01-15');                      -- 1
SELECT DAY(DATE '2024-01-15');                        -- 15
SELECT HOUR(TIMESTAMP '2024-01-15 10:30:00');         -- 10
SELECT MINUTE(TIMESTAMP '2024-01-15 10:30:00');       -- 30
SELECT SECOND(TIMESTAMP '2024-01-15 10:30:45');       -- 45
SELECT DAYOFWEEK(DATE '2024-01-15');                  -- 1 (Monday)
SELECT DAYOFYEAR(DATE '2024-01-15');                  -- 15
SELECT WEEKOFYEAR(DATE '2024-01-15');                 -- 3
SELECT QUARTER(DATE '2024-01-15');                    -- 1
SELECT DAYNAME(DATE '2024-01-15');                    -- 'Monday'
SELECT MONTHNAME(DATE '2024-01-15');                  -- 'January'
SELECT YEARWEEK(DATE '2024-01-15');                   -- 202403
SELECT ISODOW(DATE '2024-01-15');                     -- 1 (Monday)
SELECT LAST_DAY(DATE '2024-02-15');                   -- 2024-02-29

```

Truncation
```sql
SELECT DATE_TRUNC('month', TIMESTAMP '2024-01-15 10:30:00');  -- 2024-01-01 00:00:00
SELECT DATE_TRUNC('year', NOW());                     -- Year start
SELECT DATE_TRUNC('hour', NOW());                     -- Hour start
SELECT DATE_TRUNC('week', NOW());                     -- Week start (Monday)
SELECT DATE_TRUNC('quarter', NOW());                  -- Quarter start

```

Formatting
```sql
SELECT STRFTIME(NOW(), '%Y-%m-%d %H:%M:%S');          -- '2024-01-15 10:30:00'
SELECT STRFTIME(NOW(), '%A, %B %d, %Y');              -- 'Monday, January 15, 2024'
SELECT STRFTIME(NOW(), '%I:%M %p');                   -- '10:30 AM'

```

Timezone
```sql
SELECT TIMESTAMP '2024-01-15 10:00:00' AT TIME ZONE 'Asia/Shanghai';
SELECT timezone('UTC', TIMESTAMPTZ '2024-01-15 10:00:00+08');

```

Generate date series
```sql
SELECT * FROM generate_series(DATE '2024-01-01', DATE '2024-01-31', INTERVAL 1 DAY);
SELECT * FROM range(DATE '2024-01-01', DATE '2024-02-01', INTERVAL 1 DAY);
```

Generate timestamp series
```sql
SELECT * FROM generate_series(
    TIMESTAMP '2024-01-01', TIMESTAMP '2024-01-01 23:59:59', INTERVAL 1 HOUR
);

```

Epoch conversions
```sql
SELECT EPOCH_MS(1705312200000);                       -- ms to TIMESTAMP
SELECT EPOCH(TIMESTAMP '2024-01-15');                 -- TIMESTAMP to epoch seconds
SELECT TO_TIMESTAMP(1705312200);                      -- Epoch seconds to TIMESTAMP

```

Date part functions (boolean)
```sql
SELECT ISFINITE(DATE '2024-01-15');                   -- true
SELECT ISFINITE(DATE 'infinity');                     -- false
SELECT ISINF(TIMESTAMP 'infinity');                   -- true

```

Note: STRFTIME/STRPTIME use C-style format strings (%, not Java/Oracle patterns)
Note: TRY_STRPTIME returns NULL on parse failure (safe parsing)
Note: generate_series/range produce date sequences efficiently
Note: DATE_DIFF is the primary function for date differences in specific units
Note: Convenience functions (YEAR, MONTH, DAYNAME, etc.) avoid verbose EXTRACT
Note: EPOCH_MS handles millisecond timestamps (common in event data)
