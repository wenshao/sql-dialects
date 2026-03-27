-- DuckDB: Date/Time Types (v0.8+)
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- DATE: Calendar date (4 bytes)
-- TIME: Time of day without timezone (8 bytes)
-- TIMESTAMP: Date + time without timezone (8 bytes), microsecond precision
-- TIMESTAMPTZ / TIMESTAMP WITH TIME ZONE: Date + time with timezone (8 bytes)
-- INTERVAL: Time interval

CREATE TABLE events (
    id         BIGINT PRIMARY KEY,
    event_date DATE,
    event_time TIME,
    created_at TIMESTAMP,             -- Microsecond precision (default)
    updated_at TIMESTAMPTZ            -- With timezone
);

-- Additional timestamp types (DuckDB-specific)
-- TIMESTAMP_S:  Second precision
-- TIMESTAMP_MS: Millisecond precision
-- TIMESTAMP_NS: Nanosecond precision
CREATE TABLE high_precision (
    ts_sec  TIMESTAMP_S,
    ts_ms   TIMESTAMP_MS,
    ts_us   TIMESTAMP,                -- Default microsecond
    ts_ns   TIMESTAMP_NS              -- Nanosecond (useful for IoT, HFT)
);

-- Current date/time
SELECT CURRENT_DATE;                  -- DATE
SELECT CURRENT_TIMESTAMP;             -- TIMESTAMPTZ
SELECT NOW();                         -- TIMESTAMPTZ (same as CURRENT_TIMESTAMP)
SELECT CURRENT_TIME;                  -- TIME WITH TIME ZONE

-- Date/time literals
SELECT DATE '2024-01-15';
SELECT TIME '10:30:00';
SELECT TIMESTAMP '2024-01-15 10:30:00';
SELECT TIMESTAMPTZ '2024-01-15 10:30:00+08:00';
SELECT INTERVAL '1 year 2 months 3 days 4 hours';
SELECT INTERVAL 1 DAY;
SELECT INTERVAL '30' MINUTE;

-- Date construction
SELECT MAKE_DATE(2024, 1, 15);        -- 2024-01-15
SELECT MAKE_TIME(10, 30, 0);          -- 10:30:00
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);

-- Date arithmetic
SELECT DATE '2024-01-15' + INTERVAL 1 DAY;
SELECT DATE '2024-01-15' + INTERVAL '3 months';
SELECT DATE '2024-01-15' + 7;         -- Add 7 days (integer)
SELECT TIMESTAMP '2024-01-15 10:30:00' - INTERVAL '2 hours';
SELECT DATE '2024-12-31' - DATE '2024-01-01';  -- Integer days

-- Age function
SELECT AGE(DATE '2024-12-31', DATE '2024-01-01');  -- Returns INTERVAL
SELECT DATE_DIFF('day', DATE '2024-01-01', DATE '2024-12-31');  -- 365
SELECT DATE_DIFF('month', DATE '2024-01-01', DATE '2024-12-31');  -- 11
SELECT DATE_DIFF('year', DATE '2020-01-01', DATE '2024-01-01');   -- 4

-- Extraction
SELECT EXTRACT(YEAR FROM TIMESTAMP '2024-01-15 10:30:00');
SELECT EXTRACT(MONTH FROM DATE '2024-01-15');
SELECT EXTRACT(DOW FROM DATE '2024-01-15');      -- Day of week (0=Sunday)
SELECT EXTRACT(EPOCH FROM TIMESTAMP '2024-01-15 10:30:00');  -- Unix timestamp
SELECT YEAR(DATE '2024-01-15');                  -- Function syntax
SELECT MONTH(DATE '2024-01-15');
SELECT DAY(DATE '2024-01-15');
SELECT HOUR(TIMESTAMP '2024-01-15 10:30:00');
SELECT DAYOFWEEK(DATE '2024-01-15');
SELECT DAYOFYEAR(DATE '2024-01-15');
SELECT WEEKOFYEAR(DATE '2024-01-15');

-- Truncation
SELECT DATE_TRUNC('month', TIMESTAMP '2024-01-15 10:30:00');  -- Month start
SELECT DATE_TRUNC('year', NOW());
SELECT DATE_TRUNC('hour', NOW());

-- Formatting
SELECT STRFTIME(NOW(), '%Y-%m-%d %H:%M:%S');     -- C-style format
SELECT STRFTIME(NOW(), '%A, %B %d, %Y');          -- "Monday, January 15, 2024"

-- Parsing
SELECT STRPTIME('2024-01-15', '%Y-%m-%d');        -- String to TIMESTAMP

-- Timezone conversion
SELECT TIMESTAMP '2024-01-15 10:00:00' AT TIME ZONE 'Asia/Shanghai';
SELECT timezone('UTC', TIMESTAMPTZ '2024-01-15 10:00:00+08');

-- Generate date series
SELECT * FROM generate_series(DATE '2024-01-01', DATE '2024-01-31', INTERVAL 1 DAY);
SELECT * FROM range(DATE '2024-01-01', DATE '2024-02-01', INTERVAL 1 DAY);

-- EPOCH conversions
SELECT EPOCH_MS(1705312200000);        -- Milliseconds to TIMESTAMP
SELECT EPOCH(TIMESTAMP '2024-01-15');  -- TIMESTAMP to seconds

-- Note: DuckDB has TIMESTAMP_NS for nanosecond precision (unique feature)
-- Note: STRFTIME/STRPTIME use C-style format strings (not TO_CHAR/TO_TIMESTAMP)
-- Note: DATE_DIFF function is the primary way to get differences in specific units
-- Note: Timezone support is available but TIMESTAMP is timezone-naive by default
-- Note: generate_series/range can produce date sequences efficiently
