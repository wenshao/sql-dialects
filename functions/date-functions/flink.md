# Flink SQL: 日期函数

> 参考资料:
> - [Flink SQL Documentation](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
> - [Flink SQL - Built-in Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/)
> - [Flink SQL - Data Types](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

```sql
SELECT CURRENT_DATE;                                   -- DATE
SELECT CURRENT_TIME;                                   -- TIME
SELECT CURRENT_TIMESTAMP;                             -- TIMESTAMP_LTZ
SELECT NOW();                                          -- TIMESTAMP_LTZ
SELECT LOCALTIMESTAMP;                                 -- TIMESTAMP (no timezone)
SELECT CURRENT_ROW_TIMESTAMP();                        -- TIMESTAMP_LTZ (Flink 1.17+)
SELECT PROCTIME();                                     -- Processing time attribute

```

Date construction
```sql
SELECT DATE '2024-01-15';
SELECT TIME '10:30:00';
SELECT TIMESTAMP '2024-01-15 10:30:00';

```

Parsing
```sql
SELECT TO_DATE('2024-01-15', 'yyyy-MM-dd');
SELECT TO_DATE('2024-01-15');                          -- Default format
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00');            -- Default format
SELECT TO_TIMESTAMP_LTZ(1705312200, 0);                -- Epoch seconds to TIMESTAMP_LTZ
SELECT TO_TIMESTAMP_LTZ(1705312200000, 3);             -- Epoch milliseconds

```

Date arithmetic
```sql
SELECT DATE '2024-01-15' + INTERVAL '7' DAY;
SELECT DATE '2024-01-15' + INTERVAL '3' MONTH;
SELECT TIMESTAMP '2024-01-15 10:30:00' + INTERVAL '2' HOUR;
SELECT TIMESTAMP '2024-01-15 10:30:00' - INTERVAL '30' MINUTE;
SELECT TIMESTAMPADD(DAY, 7, DATE '2024-01-15');        -- Add 7 days
SELECT TIMESTAMPADD(MONTH, 3, DATE '2024-01-15');      -- Add 3 months
SELECT TIMESTAMPADD(HOUR, 2, TIMESTAMP '2024-01-15 10:30:00');

```

Date difference
```sql
SELECT TIMESTAMPDIFF(DAY, DATE '2024-01-01', DATE '2024-12-31');    -- 365
SELECT TIMESTAMPDIFF(MONTH, DATE '2024-01-01', DATE '2024-12-31'); -- 11
SELECT TIMESTAMPDIFF(HOUR, TIMESTAMP '2024-01-15 10:00:00',
                          TIMESTAMP '2024-01-15 15:30:00');          -- 5

```

Extraction
```sql
SELECT EXTRACT(YEAR FROM DATE '2024-01-15');           -- 2024
SELECT EXTRACT(MONTH FROM DATE '2024-01-15');          -- 1
SELECT EXTRACT(DAY FROM DATE '2024-01-15');            -- 15
SELECT EXTRACT(HOUR FROM TIMESTAMP '2024-01-15 10:30:00');
SELECT EXTRACT(MINUTE FROM TIMESTAMP '2024-01-15 10:30:00');
SELECT EXTRACT(SECOND FROM TIMESTAMP '2024-01-15 10:30:45');
SELECT EXTRACT(DOW FROM DATE '2024-01-15');            -- Day of week
SELECT EXTRACT(DOY FROM DATE '2024-01-15');            -- Day of year
SELECT EXTRACT(WEEK FROM DATE '2024-01-15');           -- Week number
SELECT EXTRACT(QUARTER FROM DATE '2024-01-15');        -- Quarter

```

Convenience extraction functions
```sql
SELECT YEAR(DATE '2024-01-15');                        -- 2024
SELECT MONTH(DATE '2024-01-15');                       -- 1
SELECT DAYOFMONTH(DATE '2024-01-15');                  -- 15
SELECT DAYOFWEEK(DATE '2024-01-15');                   -- Day of week
SELECT DAYOFYEAR(DATE '2024-01-15');                   -- 15
SELECT HOUR(TIMESTAMP '2024-01-15 10:30:00');          -- 10
SELECT MINUTE(TIMESTAMP '2024-01-15 10:30:00');        -- 30
SELECT SECOND(TIMESTAMP '2024-01-15 10:30:45');        -- 45
SELECT QUARTER(DATE '2024-01-15');                     -- 1

```

Formatting
```sql
SELECT DATE_FORMAT(TIMESTAMP '2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy-MM-dd');

```

Unix timestamp
```sql
SELECT UNIX_TIMESTAMP();                               -- Current epoch seconds
SELECT UNIX_TIMESTAMP(TIMESTAMP '2024-01-15 10:30:00'); -- Timestamp to epoch
SELECT FROM_UNIXTIME(1705312200);                      -- Epoch to string
SELECT FROM_UNIXTIME(1705312200, 'yyyy-MM-dd HH:mm:ss');

```

Ceil / Floor on timestamps
```sql
SELECT CEIL(TIMESTAMP '2024-01-15 10:30:00' TO HOUR);  -- 2024-01-15 11:00:00
SELECT FLOOR(TIMESTAMP '2024-01-15 10:30:00' TO HOUR); -- 2024-01-15 10:00:00
SELECT CEIL(TIMESTAMP '2024-01-15 10:30:00' TO DAY);   -- 2024-01-16 00:00:00
SELECT FLOOR(TIMESTAMP '2024-01-15 10:30:00' TO DAY);  -- 2024-01-15 00:00:00

```

Streaming-specific time functions

Watermark with timestamp manipulation
WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND

Window helper functions (in GROUP BY windows)
TUMBLE_START(event_time, INTERVAL '1' HOUR)
TUMBLE_END(event_time, INTERVAL '1' HOUR)
TUMBLE_ROWTIME(event_time, INTERVAL '1' HOUR)
TUMBLE_PROCTIME(event_time, INTERVAL '1' HOUR)

HOP window functions
HOP_START(event_time, INTERVAL '5' MINUTE, INTERVAL '1' HOUR)
HOP_END(event_time, INTERVAL '5' MINUTE, INTERVAL '1' HOUR)

SESSION window functions
SESSION_START(event_time, INTERVAL '30' MINUTE)
SESSION_END(event_time, INTERVAL '30' MINUTE)

Note: Date format uses Java SimpleDateFormat patterns (yyyy-MM-dd)
Note: TIMESTAMPADD/TIMESTAMPDIFF are the primary arithmetic/difference functions
Note: CEIL/FLOOR on timestamps is unique to Flink (truncation alternative)
Note: TO_TIMESTAMP_LTZ handles epoch seconds (precision 0) and milliseconds (precision 3)
Note: No generate_series for date ranges
Note: Window helper functions (TUMBLE_START, etc.) are for streaming time windows
Note: PROCTIME() returns a special processing-time attribute
