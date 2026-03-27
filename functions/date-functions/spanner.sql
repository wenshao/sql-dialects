-- Google Cloud Spanner: Date Functions (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- Current date/time
SELECT CURRENT_DATE();                           -- DATE (note: parentheses required)
SELECT CURRENT_TIMESTAMP();                      -- TIMESTAMP (UTC)

-- Construct dates
SELECT DATE(2024, 1, 15);                       -- DATE from parts
SELECT DATE('2024-01-15');                       -- DATE from string
SELECT TIMESTAMP('2024-01-15 10:30:00 UTC');     -- TIMESTAMP from string
SELECT TIMESTAMP('2024-01-15 10:30:00', 'Asia/Shanghai'); -- with timezone

-- Date arithmetic
SELECT DATE_ADD(DATE '2024-01-15', INTERVAL 1 DAY);
SELECT DATE_ADD(DATE '2024-01-15', INTERVAL 3 MONTH);
SELECT DATE_SUB(DATE '2024-01-15', INTERVAL 7 DAY);
SELECT TIMESTAMP_ADD(TIMESTAMP '2024-01-15 10:00:00 UTC', INTERVAL 2 HOUR);
SELECT TIMESTAMP_ADD(TIMESTAMP '2024-01-15 10:00:00 UTC', INTERVAL 30 MINUTE);
SELECT TIMESTAMP_SUB(TIMESTAMP '2024-01-15 10:00:00 UTC', INTERVAL 1 HOUR);

-- Date difference
SELECT DATE_DIFF(DATE '2024-12-31', DATE '2024-01-01', DAY);     -- 365
SELECT DATE_DIFF(DATE '2024-12-31', DATE '2024-01-01', MONTH);   -- 11
SELECT DATE_DIFF(DATE '2024-12-31', DATE '2024-01-01', YEAR);    -- 0
SELECT TIMESTAMP_DIFF(TIMESTAMP '2024-01-15 12:00:00 UTC',
                      TIMESTAMP '2024-01-15 10:00:00 UTC', HOUR); -- 2
SELECT TIMESTAMP_DIFF(ts1, ts2, SECOND);
SELECT TIMESTAMP_DIFF(ts1, ts2, MICROSECOND);

-- EXTRACT
SELECT EXTRACT(YEAR FROM DATE '2024-01-15');
SELECT EXTRACT(MONTH FROM DATE '2024-01-15');
SELECT EXTRACT(DAY FROM DATE '2024-01-15');
SELECT EXTRACT(DAYOFWEEK FROM DATE '2024-01-15');     -- 1=Sunday
SELECT EXTRACT(DAYOFYEAR FROM DATE '2024-01-15');
SELECT EXTRACT(WEEK FROM DATE '2024-01-15');          -- ISO week
SELECT EXTRACT(ISOWEEK FROM DATE '2024-01-15');
SELECT EXTRACT(HOUR FROM TIMESTAMP '2024-01-15 10:30:00 UTC');
SELECT EXTRACT(MINUTE FROM TIMESTAMP '2024-01-15 10:30:00 UTC');

-- Truncation
SELECT DATE_TRUNC(DATE '2024-01-15', MONTH);          -- 2024-01-01
SELECT DATE_TRUNC(DATE '2024-01-15', YEAR);            -- 2024-01-01
SELECT DATE_TRUNC(DATE '2024-01-15', WEEK);            -- start of week
SELECT TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), HOUR);
SELECT TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), DAY);
SELECT TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), MONTH);

-- Formatting
SELECT FORMAT_DATE('%Y-%m-%d', CURRENT_DATE());
SELECT FORMAT_DATE('%A, %B %d, %Y', DATE '2024-01-15');
SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', CURRENT_TIMESTAMP());
SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S %Z', CURRENT_TIMESTAMP(), 'Asia/Shanghai');

-- Parsing
SELECT PARSE_DATE('%Y-%m-%d', '2024-01-15');
SELECT PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %Z', '2024-01-15 10:00:00 UTC');

-- Date from/to Unix epoch
SELECT UNIX_DATE(DATE '2024-01-15');              -- days since 1970-01-01
SELECT DATE_FROM_UNIX_DATE(19738);                -- DATE from days
SELECT UNIX_SECONDS(TIMESTAMP '2024-01-15 00:00:00 UTC'); -- seconds since epoch
SELECT UNIX_MILLIS(CURRENT_TIMESTAMP());          -- milliseconds since epoch
SELECT UNIX_MICROS(CURRENT_TIMESTAMP());          -- microseconds since epoch
SELECT TIMESTAMP_SECONDS(1705276800);             -- TIMESTAMP from seconds
SELECT TIMESTAMP_MILLIS(1705276800000);           -- TIMESTAMP from millis
SELECT TIMESTAMP_MICROS(1705276800000000);        -- TIMESTAMP from micros

-- Commit timestamp
SELECT PENDING_COMMIT_TIMESTAMP();                -- set at commit time

-- Note: Functions are type-prefixed: DATE_*, TIMESTAMP_*
-- Note: No AGE() function (use DATE_DIFF)
-- Note: No INTERVAL as a return type (only for arithmetic)
-- Note: No generate_series for dates
-- Note: UNIX_* functions for epoch conversions
-- Note: PENDING_COMMIT_TIMESTAMP() for exact server commit time
