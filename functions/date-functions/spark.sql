-- Spark SQL: Date Functions (Spark 2.0+)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Current date/time
SELECT CURRENT_DATE();                                -- DATE
SELECT CURRENT_DATE;                                  -- DATE (without parens)
SELECT CURRENT_TIMESTAMP();                           -- TIMESTAMP
SELECT CURRENT_TIMESTAMP;                             -- TIMESTAMP
SELECT NOW();                                         -- TIMESTAMP (Spark 3.4+)

-- Date construction
SELECT MAKE_DATE(2024, 1, 15);                        -- DATE (Spark 3.0+)
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);       -- TIMESTAMP (Spark 3.0+)
SELECT TO_DATE('2024-01-15', 'yyyy-MM-dd');
SELECT TO_DATE('15/01/2024', 'dd/MM/yyyy');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');

-- Safe parsing (returns NULL on failure)
SELECT TRY_TO_TIMESTAMP('invalid', 'yyyy-MM-dd');     -- NULL (Spark 3.4+)

-- Date arithmetic
SELECT DATE_ADD(DATE '2024-01-15', 7);                -- Add 7 days
SELECT DATE_SUB(DATE '2024-01-15', 7);                -- Subtract 7 days
SELECT ADD_MONTHS(DATE '2024-01-15', 3);              -- Add 3 months
SELECT DATE '2024-01-15' + INTERVAL 1 DAY;
SELECT DATE '2024-01-15' + INTERVAL 3 MONTH;
SELECT TIMESTAMP '2024-01-15 10:30:00' - INTERVAL 2 HOUR;

-- Date difference
SELECT DATEDIFF(DATE '2024-12-31', DATE '2024-01-01');               -- 365 (days)
SELECT MONTHS_BETWEEN(DATE '2024-12-31', DATE '2024-01-01');         -- 11.96... (decimal)
SELECT TIMESTAMPDIFF(HOUR, TIMESTAMP '2024-01-15 10:00:00',
                          TIMESTAMP '2024-01-15 15:30:00');           -- 5 (Spark 3.3+)

-- Extraction
SELECT YEAR(DATE '2024-01-15');                       -- 2024
SELECT MONTH(DATE '2024-01-15');                      -- 1
SELECT DAY(DATE '2024-01-15');                        -- 15
SELECT DAYOFMONTH(DATE '2024-01-15');                 -- 15
SELECT DAYOFWEEK(DATE '2024-01-15');                  -- 2 (1=Sunday in Spark!)
SELECT DAYOFYEAR(DATE '2024-01-15');                  -- 15
SELECT HOUR(TIMESTAMP '2024-01-15 10:30:00');         -- 10
SELECT MINUTE(TIMESTAMP '2024-01-15 10:30:00');       -- 30
SELECT SECOND(TIMESTAMP '2024-01-15 10:30:45');       -- 45
SELECT WEEKOFYEAR(DATE '2024-01-15');                 -- 3
SELECT QUARTER(DATE '2024-01-15');                    -- 1
SELECT EXTRACT(YEAR FROM DATE '2024-01-15');          -- 2024
SELECT EXTRACT(DOW FROM DATE '2024-01-15');           -- Day of week (Spark 3.0+)

-- Truncation
SELECT DATE_TRUNC('MONTH', TIMESTAMP '2024-01-15 10:30:00');  -- 2024-01-01 00:00:00
SELECT DATE_TRUNC('YEAR', CURRENT_TIMESTAMP);
SELECT DATE_TRUNC('HOUR', CURRENT_TIMESTAMP);
SELECT DATE_TRUNC('WEEK', CURRENT_TIMESTAMP);
SELECT TRUNC(DATE '2024-01-15', 'MM');                -- Truncate to month
SELECT TRUNC(DATE '2024-01-15', 'YEAR');              -- Truncate to year

-- Formatting
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy-MM-dd HH:mm:ss');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'EEEE, MMMM dd, yyyy');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'hh:mm a');

-- Unix timestamp
SELECT UNIX_TIMESTAMP();                               -- Current epoch seconds
SELECT UNIX_TIMESTAMP('2024-01-15', 'yyyy-MM-dd');     -- Date to epoch
SELECT UNIX_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT FROM_UNIXTIME(1705312200);                      -- Epoch to string
SELECT FROM_UNIXTIME(1705312200, 'yyyy-MM-dd HH:mm:ss');
SELECT TO_TIMESTAMP(1705312200);                       -- Epoch to TIMESTAMP (Spark 3.1+)

-- Last day / Next day
SELECT LAST_DAY(DATE '2024-02-15');                   -- 2024-02-29
SELECT NEXT_DAY(DATE '2024-01-15', 'Monday');         -- Next Monday after 2024-01-15

-- Date from parts
SELECT DATE_FROM_UNIX_DATE(0);                         -- 1970-01-01
SELECT UNIX_DATE(DATE '2024-01-15');                   -- Days since epoch (Spark 3.0+)

-- Window functions with dates
SELECT DATE_FORMAT(order_time, 'yyyy-MM') AS month,
       SUM(amount) AS monthly_total
FROM orders
GROUP BY DATE_FORMAT(order_time, 'yyyy-MM')
ORDER BY month;

-- Generate date sequence (Spark 3.4+)
SELECT EXPLODE(SEQUENCE(DATE '2024-01-01', DATE '2024-01-31', INTERVAL 1 DAY)) AS dt;
-- Generate with custom step
SELECT EXPLODE(SEQUENCE(DATE '2024-01-01', DATE '2024-12-31', INTERVAL 1 MONTH)) AS dt;

-- Timezone functions
SELECT FROM_UTC_TIMESTAMP(TIMESTAMP '2024-01-15 10:00:00', 'Asia/Shanghai');
SELECT TO_UTC_TIMESTAMP(TIMESTAMP '2024-01-15 18:00:00', 'Asia/Shanghai');

-- Note: Spark uses Java SimpleDateFormat patterns (yyyy-MM-dd, not YYYY-MM-DD)
-- Note: DAYOFWEEK returns 1=Sunday (different from ISO standard)
-- Note: MONTHS_BETWEEN returns a decimal (not integer months)
-- Note: No generate_series; use EXPLODE(SEQUENCE(...)) instead (Spark 3.4+)
-- Note: Unix timestamps are in seconds (not milliseconds)
-- Note: TRY_TO_TIMESTAMP for safe parsing (Spark 3.4+)
