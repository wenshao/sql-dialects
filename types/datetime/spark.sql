-- Spark SQL: Date/Time Types (Spark 2.0+)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- DATE: Calendar date (days since epoch)
-- TIMESTAMP: Date + time with session timezone (microsecond precision)
-- TIMESTAMP_NTZ: Date + time without timezone (Spark 3.4+)
-- INTERVAL: Time interval (Spark 3.2+ has YEAR-MONTH and DAY-TIME subtypes)

CREATE TABLE events (
    id         BIGINT,
    event_date DATE,
    created_at TIMESTAMP,             -- With session timezone
    updated_at TIMESTAMP_NTZ          -- Without timezone (Spark 3.4+)
) USING PARQUET;

-- No TIME type in Spark (use TIMESTAMP or STRING for time-only)

-- Current date/time
SELECT CURRENT_DATE();                -- DATE (or CURRENT_DATE)
SELECT CURRENT_TIMESTAMP();           -- TIMESTAMP (or CURRENT_TIMESTAMP)
SELECT NOW();                         -- TIMESTAMP (Spark 3.4+)

-- Date/time literals
SELECT DATE '2024-01-15';
SELECT TIMESTAMP '2024-01-15 10:30:00';

-- Date construction
SELECT MAKE_DATE(2024, 1, 15);                     -- DATE (Spark 3.0+)
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);     -- TIMESTAMP (Spark 3.0+)
SELECT TO_DATE('2024-01-15', 'yyyy-MM-dd');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');

-- Date arithmetic
SELECT DATE_ADD(DATE '2024-01-15', 7);              -- Add 7 days
SELECT DATE_SUB(DATE '2024-01-15', 7);              -- Subtract 7 days
SELECT ADD_MONTHS(DATE '2024-01-15', 3);            -- Add 3 months
SELECT DATE '2024-01-15' + INTERVAL 1 DAY;
SELECT TIMESTAMP '2024-01-15 10:30:00' - INTERVAL 2 HOURS;

-- Date difference
SELECT DATEDIFF(DATE '2024-12-31', DATE '2024-01-01');  -- 365 (days)
SELECT MONTHS_BETWEEN(DATE '2024-12-31', DATE '2024-01-01');  -- Months as decimal
SELECT TIMESTAMPDIFF(HOUR, TIMESTAMP '2024-01-15 10:00:00',
                          TIMESTAMP '2024-01-15 15:30:00');   -- Spark 3.3+

-- Extraction
SELECT YEAR(DATE '2024-01-15');
SELECT MONTH(DATE '2024-01-15');
SELECT DAY(DATE '2024-01-15');
SELECT DAYOFMONTH(DATE '2024-01-15');
SELECT DAYOFWEEK(DATE '2024-01-15');    -- 1=Sunday
SELECT DAYOFYEAR(DATE '2024-01-15');
SELECT HOUR(TIMESTAMP '2024-01-15 10:30:00');
SELECT MINUTE(TIMESTAMP '2024-01-15 10:30:00');
SELECT SECOND(TIMESTAMP '2024-01-15 10:30:45');
SELECT WEEKOFYEAR(DATE '2024-01-15');
SELECT QUARTER(DATE '2024-01-15');
SELECT EXTRACT(YEAR FROM DATE '2024-01-15');

-- Truncation
SELECT DATE_TRUNC('MONTH', TIMESTAMP '2024-01-15 10:30:00');
SELECT DATE_TRUNC('YEAR', CURRENT_TIMESTAMP);
SELECT DATE_TRUNC('HOUR', CURRENT_TIMESTAMP);
SELECT TRUNC(DATE '2024-01-15', 'MM');   -- Truncate to month

-- Formatting
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy-MM-dd HH:mm:ss');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'EEEE, MMMM dd, yyyy');
SELECT FROM_UNIXTIME(1705312200, 'yyyy-MM-dd HH:mm:ss');

-- Unix timestamp
SELECT UNIX_TIMESTAMP();                              -- Current epoch seconds
SELECT UNIX_TIMESTAMP('2024-01-15', 'yyyy-MM-dd');    -- Date string to epoch
SELECT FROM_UNIXTIME(1705312200);                     -- Epoch to timestamp string
SELECT TO_TIMESTAMP(1705312200);                      -- Epoch to TIMESTAMP

-- Last day of month
SELECT LAST_DAY(DATE '2024-02-15');                   -- 2024-02-29

-- Next day
SELECT NEXT_DAY(DATE '2024-01-15', 'Monday');         -- Next Monday

-- Generate date sequence (Spark 3.4+)
SELECT EXPLODE(SEQUENCE(DATE '2024-01-01', DATE '2024-01-31', INTERVAL 1 DAY));

-- Interval types (Spark 3.2+)
SELECT INTERVAL '1' YEAR;
SELECT INTERVAL '2' MONTH;
SELECT INTERVAL '3' DAY;
SELECT INTERVAL '4' HOUR;
SELECT INTERVAL '1-6' YEAR TO MONTH;                  -- 1 year 6 months
SELECT INTERVAL '3 04:30:00' DAY TO SECOND;            -- 3 days 4h 30m

-- Note: Spark TIMESTAMP is always associated with session timezone
-- Note: TIMESTAMP_NTZ (no timezone) added in Spark 3.4+
-- Note: No TIME type; store time as STRING or use TIMESTAMP
-- Note: Date format uses Java SimpleDateFormat patterns (yyyy-MM-dd, not YYYY-MM-DD)
-- Note: DAYOFWEEK returns 1=Sunday (different from many databases)
-- Note: No generate_series; use EXPLODE(SEQUENCE(...)) (Spark 3.4+)
