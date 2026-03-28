# Flink SQL: 日期时间类型

> 参考资料:
> - [Flink SQL Documentation](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
> - [Flink SQL - Built-in Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/)
> - [Flink SQL - Data Types](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

```sql
CREATE TABLE events (
    id         BIGINT,
    event_date DATE,
    event_time TIME(3),               -- Millisecond precision
    created_at TIMESTAMP(3),          -- Millisecond precision (common for Kafka)
    updated_at TIMESTAMP_LTZ(3)       -- With local timezone
) WITH (
    'connector' = 'kafka',
    'topic' = 'events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

```

TIMESTAMP vs TIMESTAMP_LTZ
TIMESTAMP(p): No timezone info, stores as-is
TIMESTAMP_LTZ(p): Stored as UTC, displayed in session timezone
For event time in streaming: use TIMESTAMP(3) with WATERMARK

Time attributes (Flink-specific, critical for streaming)

Event time (from data)
```sql
CREATE TABLE orders (
    order_id   BIGINT,
    amount     DECIMAL(10,2),
    order_time TIMESTAMP(3),
```

Watermark declaration: tells Flink how late events can arrive
```sql
    WATERMARK FOR order_time AS order_time - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'orders',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

```

Processing time (virtual column)
```sql
CREATE TABLE sensor_data (
    sensor_id   STRING,
    temperature DOUBLE,
    proc_time   AS PROCTIME()          -- Processing-time attribute
) WITH (
    'connector' = 'kafka',
    'topic' = 'sensors',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

```

Current date/time
```sql
SELECT CURRENT_DATE;                   -- DATE
SELECT CURRENT_TIME;                   -- TIME
SELECT CURRENT_TIMESTAMP;             -- TIMESTAMP_LTZ
SELECT NOW();                          -- TIMESTAMP_LTZ
SELECT LOCALTIMESTAMP;                 -- TIMESTAMP (no timezone)

```

Date/time literals
```sql
SELECT DATE '2024-01-15';
SELECT TIME '10:30:00';
SELECT TIMESTAMP '2024-01-15 10:30:00.000';

```

Date arithmetic
```sql
SELECT DATE '2024-01-15' + INTERVAL '7' DAY;
SELECT TIMESTAMP '2024-01-15 10:30:00' + INTERVAL '2' HOUR;
SELECT TIMESTAMP '2024-01-15 10:30:00' - INTERVAL '30' MINUTE;

```

Date difference
```sql
SELECT TIMESTAMPDIFF(DAY, TIMESTAMP '2024-01-01 00:00:00', TIMESTAMP '2024-12-31 00:00:00');
SELECT TIMESTAMPDIFF(HOUR, TIMESTAMP '2024-01-15 10:00:00', TIMESTAMP '2024-01-15 15:30:00');

```

Extraction
```sql
SELECT EXTRACT(YEAR FROM DATE '2024-01-15');
SELECT EXTRACT(MONTH FROM DATE '2024-01-15');
SELECT EXTRACT(DAY FROM DATE '2024-01-15');
SELECT EXTRACT(HOUR FROM TIMESTAMP '2024-01-15 10:30:00');
SELECT YEAR(DATE '2024-01-15');
SELECT MONTH(DATE '2024-01-15');
SELECT DAYOFWEEK(DATE '2024-01-15');
SELECT DAYOFYEAR(DATE '2024-01-15');
SELECT HOUR(TIMESTAMP '2024-01-15 10:30:00');

```

Formatting
```sql
SELECT DATE_FORMAT(TIMESTAMP '2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');

```

Parsing
```sql
SELECT TO_DATE('2024-01-15', 'yyyy-MM-dd');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');

```

Truncation
```sql
SELECT DATE_FORMAT(TIMESTAMP '2024-01-15 10:30:45', 'yyyy-MM-dd HH:00:00');  -- Truncate to hour

```

Epoch conversions
```sql
SELECT UNIX_TIMESTAMP();                                      -- Current epoch seconds
SELECT FROM_UNIXTIME(1705312200, 'yyyy-MM-dd HH:mm:ss');      -- Epoch to string
SELECT TO_TIMESTAMP_LTZ(1705312200, 0);                        -- Epoch to TIMESTAMP_LTZ

```

Interval types
```sql
SELECT INTERVAL '1' YEAR;
SELECT INTERVAL '2' MONTH;
SELECT INTERVAL '3' DAY;
SELECT INTERVAL '4' HOUR;
SELECT INTERVAL '30' MINUTE;
SELECT INTERVAL '10' SECOND;

```

Watermark with computed event time
```sql
CREATE TABLE parsed_events (
    raw_ts     BIGINT,                 -- Epoch milliseconds from source
    event_time AS TO_TIMESTAMP_LTZ(raw_ts, 3),  -- Computed TIMESTAMP_LTZ
    WATERMARK FOR event_time AS event_time - INTERVAL '10' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

```

Note: TIMESTAMP(3) is the most common precision for Kafka (milliseconds)
Note: WATERMARK is essential for event-time processing in streaming
Note: PROCTIME() creates a virtual processing-time column
Note: TIMESTAMP_LTZ stores UTC internally, converts to session timezone on display
Note: No TIMESTAMP_NS (nanosecond) type; max precision is TIMESTAMP(9)
Note: Time attributes (event time, processing time) are unique to Flink streaming
Note: Date format uses Java SimpleDateFormat patterns
